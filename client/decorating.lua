IsDecorating = false
local sharedConfig = require 'config.shared'
CurrentPropertyName = ''
local config = require 'config.client'
local camera
local previewObject
local pendingObject
local cursorMode = false
local currentlySelected
local IsDisabledControlPressed = IsDisabledControlPressed
local SetCamCoord = SetCamCoord
local SetCamRot = SetCamRot
local GetCamCoord = GetCamCoord
local GetCamRot = GetCamRot
local GetHashKey = GetHashKey

local freecamMoving = false

function IsFreecamActive()
    return camera ~= nil
end

function IsFreecamMoving()
    return freecamMoving
end

function GetDecoratingCam()
    if camera then
        return GetCamCoord(camera), GetCamRot(camera, 2)
    end
    return GetGameplayCamCoord(), GetGameplayCamRot(2)
end

local function ensureFreecam()
    if camera then return end

    local cameraPosition = GetGameplayCamCoord()
    local cameraRotation = GetGameplayCamRot(2)
    camera = CreateCameraWithParams('DEFAULT_SCRIPTED_CAMERA', cameraPosition.x, cameraPosition.y, cameraPosition.z, cameraRotation.x, cameraRotation.y, cameraRotation.z, GetGameplayCamFov(), true, 2)
    RenderScriptCams(true, true, 500, true, true)

    CreateThread(function()
        local multiplier = 0.1
        while camera and IsDecorating do
            if freecamMoving and not IsUIFocused() then
                cameraPosition = GetCamCoord(camera)
                cameraRotation = GetCamRot(camera, 2)
                local forwardX = -math.sin(math.rad(cameraRotation.z))
                local forwardY = math.cos(math.rad(cameraRotation.z))
                local rightX = math.cos(math.rad(cameraRotation.z))
                local rightY = math.sin(math.rad(cameraRotation.z))
                local upwardZ = math.sin(math.rad(cameraRotation.x))
                if IsDisabledControlPressed(0, 241) then multiplier = multiplier + 0.01 end
                if IsDisabledControlPressed(0, 242) then multiplier = multiplier - 0.01 end
                if multiplier < 0.01 then multiplier = 0.001 end
                if multiplier > 1.0 then multiplier = 1.0 end
                if IsDisabledControlPressed(0, 32) then
                    cameraPosition = cameraPosition + vector3(forwardX * multiplier, forwardY * multiplier, upwardZ * multiplier)
                end
                if IsDisabledControlPressed(0, 33) then
                    cameraPosition = cameraPosition - vector3(forwardX * multiplier, forwardY * multiplier, upwardZ * multiplier)
                end
                if IsDisabledControlPressed(0, 34) then
                    cameraPosition = cameraPosition - vector3(rightX * multiplier, rightY * multiplier, 0)
                end
                if IsDisabledControlPressed(0, 35) then
                    cameraPosition = cameraPosition + vector3(rightX * multiplier, rightY * multiplier, 0)
                end
                if IsDisabledControlPressed(0, 36) then
                    cameraPosition = cameraPosition - vector3(0, 0, multiplier)
                end
                if IsDisabledControlPressed(0, 203) then
                    cameraPosition = cameraPosition + vector3(0, 0, multiplier)
                end
                cameraRotation = cameraRotation - vector3(GetDisabledControlNormal(0, 272) * 5, 0, GetDisabledControlNormal(0, 270) * 5)

                local anchor = GetEntityCoords(cache.ped)
                local offset = cameraPosition - anchor
                local range = sharedConfig.freecamRange
                if #(offset) > range then
                    cameraPosition = anchor + offset / #(offset) * range
                end

                SetCamCoord(camera, cameraPosition.x, cameraPosition.y, cameraPosition.z)
                SetCamRot(camera, math.min(math.max(cameraRotation.x, -89), 89), cameraRotation.y, cameraRotation.z, 2)
            end
            Wait(0)
        end
    end)
end

local function destroyFreecam()
    freecamMoving = false
    if not camera then return end
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(camera, false)
    camera = nil
end

function ToggleFreecam()
    if not IsDecorating then return end

    ensureFreecam()
    freecamMoving = not freecamMoving
    if freecamMoving then
        SetCursorMode(false)
        SetUIFocus(false)
    else
        SetCursorMode(previewObject ~= nil)
        SetUIFocus(true, previewObject ~= nil)
    end
    PushDecoratingState()
end

local lastMatrix
local furnitureLabels
local currentTint = 0
local lastTransformPush = 0

---@param value boolean
function SetCursorMode(value)
    if cursorMode == value then return end
    cursorMode = value

    if value then
        EnterCursorMode()
    else
        LeaveCursorMode()
    end
end

function HasPreviewObject()
    return previewObject ~= nil
