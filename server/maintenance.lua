local config = require 'config.server'
local sharedConfig = require 'config.shared'
local maintenance = sharedConfig.maintenance

local function touchActivity(citizenId)
    if not citizenId then return end
    MySQL.update('INSERT INTO properties_activity (citizenid, last_active) VALUES (?, NOW()) ON DUPLICATE KEY UPDATE last_active = NOW()', {citizenId})
end

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local player = exports.qbx_core:GetPlayer(source)
    if player then touchActivity(player.PlayerData.citizenid) end
end)

AddEventHandler('playerDropped', function()
    local player = exports.qbx_core:GetPlayer(source)
    if player then touchActivity(player.PlayerData.citizenid) end
end)

if not maintenance or not maintenance.enabled then return end

local apartmentInteriors = {}
for key, entry in pairs(Apartments) do
    if entry.type == 'interior' then apartmentInteriors[key] = true end
end

---@param property table needs price and interior
---@return boolean
local function subjectToMaintenance(property)
    return (property.price or 0) > 0 and not apartmentInteriors[property.interior]
end

---@param price integer
---@return integer
local function feeFor(price)
    return math.max(math.floor((price or 0) * (maintenance.percent or 0)), maintenance.minimum or 0)
end

---@param property table needs owner, price, property_name, id
---@return boolean
local function chargeFee(property)
    local fee = feeFor(property.price)
    if fee <= 0 then return true end

    local player = exports.qbx_core:GetPlayerByCitizenId(property.owner) or exports.qbx_core:GetOfflinePlayer(property.owner)
    if not player then return false end

    local reason = string.format('Maintenance for %s', property.property_name)

    if player.Offline then
        if player.PlayerData.money.bank < fee then return false end
        player.PlayerData.money.bank = player.PlayerData.money.bank - fee
        exports.qbx_core:SaveOffline(player.PlayerData)
    else
        if not player.Functions.RemoveMoney('bank', fee, reason) then return false end
        exports.qbx_core:Notify(player.PlayerData.source, string.format('The maintenance fee of $%d for %s was paid automatically.', fee, property.property_name))
    end

    PayAccount(config.governmentAccount, fee, reason)
    RecordPropertyPayment(property.id, 'maintenance', property.owner, fee)
    return true
end

local function processMaintenance()
    AwaitMigration()

    local candidates = MySQL.query.await([[
        SELECT id, interior, price FROM properties
        WHERE owner IS NOT NULL AND building IS NULL AND rent_interval IS NULL AND price > 0 AND maintenance_paid_until IS NULL
    ]]) or {}

    for i = 1, #candidates do
        if subjectToMaintenance(candidates[i]) then
            MySQL.update.await('UPDATE properties SET maintenance_paid_until = DATE_ADD(NOW(), INTERVAL ? DAY) WHERE id = ?', {maintenance.intervalDays, candidates[i].id})
        end
    end

    local due = MySQL.query.await([[
        SELECT id, owner, price, interior, property_name, UNIX_TIMESTAMP(maintenance_paid_until) AS paidUntil FROM properties
        WHERE owner IS NOT NULL AND building IS NULL AND rent_interval IS NULL AND maintenance_paid_until < NOW()
    ]]) or {}

    for i = 1, #due do
        local property = due[i]

        if not subjectToMaintenance(property) then
            MySQL.update.await('UPDATE properties SET maintenance_paid_until = NULL WHERE id = ?', {property.id})
        elseif chargeFee(property) then
            MySQL.update.await([[
                UPDATE properties SET maintenance_paid_until = DATE_ADD(GREATEST(maintenance_paid_until, DATE_SUB(NOW(), INTERVAL ? DAY)), INTERVAL ? DAY) WHERE id = ?
            ]], {maintenance.intervalDays, maintenance.intervalDays, property.id})
        else
            local seizeAfter = (maintenance.seizeAfterDays or 0) * 86400

            if seizeAfter > 0 and os.time() > property.paidUntil + seizeAfter then
                EvictProperty(property.id)

                local owner = exports.qbx_core:GetPlayerByCitizenId(property.owner)
                if owner then
                    owner.Functions.SetMetaData('currentPropertyId', nil)
                    exports.qbx_core:Notify(owner.PlayerData.source, string.format('%s was seized over unpaid maintenance.', property.property_name), 'error', 10000)
                end

                TriggerClientEvent('qbx_properties:client:refreshBlips', -1)
                LogAction(0, 'qbx_properties:server:maintenanceSeize', string.format('%s was seized from %s over unpaid maintenance', property.property_name, property.owner))
            else
                local owner = exports.qbx_core:GetPlayerByCitizenId(property.owner)
                if owner then
                    local graceDays = maintenance.seizeAfterDays or 0
                    exports.qbx_core:Notify(owner.PlayerData.source, graceDays > 0
                        and string.format('The maintenance fee for %s is overdue — pay within %d days of the due date or lose it.', property.property_name, graceDays)
                        or string.format('The maintenance fee for %s is overdue.', property.property_name), 'error', 10000)
                end
            end
        end
    end
