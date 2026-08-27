local sharedConfig = require 'config.shared'

local cache = {}

---@param propertyType string?
---@return table catalog
local function catalogFor(propertyType)
    local perType = sharedConfig.typeUpgrades or {}
    return perType[propertyType or 'residential'] or sharedConfig.upgrades or {}
end

---@param propertyId integer
---@return string?
local function propertyTypeOf(propertyId)
    return MySQL.scalar.await('SELECT type FROM properties WHERE id = ?', {propertyId})
end

---@param propertyId integer
---@return table<string, boolean>
function GetPropertyUpgrades(propertyId)
    local owned = cache[propertyId]
    if owned then return owned end

    owned = {}
    local rows = MySQL.query.await('SELECT upgrade FROM properties_upgrades WHERE property_id = ?', {propertyId}) or {}
    for i = 1, #rows do
        owned[rows[i].upgrade] = true
    end
    cache[propertyId] = owned
    return owned
end

function InvalidateUpgradeCache(propertyId)
    cache[propertyId] = nil
end

---@param propertyId integer
---@param field string numeric field on catalog entries
---@param propertyType string?
---@return number highest value among owned upgrades
local function highestOwned(propertyId, field, propertyType)
    local catalog = catalogFor(propertyType or propertyTypeOf(propertyId))
    local owned = GetPropertyUpgrades(propertyId)
    local best = 0
    for name in pairs(owned) do
        local entry = catalog[name]
        local value = entry and entry[field]
        if type(value) == 'number' and value > best then best = value end
    end
    return best
end

---@param propertyId integer?
---@return number
function GetUpgradePowerBonus(propertyId)
    if not propertyId then return 0 end
    return highestOwned(propertyId, 'powerBonus')
end

---@param property table needs id and type
---@return number
function GetStashMultiplier(property)
    return GetPropertyType(property).stashMultiplier or 1.0
end

---@param property table needs id and type
---@return integer? limit nil means unlimited
function GetStashLimit(property)
    local base = sharedConfig.stashLimit
    if not base then return nil end
    return base + highestOwned(property.id, 'stashLimitBonus', property.type)
end

---@param propertyId integer
---@return integer? limit nil means unlimited
function GetKeyholderLimit(propertyId)
    local base = sharedConfig.keyholderLimit
    if not base then return nil end
    return base + highestOwned(propertyId, 'keyholderBonus')
end

---@param propertyId integer
---@return integer tier 0 when unsecured
function GetSecurityTier(propertyId)
    return highestOwned(propertyId, 'securityTier')
end

---@param propertyId integer
---@return integer extra spots on top of the standard one
function GetGarageSpotBonus(propertyId)
    return highestOwned(propertyId, 'garageSpots')
end

exports('HasPropertyUpgrade', function(propertyId, upgrade)
    propertyId = ToId(propertyId)
    if not propertyId or type(upgrade) ~= 'string' then return false end
    return GetPropertyUpgrades(propertyId)[upgrade] == true
end)

---@param garage any decoded garage column
---@return table[] points
function NormalizeGaragePoints(garage)
    if type(garage) ~= 'table' then return {} end
    if garage.x then return { garage } end
    return garage
end

lib.callback.register('qbx_properties:callback:getUpgrades', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return end

    local property = MySQL.single.await('SELECT id, owner, keyholders, building, type, group_name, garage FROM properties WHERE id = ?', {propertyId})
    if not property or not property.owner or property.building then return end
    if not HasPropertyAccess(player.PlayerData.citizenid, property, 'furniture') then return end

    local catalog = catalogFor(property.type)
    local owned = GetPropertyUpgrades(propertyId)
    local list = {}
    for name, entry in pairs(catalog) do
        list[#list + 1] = {
            name = name,
            label = entry.label,
            description = entry.description,
            price = entry.price,
            requires = entry.requires,
            owned = owned[name] == true,
            locked = entry.requires ~= nil and not owned[entry.requires],
        }
    end
    table.sort(list, function(a, b) return a.name < b.name end)

    local garagePoints = NormalizeGaragePoints(property.garage and json.decode(property.garage) or nil)

    return {
        upgrades = list,
        isOwner = property.owner == player.PlayerData.citizenid,
        garageSpots = #garagePoints,
        garageLimit = property.building == nil and (1 + GetGarageSpotBonus(propertyId)) or 0,
    }
end)

lib.callback.register('qbx_properties:callback:placeOwnGarage', function(source, propertyId, point)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId or type(point) ~= 'vector4' then return false end

    local property = MySQL.single.await('SELECT id, property_name, owner, building, coords, garage, type FROM properties WHERE id = ?', {propertyId})
    if not property or property.building or property.owner ~= player.PlayerData.citizenid then return false end

    local points = NormalizeGaragePoints(property.garage and json.decode(property.garage) or nil)
    if #points >= 1 + GetGarageSpotBonus(propertyId) then
        exports.qbx_core:Notify(source, 'No garage spots left, buy the garage upgrade.', 'error')
        return false
    end

    local coords = json.decode(property.coords)
    if #(vec3(coords.x, coords.y, coords.z) - vec3(point.x, point.y, point.z)) > 100.0 then return false end

    points[#points + 1] = { x = point.x, y = point.y, z = point.z, w = point.w }
    MySQL.update.await('UPDATE properties SET garage = ? WHERE id = ?', {json.encode(points), propertyId})
    RegisterPropertyGarage(propertyId, property.property_name, points)
    TriggerClientEvent('qbx_properties:client:refreshBlips', -1)

    LogAction(source, 'qbx_properties:server:placeOwnGarage', string.format('%s placed garage spot %d for property %d', player.PlayerData.citizenid, #points, propertyId))
    return true
end)

lib.callback.register('qbx_properties:callback:buyUpgrade', function(source, propertyId, name)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId or type(name) ~= 'string' then return false end

    local property = MySQL.single.await('SELECT id, property_name, owner, building, type FROM properties WHERE id = ?', {propertyId})
    if not property or property.building or property.owner ~= player.PlayerData.citizenid then return false end

    local entry = catalogFor(property.type)[name]
    if not entry then return false end

    local owned = GetPropertyUpgrades(propertyId)
    if owned[name] then return false end
    if entry.requires and not owned[entry.requires] then
        exports.qbx_core:Notify(source, 'This upgrade needs a previous tier first.', 'error')
        return false
    end

    if not player.Functions.RemoveMoney('bank', entry.price, string.format('%s upgrade for %s', entry.label, property.property_name)) then
        exports.qbx_core:Notify(source, 'Not enough money in your bank.', 'error')
        return false
    end

    MySQL.insert.await('INSERT IGNORE INTO properties_upgrades (property_id, upgrade) VALUES (?, ?)', {propertyId, name})
    InvalidateUpgradeCache(propertyId)

    if entry.powerBonus and RefreshUtilities then RefreshUtilities(propertyId) end

    exports.qbx_core:Notify(source, string.format('%s purchased.', entry.label), 'success')
    LogAction(source, 'qbx_properties:server:buyUpgrade', string.format('%s bought upgrade %s for property %d', player.PlayerData.citizenid, name, propertyId))

    return true
end)
