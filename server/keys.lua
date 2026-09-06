local config = require 'config.server'
local sharedConfig = require 'config.shared'
local keys = sharedConfig.physicalKeys or {}

---@return boolean
function PhysicalKeysEnabled()
    return keys.enabled == true
end

---@param kind 'key'|'lock'
---@return integer
local function keyPrice(kind)
    return math.max(0, math.floor(tonumber(keys.prices and keys.prices[kind]) or 0))
end

---@param property table needs id
---@return integer
local function lockVersion(property)
    if type(property.lock_version) ~= 'number' then
        property.lock_version = MySQL.scalar.await('SELECT lock_version FROM properties WHERE id = ?', {property.id}) or 1
    end
    return property.lock_version
end

---@param property table needs id, property_name, building
---@return table
local function keyMetadata(property)
    local building = property.building and Buildings[property.building]
    local labels = keys.labels or {}

    return {
        label = building and (building.keyLabel or labels.apartment or 'Apartment key') or string.format(labels.house or '%s key', property.property_name),
        description = building and property.property_name or string.format('Opens the doors of %s', property.property_name),
        property = property.id,
        lock = lockVersion(property),
        imageurl = ('nui://%s/web/build/items/property_key.png'):format(GetCurrentResourceName()),
    }
end

---@param propertyId integer
---@return table?
local function fetchProperty(propertyId)
    return MySQL.single.await('SELECT id, property_name, owner, tenant, building, lock_version FROM properties WHERE id = ?', {propertyId})
end

---@param slots table? slot list from ox_inventory or a decoded stash row
---@param propertyId integer
---@param version integer
---@return boolean
local function slotsHoldKey(slots, propertyId, version)
    if type(slots) ~= 'table' then return false end

    for _, slot in pairs(slots) do
        if type(slot) == 'table' and slot.name == keys.item then
            local metadata = slot.metadata
            if metadata and tonumber(metadata.property) == propertyId and tonumber(metadata.lock) == version then
                return true
            end
        end
    end

    return false
end

---@param slot table
---@return string? inventory id of the bag or container this item opens
local function bagInventoryId(slot)
    local metadata = slot.metadata
    if type(metadata) ~= 'table' then return end
    if metadata.container then return metadata.container end

    if metadata.id then
        local definition = exports.ox_inventory:Items(slot.name)
        if definition and definition.backpack then return ('backpack-%s'):format(metadata.id) end
    end
end

---@param inventoryId string
---@param propertyId integer
---@param version integer
---@return boolean
local function bagHoldsKey(inventoryId, propertyId, version)
    if exports.ox_inventory:GetInventory(inventoryId) then
        return slotsHoldKey(exports.ox_inventory:Search(inventoryId, 'slots', keys.item), propertyId, version)
    end

    local ok, stored = pcall(MySQL.scalar.await, "SELECT data FROM ox_inventory WHERE owner = '' AND name = ?", {inventoryId})
    if not ok or type(stored) ~= 'string' then return false end

    local decoded = json.decode(stored)
    return type(decoded) == 'table' and slotsHoldKey(decoded, propertyId, version)
end

---@param source integer
---@param property table needs id
---@return boolean
function HasPropertyKey(source, property)
    local version = lockVersion(property)
    if slotsHoldKey(exports.ox_inventory:Search(source, 'slots', keys.item), property.id, version) then return true end

    local items = exports.ox_inventory:GetInventoryItems(source)
    if type(items) ~= 'table' then return false end

    for _, slot in pairs(items) do
        local bag = type(slot) == 'table' and bagInventoryId(slot)
        if bag and bagHoldsKey(bag, property.id, version) then return true end
    end

    return false
end

---@param source integer
---@param property table needs id, property_name, building
---@return boolean
function GivePropertyKey(source, property)
    if not PhysicalKeysEnabled() then return false end

    if not exports.ox_inventory:Items(keys.item) then
        lib.print.error(('the %s item is not defined in ox_inventory, add it to data/items.lua (README, Physical door keys)'):format(keys.item))
        return false
    end

    if not exports.ox_inventory:CanCarryItem(source, keys.item, 1) then
        exports.qbx_core:Notify(source, 'Your pockets are full, the key would not fit.', 'error')
        return false
    end

    local ok, response = exports.ox_inventory:AddItem(source, keys.item, 1, keyMetadata(property))
    if not ok then
        lib.print.warn(('could not hand out a key for property %d: %s (is the %s item defined in ox_inventory?)'):format(property.id, tostring(response), keys.item))
        return false
    end

    local player = exports.qbx_core:GetPlayer(source)
    if player then
        MySQL.insert.await('INSERT INTO properties_keys (property_id, citizenid, lock_version) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE lock_version = VALUES(lock_version)', {
            property.id, player.PlayerData.citizenid, lockVersion(property),
        })
    end

    return true
end

---@param propertyId integer
---@return integer
function RotatePropertyLock(propertyId)
    MySQL.update.await('UPDATE properties SET lock_version = lock_version + 1 WHERE id = ?', {propertyId})
    MySQL.update.await('DELETE FROM properties_keys WHERE property_id = ?', {propertyId})
    return MySQL.scalar.await('SELECT lock_version FROM properties WHERE id = ?', {propertyId}) or 1
end

---@param propertyId integer
---@param source integer? the new holder, when online
function HandoverPropertyKeys(propertyId, source)
    if not PhysicalKeysEnabled() then return end

    RotatePropertyLock(propertyId)
    if not source then return end

    local property = fetchProperty(propertyId)
    if property then GivePropertyKey(source, property) end
