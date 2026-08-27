local sharedConfig = require 'config.shared'

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
    MySQL.update.await('UPDATE properties SET tenant = NULL, tenant_rent = NULL, tenant_interval = NULL, tenant_last_paid = NULL, tenant_paid_until = NULL, tenant_contract_end = NULL, tenant_notice_end = NULL WHERE id = ?', {propertyId})
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
            local property = MySQL.single.await([[
                SELECT id, property_name, owner, tenant, tenant_rent, tenant_interval,
                       UNIX_TIMESTAMP(tenant_last_paid) AS lastPaid,
                       UNIX_TIMESTAMP(tenant_paid_until) AS paidUntil,
                       UNIX_TIMESTAMP(tenant_contract_end) AS contractEnd,
                       UNIX_TIMESTAMP(tenant_notice_end) AS noticeEnd
                FROM properties WHERE id = ?
            ]], {propertyId})
            if not property or not property.owner or not property.tenant or not property.tenant_rent then break end

            local now = os.time()

            if property.noticeEnd and now >= property.noticeEnd then
                endTenancy(propertyId, property, 'eviction notice expired')
                break
            end

            if property.contractEnd and now >= property.contractEnd then
                endTenancy(propertyId, property, 'contract ended')
                break
            end

            local paidUntil = property.paidUntil or ((property.lastPaid or now) + property.tenant_interval * 3600)

            if now < paidUntil then
                local waitUntil = paidUntil
                if property.contractEnd and property.contractEnd < waitUntil then waitUntil = property.contractEnd end
                if property.noticeEnd and property.noticeEnd < waitUntil then waitUntil = property.noticeEnd end
                Wait(math.max(waitUntil - now, 30) * 1000)
            else
                local reason = string.format('Rent for %s', property.property_name)
                if not charge(property.tenant, property.tenant_rent, reason) then
                    endTenancy(propertyId, property, 'missed rent')
                    break
                end

                payOut(property.owner, property.tenant_rent, reason)
                RecordPropertyPayment(propertyId, 'rent', property.tenant, property.tenant_rent)
                notifyCitizen(property.tenant, string.format('You paid $%d rent for %s.', property.tenant_rent, property.property_name))
                MySQL.update.await([[
                    UPDATE properties SET tenant_last_paid = NOW(),
                        tenant_paid_until = DATE_ADD(GREATEST(COALESCE(tenant_paid_until, NOW()), NOW()), INTERVAL tenant_interval HOUR)
                    WHERE id = ?
                ]], {propertyId})
            end
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

