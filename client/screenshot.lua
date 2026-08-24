local sharedConfig = require 'config.shared'
local config = require 'config.client'

local STUDIO_COORDS = vec3(-1899.83, -3340.52, 150.24)

local COLORS = {
    green = { 0, 255, 0 },
    magenta = { 255, 0, 255 },
    blue = { 0, 60, 255 },
    orange = { 255, 128, 0 },
}
local MATTE_PARTNER = { green = 'magenta', magenta = 'green', blue = 'orange', orange = 'blue' }

local session

local backdropActive = false
local backdropColor = COLORS.green
local backdropCenter, backdropRight, backdropUp
local subjectPos, camPos

local function setBackdropColor(name)
    backdropColor = COLORS[name] or COLORS.green
end

---@param subjectCoords vector3
---@param camCoords vector3
---@param fov number
---@param behind number how far behind the subject the quad sits
local function placeBackdrop(subjectCoords, camCoords, fov, behind)
    subjectPos, camPos = subjectCoords, camCoords
    local toCam = camCoords - subjectCoords
    local dist = #toCam
    local viewDir = -toCam / dist
    backdropCenter = subjectCoords + viewDir * behind

    -- camera-aligned axes so the quad fills the frame at any pitch, sized for the widest aspect
    local aspect = GetAspectRatio(false)
    if not aspect or aspect < 1.0 or aspect > 4.0 then aspect = 1.78 end
    local size = math.tan(math.rad(fov) / 2) * (dist + behind) * aspect * 1.35

    local right = vec3(viewDir.y, -viewDir.x, 0.0)
    local rightLen = #right
    if rightLen < 0.01 then right = vec3(1.0, 0.0, 0.0) else right = right / rightLen end
    local up = vec3(
        viewDir.y * right.z - viewDir.z * right.y,
        viewDir.z * right.x - viewDir.x * right.z,
        viewDir.x * right.y - viewDir.y * right.x)

    backdropRight = right * size
    backdropUp = up * size
end

local function startBackdrop()
    if backdropActive then return end
    backdropActive = true
    NetworkOverrideClockTime(12, 30, 0)
    NetworkOverrideClockMillisecondsPerGameMinute(1000000)
    SetOverrideWeather('EXTRASUNNY')
    SetWind(0.0)
    SetWindSpeed(0.0)

    CreateThread(function()
        while backdropActive do
            HideHudAndRadarThisFrame()
            if subjectPos and camPos then
                local dir = subjectPos - camPos
                dir = dir / #dir
                DrawSpotLight(camPos.x, camPos.y, camPos.z + 0.3, dir.x, dir.y, dir.z,
                    255, 255, 255, 12.0, 1.1, 0.0, 13.0, 1.0)
                DrawLightWithRange(subjectPos.x, subjectPos.y, subjectPos.z + 0.8,
                    255, 255, 255, 3.5, 0.9)
            end
            if backdropCenter then
                local r, g, b = backdropColor[1], backdropColor[2], backdropColor[3]
                local a = backdropCenter - backdropRight - backdropUp
                local bq = backdropCenter + backdropRight - backdropUp
                local c = backdropCenter + backdropRight + backdropUp
                local d = backdropCenter - backdropRight + backdropUp
                DrawPoly(a.x, a.y, a.z, bq.x, bq.y, bq.z, c.x, c.y, c.z, r, g, b, 255)
                DrawPoly(a.x, a.y, a.z, c.x, c.y, c.z, d.x, d.y, d.z, r, g, b, 255)
                DrawPoly(c.x, c.y, c.z, bq.x, bq.y, bq.z, a.x, a.y, a.z, r, g, b, 255)
                DrawPoly(d.x, d.y, d.z, c.x, c.y, c.z, a.x, a.y, a.z, r, g, b, 255)
            end
            Wait(0)
        end
    end)
end

local function stopBackdrop()
    backdropActive = false
    backdropCenter = nil
    subjectPos, camPos = nil, nil
    NetworkOverrideClockMillisecondsPerGameMinute(2000)
    NetworkClearClockTimeOverride()
    ClearOverrideWeather()
end

local function captureRaw()
    local p = promise.new()
    local settled = false
    local function settle(value)
        if settled then return end
        settled = true
        p:resolve(value)
    end
    exports.screencapture:requestScreenshot({ encoding = 'png' }, settle)
    SetTimeout(10000, function() settle(nil) end)
    return Citizen.Await(p)
end

local pendingProcess = {}
local processCounter = 0

