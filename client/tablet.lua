local function pushAccess()
    if not CurrentPropertyId then return end
    SendUI('tablet:access', lib.callback.await('qbx_properties:callback:getAccessList', false, CurrentPropertyId))
end

local function pushUtilities()
    if not CurrentPropertyId then return end
    SendUI('tablet:utilities', lib.callback.await('qbx_properties:callback:getUtilities', false, CurrentPropertyId))
end

local function pushUpgrades()
    if not CurrentPropertyId then return end
    SendUI('tablet:upgrades', lib.callback.await('qbx_properties:callback:getUpgrades', false, CurrentPropertyId))
end

local function pushTenancy()
    if not CurrentPropertyId then return end
    SendUI('tablet:tenancy', lib.callback.await('qbx_properties:callback:getTenancy', false, CurrentPropertyId))
end

local function placeOwnGarage()
    local propertyId = CurrentPropertyId
    CloseUI()
    local coords = PlaceVehicleOnGround('sultanrs', 'Aim where cars should exit, scroll to rotate')
    if not coords then return end

    local ok = lib.callback.await('qbx_properties:callback:placeOwnGarage', false, propertyId, coords)
    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and 'Garage placed.' or 'Could not place the garage there.',
    })
end

function OpenTablet()
    if not CurrentPropertyId then
        lib.notify({ type = 'error', description = 'No property detected here.' })
        return
    end

    local sharedConfig = require 'config.shared'

    OpenUI('tablet')
    SendUI('tablet:init', {
        propertyName = CurrentPropertyName or '',
        wallColors = sharedConfig.wallColors.enabled and sharedConfig.wallColors.palette or nil,
        wallColor = lib.callback.await('qbx_properties:callback:getWallColor', false, CurrentPropertyId),
    })
    pushAccess()
    pushUtilities()
    pushUpgrades()
    pushTenancy()
end

RegisterNUICallback('tablet:rentOut', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not CurrentPropertyId then return end

    local ok = lib.callback.await('qbx_properties:callback:rentOut', false, CurrentPropertyId, data.citizenid, data.rent, data.interval)
    if not ok then
        lib.notify({ type = 'error', description = 'Could not offer the lease.' })
    end
    pushTenancy()
end)

RegisterNUICallback('tablet:endTenancy', function(_, cb)
    cb(1)
    if not CurrentPropertyId then return end

    lib.callback.await('qbx_properties:callback:endTenancy', false, CurrentPropertyId)
    pushTenancy()
end)

RegisterNetEvent('qbx_properties:client:tenancyRequest', function(data)
    local confirm = lib.alertDialog({
        header = 'Lease offer',
        content = string.format('**%s** offers you **%s** for **$%s** every **%sh**, billed from your bank.', data.owner, data.property, data.rent, data.interval),
        centered = true,
        cancel = true,
    })
    TriggerServerEvent('qbx_properties:server:tenancyConfirm', confirm == 'confirm')
end)

RegisterNUICallback('tablet:getAccess', function(_, cb)
    cb(1)
    pushAccess()
end)

RegisterNUICallback('tablet:getUpgrades', function(_, cb)
    cb(1)
    pushUpgrades()
end)

RegisterNUICallback('tablet:buyUpgrade', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or type(data.name) ~= 'string' or not CurrentPropertyId then return end

    local ok = lib.callback.await('qbx_properties:callback:buyUpgrade', false, CurrentPropertyId, data.name)
    pushUpgrades()
    pushUtilities()

    if ok and data.name == 'garage' then
        placeOwnGarage()
    end
end)

RegisterNUICallback('tablet:placeGarage', function(_, cb)
    cb(1)
    if not CurrentPropertyId then return end
    placeOwnGarage()
end)

RegisterNUICallback('tablet:repairBreaker', function(_, cb)
    cb(1)
    if not CurrentPropertyId then return end

    local sharedConfig = require 'config.shared'
    SetUIFocus(false)
    local success = lib.skillCheck(sharedConfig.electricity and sharedConfig.electricity.repairSkillCheck or { 'medium', 'medium' })
    if success then
        lib.callback.await('qbx_properties:callback:repairBreaker', false, CurrentPropertyId)
    else
        lib.notify({ type = 'error', description = 'Sparks fly, try again.' })
    end
    SetUIFocus(true)
    pushUtilities()
end)

RegisterNUICallback('tablet:getUtilities', function(_, cb)
    cb(1)
    pushUtilities()
end)

RegisterNUICallback('tablet:getNearby', function(_, cb)
    cb(1)
    SendUI('tablet:nearby', lib.callback.await('qbx_properties:callback:getNearbyCitizens', false))
end)

RegisterNUICallback('tablet:setAccess', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not CurrentPropertyId then return end

    data.propertyId = CurrentPropertyId
    local ok = lib.callback.await('qbx_properties:callback:setAccess', false, data)

    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and 'Access updated.' or 'Could not update access.',
    })

    pushAccess()
end)

RegisterNUICallback('tablet:payUtilities', function(_, cb)
    cb(1)
    if not CurrentPropertyId then return end

    TriggerServerEvent('qbx_properties:server:payUtilities', CurrentPropertyId)
    Wait(500)
    pushUtilities()
end)
