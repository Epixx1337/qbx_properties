local sharedConfig = require 'config.shared'

if not sharedConfig.dynamicApartments then return end

local DOOR_PREFIX = 'qbx_properties:'
local runtimeDoors = false

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

CreateThread(function()
    if GetResourceState('ox_doorlock') ~= 'started' then
        lib.print.warn('ox_doorlock is not started, apartment doors will not be registered')
        return
    end

    Wait(2000)

    runtimeDoors = pcall(function() return exports.ox_doorlock:createDoorProgrammatic(nil) end)
    if not runtimeDoors then
        lib.print.warn('ox_doorlock is missing the createDoorProgrammatic export, apartment doors are disabled')
        return
    end

    exports.ox_doorlock:registerHook('doorAuthorization', function(payload)
        local propertyId = ToId(payload.door.name:match('^' .. DOOR_PREFIX .. '(%d+):'))
        if not propertyId then return end

        local player = exports.qbx_core:GetPlayer(payload.source)
        if not player then return false end

        if IsBreached and IsBreached(propertyId) then return payload.door.state == 1 end

        if IsRealtor(player.PlayerData.job) then return true end

        local property = MySQL.single.await('SELECT id, owner, keyholders, building FROM properties WHERE id = ?', {propertyId})
        if not property then return false end

        return HasPropertyAccess(player.PlayerData.citizenid, property, 'door')
    end, {
        nameFilter = '^' .. DOOR_PREFIX,
    })

    local units = MySQL.query.await('SELECT id, building, floor, room FROM properties WHERE building IS NOT NULL')
    local created = 0
    for i = 1, #units do
        created += RegisterUnitDoors(units[i].id, units[i].building, units[i].floor, units[i].room)
    end

    if created > 0 then
        lib.print.info(('registered %d apartment door(s)'):format(created))
    end
end)

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
                exports.ox_doorlock:setDoorState(door.id, breached and 0 or 1)
            end
        end
    end)
end
