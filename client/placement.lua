local sharedConfig = require 'config.shared'

local active = false
local ghost = nil

---@return boolean
function IsPlacementActive()
    return active
end

local function drawLaser(from, to, hit)
    local r, g, b = hit and 60 or 200, hit and 200 or 60, 80
    DrawLine(from.x, from.y, from.z, to.x, to.y, to.z, r, g, b, 200)
    if hit then
        DrawMarker(28, to.x, to.y, to.z, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.1, 0.1, 0.1, r, g, b, 180, false, true, 2, nil, nil, false)
    end
end

---@param entity number
local function drawEntityBox(entity)
    local min, max = GetModelDimensions(GetEntityModel(entity))
    local right, forward, up, position = GetEntityMatrix(entity)
    local dim = vec3(0.5 * (max.x - min.x), 0.5 * (max.y - min.y), 0.5 * (max.z - min.z))

    local edges = {}
    edges[1] = position - dim.y * right - dim.x * forward - dim.z * up
    edges[2] = edges[1] + 2 * dim.y * right
    edges[3] = edges[2] + 2 * dim.z * up
    edges[4] = edges[1] + 2 * dim.z * up
    edges[5] = position + dim.y * right + dim.x * forward + dim.z * up
    edges[6] = edges[5] - 2 * dim.y * right
    edges[7] = edges[6] - 2 * dim.z * up
    edges[8] = edges[5] - 2 * dim.z * up

    for i = 1, 4 do
        local j = i % 4 + 1
        DrawLine(edges[i].x, edges[i].y, edges[i].z, edges[j].x, edges[j].y, edges[j].z, 60, 200, 80, 200)
        DrawLine(edges[i + 4].x, edges[i + 4].y, edges[i + 4].z, edges[j + 4].x, edges[j + 4].y, edges[j + 4].z, 60, 200, 80, 200)
        DrawLine(edges[i].x, edges[i].y, edges[i].z, edges[i + 4].x, edges[i + 4].y, edges[i + 4].z, 60, 200, 80, 200)
    end
end

---@param flags integer
---@return boolean hit, vector3 coords, number entity
local function castFromPed(flags)
    local origin = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local rad = vec3(math.rad(camRot.x), math.rad(camRot.y), math.rad(camRot.z))
    local direction = vec3(-math.sin(rad.z) * math.abs(math.cos(rad.x)), math.cos(rad.z) * math.abs(math.cos(rad.x)), math.sin(rad.x))
    local target = origin + direction * 25.0

    local handle = StartShapeTestRay(origin.x, origin.y, origin.z, target.x, target.y, target.z, flags, cache.ped, 0)
    local _, hit, endCoords, _, entity = GetShapeTestResult(handle)

    return hit, endCoords, entity
end

local function disablePlacementControls()
    DisableControlAction(0, 24, true)
    DisableControlAction(0, 25, true)
    DisableControlAction(0, 200, true)
    DisableControlAction(0, 199, true)
end

local function wantsCancel()
    return IsControlJustReleased(0, 202) or IsDisabledControlJustReleased(0, 200)
end

---@param prompt string
---@param flags integer?
---@return vector3? coords, number? entity, number? heading
function PickWithLaser(prompt, flags)
    if active then return end
    active = true

    SendUI('placement:show', { prompt = prompt })

    local result, entity, heading
    local cancelled = false

    while not result and not cancelled do
        Wait(0)

        local hit, coords, hitEntity = castFromPed(flags or -1)
        local origin = GetPedBoneCoords(cache.ped, 24818, 0.0, 0.0, 0.0)

        local onEntity = hitEntity and hitEntity ~= 0
            and (IsEntityAVehicle(hitEntity) or IsEntityAPed(hitEntity) or IsEntityAnObject(hitEntity))

        if coords and (coords.x ~= 0.0 or coords.y ~= 0.0) then
            drawLaser(origin, coords, hit)
            if onEntity then drawEntityBox(hitEntity) end
        end

        disablePlacementControls()

        if hit and IsDisabledControlJustReleased(0, 24) then
            result = coords
            entity = hitEntity
            heading = GetEntityHeading(cache.ped)
        end

        if wantsCancel() then cancelled = true end
    end

    active = false
    SendUI('placement:hide')

    if cancelled then return end
    return result, entity, heading
end

