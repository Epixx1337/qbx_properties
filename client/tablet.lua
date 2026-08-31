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

local function pushRent()
    if not CurrentPropertyId then return end
    SendUI('tablet:rent', lib.callback.await('qbx_properties:callback:getRentData', false, CurrentPropertyId))
end

local function pushMaintenance()
    if not CurrentPropertyId then return end
    SendUI('tablet:maintenance', lib.callback.await('qbx_properties:callback:getMaintenance', false, CurrentPropertyId))
end

local function pushLayouts()
    if not CurrentPropertyId then return end
    SendUI('tablet:layouts', lib.callback.await('qbx_properties:callback:getLayouts', false))
end

local function pushSaleAuth()
    if not CurrentPropertyId then return end
    SendUI('tablet:saleAuth', lib.callback.await('qbx_properties:callback:getSaleAuthorized', false, CurrentPropertyId))
end

local function pushTimecycle()
    if not CurrentPropertyId then return end
    SendUI('tablet:timecycle', lib.callback.await('qbx_properties:callback:getTimecycle', false, CurrentPropertyId))
end

local doorcamPoints = {}
local activeDoorcam
local doorcamClosing = false

RegisterNUICallback('doorcam:close', function(_, cb)
    cb(1)
    doorcamClosing = true
end)

local function pushDoorcam()
    if not CurrentPropertyId then return end
    local data = lib.callback.await('qbx_properties:callback:getDoorcamData', false)
    doorcamPoints = data and data.cams or {}
    SendUI('tablet:doorcam', data)
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
        timecycles = sharedConfig.timecycles,
        rentIntervals = sharedConfig.rentIntervals,
    })
    pushAccess()
    pushUtilities()
    pushUpgrades()
    pushRent()
    pushDoorcam()
    pushMaintenance()
    pushLayouts()
    pushSaleAuth()
    pushTimecycle()
end

RegisterNetEvent('qbx_properties:client:doorbellRang', function(propertyId)
    if CurrentPropertyId ~= propertyId then return end
    pushDoorcam()
end)

RegisterNUICallback('tablet:getDoorcam', function(_, cb)
    cb(1)
    pushDoorcam()
end)

RegisterNUICallback('tablet:letIn', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or type(data.citizenid) ~= 'string' or not CurrentPropertyId then return end

    TriggerServerEvent('qbx_properties:server:letRingerIn', data.citizenid)
    Wait(400)
    pushDoorcam()
end)

RegisterNUICallback('tablet:showDoorcam', function(data, cb)
    cb(1)
    local index = type(data) == 'table' and tonumber(data.index) or 1
    local point = doorcamPoints[index] or doorcamPoints[1]
    if not point then
        lib.notify({ type = 'error', description = 'There is no doorcam for this property.' })
        return
    end

    local position = vec3(point.x, point.y, point.z)
    local heading = point.w or 0.0
    local pitch = -18.0

    if point.custom then
        pitch = point.p or -12.0
    else
        if point.model then
            SetFocusPosAndVel(position.x, position.y, position.z, 0.0, 0.0, 0.0)
            local deadline = GetGameTimer() + 2000
            local entity = 0
            while entity == 0 and GetGameTimer() < deadline do
                entity = GetClosestObjectOfType(position.x, position.y, position.z, 2.0, point.model, false, false, false)
                if entity == 0 then Wait(50) end
            end

            if entity ~= 0 then
                local min, max = GetModelDimensions(GetEntityModel(entity))
                local center = GetOffsetFromEntityInWorldCoords(entity, (min.x + max.x) / 2, (min.y + max.y) / 2, (min.z + max.z) / 2)
                position = vec3(center.x, center.y, center.z)
                heading = GetEntityHeading(entity)
            end
        end

        position = position + vec3(0.0, 0.0, 0.2)
        heading = (heading + 180.0) % 360.0
    end

    SendUI('doorcam:view', true)
    doorcamClosing = false
    SetNuiFocus(true, false)
    SetNuiFocusKeepInput(false)

    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', position.x, position.y, position.z, pitch, 0.0, heading, 75.0, false, 2)
    activeDoorcam = cam
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 400, true, true)
    SetFocusPosAndVel(position.x, position.y, position.z, 0.0, 0.0, 0.0)

    local deadline = GetGameTimer() + 60000
    while GetGameTimer() < deadline and not doorcamClosing do
        Wait(0)
        DisableAllControlActions(0)
        HideHudAndRadarThisFrame()
    end

    SendUI('doorcam:view', false)
    RenderScriptCams(false, true, 400, true, true)
    DestroyCam(cam, false)
    activeDoorcam = nil
    ClearFocus()
    SetUIFocus(true)
    pushDoorcam()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    if not activeDoorcam then return end

    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(activeDoorcam, false)
    activeDoorcam = nil
    ClearFocus()