lib.callback.register('qbx_properties:callback:rentOut', function(source, propertyId, targetCid, rent, interval, contract)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    rent = ToId(rent)
    interval = ToId(interval)
    contract = ToId(contract)
    if not player or not propertyId or not rent or not interval or type(targetCid) ~= 'string' then return false end
    if rent < 1 or rent > 1000000 or interval < 1 or interval > 168 then return false end
    if contract and (contract < 1 or contract > 104) then contract = nil end

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
        contract = contract,
        expires = os.time() + 60,
    }

    local charinfo = player.PlayerData.charinfo
    TriggerClientEvent('qbx_properties:client:tenancyRequest', target.PlayerData.source, {
        property = property.property_name,
        owner = ('%s %s'):format(charinfo.firstname, charinfo.lastname),
        rent = rent,
        interval = interval,
        contract = contract,
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

    local citizenId = player.PlayerData.citizenid
    local reason = string.format('First rent for %s', property.property_name)

    if not charge(citizenId, pending.rent, reason) then
        exports.qbx_core:Notify(playerSource, 'You do not have enough money in the bank for the first payment.', 'error')
        notifyCitizen(pending.owner, 'The lease fell through — they could not afford the first payment.')
        return
    end

    payOut(pending.owner, pending.rent, reason)

    MySQL.update.await([[
        UPDATE properties SET tenant = ?, tenant_rent = ?, tenant_interval = ?, tenant_last_paid = NOW(),
            tenant_paid_until = DATE_ADD(NOW(), INTERVAL ? HOUR),
            tenant_contract_end = IF(? > 0, DATE_ADD(NOW(), INTERVAL ? HOUR), NULL)
        WHERE id = ?
    ]], {citizenId, pending.rent, pending.interval, pending.interval, pending.contract or 0, (pending.contract or 0) * pending.interval, pending.propertyId})

    RecordPropertyPayment(pending.propertyId, 'rent', citizenId, pending.rent)
    RefreshCustomGarages()
    StartTenantThread(pending.propertyId)

    notifyCitizen(pending.owner, string.format('%s is now renting %s — the first payment of $%d is in.', player.PlayerData.charinfo.firstname, property.property_name, pending.rent))
    exports.qbx_core:Notify(playerSource, string.format('You are now renting %s for $%d every %dh. The first payment was taken from your bank.', property.property_name, pending.rent, pending.interval), 'success', 8000)

    LogAction(playerSource, 'qbx_properties:server:tenancy', string.format('%s rents property %d from %s for $%d/%dh%s', citizenId, pending.propertyId, pending.owner, pending.rent, pending.interval, pending.contract and string.format(' (%d payments)', pending.contract) or ''))
end)

lib.callback.register('qbx_properties:callback:endTenancy', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return false end

    local property = MySQL.single.await('SELECT id, property_name, owner, building, tenant, UNIX_TIMESTAMP(tenant_notice_end) AS noticeEnd FROM properties WHERE id = ?', {propertyId})
    if not property or property.building or not property.tenant then return false end

    local citizenid = player.PlayerData.citizenid
    if property.owner ~= citizenid and property.tenant ~= citizenid then return false end

    if property.owner == citizenid then
        local noticeDays = ToId(sharedConfig.rentEvictionNoticeDays) or 0

        if property.noticeEnd then
            exports.qbx_core:Notify(source, 'The eviction notice has already been served.', 'error')
            return false
        end

        if noticeDays > 0 then
            MySQL.update.await('UPDATE properties SET tenant_notice_end = DATE_ADD(NOW(), INTERVAL ? DAY) WHERE id = ?', {noticeDays, propertyId})
            StartTenantThread(propertyId)

            local endDate = os.date('%x', os.time() + noticeDays * 86400)
            exports.qbx_core:Notify(source, string.format('Eviction notice served — the lease ends %s.', endDate), 'success')
            notifyCitizen(property.tenant, string.format('You received an eviction notice for %s. The lease ends %s.', property.property_name, endDate))

            LogAction(source, 'qbx_properties:server:evictionNotice', string.format('%s served an eviction notice on property %d (%d days)', citizenid, propertyId, noticeDays))
            return true
        end
    end

    endTenancy(propertyId, property, 'terminated')
    LogAction(source, 'qbx_properties:server:endTenancy', string.format('%s ended the tenancy of property %d', citizenid, propertyId))
    return true
end)

local RENT_COLUMNS <const> = [[
    SELECT id, property_name, owner, building, keyholders, type, group_name, tenant, tenant_rent, tenant_interval,
           UNIX_TIMESTAMP(tenant_paid_until) AS paidUntil,
           UNIX_TIMESTAMP(tenant_contract_end) AS contractEnd,
           UNIX_TIMESTAMP(tenant_notice_end) AS noticeEnd
    FROM properties WHERE id = ?
]]

---@param citizenId string
---@return string
local function citizenName(citizenId)
    local target = exports.qbx_core:GetPlayerByCitizenId(citizenId) or exports.qbx_core:GetOfflinePlayer(citizenId)
    local charinfo = target and target.PlayerData.charinfo
    return charinfo and ('%s %s'):format(charinfo.firstname, charinfo.lastname) or citizenId
end

lib.callback.register('qbx_properties:callback:getRentData', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return end

    local property = MySQL.single.await(RENT_COLUMNS, {propertyId})
    if not property or property.building or not property.owner then return end

    local citizenId = player.PlayerData.citizenid
    local isOwner = property.owner == citizenId
    local isTenant = property.tenant == citizenId
    local canPay = property.tenant ~= nil and (isTenant or HasPropertyAccess(citizenId, property, 'rent'))

    if not isOwner and not canPay then return end

    return {
        role = isOwner and 'owner' or isTenant and 'tenant' or 'roommate',
        tenant = property.tenant and citizenName(property.tenant) or nil,
        ownerName = citizenName(property.owner),
        rent = property.tenant_rent,
        interval = property.tenant_interval,
        paidUntil = property.paidUntil,
        contractEnd = property.contractEnd,
        noticeEnd = property.noticeEnd,
        noticeDays = ToId(sharedConfig.rentEvictionNoticeDays) or 0,
        canPay = canPay,
        history = GetPropertyPayments(propertyId, 'rent'),
    }
end)

lib.callback.register('qbx_properties:callback:payRent', function(source, propertyId, periods)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    periods = ToId(periods) or 1
    if not player or not propertyId then return false, 'Invalid request.' end
    if periods < 1 or periods > 12 then return false, 'Invalid amount of payments.' end

    local property = MySQL.single.await(RENT_COLUMNS, {propertyId})
    if not property or property.building or not property.tenant or not property.tenant_rent then return false, 'There is no active lease.' end

    local citizenId = player.PlayerData.citizenid
    if property.tenant ~= citizenId and not HasPropertyAccess(citizenId, property, 'rent') then
        return false, 'You are not allowed to pay the rent here.'
    end

    local now = os.time()
    local intervalSeconds = property.tenant_interval * 3600
    local base = math.max(property.paidUntil or now, now)

    if property.contractEnd then
        while periods > 0 and base + periods * intervalSeconds > property.contractEnd + 60 do
            periods -= 1
        end
        if periods < 1 then return false, 'The rent is already paid to the end of the contract.' end
    end

    local total = property.tenant_rent * periods
    local reason = string.format('Rent for %s', property.property_name)

    if not player.Functions.RemoveMoney('bank', total, reason) then
        return false, 'Not enough money in the bank.'
    end

    payOut(property.owner, total, reason)
    RecordPropertyPayment(propertyId, 'rent', citizenId, total)

    MySQL.update.await([[
        UPDATE properties SET tenant_last_paid = NOW(),
            tenant_paid_until = DATE_ADD(GREATEST(COALESCE(tenant_paid_until, NOW()), NOW()), INTERVAL ? HOUR)
        WHERE id = ?
    ]], {periods * property.tenant_interval, propertyId})

    notifyCitizen(property.owner, string.format('%s paid $%d rent for %s.', citizenName(citizenId), total, property.property_name))

    LogAction(source, 'qbx_properties:server:payRent', string.format('%s paid $%d rent (%d period(s)) for property %d', citizenId, total, periods, propertyId))

    return true
end)

AddEventHandler('playerDropped', function()
    pendingTenancy[source] = nil
end)
