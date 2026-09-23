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

local lastFreecamToggle = 0

-- the NUI reports the F keydown and the world loop the release of the same press, so one tap must not count twice
function ToggleFreecam()
    if not IsDecorating then return end

    local now = GetGameTimer()
    if now - lastFreecamToggle < 300 then return end
    lastFreecamToggle = now

    ensureFreecam()
    freecamMoving = not freecamMoving
    if freecamMoving then
        SetCursorMode(false)
        SetUIFocus(false)
    else
        SetCursorMode(previewObject ~= nil)
        SetUIFocus(true, previewObject ~= nil)
    end
    SetPlacementMobility(IsFreePlacing() and not freecamMoving)
    PushDecoratingState()
end

local lastMatrix
local furnitureLabels
local currentTint = 0
local lastTransformPush = 0
local lastPushed
local gizmoBuffer = DataView.ArrayBuffer(64)
local gridConfig = sharedConfig.furnitureGrid or {}
local gridSnap = gridConfig.snap == true
local gridHeading = 0.0
local placeConfig = sharedConfig.freePlacement or {}
local freePlacing = false
local placeDistance = placeConfig.distance or 4.0
local placeHeading = 0.0
local placeLift = 0.0
local placeStartedAt = 0
local groundFollow = placeConfig.ground ~= false
local placeSurface
local wallSnap = false
local placePitch = 0.0
local placeRoll = 0.0
local placeAxis = 'z'
local placeDoors
local onDoor = false

local AXIS_ORDER <const> = { z = 'x', x = 'y', y = 'z' }

---@return boolean
local function fineTuning()
    return IsDisabledControlPressed(0, 19)
end

---@return number
local function rotationStep()
    if IsDisabledControlPressed(0, 36) then return placeConfig.coarseStep or 45.0 end
    if fineTuning() then return placeConfig.fineStep or 1.0 end
    if gridSnap and (gridConfig.rotation or 0.0) > 0.0 then return gridConfig.rotation end
    return placeConfig.rotationStep or 5.0
end

---@return number, number
local function liftSteps()
    if fineTuning() then
        local fine = placeConfig.fineLift or 0.01
        return fine, fine * 5
    end
    return placeConfig.liftStep or 0.05, 0.25
end

local function pushPlacementMode()
    SendUI('placement:mode', {
        grid = gridSnap,
        wall = wallSnap,
        ground = groundFollow,
        axis = placeAxis,
        door = placeDoors ~= nil and onDoor or nil,
    })
end

local function updateDoorAim()
    if not placeDoors then return end

    local hit = false
    if placeSurface and placeSurface ~= 0 and DoesEntityExist(placeSurface) then
        hit = placeDoors[GetEntityModel(placeSurface) % 4294967296] == true
    end

    if hit ~= onDoor then
        onDoor = hit
        pushPlacementMode()
    end
end

---@param direction number
local function turnPlacement(direction)
    local step = direction * rotationStep()
    if placeAxis == 'x' then
        placePitch = (placePitch + step) % 360.0
    elseif placeAxis == 'y' then
        placeRoll = (placeRoll + step) % 360.0
    else
        placeHeading = placeHeading + step
    end
end

---@param value boolean
function SetCursorMode(value)
    if cursorMode == value then return end
    cursorMode = value

    if value then
        EnterCursorMode()
    else
        LeaveCursorMode()
    end

    RefreshDecoratingMobility()
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
        placed[#placed + 1] = {
            id = id,
            model = model,
            label = labelFor(model),
            name = DecorationLabels[id],
            room = DecorationRooms[id],
            item = item ~= nil,
            image = image,
        }
    end
    table.sort(placed, function(a, b)
        if a.label == b.label then return (a.name or '') < (b.name or '') end
        return a.label < b.label
    end)
    SendUI('furniture:placed', placed)
end

local function currentObjectId()
    if not previewObject or not DoesEntityExist(previewObject) then return end
    for id, entity in pairs(DecorationObjects) do
        if entity == previewObject then return id end
    end
end

---@param id integer
---@param gizmo boolean? keep the cursor on it instead of picking it up
function SelectPlacedDecoration(id, gizmo)
    local entity = DecorationObjects[id]
    if not IsDecorating or not entity or not DoesEntityExist(entity) then return end

    clearOutline()
    discardPending()
    previewObject = entity
    lastMatrix = MakeGizmoMatrix(entity)
    currentlySelected = nil
    currentTint = DecorationTints[id] or 0
    SetEntityDrawOutline(entity, true)

    if not gizmo then
        placeDistance = math.min(math.max(#(GetEntityCoords(entity) - GetDecoratingCam()),
            placeConfig.minDistance or 1.0), placeConfig.reach or 15.0)
    end

    SetFreePlacing(not gizmo and placeConfig.default ~= false)
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

local function releaseToWorld()
    freePlacing = false
    SetCursorMode(false)
    SetUIFocus(false)
    SetPlacementMobility(not freecamMoving)
end

