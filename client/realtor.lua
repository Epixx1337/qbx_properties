local sharedConfig = require 'config.shared'

local playerCoords = vec3(0, 0, 0)

local function buildInteriorList()
    local interiors = {}
    for key in pairs(GetInteriorList()) do
        interiors[#interiors + 1] = {
            name = tostring(key),
            isShell = tonumber(key) ~= nil or IsModelValid(joaat(key)),
        }
    end
    table.sort(interiors, function(a, b) return a.name < b.name end)
    return interiors
end

local function buildingList()
    return lib.callback.await('qbx_properties:callback:getBuildings', false)
end

local propertiesQuery = { page = 1, search = '', filter = 'all' }

function RealtorProperties()
    return lib.callback.await('qbx_properties:callback:getRealtorProperties', false, propertiesQuery)
end

RegisterNUICallback('realtor:fetchProperties', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    local filter = data.filter
    if filter ~= 'free' and filter ~= 'owned' then filter = 'all' end

    propertiesQuery = {
        page = tonumber(data.page) or 1,
        search = type(data.search) == 'string' and data.search or '',
        filter = filter,
    }
    SendUI('realtor:properties', RealtorProperties())
end)

function SendRealtorData()
    playerCoords = GetEntityCoords(cache.ped)
    SendUI('realtor:init', {
        interiors = buildInteriorList(),
        buildings = buildingList(),
        properties = RealtorProperties(),
    })
end

RegisterNUICallback('realtor:preview', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    local interior = tonumber(data.interior) or data.interior
    if not GetInteriorPoints(interior) then return end

    CloseUI()
    StartShellPreview(interior)
end)

RegisterNUICallback('realtor:getUnits', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end
    SendUI('realtor:units', lib.callback.await('qbx_properties:callback:getBuildingUnits', false, data.building, data.floor))
end)

RegisterNUICallback('realtor:repossess', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    TriggerServerEvent('qbx_properties:server:repossess', data.propertyId)
    Wait(400)
    SendUI('realtor:properties', RealtorProperties())
end)

RegisterNUICallback('realtor:deleteProperty', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    TriggerServerEvent('qbx_properties:server:deleteProperty', data.propertyId)
    Wait(400)
    SendUI('realtor:properties', RealtorProperties())
end)

RegisterNUICallback('realtor:releaseUnit', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    TriggerServerEvent('qbx_properties:server:releaseUnit', data.propertyId)
    Wait(400)
    SendUI('realtor:units', lib.callback.await('qbx_properties:callback:getBuildingUnits', false, data.building, data.floor))
end)

RegisterNUICallback('realtor:createUnits', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    TriggerServerEvent('qbx_properties:server:createUnits', data.building, data.floor, data.price, data.rentInterval)
    Wait(500)
    SendUI('realtor:units', lib.callback.await('qbx_properties:callback:getBuildingUnits', false, data.building, data.floor))
    SendUI('realtor:properties', RealtorProperties())
end)

RegisterNUICallback('realtor:createListing', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    local created = lib.callback.await('qbx_properties:callback:createListing', false, data)
    lib.notify({
        type = created and 'success' or 'error',
        description = created and 'Listing created.' or 'Could not create the listing.',
    })

    SendUI('realtor:properties', RealtorProperties())
    SendUI('market:listings', lib.callback.await('qbx_properties:callback:getListings', false))
end)

RegisterNUICallback('realtor:placeShell', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    local propertyId = tonumber(data.propertyId)
    local model = tonumber(data.interior) or data.interior
    if not propertyId or not model then return end

    CloseUI()
    RemoveShellZone(propertyId)

    local coords = PlaceShell(model, GetEntityCoords(cache.ped))
    if not coords then return end

    if lib.callback.await('qbx_properties:callback:setShellCoords', false, propertyId, coords) then
        lib.notify({ type = 'success', description = 'Shell placed.' })
    else
        lib.notify({ type = 'error', description = 'Could not save the shell position.' })
    end
end)

RegisterNUICallback('realtor:details', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end
    SendUI('realtor:detailData', lib.callback.await('qbx_properties:callback:getPropertyDetails', false, data.propertyId))
end)

