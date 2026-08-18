local config = require 'config.server'
local sharedConfig = require 'config.shared'
local wallColors = sharedConfig.wallColors

if not wallColors.enabled then return end

local validIndexes = {}
for i = 1, #wallColors.palette do
    validIndexes[wallColors.palette[i].index] = true
end

---@param propertyId integer
---@return integer? colorIndex
local function readWallColor(propertyId)
    local property = MySQL.single.await('SELECT owner, building, wall_color FROM properties WHERE id = ?', {propertyId})
    if not property then return end

    if property.building then
        if not property.owner then return end
        return MySQL.scalar.await('SELECT wall_color FROM properties_apartment_walls WHERE citizenid = ?', {property.owner})
    end

    return property.wall_color
end

lib.callback.register('qbx_properties:callback:getWallColor', function(_, propertyId)
    propertyId = ToId(propertyId)
    if not propertyId then return end

    return readWallColor(propertyId)
end)

lib.callback.register('qbx_properties:callback:setWallColor', function(source, propertyId, colorIndex)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    colorIndex = ToId(colorIndex)

    if not player or not propertyId or not colorIndex or not validIndexes[colorIndex] then return false end

    local property = MySQL.single.await('SELECT id, owner, keyholders, building, property_name FROM properties WHERE id = ?', {propertyId})
    if not property then return false end

    local citizenId = player.PlayerData.citizenid
    local allowed = IsRealtor(player.PlayerData.job) or HasPropertyAccess(citizenId, property, 'furniture')

    if not allowed then
        local keyholders = GetPropertyKeyholders(property)
        for i = 1, #keyholders do
            if keyholders[i] == citizenId then
                allowed = true
                break
            end
        end
    end

    if not allowed then return false end

    if property.building then
        MySQL.insert.await([[
            INSERT INTO properties_apartment_walls (citizenid, wall_color) VALUES (?, ?)
            ON DUPLICATE KEY UPDATE wall_color = VALUES(wall_color)
        ]], {property.owner, colorIndex})
    else
        MySQL.update.await('UPDATE properties SET wall_color = ? WHERE id = ?', {colorIndex, propertyId})
    end

    lib.triggerClientEvent('qbx_properties:client:wallColor', GetPropertyOccupants(propertyId), propertyId, colorIndex)

    lib.logger(source, 'qbx_properties:server:setWallColor', string.format('%s set wall colour %d on %s', player.PlayerData.citizenid, colorIndex, property.property_name))

    return true
end)