RegisterNUICallback('screenshot:processed', function(data, cb)
    cb(1)
    local p = type(data) == 'table' and pendingProcess[data.id]
    if not p then return end
    pendingProcess[data.id] = nil
    p:resolve(data.result or { ok = false, error = 'no result' })
end)

---@param filename string
---@return table result { ok, clipped?, error? }
local function takeShot(filename)
    local primary = session.primary
    setBackdropColor(primary)
    Wait(120)
    local raw1 = captureRaw()
    setBackdropColor(MATTE_PARTNER[primary] or 'magenta')
    Wait(120)
    local raw2 = captureRaw()
    setBackdropColor(primary)
    if not raw1 or raw1 == '' or not raw2 or raw2 == '' then
        return { ok = false, error = 'capture failed' }
    end

    processCounter += 1
    local id = processCounter
    local p = promise.new()
    pendingProcess[id] = p
    SendNUIMessage({ action = 'screenshot:process', data = { id = id, uri1 = raw1, uri2 = raw2 } })
    SetTimeout(15000, function()
        if pendingProcess[id] then
            pendingProcess[id] = nil
            p:resolve({ ok = false, error = 'process timeout' })
        end
    end)
    local result = Citizen.Await(p)

    if result.ok and result.dataUri then
        local base64 = result.dataUri
        result.dataUri = nil
        if #base64 > 120000 then
            return { ok = false, error = 'image too large for transport' }
        end
        local write = lib.callback.await('qbx_properties:callback:furnitureShotWrite', false, filename, base64)
        if not write or not write.ok then
            return { ok = false, error = write and write.error or 'write failed' }
        end
        session.existing[filename .. '.webp'] = true
    end
    return result
end

local function currentItem()
    return session and session.work[session.index]
end

---@param item table
---@return table? tuning entry for this object
local function itemTuning(item)
    local tune = session.tuning[item.object]
    return type(tune) == 'table' and tune or nil
end

