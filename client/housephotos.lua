local touring = false
local tourCam = nil

local function rotToDir(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local cosX = math.abs(math.cos(x))
    return vec3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
end

local function dirToRot(dir)
    return vec3(math.deg(math.asin(math.max(-1.0, math.min(1.0, dir.z)))), 0.0, math.deg(math.atan(-dir.x, dir.y)))
end

local function endTour()
    touring = false
    TriggerServerEvent('qbx_properties:server:photoTourEnd')
    SendUI('placement:hide')
    NewLoadSceneStop()
    RenderScriptCams(false, true, 400, true, true)
    if tourCam then
        DestroyCam(tourCam, false)
        tourCam = nil
    end
    ClearFocus()
    SetEntityVisible(cache.ped, true, false)
    FreezeEntityPosition(cache.ped, false)
end

local function streamArea(target)
    SetFocusPosAndVel(target.x, target.y, target.z, 0.0, 0.0, 0.0)
    NewLoadSceneStartSphere(target.x, target.y, target.z, 60.0, 0)

    local deadline = GetGameTimer() + 5000
    while not IsNewLoadSceneLoaded() and GetGameTimer() < deadline do Wait(50) end
    NewLoadSceneStop()
end

RegisterNetEvent('qbx_properties:client:housePhotoTour', function(mode)
    if touring then
        lib.notify({ type = 'error', description = 'A photo tour is already running.' })
        return
    end

    local tour = lib.callback.await('qbx_properties:callback:getPhotoTour', false, mode)
    if not tour or #tour == 0 then
        lib.notify({ type = 'success', description = 'Every house already has a photo.' })
        return
    end

    touring = true
    local startCoords = GetEntityCoords(cache.ped)
    local shot, skipped = 0, 0

    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do Wait(0) end

    FreezeEntityPosition(cache.ped, true)
    SetEntityVisible(cache.ped, false, false)

    tourCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', 0.0, 0.0, 100.0, 0.0, 0.0, 0.0, 55.0, false, 2)
    SetCamActive(tourCam, true)
    RenderScriptCams(true, false, 0, true, true)

    for i = 1, #tour do
        if not touring then break end

        local stop = tour[i]
        local target = vec3(stop.door.x, stop.door.y, stop.door.z)
        local inside = vec3(stop.inside.x, stop.inside.y, stop.inside.z)

        local camPos = target + vec3(6.0, -6.0, 2.0)
        local lookAt = target + vec3(0.0, 0.0, 0.6) - camPos
        local rot = dirToRot(lookAt / #lookAt)
        SetCamCoord(tourCam, camPos.x, camPos.y, camPos.z)
        SetCamRot(tourCam, rot.x, 0.0, rot.z, 2)

        SetEntityCoordsNoOffset(cache.ped, inside.x, inside.y, inside.z, false, false, false)
        FreezeEntityPosition(cache.ped, true)
        RequestCollisionAtCoord(inside.x, inside.y, inside.z)

        streamArea(target)

        local deadline = GetGameTimer() + 5000
        while not HasCollisionLoadedAroundEntity(cache.ped) and GetGameTimer() < deadline do Wait(50) end
        Wait(200)

        if IsScreenFadedOut() then DoScreenFadeIn(300) end

        SendUI('placement:show', {
            prompt = ('House %d of %d — %s'):format(i, #tour, stop.name),
            photo = true,
            tour = true,
        })

        local speed = 0.35
        local action = nil

        while touring and not action do
            Wait(0)

            HideHudAndRadarThisFrame()
            DisableAllControlActions(0)
            EnableControlAction(0, 220, true)
            EnableControlAction(0, 221, true)

            rot = vec3(
                math.max(-89.0, math.min(89.0, rot.x - GetDisabledControlNormal(0, 221) * 5.0)),
                0.0,
                rot.z - GetDisabledControlNormal(0, 220) * 7.0
            )

            if IsDisabledControlJustPressed(0, 241) then speed = math.min(3.0, speed * 1.3) end
            if IsDisabledControlJustPressed(0, 242) then speed = math.max(0.05, speed / 1.3) end

            local moveSpeed = speed * (IsDisabledControlPressed(0, 21) and 3.0 or 1.0)
            local forward = rotToDir(rot)
            local right = vec3(math.cos(math.rad(rot.z)), math.sin(math.rad(rot.z)), 0.0)
            local move = vec3(0.0, 0.0, 0.0)

            if IsDisabledControlPressed(0, 32) then move += forward end
            if IsDisabledControlPressed(0, 33) then move -= forward end
            if IsDisabledControlPressed(0, 35) then move += right end
            if IsDisabledControlPressed(0, 34) then move -= right end
            if IsDisabledControlPressed(0, 22) then move += vec3(0.0, 0.0, 1.0) end
            if IsDisabledControlPressed(0, 36) then move -= vec3(0.0, 0.0, 1.0) end

            camPos += move * moveSpeed
            SetCamCoord(tourCam, camPos.x, camPos.y, camPos.z)
            SetCamRot(tourCam, rot.x, 0.0, rot.z, 2)
            SetFocusPosAndVel(camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0)

            if IsDisabledControlJustPressed(0, 47) then action = 'snap' end
            if IsDisabledControlJustPressed(0, 73) then action = 'skip' end
            if IsDisabledControlJustPressed(0, 202) or IsDisabledControlJustPressed(0, 200) then action = 'stop' end
        end

        SendUI('placement:hide')

        if action == 'snap' then
            local hiding = true
            CreateThread(function()
                while hiding do
                    HideHudAndRadarThisFrame()
                    Wait(0)
                end
            end)
            Wait(150)

            local ok, kind = lib.callback.await('qbx_properties:callback:savePropertyPhoto', false, stop.id)
            hiding = false

            if ok then
                shot += 1
                lib.notify({ type = 'success', description = ('%s photographed (%s).'):format(stop.name, kind == 'cdn' and 'CDN' or 'local file') })
            else
                skipped += 1
                lib.notify({ type = 'error', description = kind or 'The photo could not be saved.' })
            end
        elseif action == 'skip' then
            skipped += 1
        elseif action == 'stop' then
            break
        end
    end

    local remaining = #tour - shot - skipped

    DoScreenFadeOut(300)
    while not IsScreenFadedOut() do Wait(0) end

    endTour()
    SetEntityCoordsNoOffset(cache.ped, startCoords.x, startCoords.y, startCoords.z, false, false, false)
    RequestCollisionAtCoord(startCoords.x, startCoords.y, startCoords.z)
    Wait(300)
    DoScreenFadeIn(400)

    lib.notify({
        type = 'success',
        description = ('Photo tour done — %d photographed, %d skipped%s.'):format(shot, skipped, remaining > 0 and (', %d left'):format(remaining) or ''),
        duration = 8000,
    })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource or not touring then return end
    endTour()
end)
