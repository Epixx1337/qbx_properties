local sharedConfig = require 'config.shared'

if not sharedConfig.dynamicApartments then return end

local DOOR_PREFIX = GetDoorPrefix()
local DOOR_PATTERN = EscapePattern(DOOR_PREFIX)
local runtimeDoors = false
local trustedDoors = {}

-- ox_doorlock authorises its setDoorState export against whatever `source` its runtime last saw, so state
-- changes made by the resource itself are marked trusted for the authorization hook for the duration of the call
---@param doorId integer
---@param state 0|1
---@return boolean
function SetPropertyDoorState(doorId, state)
    trustedDoors[doorId] = GetGameTimer() + 1000
    local ok = pcall(function() exports.ox_doorlock:setDoorState(doorId, state) end)
    trustedDoors[doorId] = nil
    return ok
end

---@param propertyId integer
---@param buildingKey string
---@param floor integer
---@param room integer
---@return integer created
function RegisterUnitDoors(propertyId, buildingKey, floor, room)
    if not runtimeDoors then return 0 end

    local building = Buildings[buildingKey]
    local doors = building and building.roomLayout and building.roomLayout.doors
    if not doors or #doors == 0 then return 0 end

    local anchor = GetRoomCoords(buildingKey, floor, room)
    if not anchor then return 0 end

    local created = 0

    for i = 1, #doors do
        local name = string.format('%s%d:%d', DOOR_PREFIX, propertyId, i)

        if not exports.ox_doorlock:getDoorFromName(name) then
            local coords = RotateOffset(anchor, doors[i].coords)

            local id = exports.ox_doorlock:createDoorProgrammatic({
                name = name,
                coords = vec3(coords.x, coords.y, coords.z),
                model = doors[i].model,
                heading = doors[i].heading or ((anchor.w + (doors[i].headingOffset or 0.0)) % 360.0),
                maxDistance = doors[i].maxDistance or 1.5,
                state = 1,
                characters = { DOOR_PREFIX .. propertyId },
            })

            if id then created += 1 end
        end
    end

    return created
end

---@param property table
function SyncFurnitureDoors(property)
    if not runtimeDoors then return end

    local prefix = string.format('%s%d:f', DOOR_PREFIX, property.id)
    exports.ox_doorlock:removeDoorByName(prefix)

    local types = GetFurnitureTypes()
    local decorations = GetPropertyDecorations(property)
    local anchor = property.building and GetRoomCoords(property.building, property.floor, property.room)

    for i = 1, #decorations do
        if types[decorations[i].model] == 'door' then
            local stored = json.decode(decorations[i].coords)
            local rotation = json.decode(decorations[i].rotation)
            local coords = anchor and RotateOffset(anchor, vec3(stored.x, stored.y, stored.z)) or vec3(stored.x, stored.y, stored.z)
            local heading = anchor and (rotation.z + anchor.w) % 360.0 or rotation.z

            exports.ox_doorlock:createDoorProgrammatic({
                name = string.format('%s%d', prefix, decorations[i].id),
                coords = coords,
                model = joaat(decorations[i].model),
                heading = heading,
                maxDistance = 1.5,
                state = 1,
                characters = { DOOR_PREFIX .. property.id },
            })
        end
    end
end

---@param propertyId integer
---@param doors table
function SyncPropertyDoors(propertyId, doors)
    if not runtimeDoors then return end

    local prefix = string.format('%s%d:d', DOOR_PREFIX, propertyId)
    exports.ox_doorlock:removeDoorByName(prefix)

    for i = 1, #doors do
        local entry = doors[i]
        local payload = {
            name = string.format('%s%d', prefix, i),
            state = 1,
            maxDistance = 2.5,
            characters = { DOOR_PREFIX .. propertyId },
        }

        if entry.double and #entry.leaves == 2 then
            payload.doors = {
                { model = entry.leaves[1].model, coords = entry.leaves[1].coords, heading = entry.leaves[1].heading },
                { model = entry.leaves[2].model, coords = entry.leaves[2].coords, heading = entry.leaves[2].heading },
            }
            payload.coords = vec3(
                (entry.leaves[1].coords.x + entry.leaves[2].coords.x) / 2,
                (entry.leaves[1].coords.y + entry.leaves[2].coords.y) / 2,
                (entry.leaves[1].coords.z + entry.leaves[2].coords.z) / 2
            )
        else
            local leaf = entry.leaves[1]
            payload.model = leaf.model
            payload.coords = vec3(leaf.coords.x, leaf.coords.y, leaf.coords.z)
            payload.heading = leaf.heading
        end

        exports.ox_doorlock:createDoorProgrammatic(payload)
    end
end

