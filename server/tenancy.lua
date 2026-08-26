local tenantThreads = {}
local pendingTenancy = {}

---@param citizenId string
---@param amount integer
---@param reason string
local function payOut(citizenId, amount, reason)
    if amount <= 0 then return end
    local player = exports.qbx_core:GetPlayerByCitizenId(citizenId)
    if player then
        player.Functions.AddMoney('bank', amount, reason)
        return
    end

    local offline = exports.qbx_core:GetOfflinePlayer(citizenId)
    if not offline then return end
    offline.PlayerData.money.bank = offline.PlayerData.money.bank + amount
    exports.qbx_core:SaveOffline(offline.PlayerData)
end

---@param citizenId string
---@param amount integer
---@param reason string
---@return boolean
local function charge(citizenId, amount, reason)
    local player = exports.qbx_core:GetPlayerByCitizenId(citizenId)
    if player then
        return player.Functions.RemoveMoney('bank', amount, reason)
    end

    local offline = exports.qbx_core:GetOfflinePlayer(citizenId)
    if not offline or offline.PlayerData.money.bank < amount then return false end
    offline.PlayerData.money.bank = offline.PlayerData.money.bank - amount
    exports.qbx_core:SaveOffline(offline.PlayerData)
    return true
end

---@param citizenId string
---@param message string
local function notifyCitizen(citizenId, message)
    local player = exports.qbx_core:GetPlayerByCitizenId(citizenId)
    if player then
        exports.qbx_core:Notify(player.PlayerData.source, message, 'info', 8000)
    end
end

---@param propertyId integer
---@param property table needs property_name, owner, tenant
local function endTenancy(propertyId, property, reason)
    MySQL.update.await('UPDATE properties SET tenant = NULL, tenant_rent = NULL, tenant_interval = NULL, tenant_last_paid = NULL WHERE id = ?', {propertyId})
    RefreshCustomGarages()

    notifyCitizen(property.owner, string.format('The tenancy of %s ended (%s).', property.property_name, reason))
    if property.tenant then
        notifyCitizen(property.tenant, string.format('Your tenancy of %s ended (%s).', property.property_name, reason))
    end
end

function StartTenantThread(propertyId)
    if tenantThreads[propertyId] then return end
    tenantThreads[propertyId] = true

    CreateThread(function()
        while true do
            local property = MySQL.single.await('SELECT id, property_name, owner, tenant, tenant_rent, tenant_interval, UNIX_TIMESTAMP(tenant_last_paid) AS lastPaid FROM properties WHERE id = ?', {propertyId})
            if not property or not property.owner or not property.tenant or not property.tenant_rent then break end

            local due = (property.lastPaid or os.time()) + property.tenant_interval * 3600
            local remaining = due - os.time()
            if remaining > 0 then Wait(remaining * 1000) end

            property = MySQL.single.await('SELECT id, property_name, owner, tenant, tenant_rent, tenant_interval FROM properties WHERE id = ?', {propertyId})
            if not property or not property.owner or not property.tenant then break end

            local reason = string.format('Rent for %s', property.property_name)
            if not charge(property.tenant, property.tenant_rent, reason) then
                endTenancy(propertyId, property, 'missed rent')
                break
            end

            payOut(property.owner, property.tenant_rent, reason)
            notifyCitizen(property.tenant, string.format('You paid $%d rent for %s.', property.tenant_rent, property.property_name))
            MySQL.update.await('UPDATE properties SET tenant_last_paid = NOW() WHERE id = ?', {propertyId})
        end

        tenantThreads[propertyId] = nil
    end)
end

CreateThread(function()
    AwaitMigration()
    local rows = MySQL.query.await('SELECT id FROM properties WHERE tenant IS NOT NULL') or {}
    for i = 1, #rows do
        StartTenantThread(rows[i].id)
    end
end)