function ConfirmDecoration()
    if not previewObject or not DoesEntityExist(previewObject) then return end
    local stayInWorld = freePlacing

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
            if stayInWorld then releaseToWorld() else SetCursorMode(false) SetUIFocus(true) end
            PushDecoratingState()
            pushCart()
            lib.notify({ type = 'info', description = 'Added to the cart. Pay in the furniture menu to keep it.' })
            return
        end
    end

    local event = CurrentGardenId and not CurrentPropertyId and 'qbx_properties:server:addGardenDecoration' or 'qbx_properties:server:addDecoration'

    SaveExtraSelection(event)
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
    if stayInWorld then releaseToWorld() else SetCursorMode(false) SetUIFocus(true) end
    PushDecoratingState()
end

---@param id integer? defaults to whatever is selected
function RemoveSelectedDecoration(id)
    local objectId = id or currentObjectId()
    if not objectId or not DecorationObjects[objectId] then return end

    clearOutline()

    local event = CurrentGardenId and not CurrentPropertyId and 'qbx_properties:server:removeGardenDecoration' or 'qbx_properties:server:removeDecoration'

    if not id then
        local extras = GetExtraSelectionIds()
        for i = 1, #extras do
            TriggerServerEvent(event, extras[i])
        end
        ClearExtraSelection()
    end

    TriggerServerEvent(event, objectId)

    if not id or objectId == currentObjectId() then
        discardPending()
        previewObject = nil
        currentlySelected = nil
        lastMatrix = nil
    end

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
        gridSnap = gridSnap,
        gridSize = gridConfig.size,
        axis = placeAxis,
        freePlacing = freePlacing,
        freePlaceSupported = placeConfig.enabled == true,
        groundFollow = groundFollow,
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

local function writeGizmoMatrix(entity, view)
    local f, r, u, a = GetEntityMatrix(entity)
    view:SetFloat32(0, r[1]):SetFloat32(4, r[2]):SetFloat32(8, r[3]):SetFloat32(12, 0)
        :SetFloat32(16, f[1]):SetFloat32(20, f[2]):SetFloat32(24, f[3]):SetFloat32(28, 0)
        :SetFloat32(32, u[1]):SetFloat32(36, u[2]):SetFloat32(40, u[3]):SetFloat32(44, 0)
        :SetFloat32(48, a[1]):SetFloat32(52, a[2]):SetFloat32(56, a[3]):SetFloat32(60, 1)
    return view
end

function MakeGizmoMatrix(entity)
    return writeGizmoMatrix(entity, DataView.ArrayBuffer(64))
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

function SetGridHeading(heading)
    gridHeading = tonumber(heading) or 0.0
end

local function rotateGrid(x, y, degrees)
    local rad = math.rad(degrees)
    local cos, sin = math.cos(rad), math.sin(rad)
    return x * cos - y * sin, x * sin + y * cos
end

local function quantise(value, step)
    return math.floor(value / step + 0.5) * step
end

---@return number
function ActiveGridHeading()
    if freePlacing and previewObject and DoesEntityExist(previewObject) then
        return GetEntityHeading(previewObject)
    end
    return gridHeading
end

local function applyGridSnap(entity)
    local step = gridConfig.size or 0.5
    if step < 0.01 then return end

    local turn = gridConfig.rotation or 0.0
    if turn > 0 then
        local rot = GetEntityRotation(entity, 2)
        SetEntityRotation(entity, quantise(rot.x, turn), quantise(rot.y, turn), quantise(rot.z, turn), 2, false)
    end

    local heading = ActiveGridHeading()
    local coords = GetEntityCoords(entity)
    local gx, gy = rotateGrid(coords.x, coords.y, -heading)
    local wx, wy = rotateGrid(quantise(gx, step), quantise(gy, step), heading)
    SetEntityCoordsNoOffset(entity, wx, wy, coords.z, false, false, false)
end

local function drawFurnitureGrid(origin)
    local step = gridConfig.size or 0.5
    local cells = gridConfig.cells or 10
    if step < 0.01 or cells < 2 then return end

    local color = gridConfig.color or { 255, 255, 255 }
    local red, green, blue = color[1] or 255, color[2] or 255, color[3] or 255
    local alpha = gridConfig.alpha or 110
    local major = gridConfig.major or 0

    local half = math.floor(cells / 2)
    local extent = half * step
    local z = origin.z + 0.01
    local heading = ActiveGridHeading()

    local gx, gy = rotateGrid(origin.x, origin.y, -heading)
    local cx, cy = quantise(gx, step), quantise(gy, step)

    for i = -half, half do
        local offset = i * step
        local line = alpha
        if major > 0 and i % major == 0 then line = math.min(math.floor(alpha * 1.7), 255) end

        local ax, ay = rotateGrid(cx + offset, cy - extent, heading)
        local bx, by = rotateGrid(cx + offset, cy + extent, heading)
        DrawLine(ax, ay, z, bx, by, z, red, green, blue, line)

        ax, ay = rotateGrid(cx - extent, cy + offset, heading)
        bx, by = rotateGrid(cx + extent, cy + offset, heading)
        DrawLine(ax, ay, z, bx, by, z, red, green, blue, line)
    end

    if not gridSnap then return end
    local arm = step * 0.45
    local ax, ay = rotateGrid(cx - arm, cy, heading)
    local bx, by = rotateGrid(cx + arm, cy, heading)
    DrawLine(ax, ay, z, bx, by, z, red, green, blue, 255)

    ax, ay = rotateGrid(cx, cy - arm, heading)
    bx, by = rotateGrid(cx, cy + arm, heading)
    DrawLine(ax, ay, z, bx, by, z, red, green, blue, 255)
