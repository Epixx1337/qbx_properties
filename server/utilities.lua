local config = require 'config.server'
local sharedConfig = require 'config.shared'
local utilities = sharedConfig.utilities

if not utilities.enabled then return end

---@param property table
---@return table
function GetUtilities(property)
    local row = MySQL.single.await('SELECT * FROM properties_utilities WHERE property_id = ?', {property.id})
    if not row then
        MySQL.insert.await('INSERT IGNORE INTO properties_utilities (property_id) VALUES (?)', {property.id})
        row = { property_id = property.id, power_used = 0, humidity = utilities.humidity.base, temperature = 21, powered = 1 }
    end
    return row
end

---@param propertyId integer
---@return table? state
function RefreshUtilities(propertyId)
    local property = MySQL.single.await('SELECT id, owner, building, power_limit FROM properties WHERE id = ?', {propertyId})
    if not property then return end

    local decorations = GetPropertyDecorations(property)
    local power, humidityOffset = CalculateUtilityLoad(decorations)

    local humidity = math.floor(utilities.humidity.base + power * utilities.humidity.perKilowatt + humidityOffset)
    humidity = math.max(0, math.min(utilities.humidity.max, humidity))

    local limit = GetPowerLimit(property)
    local state = GetUtilities(property)
    local powered = ToBool(state.powered) and power <= limit

    MySQL.update.await([[
        UPDATE properties_utilities SET power_used = ?, humidity = ?, powered = ? WHERE property_id = ?
    ]], {power, humidity, powered and 1 or 0, propertyId})

    TriggerClientEvent('qbx_properties:client:utilityState', -1, propertyId, {
        powered = powered,
        power = power,
        limit = limit,
        humidity = humidity,
    })

    return { powered = powered, power = power, limit = limit, humidity = humidity }
end

lib.callback.register('qbx_properties:callback:getUtilities', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return end

    local property = MySQL.single.await('SELECT id, owner, building, size, power_limit, UNIX_TIMESTAMP(utilities_paid_until) AS paidUntil FROM properties WHERE id = ?', {propertyId})
    if not property then return end
    if not HasPropertyAccess(player.PlayerData.citizenid, property, 'furniture') then return end

    local state = RefreshUtilities(propertyId)
    if not state then return end

    local cost = GetUtilityCost(property)

    return {
        power = state.power,
        limit = state.limit,
        humidity = state.humidity,
        powered = state.powered,
        cost = cost,
        free = cost == 0,
        size = property.building and 'Apartment' or GetPropertySize(property.size).label,
        paidUntil = property.paidUntil,
        overdue = cost > 0 and (not property.paidUntil or os.time() > property.paidUntil),
    }
end)

RegisterNetEvent('qbx_properties:server:payUtilities', function(propertyId)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return end

    local property = MySQL.single.await('SELECT id, owner, building, size, property_name FROM properties WHERE id = ?', {propertyId})
    if not property or property.owner ~= player.PlayerData.citizenid then return end

    local cost = GetUtilityCost(property)
    if cost <= 0 then return end

    local reason = string.format('Utilities for %s', property.property_name)
    if not player.Functions.RemoveMoney('bank', cost, reason) then
        exports.qbx_core:Notify(playerSource, 'Not enough money in your bank.', 'error')
        return
    end

    PayAccount(config.governmentAccount, cost, reason)

    MySQL.update.await([[
        UPDATE properties SET utilities_paid_until = DATE_ADD(GREATEST(COALESCE(utilities_paid_until, NOW()), NOW()), INTERVAL ? DAY) WHERE id = ?
    ]], {utilities.billingDays, propertyId})

    MySQL.update.await("UPDATE properties_utilities SET powered = 1, unpaid_since = NULL WHERE property_id = ?", {propertyId})
    RefreshUtilities(propertyId)

    exports.qbx_core:Notify(playerSource, 'Utilities paid.', 'success')

    lib.logger(playerSource, 'qbx_properties:server:payUtilities', string.format('%s paid utilities for %s', player.PlayerData.citizenid, property.property_name))
end)

lib.addCommand('power', {
    help = 'Toggle power for the property you are in',
    restricted = 'group.admin',
    params = {
        { name = 'state', type = 'string', help = 'on, off or blank to toggle', optional = true },
    },
}, function(source, args)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return end

    local propertyId = ToId(player.PlayerData.metadata.currentPropertyId)
    if not propertyId then
        exports.qbx_core:Notify(source, 'You are not inside a property.', 'error')
        return
    end

    local property = MySQL.single.await('SELECT id, owner, building, size, power_limit, property_name FROM properties WHERE id = ?', {propertyId})
    if not property then
        exports.qbx_core:Notify(source, 'That property no longer exists.', 'error')
        return
    end

    local state = GetUtilities(property)
    local powered
    if args.state == 'on' then
        powered = true
    elseif args.state == 'off' then
        powered = false
    else
        powered = state.powered ~= 1
    end

    MySQL.update.await('UPDATE properties_utilities SET powered = ? WHERE property_id = ?', {powered and 1 or 0, propertyId})
    TriggerClientEvent('qbx_properties:client:utilityState', -1, propertyId, { powered = powered })

    local decorations = GetPropertyDecorations(property)
    local draw, offset = CalculateUtilityLoad(decorations)
    local lights = 0
    local specs = GetFurnitureSpecs()
    for i = 1, #decorations do
        if specs[decorations[i].model] and specs[decorations[i].model].light then lights += 1 end
    end

    exports.qbx_core:Notify(source, string.format('%s power %s', property.property_name, powered and 'restored' or 'cut'), powered and 'success' or 'error')

    lib.print.info(string.format(
        '[qbx_properties] %s (id %d): powered=%s draw=%dW limit=%dW humidityOffset=%d lightProps=%d decorations=%d',
        property.property_name, propertyId, tostring(powered), draw, GetPowerLimit(property), offset, lights, #decorations
    ))
end)

local function processBilling()
    local overdue = MySQL.query.await([[
        SELECT id, owner, property_name FROM properties
        WHERE owner IS NOT NULL AND building IS NULL
          AND (utilities_paid_until IS NULL OR utilities_paid_until < DATE_SUB(NOW(), INTERVAL ? DAY))
    ]], {utilities.gracePeriodDays})

    for i = 1, #overdue do
        local property = overdue[i]

        MySQL.update.await([[
            INSERT INTO properties_utilities (property_id, powered, unpaid_since) VALUES (?, 0, NOW())
            ON DUPLICATE KEY UPDATE powered = 0, unpaid_since = COALESCE(unpaid_since, NOW())
        ]], {property.id})

        TriggerClientEvent('qbx_properties:client:utilityState', -1, property.id, { powered = false })

        local owner = exports.qbx_core:GetPlayerByCitizenId(property.owner)
        if owner then
            exports.qbx_core:Notify(owner.PlayerData.source, string.format('The power to %s has been cut off. Pay your utilities.', property.property_name), 'error')
        end
    end
end

lib.cron.new('0 * * * *', processBilling)