lib.callback.register('qbx_properties:callback:getTenancy', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return end

    local property = MySQL.single.await('SELECT id, property_name, owner, building, tenant, tenant_rent, tenant_interval, UNIX_TIMESTAMP(tenant_last_paid) AS lastPaid FROM properties WHERE id = ?', {propertyId})
    if not property or not property.owner or property.building then return end

    local citizenid = player.PlayerData.citizenid
    local role = property.owner == citizenid and 'owner' or property.tenant == citizenid and 'tenant' or nil
    if not role then return end

    local tenantName
    if property.tenant then
        local tenant = exports.qbx_core:GetPlayerByCitizenId(property.tenant) or exports.qbx_core:GetOfflinePlayer(property.tenant)
        local charinfo = tenant and tenant.PlayerData.charinfo
        tenantName = charinfo and ('%s %s'):format(charinfo.firstname, charinfo.lastname) or property.tenant
    end

    return {
        role = role,
        tenant = tenantName,
        rent = property.tenant_rent,
        interval = property.tenant_interval,
        nextDue = property.tenant and property.lastPaid and (property.lastPaid + property.tenant_interval * 3600) or nil,
    }
end)

lib.callback.register('qbx_properties:callback:rentOut', function(source, propertyId, targetCid, rent, interval)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    rent = ToId(rent)
    interval = ToId(interval)
    if not player or not propertyId or not rent or not interval or type(targetCid) ~= 'string' then return false end
    if rent < 1 or rent > 1000000 or interval < 1 or interval > 168 then return false end

    local property = MySQL.single.await('SELECT id, property_name, owner, building, tenant FROM properties WHERE id = ?', {propertyId})
    if not property or property.building or property.owner ~= player.PlayerData.citizenid then return false end
    if property.tenant then return false end
    if targetCid == property.owner then return false end

    local target = exports.qbx_core:GetPlayerByCitizenId(targetCid)
    if not target then
        exports.qbx_core:Notify(source, 'That player is not online.', 'error')
        return false
    end

    pendingTenancy[target.PlayerData.source] = {
        propertyId = propertyId,
        owner = property.owner,
        rent = rent,
        interval = interval,
        expires = os.time() + 60,
    }

    local charinfo = player.PlayerData.charinfo
    TriggerClientEvent('qbx_properties:client:tenancyRequest', target.PlayerData.source, {
        property = property.property_name,
        owner = ('%s %s'):format(charinfo.firstname, charinfo.lastname),
        rent = rent,
        interval = interval,
    })

    exports.qbx_core:Notify(source, 'Waiting for them to accept the lease.', 'info')
    return true
end)

RegisterNetEvent('qbx_properties:server:tenancyConfirm', function(accepted)
    local playerSource = source --[[@as number]]
    local pending = pendingTenancy[playerSource]
    pendingTenancy[playerSource] = nil
    if not pending or os.time() > pending.expires then return end

    local player = exports.qbx_core:GetPlayer(playerSource)
    if not player then return end

    if not accepted then
        notifyCitizen(pending.owner, 'They declined the lease.')
        return
    end

    local property = MySQL.single.await('SELECT id, property_name, owner, building, tenant FROM properties WHERE id = ?', {pending.propertyId})
    if not property or property.building or property.owner ~= pending.owner or property.tenant then return end

    MySQL.update.await('UPDATE properties SET tenant = ?, tenant_rent = ?, tenant_interval = ?, tenant_last_paid = NOW() WHERE id = ?',
        {player.PlayerData.citizenid, pending.rent, pending.interval, pending.propertyId})
    RefreshCustomGarages()
    StartTenantThread(pending.propertyId)

    notifyCitizen(pending.owner, string.format('%s is now renting %s.', player.PlayerData.charinfo.firstname, property.property_name))
    exports.qbx_core:Notify(playerSource, string.format('You are now renting %s for $%d every %dh.', property.property_name, pending.rent, pending.interval), 'success', 8000)

    lib.logger(playerSource, 'qbx_properties:server:tenancy', string.format('%s rents property %d from %s for $%d/%dh', player.PlayerData.citizenid, pending.propertyId, pending.owner, pending.rent, pending.interval))
end)

lib.callback.register('qbx_properties:callback:endTenancy', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return false end

    local property = MySQL.single.await('SELECT id, property_name, owner, building, tenant FROM properties WHERE id = ?', {propertyId})
    if not property or property.building or not property.tenant then return false end

    local citizenid = player.PlayerData.citizenid
    if property.owner ~= citizenid and property.tenant ~= citizenid then return false end

    endTenancy(propertyId, property, 'terminated')
    lib.logger(source, 'qbx_properties:server:endTenancy', string.format('%s ended the tenancy of property %d', citizenid, propertyId))
    return true
end)

AddEventHandler('playerDropped', function()
    pendingTenancy[source] = nil
end)
