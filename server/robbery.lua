local config = require 'config.server'
local robbery = require('config.crime').robbery

if not robbery.enabled then return end

local attempts = {}

---@param property table
---@return boolean
local function robbable(property)
    return property ~= nil and property.owner ~= nil and (robbery.allowApartments or not property.building)
end

lib.callback.register('qbx_properties:callback:canRobDoor', function(source, propertyId)
    propertyId = ToId(propertyId)
    if not propertyId then return false end
    if IsBreached and IsBreached(propertyId) then return false end
    if not robbable(MySQL.single.await('SELECT owner, building FROM properties WHERE id = ?', {propertyId})) then return false end

    local until_ = attempts[propertyId]
    if until_ and os.time() < until_ then return false end

    local player = exports.qbx_core:GetPlayer(source)
    if not player then return false end

    return (exports.ox_inventory:GetItemCount(source, robbery.item) or 0) > 0
end)

lib.callback.register('qbx_properties:callback:robDoor', function(source, propertyId, success)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return false end

    if (exports.ox_inventory:GetItemCount(source, robbery.item) or 0) <= 0 then return false end

    local property = MySQL.single.await('SELECT id, property_name, owner, building FROM properties WHERE id = ?', {propertyId})
    if not robbable(property) then return false end

    if not success then
        attempts[propertyId] = os.time() + robbery.cooldown
        if robbery.removeOnSuccess then exports.ox_inventory:RemoveItem(source, robbery.item, 1) end
        return false
    end

    if not MarkBreached(propertyId, player.PlayerData.citizenid) then return false end


    if robbery.removeOnSuccess then exports.ox_inventory:RemoveItem(source, robbery.item, 1) end
    attempts[propertyId] = nil

    lib.logger(source, 'qbx_properties:server:robDoor', string.format('%s forced the door of %s', player.PlayerData.citizenid, property.property_name))

    return property.property_name
end)
