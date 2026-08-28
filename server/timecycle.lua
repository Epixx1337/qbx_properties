local sharedConfig = require 'config.shared'
local timecycles = sharedConfig.timecycles

if not timecycles or #timecycles == 0 then return end

local validValues = {}
for i = 1, #timecycles do
    validValues[timecycles[i].value] = true
end

lib.callback.register('qbx_properties:callback:getTimecycle', function(_, propertyId)
    propertyId = ToId(propertyId)
    if not propertyId then return end

    local property = MySQL.single.await('SELECT id, building, timecycle FROM properties WHERE id = ?', {propertyId})
    if not property or property.building then return end

    return {
        current = property.timecycle,
        unlocked = GetPropertyUpgrades and GetPropertyUpgrades(propertyId).timecycle == true or false,
    }
end)

lib.callback.register('qbx_properties:callback:setTimecycle', function(source, propertyId, value)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return false end
    if value ~= nil and not validValues[value] then return false end

    local property = MySQL.single.await('SELECT id, property_name, owner, keyholders, building, type, group_name, tenant FROM properties WHERE id = ?', {propertyId})
    if not property or property.building then return false end
    if not HasPropertyAccess(player.PlayerData.citizenid, property, 'furniture') then return false end

    if not (GetPropertyUpgrades and GetPropertyUpgrades(propertyId).timecycle) then
        exports.qbx_core:Notify(source, 'This property needs the lighting upgrade first.', 'error')
        return false
    end

    if value then
        MySQL.update.await('UPDATE properties SET timecycle = ? WHERE id = ?', {value, propertyId})
    else
        MySQL.update.await('UPDATE properties SET timecycle = NULL WHERE id = ?', {propertyId})
    end

    lib.triggerClientEvent('qbx_properties:client:timecycle', GetPropertyOccupants(propertyId), propertyId, value)

    LogAction(source, 'qbx_properties:server:setTimecycle', string.format('%s set the lighting of %s to %s', player.PlayerData.citizenid, property.property_name, value or 'default'))
    return true
end)
