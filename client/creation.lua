local sharedConfig = require 'config.shared'

local draft = nil

local function pushDraft()
    SendUI('creation:state', draft)
end

local function resetDraft()
    draft = nil
    SendUI('creation:state', nil)
end

---@param kind string 'shell' | 'mlo'
function StartPropertyCreation(kind, interior)
    local isShell = kind == 'shell' and (tonumber(interior) ~= nil or IsModelValid(joaat(interior)))
    local defaults = kind == 'shell' and lib.callback.await('qbx_properties:callback:getShellDefaults', false, tostring(interior)) or nil

    draft = {
        kind = kind,
        interior = interior,
        isShell = isShell,
        hasPoints = defaults ~= nil and defaults.exit ~= nil,
        entrance = nil,
        doors = {},
        garden = nil,
        garage = nil,
    }
    pushDraft()
end

function RefreshDraftPoints()
    if not draft or draft.kind ~= 'shell' then return end

    local defaults = lib.callback.await('qbx_properties:callback:getShellDefaults', false, tostring(draft.interior))
    draft.hasPoints = defaults ~= nil and defaults.exit ~= nil
    pushDraft()
end

RegisterNUICallback('creation:capturePoints', function(_, cb)
    cb(1)
    if not draft or draft.kind ~= 'shell' then return end

    CloseUI()
    StartShellPreview(tonumber(draft.interior) or draft.interior, 'create')
end)

RegisterNUICallback('creation:start', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end
    if data.kind ~= 'shell' and data.kind ~= 'mlo' then return end

    StartPropertyCreation(data.kind, data.interior)
end)

RegisterNUICallback('creation:captureInterior', function(_, cb)
    cb(1)
    if not draft or draft.kind ~= 'mlo' then return end

    if GetInteriorFromEntity(cache.ped) == 0 then
        lib.notify({ type = 'error', description = 'Stand inside the MLO first.' })
        return
    end

    local coords = GetEntityCoords(cache.ped)
    draft.entrance = { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(cache.ped) }
    lib.notify({ type = 'success', description = 'Interior point captured.' })
    pushDraft()
end)

RegisterNUICallback('creation:pickEntrance', function(_, cb)
    cb(1)
    if not draft then return end

    CloseUI()
    local coords, _, heading = PickWithLaser('Aim at the entrance and click to place it')

    if coords then
        draft.entrance = { x = coords.x, y = coords.y, z = coords.z, w = heading or 0.0 }
    end

    OpenUI('housing')
    SendUI('housing:tab', 'create')
    pushDraft()
end)

RegisterNUICallback('creation:pickDoor', function(data, cb)
    cb(1)
    if not draft then return end

    local double = type(data) == 'table' and data.double
    CloseUI()

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
        draft.doors[#draft.doors + 1] = { double = double or false, leaves = leaves }
    end

    OpenUI('housing')
    SendUI('housing:tab', 'create')
    pushDraft()
end)

RegisterNUICallback('creation:removeDoor', function(data, cb)
    cb(1)
    if not draft or type(data) ~= 'table' then return end

    local index = tonumber(data.index)
    if index and draft.doors[index] then table.remove(draft.doors, index) end
    pushDraft()
end)

RegisterNUICallback('creation:pickGarden', function(_, cb)
    cb(1)
    if not draft or not sharedConfig.gardens.enabled then return end

    CloseUI()
    local points, height = DrawZoneWithLaser('Aim and click to add a corner. Scroll to set the height', sharedConfig.gardens.maxPoints)

    if points then
        local zone = { points = {}, height = height }
        for i = 1, #points do
            zone.points[i] = { x = points[i].x, y = points[i].y, z = points[i].z }
        end
        draft.garden = zone
    end

    OpenUI('housing')
    SendUI('housing:tab', 'create')
    pushDraft()
end)

RegisterNUICallback('creation:pickGarage', function(_, cb)
    cb(1)
    if not draft then return end

    CloseUI()
    local coords = PlaceVehicleOnGround('sultanrs', 'Aim where cars should exit, scroll to rotate')

    if coords then
        draft.garage = { x = coords.x, y = coords.y, z = coords.z, w = coords.w }
    end

    OpenUI('housing')
    SendUI('housing:tab', 'create')
    pushDraft()
end)

RegisterNUICallback('creation:pickShellPosition', function(_, cb)
    cb(1)
    if not draft or draft.kind ~= 'shell' then return end

    CloseUI()
    local coords = PlaceModelWithGizmo(tonumber(draft.interior) or draft.interior, GetEntityCoords(cache.ped), 'Position the shell')

    if coords then
        draft.shell = { x = coords.x, y = coords.y, z = coords.z, w = coords.w }
    end

    OpenUI('housing')
    SendUI('housing:tab', 'create')
    pushDraft()
end)

RegisterNUICallback('creation:submit', function(data, cb)
    cb(1)
    if not draft or type(data) ~= 'table' then return end

    local created = lib.callback.await('qbx_properties:callback:createProperty', false, {
        kind = draft.kind,
        interior = draft.interior,
        name = data.name,
        price = data.price,
        rentInterval = data.rentInterval,
        size = data.size,
        isShell = draft.isShell,
        entrance = draft.entrance,
        shell = draft.shell,
        doors = draft.doors,
        garden = draft.garden,
        garage = draft.garage,
        listing = data.listing,
    })

    lib.notify({
        type = created and 'success' or 'error',
        description = created and 'Property created.' or 'Could not create the property.',
    })

    if created then
        resetDraft()
        SendUI('realtor:properties', RealtorProperties())
    end
end)

RegisterNUICallback('creation:cancel', function(_, cb)
    cb(1)
    resetDraft()
end)
