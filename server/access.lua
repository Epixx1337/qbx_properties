local config = require 'config.server'

local PERMISSIONS = { door = true, stash = true, furniture = true, garage = true, utilities = true, rent = true }
local BUILDING_EXCLUDED = { garage = true, rent = true }
local BREACH_OPEN = { door = true, stash = true }

---@param property table needs id, owner and building
---@return table
local function accessKey(property)
    if property.building then
        return { column = 'tenant', value = property.owner }
    end
    return { column = 'property_id', value = property.id }
end

---@param property table
---@param permission string
---@return boolean
local function appliesTo(property, permission)
    if not PERMISSIONS[permission] then return false end
    return not (BUILDING_EXCLUDED[permission] and property.building)
end

---@param citizenId string
---@param property table
---@return boolean
local function isKeyholder(citizenId, property)
    local keyholders = GetPropertyKeyholders(property)
    for i = 1, #keyholders do
        if keyholders[i] == citizenId then return true end
    end
    return false
end

---@param citizenId string
---@param property table needs type and group_name
---@return boolean
local function isGroupMember(citizenId, property)
    if not property.group_name or not GetPropertyType(property).groupAccess then return false end
    local player = exports.qbx_core:GetPlayerByCitizenId(citizenId)
    local gang = player and player.PlayerData.gang
    return gang ~= nil and gang.name == property.group_name
end

---@param citizenId string
---@param property table
---@param permission string
---@return boolean
function HasPropertyAccess(citizenId, property, permission)
    if not property or not citizenId then return false end
    if IsBreached and IsBreached(property.id) and BREACH_OPEN[permission] then return true end
    if property.owner == citizenId then return appliesTo(property, permission) end
    if not appliesTo(property, permission) then return false end
    if property.tenant == citizenId then return true end
    if isKeyholder(citizenId, property) then return true end
    if isGroupMember(citizenId, property) then return true end

    local key = accessKey(property)
    if not key.value then return false end

    return MySQL.scalar.await(
        string.format('SELECT 1 FROM properties_access WHERE `%s` = ? AND citizenid = ? AND `%s` = 1', key.column, permission),
        {key.value, citizenId}
    ) ~= nil
end

---@param citizenId string
---@param property table
---@return table
function GetAccessFlags(citizenId, property)
    local house = not property.building
    local flags

    if property.owner == citizenId or property.tenant == citizenId or isKeyholder(citizenId, property) or isGroupMember(citizenId, property) then
        flags = { door = true, stash = true, furniture = true, garage = house, utilities = true, rent = house }
    else
        local key = accessKey(property)
        local row = key.value and MySQL.single.await(
            string.format('SELECT door, stash, furniture, garage, utilities, rent FROM properties_access WHERE `%s` = ? AND citizenid = ?', key.column),
            {key.value, citizenId}
        )

        flags = row and {
            door = ToBool(row.door),
            stash = ToBool(row.stash),
            furniture = ToBool(row.furniture),
            garage = house and ToBool(row.garage),
            utilities = ToBool(row.utilities),
            rent = house and ToBool(row.rent),
        } or { door = false, stash = false, furniture = false, garage = false, utilities = false, rent = false }
    end

    return flags
end

---@param property table
---@return table
function GetPropertyAccessList(property)
    local key = accessKey(property)
    if not key.value then return {} end

    local rows = MySQL.query.await(string.format([[
        SELECT a.citizenid, a.door, a.stash, a.furniture, a.garage, a.utilities, a.rent, p.charinfo
        FROM properties_access a
        LEFT JOIN players p ON p.citizenid = a.citizenid
        WHERE a.`%s` = ?
    ]], key.column), {key.value})

    local result = {}
    for i = 1, #rows do
        local charinfo = rows[i].charinfo and json.decode(rows[i].charinfo)
        result[i] = {
            citizenid = rows[i].citizenid,
            name = charinfo and string.format('%s %s', charinfo.firstname, charinfo.lastname) or rows[i].citizenid,
            door = ToBool(rows[i].door),
            stash = ToBool(rows[i].stash),
            furniture = ToBool(rows[i].furniture),
            garage = ToBool(rows[i].garage),
            utilities = ToBool(rows[i].utilities),
            rent = ToBool(rows[i].rent),
        }
    end
    return result
end

lib.callback.register('qbx_properties:callback:getAccessList', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return {} end

    local property = MySQL.single.await('SELECT id, owner, building, tenant FROM properties WHERE id = ?', {propertyId})
    if not property then return {} end

    local citizenId = player.PlayerData.citizenid
    if property.owner ~= citizenId and property.tenant ~= citizenId then return {} end

    return { access = GetPropertyAccessList(property), apartment = property.building ~= nil }
end)

lib.callback.register('qbx_properties:callback:setAccess', function(source, data)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or type(data) ~= 'table' then return false end

    local propertyId = ToId(data.propertyId)
    if not propertyId or type(data.citizenid) ~= 'string' then return false end

    local property = MySQL.single.await('SELECT id, owner, building, tenant, property_name FROM properties WHERE id = ?', {propertyId})
    if not property then return false end

    local citizenId = player.PlayerData.citizenid
    if property.owner ~= citizenId and property.tenant ~= citizenId then return false end
    if data.citizenid == property.owner or data.citizenid == property.tenant then return false end

    if not MySQL.scalar.await('SELECT citizenid FROM players WHERE citizenid = ?', {data.citizenid}) then return false end

    local key = accessKey(property)
    if not key.value then return false end

    local door = data.door and 1 or 0
    local stash = data.stash and 1 or 0
    local furniture = data.furniture and 1 or 0
    local garage = (data.garage and not property.building) and 1 or 0
    local utilities = data.utilities and 1 or 0
    local rent = (data.rent and not property.building) and 1 or 0

    if door + stash + furniture + garage + utilities + rent == 0 then
        MySQL.update.await(string.format('DELETE FROM properties_access WHERE `%s` = ? AND citizenid = ?', key.column), {key.value, data.citizenid})
    else
        MySQL.update.await(string.format([[
            INSERT INTO properties_access (`%s`, citizenid, door, stash, furniture, garage, utilities, rent) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE door = VALUES(door), stash = VALUES(stash), furniture = VALUES(furniture), garage = VALUES(garage), utilities = VALUES(utilities), rent = VALUES(rent)
        ]], key.column), {key.value, data.citizenid, door, stash, furniture, garage, utilities, rent})
    end

    LogAction(source, 'qbx_properties:server:setAccess', string.format('%s updated access for %s on %s', player.PlayerData.citizenid, data.citizenid, property.property_name))

    TriggerClientEvent('qbx_properties:client:invalidateUnitAccess', -1)
    return true
end)

lib.callback.register('qbx_properties:callback:getNearbyCitizens', function(source)
    local coords = GetEntityCoords(GetPlayerPed(source))
    local nearby = {}

    for _, playerId in ipairs(GetPlayers()) do
        local id = tonumber(playerId) --[[@as number]]
        if id ~= source and #(GetEntityCoords(GetPlayerPed(id)) - coords) <= 5.0 then
            local target = exports.qbx_core:GetPlayer(id)
            if target then
                nearby[#nearby + 1] = {
                    serverId = id,
                    citizenid = target.PlayerData.citizenid,
                    name = string.format('%s %s', target.PlayerData.charinfo.firstname, target.PlayerData.charinfo.lastname),
                }
            end
        end
    end

    return nearby
end)
