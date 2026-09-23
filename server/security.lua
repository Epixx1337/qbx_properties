local sharedConfig = require 'config.shared'
local security = sharedConfig.security

if not security then return end

local DOOR_COLUMNS <const> = 'id, property_name, owner, keyholders, building, floor, room, type, group_name, tenant, interior, coords, door_data, doorcam'

---@param property table
---@return vector3[]
local function doorPoints(property)
    local points = {}

    if property.building then
        local anchor = GetRoomCoords(property.building, property.floor, property.room)
        if anchor then points[#points + 1] = anchor.xyz end
        return points
    end

    if property.door_data then
        local ok, doors = pcall(json.decode, property.door_data)
        if ok and type(doors) == 'table' then
            for i = 1, #doors do
                local leaf = doors[i].leaves and doors[i].leaves[1]
                if leaf and leaf.coords then
                    points[#points + 1] = vec3(leaf.coords.x, leaf.coords.y, leaf.coords.z)
                end
            end
        end
    end

    if property.coords then
        local ok, coords = pcall(json.decode, property.coords)
        if ok and coords and coords.x then
            points[#points + 1] = vec3(coords.x, coords.y, coords.z)
        end
    end

    return points
end

---@param property table
---@return table[] every leaf that can carry the doorbell
local function doorLeaves(property)
    local leaves = {}
    if not property.door_data then return leaves end

    local ok, doors = pcall(json.decode, property.door_data)
    if not ok or type(doors) ~= 'table' then return leaves end

    for i = 1, #doors do
        for j = 1, #(doors[i].leaves or {}) do
            local leaf = doors[i].leaves[j]
            if leaf and leaf.model and leaf.coords then
                leaves[#leaves + 1] = {
                    model = leaf.model,
                    x = leaf.coords.x, y = leaf.coords.y, z = leaf.coords.z,
                }
            end
        end
    end

    return leaves
end

---@param attach table? the leaf the client landed on
---@param coords vector3
---@return table?
local function sanitiseAttach(attach, coords)
    if type(attach) ~= 'table' then return end

    local model = tonumber(attach.model)
    local anchor = vec3(tonumber(attach.x) or 0/0, tonumber(attach.y) or 0/0, tonumber(attach.z) or 0/0)
    local offset = vec3(tonumber(attach.ox) or 0/0, tonumber(attach.oy) or 0/0, tonumber(attach.oz) or 0/0)
    local heading = tonumber(attach.w)

    if not model or not heading or not IsFiniteVector(anchor) or not IsFiniteVector(offset) then return end
    if #(offset) > 4.0 or #(anchor - coords) > 5.0 then return end

    return {
        model = model,
        x = anchor.x, y = anchor.y, z = anchor.z,
        ox = offset.x, oy = offset.y, oz = offset.z,
        w = heading % 360.0,
    }
end

---@param property table
---@param coords vector3
---@return boolean
local function nearADoor(property, coords)
    local points = doorPoints(property)
    local range = security.doorbellRange or 2.0

    for i = 1, #points do
        if #(points[i] - coords) <= range + 1.5 then return true end
    end
    return false
end

---@param source number
---@return table?
local function findDoorbellProperty(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return end

    local citizenId = player.PlayerData.citizenid
    local coords = GetEntityCoords(GetPlayerPed(source))

    local rows = MySQL.query.await(([[
        SELECT %s FROM properties
        WHERE owner IS NOT NULL AND building IS NULL
          AND ABS(JSON_EXTRACT(coords, '$.x') - ?) < 60
          AND ABS(JSON_EXTRACT(coords, '$.y') - ?) < 60
    ]]):format(DOOR_COLUMNS), {coords.x, coords.y}) or {}

    local units = MySQL.query.await(([[
        SELECT %s FROM properties WHERE building IS NOT NULL AND (owner = ? OR tenant = ?)
    ]]):format(DOOR_COLUMNS), {citizenId, citizenId}) or {}

    for i = 1, #units do rows[#rows + 1] = units[i] end

    for i = 1, #rows do
        local property = rows[i]
        if nearADoor(property, coords) and HasPropertyAccess(citizenId, property, 'furniture') then
            return property
        end
    end
end

lib.callback.register('qbx_properties:callback:getDoorbellSpots', function(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return {} end

    local citizenId = player.PlayerData.citizenid
    local gang = player.PlayerData.gang
    local job = player.PlayerData.job

    local rows = MySQL.query.await(([[
        SELECT p.%s FROM properties p
        WHERE p.owner IS NOT NULL AND (
            p.owner = ?
            OR p.tenant = ?
            OR JSON_SEARCH(p.keyholders, 'one', ?) IS NOT NULL
            OR (p.group_name IS NOT NULL AND p.group_name = ?)
            OR EXISTS (
                SELECT 1 FROM properties_access a
                WHERE a.citizenid = ? AND a.furniture = 1
                  AND (a.property_id = p.id OR (p.building IS NOT NULL AND a.tenant = p.owner))
            )
            OR EXISTS (
                SELECT 1 FROM properties_job_access j
                WHERE j.property_id = p.id AND j.furniture = 1
                  AND j.job_name = ? AND j.min_grade <= ?
            )
        )
    ]]):format((DOOR_COLUMNS:gsub(', ', ', p.'))), {
        citizenId, citizenId, citizenId,
        gang and gang.name or '',
        citizenId,
        job and job.name or '', job and job.grade.level or 0,
    }) or {}

    local spots = {}
    for i = 1, #rows do
        local property = rows[i]
        if HasPropertyAccess(citizenId, property, 'furniture') then
            local points = doorPoints(property)
            for j = 1, #points do
                spots[#spots + 1] = { propertyId = property.id, coords = points[j] }
            end
        end
    end

    return spots
end)

lib.callback.register('qbx_properties:callback:canPlaceDoorbell', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return end

    local property
    propertyId = ToId(propertyId)

    if propertyId then
        property = MySQL.single.await(('SELECT %s FROM properties WHERE id = ?'):format(DOOR_COLUMNS), {propertyId})
        if not property or not HasPropertyAccess(player.PlayerData.citizenid, property, 'furniture') then return end
    else
        property = findDoorbellProperty(source)
    end

    if not property then return end

    return {
        propertyId = property.id,
        name = property.property_name,
        model = security.doorbellModel,
        replacing = property.doorcam ~= nil,
        doors = doorLeaves(property),
    }
end)

lib.callback.register('qbx_properties:callback:placeDoorbell', function(source, propertyId, coords, heading, attach)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId or not IsFiniteVector(coords) then return false end

    local property = MySQL.single.await(('SELECT %s FROM properties WHERE id = ?'):format(DOOR_COLUMNS), {propertyId})
    if not property or not HasPropertyAccess(player.PlayerData.citizenid, property, 'furniture') then return false end

    local ped = GetEntityCoords(GetPlayerPed(source))
    if #(ped - coords) > sharedConfig.placementReach then return false end
    if not nearADoor(property, coords) then
        exports.qbx_core:Notify(source, 'The doorbell has to go by one of your doors.', 'error')
        return false
    end

    local payload = {
        x = coords.x, y = coords.y, z = coords.z,
        w = (tonumber(heading) or 0.0) % 360.0,
        model = security.doorbellModel,
        door = sanitiseAttach(attach, coords),
    }

    MySQL.update.await('UPDATE properties SET doorcam = ? WHERE id = ?', {json.encode(payload), propertyId})
    TriggerClientEvent('qbx_properties:client:doorbellPlaced', -1, propertyId, payload)

    LogAction(source, 'qbx_properties:server:placeDoorbell', string.format('%s fitted a doorbell at %s', player.PlayerData.citizenid, property.property_name))
    return true
end)

lib.callback.register('qbx_properties:callback:removeDoorbell', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return false end

    local property = MySQL.single.await(('SELECT %s FROM properties WHERE id = ?'):format(DOOR_COLUMNS), {propertyId})
    if not property or not HasPropertyAccess(player.PlayerData.citizenid, property, 'furniture') then return false end

    MySQL.update.await('UPDATE properties SET doorcam = NULL WHERE id = ?', {propertyId})
    TriggerClientEvent('qbx_properties:client:doorbellPlaced', -1, propertyId, nil)

    LogAction(source, 'qbx_properties:server:removeDoorbell', string.format('%s removed the doorbell at %s', player.PlayerData.citizenid, property.property_name))
    return true
end)

lib.callback.register('qbx_properties:callback:getDoorbells', function()
    local rows = MySQL.query.await('SELECT id, doorcam FROM properties WHERE doorcam IS NOT NULL') or {}
    local result = {}

    for i = 1, #rows do
        local ok, point = pcall(json.decode, rows[i].doorcam)
        if ok and type(point) == 'table' and point.model and point.x then
            result[#result + 1] = {
                propertyId = rows[i].id,
                model = point.model,
                coords = vec3(point.x, point.y, point.z),
                heading = tonumber(point.w) or 0.0,
                door = point.door,
            }
        end
    end

    return result
end)

lib.callback.register('qbx_properties:callback:setCameraPan', function(source, decorationId, pan)
    local player = exports.qbx_core:GetPlayer(source)
    decorationId = ToId(decorationId)
    pan = tonumber(pan)
    if not player or not decorationId or not pan then return false end

    local limit = (security.pan and security.pan.limit) or 80.0
    pan = math.max(-limit, math.min(limit, pan))

    local row = MySQL.single.await('SELECT property_id FROM properties_decorations WHERE id = ?', {decorationId})
    if not row then return false end

    local property = MySQL.single.await('SELECT id, owner, keyholders, building, type, group_name, tenant FROM properties WHERE id = ?', {row.property_id})
    if not property or not HasPropertyAccess(player.PlayerData.citizenid, property, 'door') then return false end

    MySQL.update.await('UPDATE properties_decorations SET camera_pan = ? WHERE id = ?', {pan, decorationId})
    return true
end)