end

---@param propertyId integer
---@param source integer
function IssuePropertyKey(propertyId, source)
    if not PhysicalKeysEnabled() then return end

    local property = fetchProperty(propertyId)
    if property then GivePropertyKey(source, property) end
end

---@param source integer
local function issueMissingKeys(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return end
    local citizenId = player.PlayerData.citizenid

    local rows = MySQL.query.await([[
        SELECT p.id, p.property_name, p.building, p.lock_version
        FROM properties p
        LEFT JOIN properties_keys k ON k.property_id = p.id AND k.citizenid = ?
        WHERE (p.owner = ? OR p.tenant = ?) AND (k.lock_version IS NULL OR k.lock_version <> p.lock_version)
    ]], {citizenId, citizenId, citizenId}) or {}

    for i = 1, #rows do
        GivePropertyKey(source, rows[i])
    end
end

CreateThread(function()
    if not PhysicalKeysEnabled() then return end
    Wait(2000)
    if not exports.ox_inventory:Items(keys.item) then
        lib.print.error(('physicalKeys is enabled but the %s item is not defined in ox_inventory, nobody can get a key until it is added to data/items.lua (README, Physical door keys)'):format(keys.item))
    end
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    if not PhysicalKeysEnabled() then return end
    local playerSource = source --[[@as number]]

    CreateThread(function()
        local deadline = GetGameTimer() + 30000
        while GetGameTimer() < deadline do
            if not exports.qbx_core:GetPlayer(playerSource) then return end
            if exports.ox_inventory:GetInventory(playerSource) then
                issueMissingKeys(playerSource)
                return
            end
            Wait(500)
        end
    end)
end)

---@param source integer
---@param propertyId integer
---@return table? player, table? property
local function keyHolderProperty(source, propertyId)
    if not PhysicalKeysEnabled() then return end

    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return end

    local property = fetchProperty(propertyId)
    if not property then return end

    local citizenId = player.PlayerData.citizenid
    if property.owner ~= citizenId and property.tenant ~= citizenId then return end

    return player, property
end

---@param player table
---@param amount integer
---@param reason string
---@return boolean
local function charge(player, amount, reason)
    if amount <= 0 then return true end

    if not player.Functions.RemoveMoney('bank', amount, reason) then
        exports.qbx_core:Notify(player.PlayerData.source, 'Not enough money in your bank.', 'error')
        return false
    end

    PayAccount(config.governmentAccount, amount, reason)
    return true
end

lib.callback.register('qbx_properties:callback:cutKey', function(source, propertyId, targetCid)
    local player, property = keyHolderProperty(source, propertyId)
    if not player or not property then return false end

    local target = source
    if type(targetCid) == 'string' and targetCid ~= '' and targetCid ~= player.PlayerData.citizenid then
        local other = exports.qbx_core:GetPlayerByCitizenId(targetCid)
        if not other or #(GetEntityCoords(GetPlayerPed(other.PlayerData.source)) - GetEntityCoords(GetPlayerPed(source))) > 10.0 then
            exports.qbx_core:Notify(source, 'They need to be standing next to you.', 'error')
            return false
        end
        target = other.PlayerData.source
    end

    if not exports.ox_inventory:CanCarryItem(target, keys.item, 1) then
        exports.qbx_core:Notify(source, target == source and 'Your pockets are full, the key would not fit.' or 'Their pockets are full, the key would not fit.', 'error')
        return false
    end

    local price = keyPrice('key')
    if not charge(player, price, string.format('Key cut for %s', property.property_name)) then return false end
    if not GivePropertyKey(target, property) then return false end

    if target ~= source then
        exports.qbx_core:Notify(target, string.format('You were handed a key for %s.', property.property_name), 'success')
        exports.qbx_core:Notify(source, 'Key cut and handed over.', 'success')
    else
        exports.qbx_core:Notify(source, 'Key cut.', 'success')
    end

    LogAction(source, 'qbx_properties:server:cutKey', string.format('%s cut a key for property %d%s', player.PlayerData.citizenid, property.id, target ~= source and (' for ' .. targetCid) or ''))
    return true
end)

lib.callback.register('qbx_properties:callback:changeLock', function(source, propertyId)
    local player, property = keyHolderProperty(source, propertyId)
    if not player or not property then return false end

    local price = keyPrice('lock')
    if not charge(player, price, string.format('New lock for %s', property.property_name)) then return false end

    local slots = exports.ox_inventory:Search(source, 'slots', keys.item)
    if type(slots) == 'table' then
        for i = 1, #slots do
            local metadata = slots[i].metadata
            if metadata and tonumber(metadata.property) == property.id then
                exports.ox_inventory:RemoveItem(source, keys.item, 1, nil, slots[i].slot)
            end
        end
    end

    property.lock_version = RotatePropertyLock(property.id)
    GivePropertyKey(source, property)

    local citizenId = player.PlayerData.citizenid
    local otherCid = property.owner ~= citizenId and property.owner or property.tenant ~= citizenId and property.tenant or nil
    local other = otherCid and exports.qbx_core:GetPlayerByCitizenId(otherCid)
    if other then
        GivePropertyKey(other.PlayerData.source, property)
        exports.qbx_core:Notify(other.PlayerData.source, string.format('The lock of %s was changed, here is your new key.', property.property_name))
    end

    exports.qbx_core:Notify(source, 'New lock fitted, every old key is useless now.', 'success')
    LogAction(source, 'qbx_properties:server:changeLock', string.format('%s changed the lock of property %d', citizenId, property.id))
    return true
end)