end)

RegisterNUICallback('tablet:rentOut', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not CurrentPropertyId then return end

    local ok = lib.callback.await('qbx_properties:callback:rentOut', false, CurrentPropertyId, data.citizenid, data.rent, data.interval, data.contract)
    if not ok then
        lib.notify({ type = 'error', description = 'Could not offer the lease.' })
    end
    pushRent()
end)

RegisterNUICallback('tablet:endTenancy', function(_, cb)
    cb(1)
    if not CurrentPropertyId then return end

    lib.callback.await('qbx_properties:callback:endTenancy', false, CurrentPropertyId)
    pushRent()
end)

RegisterNUICallback('tablet:payRent', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not CurrentPropertyId then return end

    local ok, err = lib.callback.await('qbx_properties:callback:payRent', false, CurrentPropertyId, data.periods)
    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and 'Rent paid.' or err or 'Could not pay the rent.',
    })
    pushRent()
end)

local function intervalLabel(hours)
    local sharedConfig = require 'config.shared'
    for i = 1, #(sharedConfig.rentIntervals or {}) do
        if sharedConfig.rentIntervals[i].value == hours then return sharedConfig.rentIntervals[i].label end
    end
    return string.format('%sh', hours)
end

RegisterNetEvent('qbx_properties:client:tenancyRequest', function(data)
    local terms = data.contract
        and string.format('The contract runs for **%s payments**.', data.contract)
        or 'The lease is open-ended.'

    local confirm = lib.alertDialog({
        header = 'Lease offer',
        content = string.format('**%s** offers you **%s** for **$%s** every **%s**, billed from your bank. %s The first payment is taken when you accept.', data.owner, data.property, data.rent, intervalLabel(data.interval), terms),
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
    pushTimecycle()

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

RegisterNUICallback('tablet:payMaintenance', function(_, cb)
    cb(1)
    if not CurrentPropertyId then return end

    TriggerServerEvent('qbx_properties:server:payMaintenance', CurrentPropertyId)
    Wait(500)
    pushMaintenance()
end)

RegisterNUICallback('tablet:saveLayout', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not CurrentPropertyId then return end

    local ok, err = lib.callback.await('qbx_properties:callback:saveLayout', false, data.name)
    if not ok then
        lib.notify({ type = 'error', description = err or 'Could not save the layout.' })
    else
        lib.notify({ type = 'success', description = 'Layout saved.' })
    end
    pushLayouts()
end)

RegisterNUICallback('tablet:applyLayout', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not CurrentPropertyId then return end

    local ok, err
    if data.code then
        ok, err = lib.callback.await('qbx_properties:callback:importLayout', false, data.code)
    else
        ok, err = lib.callback.await('qbx_properties:callback:applyLayout', false, data.id)
    end

    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and 'Layout applied.' or err or 'Could not apply the layout.',
    })
    pushLayouts()
end)

RegisterNUICallback('tablet:previewLayoutCode', function(data, cb)
    if type(data) ~= 'table' or not CurrentPropertyId then cb(false) return end
    cb(lib.callback.await('qbx_properties:callback:previewLayoutCode', false, data.code) or false)
end)

RegisterNUICallback('tablet:deleteLayout', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not CurrentPropertyId then return end

    lib.callback.await('qbx_properties:callback:deleteLayout', false, data.id)
    pushLayouts()
end)

RegisterNUICallback('tablet:setSaleAuth', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not CurrentPropertyId then return end

    local ok = lib.callback.await('qbx_properties:callback:setSaleAuthorized', false, CurrentPropertyId, data.enabled == true)
    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and (data.enabled and 'Realtors may now sell this property.' or 'Realtor sales revoked.') or 'Could not change the authorisation.',
    })
    pushSaleAuth()
end)

RegisterNUICallback('tablet:setJobAccess', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not CurrentPropertyId then return end

    data.propertyId = CurrentPropertyId
    local ok = lib.callback.await('qbx_properties:callback:setJobAccess', false, data)
    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and 'Job access updated.' or 'Could not update job access.',
    })
    pushAccess()
end)

RegisterNUICallback('tablet:setTimecycle', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not CurrentPropertyId then return end

    local ok = lib.callback.await('qbx_properties:callback:setTimecycle', false, CurrentPropertyId, data.value)
    if not ok then
        lib.notify({ type = 'error', description = 'Could not change the lighting.' })
    end
    pushTimecycle()
end)
