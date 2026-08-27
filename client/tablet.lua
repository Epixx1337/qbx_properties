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

local doorcamPoint
local activeDoorcam

local function pushDoorcam()
    if not CurrentPropertyId then return end
    local data = lib.callback.await('qbx_properties:callback:getDoorcamData', false)
    doorcamPoint = data and data.cam or nil
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
    })
    pushAccess()
    pushUtilities()
    pushUpgrades()
    pushRent()
    pushDoorcam()
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

RegisterNUICallback('tablet:showDoorcam', function(_, cb)
    cb(1)
    if not doorcamPoint then
        lib.notify({ type = 'error', description = 'There is no doorcam for this property.' })
        return
    end

    local position = vec3(doorcamPoint.x, doorcamPoint.y, doorcamPoint.z)
    local heading = doorcamPoint.w or 0.0

    if doorcamPoint.model then
        SetFocusPosAndVel(position.x, position.y, position.z, 0.0, 0.0, 0.0)
        local deadline = GetGameTimer() + 2000
        local entity = 0
        while entity == 0 and GetGameTimer() < deadline do
            entity = GetClosestObjectOfType(position.x, position.y, position.z, 2.0, doorcamPoint.model, false, false, false)
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

    SetUIFocus(false)
    SendUI('doorcam:view', true)

    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', position.x, position.y, position.z, -18.0, 0.0, heading, 75.0, false, 2)
    activeDoorcam = cam
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 400, true, true)
    SetFocusPosAndVel(position.x, position.y, position.z, 0.0, 0.0, 0.0)

    local deadline = GetGameTimer() + 60000
    while GetGameTimer() < deadline do
        Wait(0)
        DisableControlAction(0, 47, true)
        if IsDisabledControlJustPressed(0, 47) then break end
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

RegisterNetEvent('qbx_properties:client:tenancyRequest', function(data)
    local terms = data.contract
        and string.format('The contract runs for **%s payments**.', data.contract)
        or 'The lease is open-ended.'

    local confirm = lib.alertDialog({
        header = 'Lease offer',
        content = string.format('**%s** offers you **%s** for **$%s** every **%sh**, billed from your bank. %s The first payment is taken when you accept.', data.owner, data.property, data.rent, data.interval, terms),
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