end

---@return vector3 coords, boolean onSurface
local function placeTarget()
    local camPos, camRot = GetDecoratingCam()
    local pitch, yaw = math.rad(camRot.x), math.rad(camRot.z)
    local cp = math.cos(pitch)
    local dir = vec3(-math.sin(yaw) * cp, math.cos(yaw) * cp, math.sin(pitch))

    local reach = math.min(placeConfig.reach or 15.0, sharedConfig.placementReach or 15.0)
    local dest = camPos + dir * reach

    local probe = StartExpensiveSynchronousShapeTestLosProbe(
        camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, 1 | 16 | 256, previewObject, 4)
    local status, hit, endCoords, normal, _, entityHit = GetShapeTestResultIncludingMaterial(probe)

    local landed = status == 2 and (hit == true or hit == 1)
    local point = landed and endCoords or camPos + dir * math.min(placeDistance, reach)

    local pedCoords = GetEntityCoords(cache.ped)
    local offset = point - pedCoords
    local limit = (sharedConfig.placementReach or 15.0) - 0.5

    if #(offset) > limit then
        return pedCoords + offset / #(offset) * limit, false
    end

    return point, landed, landed and entityHit or nil, landed and normal or nil
end

---@param entity integer
---@return number
local function baseOffset(entity)
    local minimum = GetModelDimensions(GetEntityModel(entity))
    return minimum and -minimum.z or 0.0
end

local function updateFreePlace()
    if not previewObject or not DoesEntityExist(previewObject) then return end

    local target, onSurface, surface, normal = placeTarget()
    placeSurface = surface

    if wallSnap and onSurface and normal and math.abs(normal.z) < 0.7 then
        local _, max = GetModelDimensions(GetEntityModel(previewObject))
        local point = target + normal * max.y

        placeHeading = math.deg(math.atan(normal.x, -normal.y)) % 360.0
        SetEntityCoordsNoOffset(previewObject, point.x, point.y, point.z + placeLift, false, false, false)
        SetEntityRotation(previewObject, placePitch, placeRoll, placeHeading, 2, false)
        ApplySelectionOffsets()
        return
    end

    local lift = placeLift
    if onSurface and groundFollow then lift = lift + baseOffset(previewObject) end

    SetEntityCoordsNoOffset(previewObject, target.x, target.y, target.z + lift, false, false, false)
    SetEntityRotation(previewObject, placePitch, placeRoll, placeHeading % 360.0, 2, false)
    if gridSnap then applyGridSnap(previewObject) end
    ApplySelectionOffsets()
end

local extraSelection = {}

function ClearExtraSelection()
    for i = 1, #extraSelection do
        if DoesEntityExist(extraSelection[i].entity) then
            SetEntityDrawOutline(extraSelection[i].entity, false)
        end
    end
    extraSelection = {}
end

---@param entity integer
---@return integer?
local function decorationIdFor(entity)
    for id, placed in pairs(DecorationObjects) do
        if placed == entity then return id end
    end
end

local function captureSelectionOffsets()
    if not previewObject or not DoesEntityExist(previewObject) then return end

    local origin = GetEntityCoords(previewObject)
    local heading = GetEntityHeading(previewObject)

    for i = 1, #extraSelection do
        local entry = extraSelection[i]
        if DoesEntityExist(entry.entity) then
            local world = GetEntityCoords(entry.entity) - origin
            local lx, ly = rotateGrid(world.x, world.y, -heading)
            entry.offset = vec3(lx, ly, world.z)
            entry.heading = GetEntityHeading(entry.entity) - heading
        end
    end
end

function ApplySelectionOffsets()
    if #extraSelection == 0 or not previewObject or not DoesEntityExist(previewObject) then return end

    local origin = GetEntityCoords(previewObject)
    local heading = GetEntityHeading(previewObject)

    for i = 1, #extraSelection do
        local entry = extraSelection[i]
        if entry.offset and DoesEntityExist(entry.entity) then
            local wx, wy = rotateGrid(entry.offset.x, entry.offset.y, heading)
            SetEntityCoordsNoOffset(entry.entity, origin.x + wx, origin.y + wy, origin.z + entry.offset.z, false, false, false)
            SetEntityHeading(entry.entity, (heading + (entry.heading or 0.0)) % 360.0)
        end
    end
end