RegisterNUICallback('realtor:updateProperty', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    local ok = lib.callback.await('qbx_properties:callback:updateProperty', false, data.propertyId, data)
    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and 'Property updated.' or 'Could not update the property.',
    })

    SendUI('realtor:properties', RealtorProperties())
    SendUI('realtor:detailData', lib.callback.await('qbx_properties:callback:getPropertyDetails', false, data.propertyId))
end)

RegisterNUICallback('realtor:setMailbox', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    CloseUI()
    local coords, entity = PickWithLaser('Aim at the mailbox prop, or at the spot for one, and click')
    if not coords then return end

    local point = { x = coords.x, y = coords.y, z = coords.z }
    if entity and DoesEntityExist(entity) and GetEntityType(entity) == 3 then
        local entityCoords = GetEntityCoords(entity)
        point = { x = entityCoords.x, y = entityCoords.y, z = entityCoords.z, model = GetEntityModel(entity) }
    end

    local ok = lib.callback.await('qbx_properties:callback:setMailbox', false, data.propertyId, point)
    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and 'Mailbox set.' or 'Could not set the mailbox there.',
    })
end)

RegisterNUICallback('realtor:setDoorcam', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    CloseUI()
    local coords = PickWithLaser('Aim where the doorbell camera sits — above the door, facing out — and click')

    if coords then
        local eye = GetPedBoneCoords(cache.ped, 31086, 0.0, 0.0, 0.0)
        local direction = eye - coords
        local length = #direction

        if length > 0.2 then
            direction = direction / length
            local camPos = coords + direction * 0.15
            local heading = math.deg(math.atan(-direction.x, direction.y)) % 360.0
            local pitch = math.deg(math.asin(math.max(-1.0, math.min(1.0, direction.z))))

            local ok = lib.callback.await('qbx_properties:callback:setDoorcam', false, data.propertyId, {
                x = camPos.x, y = camPos.y, z = camPos.z, w = heading, p = pitch,
            })
            lib.notify({
                type = ok and 'success' or 'error',
                description = ok and 'Doorcam placed, looking back at where you stood.' or 'Could not place the doorcam there.',
            })
        else
            lib.notify({ type = 'error', description = 'Step back a little from the camera spot.' })
        end
    end

    OpenUI('housing')
    SendUI('housing:tab', 'manage')
    SendUI('realtor:detailData', lib.callback.await('qbx_properties:callback:getPropertyDetails', false, data.propertyId))
end)

RegisterNUICallback('realtor:clearDoorcam', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    local ok = lib.callback.await('qbx_properties:callback:clearDoorcam', false, data.propertyId)
    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and 'Doorcam removed, the automatic placement is back.' or 'Could not remove the doorcam.',
    })
    SendUI('realtor:detailData', lib.callback.await('qbx_properties:callback:getPropertyDetails', false, data.propertyId))
end)

RegisterNUICallback('realtor:editGarage', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    CloseUI()
    local coords = PlaceVehicleOnGround('sultanrs', 'Aim where cars should exit, scroll to rotate')

    if coords then
        local ok = lib.callback.await('qbx_properties:callback:updatePropertyZones', false, data.propertyId, {
            garage = { x = coords.x, y = coords.y, z = coords.z, w = coords.w },
        })
        lib.notify({
            type = ok and 'success' or 'error',
            description = ok and 'Garage updated.' or 'Could not update the garage.',
        })
    end

    OpenUI('housing')
    SendUI('housing:tab', 'manage')
end)

RegisterNUICallback('realtor:editGarden', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    local sharedConfig = require 'config.shared'

    CloseUI()
    local points, height = DrawZoneWithLaser('Aim and click to add a corner. Scroll to set the height', sharedConfig.gardens.maxPoints)

    if points then
        local zone = { points = {}, height = height }
        for i = 1, #points do
            zone.points[i] = { x = points[i].x, y = points[i].y, z = points[i].z }
        end

        local ok = lib.callback.await('qbx_properties:callback:updatePropertyZones', false, data.propertyId, { garden = zone })
        lib.notify({
            type = ok and 'success' or 'error',
            description = ok and 'Garden updated.' or 'Could not update the garden.',
        })
    end

    OpenUI('housing')
    SendUI('housing:tab', 'manage')
end)