-- computes the camera for the current item from config, saved tuning and live nudges
local function reframe(zoomExtra)
    local item = currentItem()
    local object = session.object
    if not item or not object or not DoesEntityExist(object) then return end

    local modelHash = GetEntityModel(object)
    local minDimension, maxDimension = GetModelDimensions(modelHash)
    local modelSize = maxDimension - minDimension
    local tune = itemTuning(item)

    local fov = (tune and tune.fov) or item.screenshotFov
        or math.min(math.max(modelSize.x, modelSize.y) / 0.35 * 10, 60)
    fov = math.min(math.max(fov + session.nudge.fov, 5.0), 100.0)

    local objectCoords = GetEntityCoords(object)
    local center = vec3(
        objectCoords.x + (minDimension.x + maxDimension.x) / 2,
        objectCoords.y + (minDimension.y + maxDimension.y) / 2,
        objectCoords.z + (minDimension.z + maxDimension.z) / 2)

    local offset
    if tune and tune.camOffset then
        offset = vec3(tune.camOffset.x, tune.camOffset.y, tune.camOffset.z)
    elseif item.screenshotCameraOffset then
        offset = item.screenshotCameraOffset
    elseif modelSize.z < 0.25 then
        -- flat pieces (tiles, rugs) get a raised camera looking down at the face
        local span = math.max(modelSize.x, modelSize.y, 1.0)
        offset = vec3(0.55, -0.55, 1.1) * span
    else
        local objectForward = -GetEntityForwardVector(object) * 2
        offset = objectForward * 2 + vec3(1.5, -1, 1.5 * modelSize.z)
    end

    if session.nudge.dist ~= 0 or session.nudge.z ~= 0 then
        local dir = offset / #offset
        offset = offset + dir * session.nudge.dist + vec3(0.0, 0.0, session.nudge.z)
    end
    if zoomExtra and zoomExtra > 0 then
        offset = offset * (1.0 + zoomExtra)
    end

    local cameraPosition = center + offset
    SetCamFov(session.cam, fov)
    SetCamCoord(session.cam, cameraPosition.x, cameraPosition.y, cameraPosition.z)
    PointCamAtCoord(session.cam, center.x, center.y, center.z)

    local behind = math.max(2.0, #modelSize * 0.75)
    placeBackdrop(center, cameraPosition, fov, behind)
    session.lastFrame = { offset = offset, fov = fov }
end

local function pushProgress()
    local item = currentItem()
    SendNUIMessage({ action = 'shotstudio:progress', data = {
        index = session.index, total = #session.work,
        label = item and item.label or '', object = item and item.object or '',
        paused = session.paused, primary = session.primary,
        done = session.done, skipped = session.skipped, failed = session.failed, empty = session.empty,
        hasImage = item and session.existing[item.object .. '.webp'] == true or false,
        tuned = item and itemTuning(item) ~= nil or false,
    } })
end

-- spawns the current item in front of the camera without shooting it
local function showItem()
    if session.object and DoesEntityExist(session.object) then DeleteEntity(session.object) end
    session.object = nil
    session.shownIndex = nil

    local item = currentItem()
    if not item then return false end

    local modelHash = joaat(item.object)
    if not IsModelValid(modelHash) then return false end

    lib.requestModel(modelHash, 60000)
    local object = CreateObjectNoOffset(modelHash, STUDIO_COORDS.x, STUDIO_COORDS.y, STUDIO_COORDS.z, false, false, false)
    SetModelAsNoLongerNeeded(modelHash)
    FreezeEntityPosition(object, true)
    session.object = object

    local tune = itemTuning(item)
    local spin = (tune and tune.rot) or item.screenshotRotation
    if spin then SetEntityRotation(object, spin.x, spin.y, spin.z, 2, false) end

    session.shownIndex = session.index
    reframe()
    pushProgress()
    return true
end

---@return 'done'|'empty'|'invalid'|string
local function shootCurrent()
    local item = currentItem()
    if not item then return 'invalid' end
    -- keep the shown object (and any live drag rotation) when re-shooting the same item
    if session.shownIndex ~= session.index or not session.object or not DoesEntityExist(session.object) then
        if not showItem() then return 'invalid' end
    end
    Wait(300)

    local outcome
    local zoomExtra = 0.0
    local clipTries = 0
    local matteFlips = 0
    while true do
        if session.stopped then
            outcome = 'stopped'
            break
        end
        local result = takeShot(item.object)
        if not result.ok then
            if result.error == 'nothing visible after matting' and matteFlips < 1
                and session.primary == 'green' then
                matteFlips += 1
                session.primary = 'blue'
                pushProgress()
            elseif result.error == 'nothing visible after matting' then
                outcome = 'empty'
                break
            else
                outcome = result.error or 'unknown'
                break
            end
        elseif result.clipped and clipTries < 3 then
            clipTries += 1
            zoomExtra += 0.18
            reframe(zoomExtra)
            Wait(200)
        else
            outcome = 'done'
            break
        end
    end
    if matteFlips > 0 then session.primary = 'green' end
    return outcome
end

local function tallyOutcome(outcome, item)
    if outcome == 'done' then
        session.done += 1
    elseif outcome == 'empty' then
        session.empty += 1
        lib.print.warn(("'%s' rendered nothing to photograph"):format(item.object))
    elseif outcome == 'invalid' then
        session.failed += 1
        lib.print.warn(("skipping invalid furniture model '%s'"):format(item.object))
    elseif outcome ~= 'stopped' then
        session.failed += 1
        lib.print.warn(("shot failed for '%s': %s"):format(item.object, outcome))
    end
end

local function stopStudio()
    if not session then return end
    local s = session
    session = nil

    stopBackdrop()
    if s.object and DoesEntityExist(s.object) then DeleteEntity(s.object) end
    DestroyCam(s.cam, false)
    RenderScriptCams(false, false, 0, false, false)
    DisableIdleCamera(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'shotstudio:close' })

    lib.notify({
        type = s.failed > 0 and 'error' or 'success',
        duration = 10000,
        description = ('Catalog shoot finished: %d shot, %d skipped, %d failed, %d empty.'):format(s.done, s.skipped, s.failed, s.empty),
    })
end

