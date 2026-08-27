local config = require 'config.server'

---@return table
local function getShells()
    local rows = MySQL.query.await('SELECT id, interior, shell_coords FROM properties WHERE shell_coords IS NOT NULL')
    local shells = {}

    for i = 1, #rows do
        local coords = json.decode(rows[i].shell_coords)
        shells[#shells + 1] = {
            id = rows[i].id,
            model = tonumber(rows[i].interior) or rows[i].interior,
            coords = vec4(coords.x, coords.y, coords.z, coords.w),
        }
    end

    return shells
end

lib.callback.register('qbx_properties:callback:getShells', function()
    return getShells()
end)

lib.callback.register('qbx_properties:callback:setShellCoords', function(source, propertyId, coords)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)

    if not player or not propertyId or not IsRealtor(player.PlayerData.job) then return false end
    if type(coords) ~= 'vector4' then return false end
    if #(GetEntityCoords(GetPlayerPed(source)) - coords.xyz) > 100.0 then return false end

    local property = MySQL.single.await('SELECT id, interior, property_name FROM properties WHERE id = ?', {propertyId})
    if not property or not tonumber(property.interior) then return false end

    MySQL.update.await('UPDATE properties SET shell_coords = ? WHERE id = ?', {json.encode(coords), propertyId})

    TriggerClientEvent('qbx_properties:client:registerShell', -1, propertyId, tonumber(property.interior), coords)

    LogAction(source, 'qbx_properties:server:setShellCoords', string.format('%s placed the shell for %s', player.PlayerData.citizenid, property.property_name))

    return true
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    TriggerClientEvent('qbx_properties:client:loadShells', source, getShells())
end)