end

lib.cron.new('30 * * * *', processMaintenance)

lib.callback.register('qbx_properties:callback:getMaintenance', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return end

    local property = MySQL.single.await('SELECT id, owner, keyholders, building, type, group_name, tenant, price, interior, rent_interval, UNIX_TIMESTAMP(maintenance_paid_until) AS paidUntil FROM properties WHERE id = ?', {propertyId})
    if not property or not property.owner or property.building or property.rent_interval then return end
    if not subjectToMaintenance(property) then return end
    if not HasPropertyAccess(player.PlayerData.citizenid, property, 'utilities') then return end

    return {
        fee = feeFor(property.price),
        intervalDays = maintenance.intervalDays,
        paidUntil = property.paidUntil,
        overdue = property.paidUntil ~= nil and os.time() > property.paidUntil,
        seizeDays = maintenance.seizeAfterDays or 0,
        history = GetPropertyPayments(propertyId, 'maintenance'),
    }
end)

RegisterNetEvent('qbx_properties:server:payMaintenance', function(propertyId)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return end

    local property = MySQL.single.await('SELECT id, owner, keyholders, building, type, group_name, tenant, price, interior, property_name, rent_interval FROM properties WHERE id = ?', {propertyId})
    if not property or not property.owner or property.building or property.rent_interval then return end
    if not subjectToMaintenance(property) then return end

    local citizenId = player.PlayerData.citizenid
    if not HasPropertyAccess(citizenId, property, 'utilities') then return end

    local fee = feeFor(property.price)
    if fee <= 0 then return end

    local reason = string.format('Maintenance for %s', property.property_name)
    if not player.Functions.RemoveMoney('bank', fee, reason) then
        exports.qbx_core:Notify(playerSource, 'Not enough money in your bank.', 'error')
        return
    end

    PayAccount(config.governmentAccount, fee, reason)
    RecordPropertyPayment(propertyId, 'maintenance', citizenId, fee)

    MySQL.update.await([[
        UPDATE properties SET maintenance_paid_until = DATE_ADD(GREATEST(COALESCE(maintenance_paid_until, NOW()), NOW()), INTERVAL ? DAY) WHERE id = ?
    ]], {maintenance.intervalDays, propertyId})

    if property.owner ~= citizenId then
        local owner = exports.qbx_core:GetPlayerByCitizenId(property.owner)
        if owner then
            exports.qbx_core:Notify(owner.PlayerData.source, string.format('The maintenance fee for %s was paid.', property.property_name), 'success')
        end
    end

    exports.qbx_core:Notify(playerSource, 'Maintenance paid.', 'success')
    LogAction(playerSource, 'qbx_properties:server:payMaintenance', string.format('%s paid $%d maintenance for %s', citizenId, fee, property.property_name))
end)
