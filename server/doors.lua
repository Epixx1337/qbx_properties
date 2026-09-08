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

local doorSpots = {}

---@param coords vector3|table
---@return string
local function spotKey(coords)
    return ('%.1f,%.1f,%.1f'):format(coords.x, coords.y, coords.z)
end

local function indexDoors()
    table.wipe(doorSpots)
    local all = exports.ox_doorlock:getAllDoors() or {}
    for i = 1, #all do
        local door = all[i]
        local propertyId = door.name and ToId(door.name:match('^' .. DOOR_PATTERN .. '(%d+):'))
        if propertyId and door.coords then
            local key = spotKey(door.coords)
            doorSpots[key] = doorSpots[key] or {}
            doorSpots[key][propertyId] = true
        end
    end
end

---@param leaf table
---@return boolean
local function usableLeaf(leaf)
    local coords = leaf and leaf.coords
    if not coords or not leaf.model or leaf.model == 0 then return false end
    return not (coords.x == 0 and coords.y == 0 and coords.z == 0)
end

---@param doors table door_data entries
---@return table clean, boolean changed
function CleanDoorData(doors)
    local clean, changed = {}, false

    for i = 1, #doors do
        local entry = doors[i]
        local leaves = {}
        for j = 1, #(entry.leaves or {}) do
            if usableLeaf(entry.leaves[j]) then
                leaves[#leaves + 1] = entry.leaves[j]
            else
                changed = true
            end
        end

        if #leaves > 0 then
            local copy = {}
            for k, v in pairs(entry) do copy[k] = v end
            copy.leaves = leaves
            copy.double = entry.double and #leaves == 2 or false
            clean[#clean + 1] = copy
        else
            changed = true
        end
    end

    return clean, changed
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

    if created > 0 then indexDoors() end
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
    local created = 0

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
            created += 1
        end
    end

    if created > 0 then indexDoors() end
end

---@param propertyId integer
---@param doors table
function SyncPropertyDoors(propertyId, doors)
    if not runtimeDoors then return end

    local prefix = string.format('%s%d:d', DOOR_PREFIX, propertyId)
    exports.ox_doorlock:removeDoorByName(prefix)
    doors = CleanDoorData(doors)

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

    indexDoors()
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

        local citizenId = player.PlayerData.citizenid
        local realtor = IsRealtor(player.PlayerData.job)
        local property = MySQL.single.await('SELECT id, owner, keyholders, building, type, group_name, tenant FROM properties WHERE id = ?', {propertyId})

        if property and ((not property.owner and realtor) or HasPropertyAccess(citizenId, property, 'door')) then
            return true
        end

        local siblings = payload.door.coords and doorSpots[spotKey(payload.door.coords)]
        if siblings then
            for otherId in pairs(siblings) do
                if otherId ~= propertyId then
                    local other = MySQL.single.await('SELECT id, owner, keyholders, building, type, group_name, tenant FROM properties WHERE id = ?', {otherId})
                    if other and ((not other.owner and realtor) or HasPropertyAccess(citizenId, other, 'door')) then
                        return true
                    end
                end
            end
        end

        return false
    end, {
        nameFilter = '^' .. DOOR_PATTERN,
    })

    local ids = {}
    local rows = MySQL.query.await('SELECT id FROM properties') or {}
    for i = 1, #rows do ids[rows[i].id] = true end

    local orphans = {}
    local existing = exports.ox_doorlock:getAllDoors() or {}
    for i = 1, #existing do
        local propertyId = existing[i].name and ToId(existing[i].name:match('^' .. DOOR_PATTERN .. '(%d+):'))
        if propertyId and not ids[propertyId] then orphans[propertyId] = true end
    end

    local pruned = 0
    for propertyId in pairs(orphans) do
        exports.ox_doorlock:removeDoorByName(string.format('%s%d:', DOOR_PREFIX, propertyId))
        pruned += 1
    end

    if pruned > 0 then
        lib.print.info(('removed the doors of %d deleted propert(ies) from ox_doorlock'):format(pruned))
    end

    local repaired = 0
    local withDoors = MySQL.query.await('SELECT id, door_data FROM properties WHERE building IS NULL AND door_data IS NOT NULL') or {}
    for i = 1, #withDoors do
        local ok, doors = pcall(json.decode, withDoors[i].door_data)
        if ok and type(doors) == 'table' then
            local clean, changed = CleanDoorData(doors)
            if changed then
                MySQL.update.await('UPDATE properties SET door_data = ? WHERE id = ?', {#clean > 0 and json.encode(clean) or nil, withDoors[i].id})
                SyncPropertyDoors(withDoors[i].id, clean)
                repaired += 1
            end
        end
    end

    if repaired > 0 then
        lib.print.info(('dropped empty door entries from %d propert(ies)'):format(repaired))
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

    indexDoors()

    local reported = {}
    for _, owners in pairs(doorSpots) do
        local list = {}
        for propertyId in pairs(owners) do list[#list + 1] = propertyId end

        if #list > 1 then
            table.sort(list)
            local key = table.concat(list, ',')

            if not reported[key] then
                reported[key] = true
                local names = MySQL.query.await(('SELECT id, property_name, owner FROM properties WHERE id IN (%s)'):format(key)) or {}
                local parts = {}
                for i = 1, #names do
                    parts[#parts + 1] = ('%d "%s"%s'):format(names[i].id, names[i].property_name, names[i].owner and '' or ' (unowned)')
                end
                lib.print.error(('properties %s share a door - they are the same house twice, keep the owned one and delete the others from the Manage tab'):format(table.concat(parts, ', ')))
            end
        end
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