RegisterNUICallback('shotstudio:control', function(data, cb)
    cb(1)
    if not session or type(data) ~= 'table' then return end
    local action = data.action

    if action == 'pause' then
        session.paused = true
        if not session.object then showItem() else pushProgress() end
    elseif action == 'resume' then
        session.paused = false
        pushProgress()
    elseif action == 'stop' then
        session.stopped = true
    elseif action == 'back' or action == 'next' then
        session.paused = true
        session.index = math.max(1, math.min(#session.work, session.index + (action == 'next' and 1 or -1)))
        showItem()
    elseif action == 'shoot' then
        session.takeNow = true
    elseif action == 'background' and MATTE_PARTNER[data.color] then
        session.primary = data.color
        setBackdropColor(data.color)
        pushProgress()
    elseif action == 'adjust' then
        local object = session.object
        if data.dx and data.dx ~= 0 and object and DoesEntityExist(object) then
            local rot = GetEntityRotation(object, 2)
            SetEntityRotation(object, rot.x, rot.y, (rot.z + data.dx * 0.4) % 360.0, 2, false)
        end
        if data.dy and data.dy ~= 0 then
            session.nudge.z = session.nudge.z + data.dy * 0.004
        end
        reframe()
    elseif action == 'zoom' and data.dir then
        session.nudge.dist = session.nudge.dist - data.dir * 0.12
        reframe()
    elseif action == 'fov' and data.dir then
        session.nudge.fov = session.nudge.fov + data.dir * 2.0
        reframe()
    elseif action == 'save' then
        local item = currentItem()
        local object = session.object
        if not item or not object or not DoesEntityExist(object) or not session.lastFrame then return end
        local rot = GetEntityRotation(object, 2)
        local offset = session.lastFrame.offset
        session.tuning[item.object] = {
            rot = { x = rot.x, y = rot.y, z = rot.z },
            camOffset = { x = offset.x, y = offset.y, z = offset.z },
            fov = session.lastFrame.fov,
        }
        session.nudge.z, session.nudge.dist, session.nudge.fov = 0.0, 0.0, 0.0
        lib.callback.await('qbx_properties:callback:furnitureShotSaveTuning', false, session.tuning)
        reframe()
        pushProgress()
        lib.notify({ type = 'success', description = ('Framing saved for %s.'):format(item.object) })
    elseif action == 'clearTune' then
        local item = currentItem()
        if not item or not itemTuning(item) then return end
        session.tuning[item.object] = nil
        lib.callback.await('qbx_properties:callback:furnitureShotSaveTuning', false, session.tuning)
        showItem()
        lib.notify({ type = 'success', description = ('Framing cleared for %s.'):format(item.object) })
    end
end)

RegisterNetEvent('qbx_properties:client:screenshotFurniture', function(mode)
    if session then
        lib.notify({ type = 'error', description = 'A screenshot run is already going.' })
        return
    end
    if GetResourceState('screencapture') ~= 'started' then
        lib.notify({ type = 'error', description = 'The screencapture resource is not running.' })
        return
    end

    local work = {}
    for _, items in pairs(config.furniture) do
        for i = 1, #items do
            work[#work + 1] = items[i]
        end
    end

    session = {
        work = work, index = 1,
        paused = mode == 'manual', stopped = false, takeNow = false,
        overwrite = mode == 'overwrite',
        primary = 'green',
        nudge = { z = 0.0, dist = 0.0, fov = 0.0 },
        existing = {}, tuning = {},
        done = 0, skipped = 0, failed = 0, empty = 0,
    }

    local listed = lib.callback.await('qbx_properties:callback:furnitureShotList', false)
    if listed and listed.ok then
        for i = 1, #listed.files do session.existing[listed.files[i]] = true end
    end
    local tuningResult = lib.callback.await('qbx_properties:callback:furnitureShotTuning', false)
    if tuningResult and tuningResult.ok then session.tuning = tuningResult.tuning or {} end

    DisableIdleCamera(true)
    session.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    RenderScriptCams(true, false, 0, false, false)
    startBackdrop()
    SendNUIMessage({ action = 'shotstudio:open', data = { total = #work } })
    SetNuiFocus(true, true)

    if session.paused then
        showItem()
    end

    CreateThread(function()
        while session and not session.stopped and session.index <= #session.work do
            if session.paused then
                if session.takeNow then
                    session.takeNow = false
                    local item = currentItem()
                    local outcome = shootCurrent()
                    tallyOutcome(outcome, item)
                    session.paused = true
                    pushProgress()
                else
                    Wait(150)
                end
            else
                local item = currentItem()
                if not session.overwrite and session.existing[item.object .. '.webp'] then
                    session.skipped += 1
                else
                    tallyOutcome(shootCurrent(), item)
                end
                pushProgress()
                if not session.paused then
                    session.index += 1
                end
            end
        end
        stopStudio()
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    if not session and not backdropActive then return end
    stopBackdrop()
    SetNuiFocus(false, false)
    RenderScriptCams(false, false, 0, false, false)
end)

local cachedCdnMap

---@return table? map of file name to CDN url, nil when serving local files
function GetFurnitureCdnMap()
    if sharedConfig.furnitureImageSource ~= 'cdn' then return nil end
    if not cachedCdnMap then
        cachedCdnMap = lib.callback.await('qbx_properties:callback:furnitureCdnMap', false) or {}
    end
    return cachedCdnMap
end