---@param id integer
---@param entity integer
local function toggleExtraSelection(id, entity)
    for i = 1, #extraSelection do
        if extraSelection[i].id == id then
            SetEntityDrawOutline(entity, false)
            table.remove(extraSelection, i)
            return
        end
    end

    if entity == previewObject then return end
    SetEntityDrawOutline(entity, true)
    extraSelection[#extraSelection + 1] = { id = id, entity = entity }
    captureSelectionOffsets()
end

---@param entity integer
---@return integer?
local function cartIndexFor(entity)
    for i = 1, #cart do
        if cart[i].entity == entity then return i end
    end
end

---@param index integer
---@param free boolean
---@return boolean
local function pickUpCartEntry(index, free)
    local entry = cart[index]
    if not entry or not DoesEntityExist(entry.entity) then return false end

    table.remove(cart, index)
    previewObject = entry.entity
    pendingObject = entry.entity
    currentlySelected = { object = entry.model, label = entry.label }
    currentTint = entry.tint or 0
    lastMatrix = nil
    SetEntityDrawOutline(previewObject, true)

    if free then
        placeHeading = GetEntityHeading(previewObject)
        SetFreePlacing(true)
    else
        SetCursorMode(true)
        SetUIFocus(true, true)
    end

    PushDecoratingState()
    pushCart()
    return true
end

---@return integer? id, integer? entity
local AIM_REACH <const> = 25.0

-- a shape test skips our own props even with base game bounds, so aim at each piece's own box
---@param origin vector3
---@param dir vector3 normalised
---@param entity integer
---@return number? distance along the ray
local function rayHitsEntity(origin, dir, entity)
    local minimum, maximum = GetModelDimensions(GetEntityModel(entity))
    local far = origin + dir * AIM_REACH

    local o = GetOffsetFromEntityGivenWorldCoords(entity, origin.x, origin.y, origin.z)
    local d = GetOffsetFromEntityGivenWorldCoords(entity, far.x, far.y, far.z) - o

    local tmin, tmax = 0.0, 1.0

    for axis = 1, 3 do
        local start = axis == 1 and o.x or axis == 2 and o.y or o.z
        local delta = axis == 1 and d.x or axis == 2 and d.y or d.z
        local low = axis == 1 and minimum.x or axis == 2 and minimum.y or minimum.z
        local high = axis == 1 and maximum.x or axis == 2 and maximum.y or maximum.z

        if math.abs(delta) < 0.000001 then
            if start < low or start > high then return end
        else
            local first = (low - start) / delta
            local second = (high - start) / delta
            if first > second then first, second = second, first end
            if first > tmin then tmin = first end
            if second < tmax then tmax = second end
            if tmin > tmax then return end
        end
    end

    return tmin * AIM_REACH
end

local function raycastDecoration()
    local camPos, camRot = GetDecoratingCam()
    local pitch, yaw = math.rad(camRot.x), math.rad(camRot.z)
    local cp = math.cos(pitch)
    local dir = vec3(-math.sin(yaw) * cp, math.cos(yaw) * cp, math.sin(pitch))

    local best, nearest

    for _, entity in pairs(DecorationObjects) do
        if entity ~= previewObject and DoesEntityExist(entity) then
            local distance = rayHitsEntity(camPos, dir, entity)
            if distance and (not nearest or distance < nearest) then
                best, nearest = entity, distance
            end
        end
    end

    for i = 1, #cart do
        local entity = cart[i].entity
        if entity and entity ~= previewObject and DoesEntityExist(entity) then
            local distance = rayHitsEntity(camPos, dir, entity)
            if distance and (not nearest or distance < nearest) then
                best, nearest = entity, distance
            end
        end
    end

    return best
end

---@return integer[]
function GetExtraSelectionIds()
    local ids = {}
    for i = 1, #extraSelection do ids[i] = extraSelection[i].id end
    return ids
end

---@param event string
function SaveExtraSelection(event)
    for i = 1, #extraSelection do
        local entry = extraSelection[i]
        if DoesEntityExist(entry.entity) then
            TriggerServerEvent(event, GetEntityArchetypeName(entry.entity), GetEntityCoords(entry.entity),
                GetEntityRotation(entry.entity, 2), entry.id, nil)
            SetEntityDrawOutline(entry.entity, false)
        end
    end
    extraSelection = {}
end

local aimedDecoration
local lastAimProbe = 0

local function updateCrosshair()
    if GetGameTimer() - lastAimProbe < 80 then return end
    lastAimProbe = GetGameTimer()

    local entity = (freePlacing or freecamMoving) and nil or raycastDecoration()
    if entity == aimedDecoration then return end

    aimedDecoration = entity
    SendUI('furniture:aim', { target = entity ~= nil })
end

local catalogOrder, catalogIndex

local function buildCatalog()
    if catalogOrder then return end

    catalogOrder = {}
    catalogIndex = {}
    local meta = config.furnitureCategories or {}

    for name, entries in pairs(config.furniture) do
        if #entries > 0 then catalogOrder[#catalogOrder + 1] = name end
    end

    table.sort(catalogOrder, function(a, b)
        local orderA = (meta[a] or {}).order or 0
        local orderB = (meta[b] or {}).order or 0
        if orderA ~= orderB then return orderA < orderB end
        return a < b
    end)

    for i = 1, #catalogOrder do
        local entries = config.furniture[catalogOrder[i]]
        for j = 1, #entries do
            catalogIndex[entries[j].object] = { category = i, item = j }
        end
    end
end

---@param categoryIndex integer
---@param itemIndex integer
local function selectCatalogEntry(categoryIndex, itemIndex)
    buildCatalog()
    if #catalogOrder == 0 then return end

    local category = catalogOrder[((categoryIndex - 1) % #catalogOrder) + 1]
    local entries = config.furniture[category]
    local entry = entries[((itemIndex - 1) % #entries) + 1]
    if not entry or not SpawnPreview(entry.object, entry.label) then return end

    placeHeading = GetEntityHeading(previewObject)
    SetFreePlacing(true)
    SendUI('furniture:highlight', { category = category, object = entry.object })
    PushDecoratingState()
end

---@param delta integer
local function cycleFurniture(delta)
    buildCatalog()
    local at = currentlySelected and catalogIndex[currentlySelected.object]
    if not at then return selectCatalogEntry(1, 1) end
    selectCatalogEntry(at.category, at.item + delta)
end

---@param delta integer
local function cycleCategory(delta)
    buildCatalog()
    local at = currentlySelected and catalogIndex[currentlySelected.object]
    selectCatalogEntry((at and at.category or 1) + delta, 1)
end

function IsFreePlacing()
    return freePlacing
end

function SetFreePlacing(active)
    if placeConfig.enabled ~= true then
        SetCursorMode(true)
        SetUIFocus(true, true)
        return
    end

    freePlacing = active == true

    SetCursorMode(not freePlacing)
    SetUIFocus(not freePlacing, true)
    SetPlacementMobility(freePlacing and not freecamMoving)

    if not freePlacing then return end
    placeStartedAt = GetGameTimer()
    SendUI('gizmo:sync', nil)

    if previewObject and DoesEntityExist(previewObject) then
        placeHeading = GetEntityHeading(previewObject)
        updateFreePlace()
    end
end

-- the clipboard is our own object attached to the hand rather than a scenario prop, so leaving the
-- editor deletes it by handle instead of hunting for whatever the scenario system dropped
local CLIPBOARD_MODEL <const> = `p_amb_clipboard_01`
local CLIPBOARD_DICT <const> = 'amb@world_human_clipboard@male@base'
local clipboardProp

function RemoveClipboard()
    if clipboardProp and DoesEntityExist(clipboardProp) then
        DetachEntity(clipboardProp, true, false)
        DeleteEntity(clipboardProp)
    end
    clipboardProp = nil
    SetModelAsNoLongerNeeded(CLIPBOARD_MODEL)
end

local function attachClipboard()
    RemoveClipboard()
    lib.requestModel(CLIPBOARD_MODEL, 5000)

    local coords = GetEntityCoords(cache.ped)
    clipboardProp = CreateObject(CLIPBOARD_MODEL, coords.x, coords.y, coords.z, false, false, false)
    SetEntityAsMissionEntity(clipboardProp, true, true)
    SetEntityCollision(clipboardProp, false, false)
    AttachEntityToEntity(clipboardProp, cache.ped, GetPedBoneIndex(cache.ped, 36029), 0.16, 0.08, 0.1, -130.0, -50.0, 0.0, true, true, false, true, 1, true)
end

local SPC_LEAVE_CAMERA_CONTROL_ON <const> = 256

---@param mobile boolean walking around while freePlacing, rather than posed with the clipboard
---@param model string
---@param prompt string
---@return vector4?
---@param model string
---@param prompt string
---@param doors table? model hashes the piece may fix itself to
---@return vector4?, integer?
function FreePlaceModel(model, prompt, doors)
    if IsDecorating or previewObject then return end

    local hash = GetHashKey(model)
    if not IsModelValid(hash) or not lib.requestModel(hash, 20000) then
        lib.notify({ type = 'error', description = ('%s is not a valid model.'):format(model) })
        return
    end

    local camPos = GetDecoratingCam()
    previewObject = CreateObjectNoOffset(hash, camPos.x, camPos.y, camPos.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    FreezeEntityPosition(previewObject, true)
    SetEntityCollision(previewObject, false, false)
    SetEntityDrawOutline(previewObject, true)
    pendingObject = previewObject

    placeDistance = placeConfig.distance or 4.0
    placeLift = 0.0
    placeHeading = GetEntityHeading(previewObject)
    freePlacing = true
    groundFollow = placeConfig.ground ~= false
    placeSurface = nil
    wallSnap = false
    placePitch = 0.0
    placeRoll = 0.0
    placeAxis = 'z'
    placeDoors = doors
    onDoor = false

    SetCursorMode(false)
    SetUIFocus(false)
    SendUI('placement:show', {
        prompt = prompt,
        freePlace = true,
        mode = { grid = gridSnap, wall = wallSnap, ground = groundFollow, axis = placeAxis },
    })

    local confirmed, cancelled = false, false
    local started = GetGameTimer()

    while not confirmed and not cancelled do
        Wait(0)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 22, true)
        DisableControlAction(0, 23, true)
        DisableControlAction(0, 47, true)
        DisableControlAction(0, 73, true)
        DisableControlAction(0, 74, true)
        DisableControlAction(0, 45, true)
        DisableControlAction(0, 19, true)
        DisableControlAction(0, 199, true)
        DisableControlAction(0, 200, true)
        DisablePlayerFiring(cache.playerId, true)

        if not freecamMoving then
            local up = IsDisabledControlJustPressed(0, 241)
            local down = IsDisabledControlJustPressed(0, 242)

            if up or down then
                local direction = up and 1.0 or -1.0
                if IsDisabledControlPressed(0, 21) then
                    local lift, reach = liftSteps()
                    if groundFollow then
                        placeLift = math.min(math.max(placeLift + direction * lift, 0.0), placeConfig.maxLift or 4.0)
                    else
                        placeDistance = math.min(math.max(placeDistance + direction * reach, placeConfig.minDistance or 1.0), placeConfig.reach or 15.0)
                    end
                else
                    turnPlacement(direction)
                end
            end
        end

        if IsDisabledControlJustReleased(0, 47) then
            groundFollow = not groundFollow
            placeLift = 0.0
            pushPlacementMode()
        end
        if IsDisabledControlJustReleased(0, 73) then
            gridSnap = not gridSnap
            pushPlacementMode()
        end
        if IsDisabledControlJustReleased(0, 74) then
            wallSnap = not wallSnap
            placeLift = 0.0
            pushPlacementMode()
        end
        if IsDisabledControlJustReleased(0, 45) then
            placeAxis = AXIS_ORDER[placeAxis] or 'z'
            pushPlacementMode()
        end

        updateFreePlace()
        updateDoorAim()
        if gridConfig.enabled then drawFurnitureGrid(GetEntityCoords(previewObject)) end

        if IsDisabledControlJustReleased(0, 24) and GetGameTimer() - started > 250 then confirmed = true end
        if IsDisabledControlJustReleased(0, 202) or IsDisabledControlJustReleased(0, 177) then cancelled = true end
    end

    local coords = GetEntityCoords(previewObject)
    local heading = GetEntityHeading(previewObject)

    DeleteEntity(previewObject)
    previewObject = nil
    pendingObject = nil
    freePlacing = false
    SendUI('placement:hide')
    SetCursorMode(false)
    SetUIFocus(false)

    placeDoors = nil
    if cancelled then return end
    return vec4(coords.x, coords.y, coords.z, heading), placeSurface
end

function RefreshDecoratingMobility()
    if not IsDecorating then return end
    SetPlacementMobility(not cursorMode and not freecamMoving)
end

function SetPlacementMobility(mobile)
    if not IsDecorating then return end

    if mobile then
        FreezeEntityPosition(cache.ped, false)
        SetPlayerControl(cache.playerId, true, 0)
    else
        FreezeEntityPosition(cache.ped, true)
        SetPlayerControl(cache.playerId, false, SPC_LEAVE_CAMERA_CONTROL_ON)
    end
end

local function setDecoratingPose(active)
    if active then
        FreezeEntityPosition(cache.ped, true)
        SetEntityInvincible(cache.ped, true)
        lib.requestAnimDict(CLIPBOARD_DICT, 5000)
        TaskPlayAnim(cache.ped, CLIPBOARD_DICT, 'base', 8.0, -8.0, -1, 49, 0.0, false, false, false)
        attachClipboard()
    else
        RemoveClipboard()
        StopAnimTask(cache.ped, CLIPBOARD_DICT, 'base', 1.0)
        ClearPedSecondaryTask(cache.ped)
        RemoveAnimDict(CLIPBOARD_DICT)
        SetEntityInvincible(cache.ped, false)
        FreezeEntityPosition(cache.ped, false)
    end
end

function ToggleDecorating()
    IsDecorating = not IsDecorating
    setDecoratingPose(IsDecorating)
    SetPlayerControl(cache.playerId, not IsDecorating, IsDecorating and SPC_LEAVE_CAMERA_CONTROL_ON or 0)

    -- emote keybinds (hands up etc.) fire through RegisterKeyMapping and ignore disabled controls
    if GetResourceState('scully_emotemenu') == 'started' then
        exports.scully_emotemenu:setLimitation(IsDecorating)
    end

    -- the inventory is bound the same way, and tab belongs to the furniture UI while decorating
    LocalPlayer.state:set('invBusy', IsDecorating or nil, false)

    if IsDecorating then
        OpenUI('furniture')
        SendUI('furniture:init', {
            categories = config.furniture,
            categoryMeta = config.furnitureCategories or {},
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
        ClearExtraSelection()
        discardPending()
        saveCartSnapshot()
        previewObject = nil
        currentlySelected = nil
        lastMatrix = nil
        freePlacing = false
        aimedDecoration = nil
        SetCursorMode(false)
        destroyFreecam()
        CloseUI()
    end

    while IsDecorating do
        Wait(0)
        while IsUIFocused() and IsDecorating do Wait(0) end
        if not IsDecorating then break end
        DisableControlAction(0, 37, true)
        DisableControlAction(0, 199, true)
        DisableControlAction(0, 200, true)
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
        if IsDisabledControlJustReleased(0, 37) then
            SetUIFocus(true)
            PushDecoratingState()
        end

        if freePlacing or not previewObject then
            if IsDisabledControlJustPressed(0, 174) then cycleFurniture(-1) end
            if IsDisabledControlJustPressed(0, 175) then cycleFurniture(1) end
            if IsDisabledControlJustPressed(0, 44) then cycleCategory(-1) end
            if IsDisabledControlJustPressed(0, 38) then cycleCategory(1) end
        end

        updateCrosshair()

        if not freePlacing and not pendingObject and not freecamMoving and IsDisabledControlJustReleased(0, 24) then
            local entity = raycastDecoration()
            local id = entity and decorationIdFor(entity)
            local cartIndex = entity and not id and cartIndexFor(entity)

            if cartIndex then
                pickUpCartEntry(cartIndex, true)
            elseif id and entity then
                if IsDisabledControlPressed(0, 36) then
                    if not previewObject then SelectPlacedDecoration(id, true) end
                    toggleExtraSelection(id, entity)
                    PushDecoratingState()
                else
                    ClearExtraSelection()
                    local camPos = GetDecoratingCam()
                    placeDistance = math.min(math.max(#(GetEntityCoords(entity) - camPos),
                        placeConfig.minDistance or 1.0), placeConfig.reach or 15.0)
                    SelectPlacedDecoration(id)
                    SetFreePlacing(true)
                end
            end
        end

        if IsDisabledControlJustReleased(0, 23) then
            ToggleFreecam()
        end
        if IsDisabledControlJustReleased(0, 214) then
            RemoveSelectedDecoration()
        end
        if IsDisabledControlJustReleased(0, 47) and previewObject and DoesEntityExist(previewObject) then
            if freePlacing then
                groundFollow = not groundFollow
                placeLift = 0.0
                if not groundFollow then
                    placeDistance = math.min(math.max(#(GetEntityCoords(previewObject) - GetDecoratingCam()),
                        placeConfig.minDistance or 1.0), placeConfig.reach or 15.0)
                end
                PushDecoratingState()
            else
                PlaceObjectOnGroundProperly(previewObject)
            end
        end
        if IsDisabledControlJustReleased(0, 73) then
            gridSnap = not gridSnap
            if gridSnap and previewObject and DoesEntityExist(previewObject) then
                applyGridSnap(previewObject)
            end
            PushDecoratingState()
        end
        if IsDisabledControlJustReleased(0, 45) and freePlacing then
            placeAxis = AXIS_ORDER[placeAxis] or 'z'
            PushDecoratingState()
        end
        if IsDisabledControlJustReleased(0, 26) and previewObject and DoesEntityExist(previewObject) then
            SetFreePlacing(not freePlacing)
            PushDecoratingState()
        end
        if IsDisabledControlJustReleased(0, 191) then
            ConfirmDecoration()
        end
        if previewObject and DoesEntityExist(previewObject) then
            if GetGameTimer() - lastTransformPush > 150 then
                local pos = GetEntityCoords(previewObject)
                local rot = GetEntityRotation(previewObject, 2)
                local settled = lastPushed and lastPushed.entity == previewObject
                    and #(pos - lastPushed.pos) < 0.001 and #(rot - lastPushed.rot) < 0.01

                if not settled then
                    lastTransformPush = GetGameTimer()
                    lastPushed = { entity = previewObject, pos = pos, rot = rot }
                    SendUI('furniture:transform', { x = pos.x, y = pos.y, z = pos.z, rx = rot.x, ry = rot.y, rz = rot.z })

                    local objectId = currentObjectId()
                    if objectId then
                        TriggerServerEvent('qbx_properties:server:decorationMoving', objectId, pos, rot)
                    end
                end
            end

            if gridConfig.enabled then drawFurnitureGrid(GetEntityCoords(previewObject)) end

            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 22, true) -- walking while freePlacing must not jump or board a vehicle
            DisableControlAction(0, 23, true)
            DisableControlAction(0, 26, true) -- C picks the piece up and puts it down
            DisableControlAction(0, 73, true) -- X toggles grid snapping
            DisableControlAction(0, 44, true) -- Q and E walk the catalog while freePlacing
            DisableControlAction(0, 172, true)
            DisableControlAction(0, 173, true)
            DisableControlAction(0, 174, true)
            DisableControlAction(0, 175, true)
            DisableControlAction(0, 74, true) -- H stays with the NUI wall snap
            DisableControlAction(0, 45, true) -- R walks the rotation axis
            DisableControlAction(0, 19, true) -- alt is the fine pass
            DisableControlAction(0, 199, true) -- escape closes the editor, not the pause menu
            DisableControlAction(0, 200, true)
            DisablePlayerFiring(cache.playerId, true)


            if freePlacing then
                if not freecamMoving then
                    local up = IsDisabledControlJustPressed(0, 241)
                    local down = IsDisabledControlJustPressed(0, 242)

                    if up or down then
                        local direction = up and 1.0 or -1.0
                        if IsDisabledControlPressed(0, 21) then
                            local lift, reach = liftSteps()
                            if groundFollow then
                                placeLift = math.min(math.max(placeLift + direction * lift, 0.0),
                                    placeConfig.maxLift or 4.0)
                            else
                                placeDistance = math.min(math.max(placeDistance + direction * reach,
                                    placeConfig.minDistance or 1.0), placeConfig.reach or 15.0)
                            end
                        else
                            turnPlacement(direction)
                        end
                    end
                end

                updateFreePlace()

                if IsDisabledControlJustReleased(0, 24) and GetGameTimer() - placeStartedAt > 250 then
                    ConfirmDecoration()
                end
            elseif sharedConfig.nuiGizmo then
                local pos = GetEntityCoords(previewObject)
                local rot = GetEntityRotation(previewObject, 2)
                local camRot = GetFinalRenderedCamRot(2)
                local camPos = GetFinalRenderedCamCoord()

                SendUI('gizmo:sync', {
                    cam = { x = camPos.x, y = camPos.y, z = camPos.z, rx = camRot.x, rz = camRot.z, fov = GetFinalRenderedCamFov() },
                    obj = { x = pos.x, y = pos.y, z = pos.z, rx = rot.x, ry = rot.y, rz = rot.z },
                })
            else
                local matrixBuffer = writeGizmoMatrix(previewObject, gizmoBuffer)
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
    SetGridHeading(GetCurrentShellHeading and GetCurrentShellHeading() or 0.0)

    if ResolveCurrentUnit then
        local buildingKey, floor, room = ResolveCurrentUnit()
        if buildingKey and floor and room then
            if not lib.callback.await('qbx_properties:callback:canDecorateUnit', false, buildingKey, floor, room) then
                lib.notify({ type = 'error', description = 'You do not hold the keys to this unit.' })
                return
            end

            CurrentPropertyName = GetUnitName(buildingKey, floor, room) or ''
            local anchor = GetRoomCoords(buildingKey, floor, room)
            SetGridHeading(anchor and anchor.w or 0.0)
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

---@param object string
---@param label string?
---@return boolean
function SpawnPreview(object, label)
    local modelHash = GetHashKey(object)
    if not IsModelValid(modelHash) or not lib.requestModel(modelHash, 60000) then
        lib.notify({ type = 'error', description = ('%s is not a valid model.'):format(label or object) })
        return false
    end

    local keepCoords, keepHeading
    if previewObject and DoesEntityExist(previewObject) then
        if previewObject == pendingObject then
            keepCoords = GetEntityCoords(previewObject)
            keepHeading = GetEntityHeading(previewObject)
        end
        if not currentObjectId() then DeleteEntity(previewObject) end
    end

    currentlySelected = { object = object, label = label }

    local coords = keepCoords
    if not coords then
        local camCoords, camRotation = GetDecoratingCam()
        coords = camCoords + vector3(-math.sin(math.rad(camRotation.z)), math.cos(math.rad(camRotation.z)), math.sin(math.rad(camRotation.x)) * 1.2) * 2
    end

    previewObject = CreateObjectNoOffset(modelHash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(modelHash)
    FreezeEntityPosition(previewObject, true)
    SetEntityCollision(previewObject, false, false)
    SetEntityDrawOutline(previewObject, true)
    SetEntityHeading(previewObject, keepHeading or gridHeading)

    pendingObject = previewObject
    lastMatrix = nil
    return true
end

RegisterNUICallback('furniture:place', function(data, cb)
    cb(1)
    if not IsDecorating or type(data) ~= 'table' or type(data.object) ~= 'string' then return end
    if not SpawnPreview(data.object, data.label) then
        currentlySelected = nil
        return
    end

    placeDistance = placeConfig.distance or 4.0
    placeLift = 0.0
    placeHeading = GetEntityHeading(previewObject)
    SetFreePlacing(placeConfig.default ~= false)
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

RegisterNUICallback('furniture:setRoom', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or type(data.ids) ~= 'table' then return end

    local ids = {}
    for i = 1, #data.ids do
        local id = tonumber(data.ids[i])
        if id and DecorationObjects[id] then ids[#ids + 1] = id end
    end

    if #ids == 0 then return end

    local room = type(data.room) == 'string' and data.room ~= '' and data.room or nil
    if lib.callback.await('qbx_properties:callback:setDecorationRoom', false, ids, room) == 0 then
        lib.notify({ type = 'error', description = 'Those pieces did not move.' })
        return
    end

    for i = 1, #ids do DecorationRooms[ids[i]] = room end
    PushPlacedDecorations()
end)

RegisterNUICallback('furniture:rename', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    local id = tonumber(data.id)
    if not id or not DecorationObjects[id] then return end

    local name = type(data.name) == 'string' and data.name or nil
    if not lib.callback.await('qbx_properties:callback:setDecorationLabel', false, id, name) then
        lib.notify({ type = 'error', description = 'That name did not stick.' })
        return
    end

    DecorationLabels[id] = (name and name ~= '') and name or nil
    PushPlacedDecorations()
end)

RegisterNUICallback('furniture:remove', function(data, cb)
    cb(1)
    RemoveSelectedDecoration(type(data) == 'table' and tonumber(data.id) or nil)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    if not IsDecorating then return end

    IsDecorating = false
    discardPending()
    discardCart(true)
    setDecoratingPose(false)
    destroyFreecam()
    LocalPlayer.state:set('invBusy', nil, false)
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
    if index then pickUpCartEntry(index, true) end
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

RegisterNUICallback('furniture:pickup', function(data, cb)
    cb(1)
    local objectId = type(data) == 'table' and tonumber(data.id) or currentObjectId()
    if not objectId or not DecorationItems[objectId] then return end

    clearOutline()
    TriggerServerEvent('qbx_properties:server:pickupDecoration', objectId)

    if objectId == currentObjectId() then
        discardPending()
        previewObject = nil
        currentlySelected = nil
        lastMatrix = nil
        SetCursorMode(false)
        SetUIFocus(true)
    end

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
