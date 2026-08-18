local function pushAccess()
    if not CurrentPropertyId then return end
    SendUI('tablet:access', lib.callback.await('qbx_properties:callback:getAccessList', false, CurrentPropertyId))
end

local function pushUtilities()
    if not CurrentPropertyId then return end
    SendUI('tablet:utilities', lib.callback.await('qbx_properties:callback:getUtilities', false, CurrentPropertyId))
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
end

RegisterNUICallback('tablet:getAccess', function(_, cb)
    cb(1)
    pushAccess()
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