local function framePhoto()
    SendUI('placement:show', { prompt = 'Frame the shot', photo = true })

    local snap, cancelled = false, false

    while not snap and not cancelled do
        Wait(0)

        HideHudAndRadarThisFrame()
        DisableControlAction(0, 200, true)
        DisableControlAction(0, 199, true)

        if IsControlJustReleased(0, 38) then snap = true end
        if IsControlJustReleased(0, 202) or IsDisabledControlJustReleased(0, 200) then cancelled = true end
    end

    return snap
end

RegisterNUICallback('realtor:addImage', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    CloseUI()

    if not framePhoto() then
        SendUI('placement:hide')
        OpenUI('housing')
        SendUI('housing:tab', 'manage')
        return
    end

    SendUI('placement:hide')

    local hiding = true
    CreateThread(function()
        while hiding do
            HideHudAndRadarThisFrame()
            Wait(0)
        end
    end)

    local ok, err = lib.callback.await('qbx_properties:callback:addPropertyImage', false, data.propertyId)
    hiding = false

    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and 'Photo added.' or (err or 'Could not take the photo.'),
    })

    OpenUI('housing')
    SendUI('housing:tab', 'manage')
    SendUI('realtor:detailData', lib.callback.await('qbx_properties:callback:getPropertyDetails', false, data.propertyId))
end)

RegisterNUICallback('realtor:removeImage', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    lib.callback.await('qbx_properties:callback:removePropertyImage', false, data.propertyId, data.index)
    SendUI('realtor:detailData', lib.callback.await('qbx_properties:callback:getPropertyDetails', false, data.propertyId))
end)

RegisterNUICallback('realtor:enterProperty', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    if CurrentPropertyId == data.propertyId then
        lib.notify({ type = 'inform', description = 'You are already inside this property.' })
        return
    end

    CloseUI()
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end
    TriggerServerEvent('qbx_properties:server:enterProperty', { id = data.propertyId, remote = true })

    SetTimeout(6000, function()
        if IsScreenFadedOut() then
            DoScreenFadeIn(500)
            lib.notify({ type = 'error', description = 'Could not enter the property.' })
        end
    end)
end)

RegisterNUICallback('realtor:recaptureInterior', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    CloseUI()
    SendUI('placement:show', { prompt = 'Walk inside the property, then press E to capture the spawn point', capture = true })

    local captured, cancelled = nil, false

    while not captured and not cancelled do
        Wait(0)

        DisableControlAction(0, 200, true)
        DisableControlAction(0, 199, true)

        if IsControlJustReleased(0, 38) then
            if GetInteriorFromEntity(cache.ped) == 0 then
                lib.notify({ type = 'error', description = 'Stand inside the MLO first.' })
            else
                captured = GetEntityCoords(cache.ped)
            end
        end

        if IsControlJustReleased(0, 202) or IsDisabledControlJustReleased(0, 200) then cancelled = true end
    end

    SendUI('placement:hide')

    if captured then
        local ok = lib.callback.await('qbx_properties:callback:recaptureInterior', false, data.propertyId, {
            x = captured.x, y = captured.y, z = captured.z,
        })
        lib.notify({
            type = ok and 'success' or 'error',
            description = ok and 'Interior point updated.' or 'Could not update the interior point.',
        })
    end

    OpenUI('housing')
    SendUI('housing:tab', 'manage')
    SendUI('realtor:detailData', lib.callback.await('qbx_properties:callback:getPropertyDetails', false, data.propertyId))
end)

RegisterNUICallback('realtor:addDoor', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    CloseUI()

    local double = data.double == true
    local leaves = {}
    local count = double and 2 or 1

    for i = 1, count do
        local prompt = double
            and string.format('Aim at door leaf %d of 2 and click', i)
            or 'Aim at the door and click'

        local coords, entity = PickWithLaser(prompt)
        if not coords or not entity or entity == 0 then break end

        leaves[#leaves + 1] = {
            model = GetEntityModel(entity),
            coords = { x = coords.x, y = coords.y, z = coords.z },
            heading = GetEntityHeading(entity),
        }
    end

    if #leaves == count then
        local ok = lib.callback.await('qbx_properties:callback:addPropertyDoor', false, data.propertyId, {
            double = double,
            leaves = leaves,
        })
        lib.notify({
            type = ok and 'success' or 'error',
            description = ok and 'Door added and locked.' or 'Could not add the door.',
        })
    end

    OpenUI('housing')
    SendUI('housing:tab', 'manage')
end)