end

function IsCursorMode()
    return cursorMode
end

local function discardPending()
    if pendingObject and DoesEntityExist(pendingObject) then
        DeleteEntity(pendingObject)
    end
    pendingObject = nil
end

local function clearOutline()
    if previewObject and DoesEntityExist(previewObject) then
        SetEntityDrawOutline(previewObject, false)
    end
end

local function labelFor(model)
    if not furnitureLabels then
        furnitureLabels = {}
        for _, category in pairs(config.furniture) do
            for i = 1, #category do
                furnitureLabels[category[i].object] = category[i].label
            end
        end
    end
    return furnitureLabels[model] or (GetFurnitureSpecs()[model] or {}).label or model
end

CreateThread(function()
    Wait(2000)

    local invalid = {}
    for _, category in pairs(config.furniture) do
        for i = 1, #category do
            if not IsModelValid(GetHashKey(category[i].object)) then
                invalid[#invalid + 1] = category[i].object
            end
        end
    end

    if #invalid > 0 then
        lib.print.warn(('%d furniture model(s) do not exist and will be skipped: %s'):format(#invalid, table.concat(invalid, ', ')))
    end
end)

local cart = {}

local function pushCart()
    local items, total = {}, 0
    for i = 1, #cart do
        items[i] = { label = cart[i].label, price = cart[i].price, model = cart[i].model }
        total += cart[i].price
    end
    SendUI('furniture:cart', { items = items, total = total })
end

local function effectivePrice(model, spec)
    if not spec or (spec.price or 0) <= 0 then return 0 end

    if spec.firstFree then
        local types = GetFurnitureTypes()
        local group = spec.type

        for _, placedModel in pairs(PlacedDecorations) do
            if placedModel == model or (group and types[placedModel] == group) then return spec.price end
        end
        for i = 1, #cart do
            local entryModel = cart[i].model
            if entryModel == model or (group and types[entryModel] == group) then return spec.price end
        end
        return 0
    end

    return spec.price
end

local savedCarts = {}

local function cartContextKey()
    if CurrentPropertyId then return 'p' .. tostring(CurrentPropertyId) end
    if CurrentGardenId then return 'g' .. tostring(CurrentGardenId) end
end

local function saveCartSnapshot()
    local key = cartContextKey()
    if not key or #cart == 0 then return end

    local snapshot = {}
    for i = 1, #cart do
        local entry = cart[i]
        if DoesEntityExist(entry.entity) then
            local coords = GetEntityCoords(entry.entity)
            local rotation = GetEntityRotation(entry.entity, 2)
            snapshot[#snapshot + 1] = {
                model = entry.model,
                label = entry.label,
                price = entry.price,
                tint = entry.tint,
                coords = coords,
                rotation = rotation,
            }
            DeleteEntity(entry.entity)
        end
    end

    cart = {}
    savedCarts[key] = #snapshot > 0 and snapshot or nil
    lib.notify({ type = 'info', description = 'Your cart was set aside for next time.' })
end

local function restoreCartSnapshot(snapshot)
    for i = 1, #snapshot do
        local entry = snapshot[i]
        local hash = lib.requestModel(entry.model, 60000)
        if hash then
            local entity = CreateObjectNoOffset(hash, entry.coords.x, entry.coords.y, entry.coords.z, false, false, false)
            SetEntityRotation(entity, entry.rotation.x, entry.rotation.y, entry.rotation.z, 2, false)
            FreezeEntityPosition(entity, true)
            SetEntityCollision(entity, false, false)
            SetModelAsNoLongerNeeded(hash)
            if entry.tint then SetObjectTextureVariation(entity, entry.tint) end

            cart[#cart + 1] = {
                entity = entity,
                model = entry.model,
                label = entry.label,
                price = entry.price,
                tint = entry.tint,
            }
        end
    end
end

local function discardCart(silent)
    for i = 1, #cart do
        if DoesEntityExist(cart[i].entity) then DeleteEntity(cart[i].entity) end
    end
    if #cart > 0 and not silent then
        lib.notify({ type = 'info', description = 'Unpurchased furniture was discarded.' })
    end
    cart = {}
    pushCart()
end

function PushPlacedDecorations()
    local placed = {}
    for id, model in pairs(PlacedDecorations) do
        local item = DecorationItems[id]
        local image = (GetFurnitureSpecs()[model] or {}).image
            or (item and ('nui://ox_inventory/web/images/%s.png'):format(item))
        placed[#placed + 1] = { id = id, model = model, label = labelFor(model), image = image }
    end
    table.sort(placed, function(a, b) return a.label < b.label end)
    SendUI('furniture:placed', placed)
end

local function currentObjectId()
    if not previewObject or not DoesEntityExist(previewObject) then return end
    for id, entity in pairs(DecorationObjects) do
        if entity == previewObject then return id end
    end
end

---@param id integer
function SelectPlacedDecoration(id)
    local entity = DecorationObjects[id]
    if not IsDecorating or not entity or not DoesEntityExist(entity) then return end

    clearOutline()
    discardPending()
    previewObject = entity
    lastMatrix = MakeGizmoMatrix(entity)
    currentlySelected = nil
    currentTint = DecorationTints[id] or 0
    SetEntityDrawOutline(entity, true)
    SetCursorMode(true)
    SetUIFocus(true, true)
    PushDecoratingState()
end

---@param id integer
function ClonePlacedDecoration(id)
    local entity = DecorationObjects[id]
    if not IsDecorating or not entity or not DoesEntityExist(entity) or DecorationItems[id] then return end

    local model = PlacedDecorations[id]
    if not IsModelValid(GetHashKey(model)) then return end
    local hash = lib.requestModel(model, 60000)
    if not hash then return end

    clearOutline()
    discardPending()

    local coords = GetEntityCoords(entity)
    local rotation = GetEntityRotation(entity, 2)

    previewObject = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityRotation(previewObject, rotation.x, rotation.y, rotation.z, 2, false)
    FreezeEntityPosition(previewObject, true)
    SetEntityCollision(previewObject, false, false)
    SetEntityDrawOutline(previewObject, true)
    SetModelAsNoLongerNeeded(hash)

    pendingObject = previewObject
    lastMatrix = nil
    currentlySelected = { object = model, label = labelFor(model) }
    currentTint = DecorationTints[id] or 0
    if currentTint > 0 then SetObjectTextureVariation(previewObject, currentTint) end
    SetCursorMode(true)
    SetUIFocus(true, true)
    PushDecoratingState()
end

---@return number
function DecorationAtCursor()
    local _, _, endCoords = lib.raycast.fromCamera(1 + 16, 4, 30.0)
    if not endCoords then return 0 end

    local best, bestDist = 0, 1.2
    for _, entity in pairs(DecorationObjects) do
        if DoesEntityExist(entity) then
            local dist = #(GetEntityCoords(entity) - endCoords)
            if dist < bestDist then best, bestDist = entity, dist end
        end
    end

    return best
end

function SnapToWall()
    if not previewObject or not DoesEntityExist(previewObject) then return end

    local coords = GetEntityCoords(previewObject)
    local forward = GetEntityForwardVector(previewObject)
    local right = vec3(forward.y, -forward.x, 0.0)
    local min, max = GetModelDimensions(GetEntityModel(previewObject))
    local halfDepth = (max.y - min.y) / 2
    local halfWidth = (max.x - min.x) / 2
    local center = GetOffsetFromEntityInWorldCoords(previewObject, (min.x + max.x) / 2, (min.y + max.y) / 2, (min.z + max.z) / 2)

    local probes = {
        { dir = forward, offset = halfDepth },
        { dir = -forward, offset = halfDepth },
        { dir = right, offset = halfWidth },
        { dir = -right, offset = halfWidth },
    }

    local best
    for i = 1, #probes do
        local dir = probes[i].dir
        local handle = StartShapeTestLosProbe(center.x, center.y, center.z, center.x + dir.x * 6.0, center.y + dir.y * 6.0, center.z + dir.z * 6.0, 1 + 16, previewObject, 4)
        local status, hit, endCoords = GetShapeTestResult(handle)
        local tries = 0
        while status == 1 and tries < 30 do
            Wait(0)
            tries += 1
            status, hit, endCoords = GetShapeTestResult(handle)
        end

        if status == 2 and (hit == true or hit == 1) then
            local dist = #(endCoords - center)
            if not best or dist < best.dist then
                best = { dist = dist, dir = dir, offset = probes[i].offset, endCoords = endCoords }
            end
        end
    end

    if not best then
        lib.notify({ type = 'error', description = 'No wall near this object.' })
        return
    end

    SetEntityCoords(previewObject, best.endCoords.x - best.dir.x * best.offset, best.endCoords.y - best.dir.y * best.offset, coords.z, false, false, false, false)
end

function ConfirmDecoration()
    if not previewObject or not DoesEntityExist(previewObject) then return end

    local objectId = currentObjectId()
    local model = objectId and GetEntityArchetypeName(previewObject) or currentlySelected and currentlySelected.object
    if not model then return end

    if not objectId then
        local spec = GetFurnitureSpecs()[model]
        local price = effectivePrice(model, spec)
        if price > 0 then
            cart[#cart + 1] = {
                entity = previewObject,
                model = model,
                label = spec.label or model,
                price = price,
                tint = currentTint > 0 and currentTint or nil,
            }
            SetEntityDrawOutline(previewObject, false)
            pendingObject = nil
            previewObject = nil
            currentlySelected = nil
            lastMatrix = nil
            SetCursorMode(false)
            SetUIFocus(true)
            PushDecoratingState()
            pushCart()
            lib.notify({ type = 'info', description = 'Added to the cart. Pay in the furniture menu to keep it.' })
            return
        end
    end

    local event = CurrentGardenId and not CurrentPropertyId and 'qbx_properties:server:addGardenDecoration' or 'qbx_properties:server:addDecoration'
    TriggerServerEvent(event, model, GetEntityCoords(previewObject), GetEntityRotation(previewObject, 2), objectId, currentTint > 0 and currentTint or nil)
    if objectId then
        SetEntityDrawOutline(previewObject, false)
    else
        DeleteEntity(previewObject)
    end
    pendingObject = nil
    previewObject = nil
    currentlySelected = nil
    lastMatrix = nil
    SetCursorMode(false)
    SetUIFocus(true)
    PushDecoratingState()
end

function RemoveSelectedDecoration()
    local objectId = currentObjectId()
    if not objectId then return end

    clearOutline()

    local event = CurrentGardenId and not CurrentPropertyId and 'qbx_properties:server:removeGardenDecoration' or 'qbx_properties:server:removeDecoration'
    TriggerServerEvent(event, objectId)
    discardPending()
    previewObject = nil
    currentlySelected = nil
    lastMatrix = nil
    PushDecoratingState()
end

function CancelDecoration()
    clearOutline()
    if previewObject and previewObject ~= pendingObject and DoesEntityExist(previewObject) and lastMatrix then
        ApplyGizmoMatrix(previewObject, lastMatrix)
        local objectId = currentObjectId()
        SetObjectTextureVariation(previewObject, objectId and DecorationTints[objectId] or 0)
        if objectId then
            TriggerServerEvent('qbx_properties:server:decorationMoving', objectId, GetEntityCoords(previewObject), GetEntityRotation(previewObject, 2))
        end
    end

    discardPending()
    previewObject = nil
    currentlySelected = nil
    lastMatrix = nil
    SetCursorMode(false)
    SetUIFocus(true)
    PushDecoratingState()
end

local function snapAxis(value, step)
    if step < 0.05 then return 0.0 end
    return math.floor(value / step + 0.5) * step
end

function SnapToNeighbor()
    if not previewObject or not DoesEntityExist(previewObject) then return end

    local specs = GetFurnitureSpecs()
    local myModel = GetEntityModel(previewObject)
    local myName = GetEntityArchetypeName(previewObject)
    local mySpec = specs[myName] or {}
    local myPos = GetEntityCoords(previewObject)

    -- doors seat into the nearest arch and stay freely movable afterwards
    local wantsArch = mySpec.type == 'door'

    local best, bestDist, bestSame
    for _, entity in pairs(DecorationObjects) do
        if entity ~= previewObject and DoesEntityExist(entity) then
            local theirName = GetEntityArchetypeName(entity)
            local theirSpec = specs[theirName] or {}
            local sameModel = GetEntityModel(entity) == myModel

            local eligible
            if wantsArch then
                eligible = theirSpec.snapGroup == 'arch'
            elseif mySpec.snapGroup then
                eligible = sameModel or theirSpec.snapGroup ~= nil
            else
                eligible = sameModel
            end

            if eligible then
                local dist = #(GetEntityCoords(entity) - myPos)
                if dist < 8.0 and (not bestDist or dist < bestDist) then
                    best, bestDist, bestSame = entity, dist, sameModel
                end
            end
        end
    end

    if not best then
        lib.notify({ type = 'error', description = 'No matching piece nearby to snap to.' })
        return
    end

    local rotation = GetEntityRotation(best, 2)

    if wantsArch then
        local archPos = GetEntityCoords(best)
        SetEntityCoordsNoOffset(previewObject, archPos.x, archPos.y, archPos.z, false, false, false)
        SetEntityRotation(previewObject, rotation.x, rotation.y, rotation.z, 2, false)
        return
    end

    local myMin, myMax = GetModelDimensions(myModel)
    local mySize = myMax - myMin
    local theirMin, theirMax = GetModelDimensions(GetEntityModel(best))
    local theirSize = theirMax - theirMin
    local off = GetOffsetFromEntityGivenWorldCoords(best, myPos.x, myPos.y, myPos.z)

    local sx, sy, sz

    if bestSame then
        sx = snapAxis(off.x, theirSize.x)
        sy = snapAxis(off.y, theirSize.y)
        sz = snapAxis(off.z, theirSize.z)

        if sx == 0.0 and sy == 0.0 and sz == 0.0 then
            if math.abs(off.x) >= math.abs(off.y) then
                sx = (off.x >= 0 and 1 or -1) * theirSize.x
            else
                sy = (off.y >= 0 and 1 or -1) * theirSize.y
            end
        end
    else
        -- different pieces butt edge to edge along the dominant axis
        if math.abs(off.x) >= math.abs(off.y) then
            sx = (off.x >= 0 and 1 or -1) * (theirSize.x + mySize.x) / 2
            sy = snapAxis(off.y, theirSize.y)
        else
            sy = (off.y >= 0 and 1 or -1) * (theirSize.y + mySize.y) / 2
            sx = snapAxis(off.x, theirSize.x)
        end
        sz = snapAxis(off.z, theirSize.z)
    end

    local target = GetOffsetFromEntityInWorldCoords(best, sx, sy, sz)
    SetEntityCoordsNoOffset(previewObject, target.x, target.y, target.z, false, false, false)
    SetEntityRotation(previewObject, rotation.x, rotation.y, rotation.z, 2, false)
end

function PushDecoratingState()
    local objectId = currentObjectId()
    local placing = previewObject ~= nil and DoesEntityExist(previewObject)

    if not placing then SendUI('gizmo:sync', nil) end

    SendUI('furniture:state', {
        placing = placing,
        worldInput = not IsUIFocused(),
        freecam = freecamMoving,
        mode = 'move',
        selected = placing and {
            label = currentlySelected and currentlySelected.label or 'Placed object',
            objectId = objectId,
        } or nil,
        tint = currentTint,
        pickup = objectId ~= nil and DecorationItems[objectId] ~= nil,
        tintSupported = placing and (GetFurnitureSpecs()[
            objectId and GetEntityArchetypeName(previewObject) or currentlySelected and currentlySelected.object or 0
        ] or {}).tint or false,
    })
end

function MakeGizmoMatrix(entity)
    local f, r, u, a = GetEntityMatrix(entity)
    local view = DataView.ArrayBuffer(64)
    view:SetFloat32(0, r[1]):SetFloat32(4, r[2]):SetFloat32(8, r[3]):SetFloat32(12, 0)
        :SetFloat32(16, f[1]):SetFloat32(20, f[2]):SetFloat32(24, f[3]):SetFloat32(28, 0)
        :SetFloat32(32, u[1]):SetFloat32(36, u[2]):SetFloat32(40, u[3]):SetFloat32(44, 0)
        :SetFloat32(48, a[1]):SetFloat32(52, a[2]):SetFloat32(56, a[3]):SetFloat32(60, 1)
    return view
end

local function normalizeAxis(x, y, z)
    local length = math.sqrt(x * x + y * y + z * z)
    if length == 0 then return 0, 0, 0 end
    return x / length, y / length, z / length
end

function ApplyGizmoMatrix(entity, view)
    local fx, fy, fz = normalizeAxis(view:GetFloat32(16), view:GetFloat32(20), view:GetFloat32(24))
    local rx, ry, rz = normalizeAxis(view:GetFloat32(0), view:GetFloat32(4), view:GetFloat32(8))
    local ux, uy, uz = normalizeAxis(view:GetFloat32(32), view:GetFloat32(36), view:GetFloat32(40))

    SetEntityMatrix(entity,
        fx, fy, fz,
        rx, ry, rz,
        ux, uy, uz,
        view:GetFloat32(48), view:GetFloat32(52), view:GetFloat32(56)
    )
end

local SCENARIO_PROPS = { `p_amb_clipboard_01`, `prop_notepad_01`, `prop_pencil_01` }

local function clearScenarioProps()
    local coords = GetEntityCoords(cache.ped)

    for i = 1, #SCENARIO_PROPS do
        local model = SCENARIO_PROPS[i]

        for _ = 1, 4 do
            local object = GetClosestObjectOfType(coords.x, coords.y, coords.z, 2.5, model, false, false, false)
            if object == 0 or not DoesEntityExist(object) then break end

            if not NetworkGetEntityIsNetworked(object) then
                SetEntityAsMissionEntity(object, true, true)
            end
            DeleteObject(object)
            if DoesEntityExist(object) then DeleteEntity(object) end
        end

        SetModelAsNoLongerNeeded(model)
    end
end

local function setDecoratingPose(active)
    if active then
        FreezeEntityPosition(cache.ped, true)
        SetEntityInvincible(cache.ped, true)
        TaskStartScenarioInPlace(cache.ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    else
        ClearPedTasksImmediately(cache.ped)
        ClearPedSecondaryTask(cache.ped)
        SetEntityInvincible(cache.ped, false)
        FreezeEntityPosition(cache.ped, false)
        clearScenarioProps()
        SetTimeout(250, clearScenarioProps)
        SetTimeout(1000, clearScenarioProps)
    end
end

function ToggleDecorating()
    IsDecorating = not IsDecorating
    setDecoratingPose(IsDecorating)
    SetPlayerControl(cache.playerId, not IsDecorating, 0)

    -- emote keybinds (hands up etc.) fire through RegisterKeyMapping and ignore disabled controls
    if GetResourceState('scully_emotemenu') == 'started' then
        exports.scully_emotemenu:setLimitation(IsDecorating)
    end

    if IsDecorating then
        OpenUI('furniture')
        SendUI('furniture:init', {
            categories = config.furniture,
            propertyName = CurrentPropertyName or '',
            palette = sharedConfig.wallColors.enabled and sharedConfig.wallColors.palette or {},
            shopEnabled = sharedConfig.furnitureShop ~= false,
            cdnMap = GetFurnitureCdnMap(),
        })
        PushPlacedDecorations()
        PushDecoratingState()
        pushCart()

        local saved = savedCarts[cartContextKey()]
        if saved then
            local total = 0
            for i = 1, #saved do total += saved[i].price end
            SendUI('furniture:restorePrompt', { count = #saved, total = total })
        end
    else
        clearOutline()
        discardPending()
        saveCartSnapshot()
        previewObject = nil
        currentlySelected = nil
        lastMatrix = nil
        SetCursorMode(false)
        destroyFreecam()
        CloseUI()
    end

    while IsDecorating do
        Wait(0)
        while IsUIFocused() and IsDecorating do Wait(0) end
        if not IsDecorating then break end
        if IsDisabledControlJustReleased(0, 202) then
            if previewObject and previewObject ~= pendingObject and DoesEntityExist(previewObject) and lastMatrix then
                ApplyGizmoMatrix(previewObject, lastMatrix)
                local objectId = currentObjectId()
                if objectId then
                    TriggerServerEvent('qbx_properties:server:decorationMoving', objectId, GetEntityCoords(previewObject), GetEntityRotation(previewObject, 2))
                end
            end
            RequestStopDecorating()
        end
        if IsDisabledControlJustReleased(0, 38) then
            SetUIFocus(true)
            PushDecoratingState()
        end

        if IsDisabledControlJustReleased(0, 23) then
            ToggleFreecam()
        end
        if IsDisabledControlJustReleased(0, 214) then
            RemoveSelectedDecoration()
        end
        if IsDisabledControlJustReleased(0, 47) and previewObject and DoesEntityExist(previewObject) then
            PlaceObjectOnGroundProperly(previewObject)
        end
        if IsDisabledControlJustReleased(0, 191) then
            ConfirmDecoration()
        end
        if previewObject and DoesEntityExist(previewObject) then
            if GetGameTimer() - lastTransformPush > 150 then
                lastTransformPush = GetGameTimer()
                local pos = GetEntityCoords(previewObject)
                local rot = GetEntityRotation(previewObject, 2)
                SendUI('furniture:transform', { x = pos.x, y = pos.y, z = pos.z, rx = rot.x, ry = rot.y, rz = rot.z })

                local objectId = currentObjectId()
                if objectId then
                    TriggerServerEvent('qbx_properties:server:decorationMoving', objectId, pos, rot)
                end
            end

            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 74, true) -- H stays with the NUI wall snap
            DisablePlayerFiring(cache.playerId, true)

            if sharedConfig.nuiGizmo then
                local pos = GetEntityCoords(previewObject)
                local rot = GetEntityRotation(previewObject, 2)
                local camRot = GetFinalRenderedCamRot(2)
                local camPos = GetFinalRenderedCamCoord()

                SendUI('gizmo:sync', {
                    cam = { x = camPos.x, y = camPos.y, z = camPos.z, rx = camRot.x, rz = camRot.z, fov = GetFinalRenderedCamFov() },
                    obj = { x = pos.x, y = pos.y, z = pos.z, rx = rot.x, ry = rot.y, rz = rot.z },
                })
            else
                local matrixBuffer = MakeGizmoMatrix(previewObject)
                local changed = Citizen.InvokeNative(0xEB2EDCA2, matrixBuffer:Buffer(), 'Editor1', Citizen.ReturnResultAnyway())
                if changed then
                    ApplyGizmoMatrix(previewObject, matrixBuffer)
                end
            end
        end
    end
end

RegisterKeyMapping('+gizmoTranslation', locale('keyMappings.gizmo_translation'), 'keyboard', 'T')
RegisterKeyMapping('+gizmoRotation', locale('keyMappings.gizmo_rotation'), 'keyboard', 'R')
RegisterKeyMapping("+gizmoSelect", locale('keyMappings.gizmo_select'), "MOUSE_BUTTON", "MOUSE_LEFT")
RegisterKeyMapping("+gizmoLocal", locale('keyMappings.gizmo_local'), "keyboard", "L")

function StartDecorating()
    if IsDecorating then return end

    if ResolveCurrentUnit then
        local buildingKey, floor, room = ResolveCurrentUnit()
        if buildingKey and floor and room then
            if not lib.callback.await('qbx_properties:callback:canDecorateUnit', false, buildingKey, floor, room) then
                lib.notify({ type = 'error', description = 'You do not hold the keys to this unit.' })
                return
            end

            CurrentPropertyName = GetUnitName(buildingKey, floor, room) or ''
            ToggleDecorating()
            return
        end
    end

    if CurrentGardenId and not CurrentPropertyId then
        if not lib.callback.await('qbx_properties:callback:canDecorateGarden', false, CurrentGardenId) then
            lib.notify({ type = 'error', description = 'You do not own this property.' })
            return
        end

        ToggleDecorating()
        return
    end

    if not lib.callback.await('qbx_properties:callback:checkAccess', false) then
        lib.notify({ type = 'error', description = 'You do not own this property.' })
        return
    end

    ToggleDecorating()
end

RegisterNetEvent('qbx_properties:client:startDecorating', StartDecorating)

RegisterNUICallback('furniture:place', function(data, cb)
    cb(1)
    if not IsDecorating or type(data) ~= 'table' or type(data.object) ~= 'string' then return end

    currentlySelected = { object = data.object, label = data.label }

    if previewObject and DoesEntityExist(previewObject) and not currentObjectId() then
        DeleteEntity(previewObject)
    end

    local modelHash = GetHashKey(data.object)
    if not IsModelValid(modelHash) or not lib.requestModel(modelHash, 60000) then
        currentlySelected = nil
        lib.notify({ type = 'error', description = ('%s is not a valid model.'):format(data.label or data.object) })
        return
    end

    local camCoords, camRotation = GetDecoratingCam()
    local forwardCoords = camCoords + vector3(-math.sin(math.rad(camRotation.z)), math.cos(math.rad(camRotation.z)), math.sin(math.rad(camRotation.x)) * 1.2) * 2

    previewObject = CreateObjectNoOffset(modelHash, forwardCoords.x, forwardCoords.y, forwardCoords.z, false, false, false)
    SetModelAsNoLongerNeeded(modelHash)
    FreezeEntityPosition(previewObject, true)
    SetEntityCollision(previewObject, false, false)
    SetEntityDrawOutline(previewObject, true)

    pendingObject = previewObject
    lastMatrix = nil
    SetCursorMode(true)
    SetUIFocus(true, true)
    PushDecoratingState()
end)

RegisterNUICallback('furniture:select', function(data, cb)
    cb(1)
    if type(data) == 'table' then SelectPlacedDecoration(data.id) end
end)

RegisterNUICallback('furniture:clone', function(data, cb)
    cb(1)
    if type(data) == 'table' then ClonePlacedDecoration(data.id) end
end)

RegisterNUICallback('furniture:confirm', function(_, cb)
    cb(1)
    ConfirmDecoration()
end)

RegisterNUICallback('furniture:cancel', function(_, cb)
    cb(1)
    CancelDecoration()
end)

RegisterNUICallback('furniture:remove', function(_, cb)
    cb(1)
    RemoveSelectedDecoration()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    if not IsDecorating then return end

    IsDecorating = false
    discardPending()
    discardCart(true)
    setDecoratingPose(false)
    destroyFreecam()
    if GetResourceState('scully_emotemenu') == 'started' then
        exports.scully_emotemenu:setLimitation(false)
    end
    SetPlayerControl(cache.playerId, true, 0)
end)

RegisterNUICallback('furniture:setTint', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not previewObject or not DoesEntityExist(previewObject) then return end

    local tint = tonumber(data.tint)
    if not tint or tint < 0 or tint > 31 then return end

    currentTint = tint
    SetObjectTextureVariation(previewObject, tint)
    PushDecoratingState()
end)

RegisterNUICallback('furniture:setTransform', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not previewObject or not DoesEntityExist(previewObject) then return end

    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
    local rx, ry, rz = tonumber(data.rx), tonumber(data.ry), tonumber(data.rz)
    if not x or not y or not z then return end

    SetEntityCoordsNoOffset(previewObject, x, y, z, false, false, false)
    if rx and ry and rz then
        SetEntityRotation(previewObject, rx, ry, rz, 2, false)
    end
end)

RegisterNUICallback('furniture:nudge', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not previewObject or not DoesEntityExist(previewObject) then return end

    local delta = tonumber(data.delta)
    if not delta then return end

    if data.axis == 'rz' then
        local rot = GetEntityRotation(previewObject, 2)
        SetEntityRotation(previewObject, rot.x, rot.y, (rot.z + delta) % 360.0, 2, false)
    elseif data.axis == 'camx' or data.axis == 'camy' then
        local heading = math.rad(GetGameplayCamRot(2).z)
        local forward = vec2(-math.sin(heading), math.cos(heading))
        local dir = data.axis == 'camy' and forward or vec2(forward.y, -forward.x)
        local pos = GetEntityCoords(previewObject)
        SetEntityCoordsNoOffset(previewObject, pos.x + dir.x * delta, pos.y + dir.y * delta, pos.z, false, false, false)
    elseif data.axis == 'x' or data.axis == 'y' or data.axis == 'z' then
        local pos = GetEntityCoords(previewObject)
        local moved = { x = pos.x, y = pos.y, z = pos.z }
        moved[data.axis] = moved[data.axis] + delta
        SetEntityCoordsNoOffset(previewObject, moved.x, moved.y, moved.z, false, false, false)
    end
end)

RegisterNUICallback('furniture:snap', function(_, cb)
    cb(1)
    SnapToNeighbor()
end)

RegisterNUICallback('gizmo:apply', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not previewObject or not DoesEntityExist(previewObject) then return end

    local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
    if x and y and z then
        SetEntityCoordsNoOffset(previewObject, x, y, z, false, false, false)
    end

    local rx, ry, rz = tonumber(data.rx), tonumber(data.ry), tonumber(data.rz)
    if rx or ry or rz then
        local rot = GetEntityRotation(previewObject, 2)
        SetEntityRotation(previewObject, (rx or rot.x) % 360.0, (ry or rot.y) % 360.0, (rz or rot.z) % 360.0, 2, false)
    end
end)

RegisterNUICallback('cart:remove', function(data, cb)
    cb(1)
    local index = tonumber(type(data) == 'table' and data.index or nil)
    local entry = index and cart[index]
    if not entry then return end

    if DoesEntityExist(entry.entity) then DeleteEntity(entry.entity) end
    table.remove(cart, index)
    pushCart()
end)

RegisterNUICallback('cart:edit', function(data, cb)
    cb(1)
    if previewObject then return end
    local index = tonumber(type(data) == 'table' and data.index or nil)
    local entry = index and cart[index]
    if not entry or not DoesEntityExist(entry.entity) then return end

    table.remove(cart, index)
    previewObject = entry.entity
    pendingObject = entry.entity
    currentlySelected = { object = entry.model, label = entry.label }
    currentTint = entry.tint or 0
    lastMatrix = nil
    SetEntityDrawOutline(previewObject, true)
    SetCursorMode(true)
    SetUIFocus(true, true)
    PushDecoratingState()
    pushCart()
end)

RegisterNUICallback('cart:checkout', function(_, cb)
    cb(1)
    if #cart == 0 then return end

    local manifest = {}
    for i = 1, #cart do
        manifest[cart[i].model] = (manifest[cart[i].model] or 0) + 1
    end

    if not lib.callback.await('qbx_properties:callback:payFurniture', false, manifest) then return end

    local event = CurrentGardenId and not CurrentPropertyId and 'qbx_properties:server:addGardenDecoration' or 'qbx_properties:server:addDecoration'
    for i = 1, #cart do
        local entry = cart[i]
        if DoesEntityExist(entry.entity) then
            TriggerServerEvent(event, entry.model, GetEntityCoords(entry.entity), GetEntityRotation(entry.entity, 2), nil, entry.tint)
            DeleteEntity(entry.entity)
        end
    end

    cart = {}
    pushCart()
end)

RegisterNUICallback('furniture:pickup', function(_, cb)
    cb(1)
    local objectId = currentObjectId()
    if not objectId or not DecorationItems[objectId] then return end

    clearOutline()
    TriggerServerEvent('qbx_properties:server:pickupDecoration', objectId)
    discardPending()
    previewObject = nil
    currentlySelected = nil
    lastMatrix = nil
    SetCursorMode(false)
    SetUIFocus(true)
    PushDecoratingState()
end)

function RequestStopDecorating()
    if not IsDecorating then return end

    if #cart > 0 then
        SetUIFocus(true)
        SendUI('furniture:confirmExit', true)
        return
    end

    ToggleDecorating()
end

RegisterNUICallback('furniture:exitChoice', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end
    if data.exit == true and IsDecorating then ToggleDecorating() end
end)

RegisterNUICallback('furniture:restoreChoice', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    local key = cartContextKey()
    local saved = key and savedCarts[key]
    if not saved then return end

    savedCarts[key] = nil
    if data.restore == true and IsDecorating then
        restoreCartSnapshot(saved)
        pushCart()
    end
end)