local function bootDoorlock()
    if GetResourceState('ox_doorlock') ~= 'started' then
        lib.print.warn('ox_doorlock is not started, apartment doors will not be registered')
        return
    end

    Wait(2000)
    AwaitMigration()

    runtimeDoors = pcall(function() return exports.ox_doorlock:createDoorProgrammatic(nil) end)
    if not runtimeDoors then
        lib.print.warn('ox_doorlock is missing the createDoorProgrammatic export, apartment doors are disabled')
        return
    end

    exports.ox_doorlock:registerHook('doorAuthorization', function(payload)
        local propertyId = ToId(payload.door.name:match('^' .. DOOR_PATTERN .. '(%d+):'))
        if not propertyId then return end

        local trusted = trustedDoors[payload.door.id]
        if trusted and GetGameTimer() < trusted then return true end

        local player = exports.qbx_core:GetPlayer(payload.source)
        if not player then return false end

        if IsBreached and IsBreached(propertyId) then return payload.door.state == 1 end

        local property = MySQL.single.await('SELECT id, owner, keyholders, building, type, group_name, tenant FROM properties WHERE id = ?', {propertyId})
        if not property then return false end

        if not property.owner and IsRealtor(player.PlayerData.job) then return true end

        return HasPropertyAccess(player.PlayerData.citizenid, property, 'door')
    end, {
        nameFilter = '^' .. DOOR_PATTERN,
    })

    local ids = {}
    local rows = MySQL.query.await('SELECT id FROM properties') or {}
    for i = 1, #rows do ids[rows[i].id] = true end

    local orphans, seen = {}, {}
    local existing = exports.ox_doorlock:getAllDoors() or {}
    for i = 1, #existing do
        local door = existing[i]
        local propertyId = door.name and ToId(door.name:match('^' .. DOOR_PATTERN .. '(%d+):'))

        if propertyId and not ids[propertyId] then
            orphans[propertyId] = true
        elseif propertyId and door.coords then
            local spot = ('%.1f,%.1f,%.1f'):format(door.coords.x, door.coords.y, door.coords.z)
            if seen[spot] and seen[spot] ~= propertyId then
                lib.print.error(('door %s shares its spot with a door of property %d, only one of them can work - remove the stale one from ox_doorlock'):format(door.name, seen[spot]))
            else
                seen[spot] = propertyId
            end
        end
    end

    local pruned = 0
    for propertyId in pairs(orphans) do
        exports.ox_doorlock:removeDoorByName(string.format('%s%d:', DOOR_PREFIX, propertyId))
        pruned += 1
    end

    if pruned > 0 then
        lib.print.info(('removed the doors of %d deleted propert(ies) from ox_doorlock'):format(pruned))
    end

    local duplicates = MySQL.query.await('SELECT building, floor, room, GROUP_CONCAT(id) AS ids FROM properties WHERE building IS NOT NULL GROUP BY building, floor, room HAVING COUNT(*) > 1') or {}
    for i = 1, #duplicates do
        lib.print.error(('properties %s all claim room %d%02d of %s, their doors fight over the same entity - delete the duplicates'):format(duplicates[i].ids, duplicates[i].floor, duplicates[i].room, duplicates[i].building))
    end

    local units = MySQL.query.await('SELECT id, building, floor, room FROM properties WHERE building IS NOT NULL')
    local created = 0
    for i = 1, #units do
        created += RegisterUnitDoors(units[i].id, units[i].building, units[i].floor, units[i].room)
    end

    if created > 0 then
        lib.print.info(('registered %d apartment door(s)'):format(created))
    end

    local standalone = MySQL.query.await('SELECT id, door_data FROM properties WHERE building IS NULL AND door_data IS NOT NULL') or {}
    local synced = 0
    for i = 1, #standalone do
        local first = string.format('%s%d:d1', DOOR_PREFIX, standalone[i].id)
        if not exports.ox_doorlock:getDoorFromName(first) then
            local ok, doors = pcall(json.decode, standalone[i].door_data)
            if ok and type(doors) == 'table' and #doors > 0 then
                SyncPropertyDoors(standalone[i].id, doors)
                synced += 1
            end
        end
    end

    if synced > 0 then
        lib.print.info(('registered the doors of %d propert(ies)'):format(synced))
    end
end

CreateThread(bootDoorlock)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'ox_doorlock' then CreateThread(bootDoorlock) end
end)

---@param propertyId integer
---@param seconds integer?
---@return boolean
function UnlockPropertyDoorsTemporarily(propertyId, seconds)
    if not runtimeDoors then return false end

    local prefix = string.format('%s%d:', DOOR_PREFIX, propertyId)
    local doors = exports.ox_doorlock:getAllDoors()
    if not doors then return false end

    local affected = {}
    for i = 1, #doors do
        local door = doors[i]
        if door.name and door.name:sub(1, #prefix) == prefix and door.state == 1 then
            affected[#affected + 1] = door.id
        end
    end

    if #affected == 0 then return false end

    for i = 1, #affected do
        SetPropertyDoorState(affected[i], 0)
    end

    SetTimeout((seconds or 10) * 1000, function()
        if IsBreached and IsBreached(propertyId) then return end
        for i = 1, #affected do
            SetPropertyDoorState(affected[i], 1)
        end
    end)

    return true
end

---@param propertyId integer
---@param breached boolean
function SetPropertyDoorsBreached(propertyId, breached)
    if not runtimeDoors then return end

    local prefix = string.format('%s%d:', DOOR_PREFIX, propertyId)
    local doors = exports.ox_doorlock:getAllDoors()
    if not doors then return end

    SetTimeout(0, function()
        for i = 1, #doors do
            local door = doors[i]
            if door.name and door.name:sub(1, #prefix) == prefix then
                SetPropertyDoorState(door.id, breached and 0 or 1)
            end
        end
    end)
end