---@param points table
---@param height number
local function drawZoneWalls(points, height)
    for i = 1, #points do
        local point = points[i]
        DrawMarker(28, point.x, point.y, point.z, 0, 0, 0, 0, 0, 0, 0.12, 0.12, 0.12, 60, 200, 80, 200, false, false, 2, false, nil, nil, false)
        DrawLine(point.x, point.y, point.z, point.x, point.y, point.z + height, 60, 200, 80, 160)

        local nextPoint = points[i + 1] or (#points >= 3 and points[1] or nil)
        if nextPoint then
            DrawLine(point.x, point.y, point.z, nextPoint.x, nextPoint.y, nextPoint.z, 60, 200, 80, 200)
            DrawLine(point.x, point.y, point.z + height, nextPoint.x, nextPoint.y, nextPoint.z + height, 60, 200, 80, 160)
        end
    end
end

---@param prompt string
---@param maxPoints integer
---@return table? points, number? height
function DrawZoneWithLaser(prompt, maxPoints)
    if active then return end
    active = true

    local maxHeight = sharedConfig.gardens.height
    local points = {}
    local height = maxHeight
    local done, cancelled = false, false

    local function push()
        SendUI('placement:show', { prompt = prompt, points = #points, zone = true, height = height })
    end

    push()

    while not done and not cancelled do
        Wait(0)

        local hit, coords = castFromPed(-1)
        local origin = GetPedBoneCoords(cache.ped, 24818, 0.0, 0.0, 0.0)

        if coords and (coords.x ~= 0.0 or coords.y ~= 0.0) then
            drawLaser(origin, coords, hit)
        end

        drawZoneWalls(points, height)

        disablePlacementControls()
        DisableControlAction(0, 14, true)
        DisableControlAction(0, 15, true)
        DisableControlAction(0, 16, true)
        DisableControlAction(0, 17, true)

        if IsDisabledControlJustPressed(0, 15) and height < maxHeight then
            height = math.min(maxHeight, height + 0.1)
            push()
        elseif IsDisabledControlJustPressed(0, 14) and height > 0.5 then
            height = math.max(0.5, height - 0.1)
            push()
        end

        if hit and IsDisabledControlJustReleased(0, 24) and #points < maxPoints then
            points[#points + 1] = coords
            push()
        end

        if IsControlJustReleased(0, 194) and #points > 0 then
            points[#points] = nil
            push()
        end

        if IsControlJustReleased(0, 191) and #points >= 3 then done = true end
        if wantsCancel() then cancelled = true end
    end

    active = false
    SendUI('placement:hide')

    if cancelled then return end
    return points, height
end

---@param model string|number
---@param prompt string
---@return vector4?
function PlaceVehicleOnGround(model, prompt)
    if active then return end

    local hash = lib.requestModel(model, 60000)
    if not hash then return end

    active = true

    local pedCoords = GetEntityCoords(cache.ped)
    ghost = CreateVehicle(hash, pedCoords.x, pedCoords.y, pedCoords.z, GetEntityHeading(cache.ped), false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(ghost, false, false)
    SetEntityAlpha(ghost, 160, false)
    SetEntityInvincible(ghost, true)
    FreezeEntityPosition(ghost, true)

    SendUI('placement:show', { prompt = prompt, vehicle = true })

    local heading = GetEntityHeading(cache.ped)
    local valid = false
    local confirmed, cancelled = false, false

    while not confirmed and not cancelled do
        Wait(0)

        local hit, coords = castFromPed(1 + 16)

        if hit and coords and (coords.x ~= 0.0 or coords.y ~= 0.0) then
            local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1.0, false)
            local z = found and groundZ or coords.z

            SetEntityCoords(ghost, coords.x, coords.y, z + 0.4, false, false, false, false)
            SetEntityHeading(ghost, heading)
            valid = true
        end

        disablePlacementControls()
        DisableControlAction(0, 14, true)
        DisableControlAction(0, 15, true)
        DisableControlAction(0, 16, true)
        DisableControlAction(0, 17, true)

        if IsDisabledControlPressed(0, 15) then
            heading = (heading + 2.5) % 360.0
        elseif IsDisabledControlPressed(0, 14) then
            heading = (heading - 2.5) % 360.0
        end

        if valid and IsDisabledControlJustReleased(0, 24) then confirmed = true end
        if wantsCancel() then cancelled = true end
    end

    local coords = GetEntityCoords(ghost)
    DeleteEntity(ghost)
    ghost = nil

    active = false
    SendUI('placement:hide')

    if cancelled then return end
    return vec4(coords.x, coords.y, coords.z, heading)
end

---@param model string|number
---@param origin vector3
---@param prompt string
---@return vector4?
function PlaceModelWithGizmo(model, origin, prompt)
    local hash = lib.requestModel(model, 60000)
    if not hash then return end

    ghost = CreateObject(hash, origin.x, origin.y, origin.z, false, false, false)
    SetEntityCollision(ghost, false, false)
    SetEntityAlpha(ghost, 180, false)
    FreezeEntityPosition(ghost, true)
    SetModelAsNoLongerNeeded(hash)

    SendUI('placement:show', { prompt = prompt, gizmo = true })
    EnterCursorMode()

    local cursorOn = true
    local confirmed, cancelled = false, false
    while not confirmed and not cancelled do
        Wait(0)

        local matrix = MakeGizmoMatrix(ghost)
        if Citizen.InvokeNative(0xEB2EDCA2, matrix:Buffer(), 'PropertyPlacement', Citizen.ReturnResultAnyway()) then
            ApplyGizmoMatrix(ghost, matrix)
        end

        DisableControlAction(0, 200, true)
        DisableControlAction(0, 199, true)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 140, true)
        DisableControlAction(0, 141, true)
        DisableControlAction(0, 142, true)
        DisablePlayerFiring(cache.playerId, true)

        if IsControlJustReleased(0, 47) or IsDisabledControlJustReleased(0, 47) then
            cursorOn = not cursorOn
            if cursorOn then EnterCursorMode() else LeaveCursorMode() end
        end

        if IsControlJustReleased(0, 191) then confirmed = true end
        if wantsCancel() then cancelled = true end
    end

    if cursorOn then LeaveCursorMode() end
    local coords = GetEntityCoords(ghost)
    local heading = GetEntityHeading(ghost)
    DeleteEntity(ghost)
    ghost = nil
    SendUI('placement:hide')

    if cancelled then return end
    return vec4(coords.x, coords.y, coords.z, heading)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    if ghost and DoesEntityExist(ghost) then DeleteEntity(ghost) end
end)
