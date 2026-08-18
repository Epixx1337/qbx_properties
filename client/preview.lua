local sharedConfig = require 'config.shared'

local previewShell
local previewInterior
local returnCoords
local previewPoints = {}
local editingProperty = nil
local editingOrigin = nil
local setupMode = false
local lastSetupShell = nil

local INTERACTIONS = { 'exit', 'stash', 'clothing', 'logout' }

function IsPreviewing()
    return previewInterior ~= nil
end

local function pushPreview()
    if editingProperty then
        SendUI('preview:state', {
            interior = editingProperty.label,
            points = previewPoints,
            types = { 'exit', 'stash', 'clothing', 'logout' },
            property = true,
        })
        return
    end
    SendUI('preview:state', {
        interior = tostring(previewInterior),
        points = previewPoints,
        types = INTERACTIONS,
        setup = setupMode,
    })
end

---@param interior string|number
local previewReturnTo = nil

---@param coords vector3
local function settleAtCoords(coords)
    SetEntityCoords(cache.ped, coords.x, coords.y, coords.z, false, false, false, false)
    FreezeEntityPosition(cache.ped, true)

    local deadline = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(cache.ped) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(50)
    end

    FreezeEntityPosition(cache.ped, false)
end

---Teleports to a height and reports whether the ped found footing instead of falling out.
---@return boolean
local function tryLanding(x, y, z, floorZ, topZ)
    SetEntityCoords(cache.ped, x, y, z, false, false, false, false)
    FreezeEntityPosition(cache.ped, true)

    local deadline = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(cache.ped) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(x, y, z)
        Wait(50)
    end

    FreezeEntityPosition(cache.ped, false)

    local settle = GetGameTimer() + 900
    while GetGameTimer() < settle do
        Wait(50)
        if GetEntityCoords(cache.ped).z < floorZ - 2.0 then return false end
    end

    local pz = GetEntityCoords(cache.ped).z
    return pz >= floorZ - 2.0 and pz <= topZ + 2.0
end

function StartShellPreview(interior, returnTo)
    if previewInterior then return end

    previewReturnTo = returnTo
    setupMode = returnTo == 'setup'
    previewInterior = interior
    returnCoords = GetEntityCoords(cache.ped)
    previewPoints = {}

    local defaults = lib.callback.await('qbx_properties:callback:getShellDefaults', false, tostring(interior))
    if defaults then previewPoints = defaults end

    local hash = tonumber(interior)
    if not hash and IsModelValid(joaat(interior)) then hash = joaat(interior) end

    if hash then
        if not IsModelValid(hash) then
            previewInterior = nil
            lib.notify({ type = 'error', description = 'That shell is not streamed on this server.' })
            lib.print.warn(('shell model %s is not streamed'):format(interior))
            return
        end

        lib.requestModel(hash, 60000)
        previewShell = CreateObject(hash, returnCoords.x, returnCoords.y, returnCoords.z - sharedConfig.shellUndergroundOffset, false, false, false)
        FreezeEntityPosition(previewShell, true)
        SetModelAsNoLongerNeeded(hash)

        local points = GetInteriorPoints(hash)
        if points and points.exit then
            local entry = CalculateOffsetCoords(returnCoords, points.exit)
            settleAtCoords(vec3(entry.x, entry.y, entry.z))
        else
            local min, max = GetModelDimensions(hash)
            local base = vec3(returnCoords.x, returnCoords.y, returnCoords.z - sharedConfig.shellUndergroundOffset)
            local cx = base.x + (min.x + max.x) / 2
            local cy = base.y + (min.y + max.y) / 2
            local floorZ, topZ = base.z + min.z, base.z + max.z
            local span = max.z - min.z

            local candidates = {
                base.z + 1.0,
                floorZ + span * 0.5 + 1.0,
                floorZ + 2.0,
                floorZ + span * 0.25 + 1.0,
                floorZ + span * 0.75 + 1.0,
            }

            local landed = false
            local tried = {}

            for i = 1, #candidates do
                local duplicate = false
                for j = 1, #tried do
                    if math.abs(tried[j] - candidates[i]) < 0.5 then duplicate = true break end
                end

                if not duplicate then
                    tried[#tried + 1] = candidates[i]
                    if tryLanding(cx, cy, candidates[i], floorZ, topZ) then
                        landed = true
                        break
                    end
                end
            end

            if not landed then
                SetEntityCoords(cache.ped, cx, cy, base.z + 1.0, false, false, false, false)
                lib.notify({ type = 'error', description = 'Could not find the shell floor, noclip to position yourself.' })
            end
        end
    else
        local points = GetInteriorPoints(interior)
        if points and points.exit then
            local entry = points.exit
            SetEntityCoords(cache.ped, entry.x, entry.y, entry.z, false, false, false, false)
        end
    end

    local players = GetActivePlayers()
    for i = 1, #players do
        if players[i] ~= cache.playerId then NetworkConcealPlayer(players[i], true, false) end
    end

    OpenUI('preview')
    SetUIFocus(false)
    pushPreview()
end

function StopShellPreview()
    if not previewInterior then return end

    if previewShell and DoesEntityExist(previewShell) then DeleteEntity(previewShell) end
    if returnCoords then
        SetEntityCoords(cache.ped, returnCoords.x, returnCoords.y, returnCoords.z, false, false, false, false)
    end

    local players = GetActivePlayers()
    for i = 1, #players do
        if players[i] ~= cache.playerId then NetworkConcealPlayer(players[i], false, false) end
    end

    previewShell = nil
    previewInterior = nil
    returnCoords = nil
    CloseUI()

    if previewReturnTo == 'create' then
        previewReturnTo = nil
        OpenUI('housing')
        SendUI('housing:tab', 'create')
        RefreshDraftPoints()
    end
    previewReturnTo = nil
end

CreateThread(function()
    while true do
        if previewInterior then
            if IsControlJustReleased(0, 202) then StopShellPreview() end
            if IsControlJustReleased(0, 38) then SetUIFocus(true) end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

RegisterNUICallback('preview:capture', function(data, cb)
    cb(1)
    if not previewInterior or type(data) ~= 'table' then return end

    SetUIFocus(false)
    local coords, _, heading = PickWithLaser(('Aim where the %s point should be and click'):format(tostring(data.type)))
    if not coords then
        pushPreview()
        return
    end

    local shellHash = tonumber(previewInterior) or (IsModelValid(joaat(previewInterior)) and joaat(previewInterior) or nil)
    local origin = shellHash and returnCoords or vec3(0, 0, 0)
    local relative = shellHash
        and vec3(coords.x - origin.x, coords.y - origin.y, coords.z - (origin.z - sharedConfig.shellUndergroundOffset))
        or coords

    previewPoints[data.type] = {
        x = relative.x,
        y = relative.y,
        z = relative.z,
        w = heading or GetEntityHeading(cache.ped),
    }

    pushPreview()
end)

RegisterNUICallback('preview:save', function(_, cb)
    cb(1)
    if not previewInterior then return end

    local ok = lib.callback.await('qbx_properties:callback:saveShellDefaults', false, tostring(previewInterior), previewPoints)
    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and 'Interaction points saved.' or 'Could not save interaction points.',
    })
end)

RegisterNUICallback('preview:exit', function(_, cb)
    cb(1)
    StopShellPreview()
end)

function StartPropertyPointEditor()
    if previewInterior or editingProperty or not CurrentPropertyId then return end

    local info = lib.callback.await('qbx_properties:callback:getPropertyPoints', false, CurrentPropertyId)
    if not info then
        lib.notify({ type = 'error', description = 'Could not load this property.' })
        return
    end

    editingProperty = { id = CurrentPropertyId, label = info.label, isShell = info.isShell }
    editingOrigin = info.isShell and vec3(info.origin.x, info.origin.y, info.origin.z) or nil
    previewPoints = info.points or {}

    OpenUI('preview')
    SetUIFocus(false)
    pushPreview()
end

local function stopPropertyPointEditor()
    editingProperty = nil
    editingOrigin = nil
    previewPoints = {}
    CloseUI()
end

CreateThread(function()
    while true do
        if editingProperty then
            if IsControlJustReleased(0, 202) then stopPropertyPointEditor() end
            if IsControlJustReleased(0, 38) then SetUIFocus(true) end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

RegisterNUICallback('preview:captureProperty', function(data, cb)
    cb(1)
    if not editingProperty or type(data) ~= 'table' then return end

    SetUIFocus(false)
    local coords, _, heading = PickWithLaser(('Aim where the %s point should be and click'):format(tostring(data.type)))
    if not coords then
        pushPreview()
        return
    end

    local relative = editingOrigin
        and vec3(coords.x - editingOrigin.x, coords.y - editingOrigin.y, coords.z - editingOrigin.z + sharedConfig.shellUndergroundOffset)
        or coords

    previewPoints[data.type] = {
        x = relative.x,
        y = relative.y,
        z = relative.z,
        w = heading or GetEntityHeading(cache.ped),
    }

    pushPreview()
end)

RegisterNUICallback('preview:saveProperty', function(_, cb)
    cb(1)
    if not editingProperty then return end

    local ok = lib.callback.await('qbx_properties:callback:savePropertyPoints', false, editingProperty.id, previewPoints)
    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and 'Points saved and applied.' or 'Could not save the points.',
    })

    if ok then stopPropertyPointEditor() end
end)

RegisterNUICallback('preview:exitProperty', function(_, cb)
    cb(1)
    stopPropertyPointEditor()
end)

-- temporary dev command: cycles through shells (and with 'all', every interior) to set their points
local setupQueue = nil

local function advanceShellSetup()
    if not setupQueue or #setupQueue == 0 then
        setupQueue = nil
        lastSetupShell = nil
        lib.notify({ type = 'success', description = 'Shell setup finished.' })
        return
    end

    local target = table.remove(setupQueue, 1)
    lastSetupShell = target

    lib.notify({
        type = 'inform',
        description = string.format('Starting %s — %d more after this.', target, #setupQueue),
    })
    StartShellPreview(target, 'setup')
end

local function startShellSetup(_, args)
    if not IsRealtor(QBX.PlayerData.job) then return end
    if previewInterior or editingProperty then
        lib.notify({ type = 'error', description = 'Finish the current preview first.' })
        return
    end

    local everything = type(args) == 'table' and args[1] == 'all'
    local queue = {}

    for name in pairs(GetInteriorList()) do
        if everything then
            queue[#queue + 1] = name
        elseif IsModelValid(joaat(name)) then
            local defaults = lib.callback.await('qbx_properties:callback:getShellDefaults', false, tostring(name))
            if not defaults or not defaults.exit then
                queue[#queue + 1] = name
            end
        end
    end
    table.sort(queue)

    if #queue == 0 then
        lib.notify({ type = 'success', description = 'Every streamed shell has its points set.' })
        return
    end

    setupQueue = queue
    advanceShellSetup()
end

RegisterNUICallback('preview:nextShell', function(_, cb)
    cb(1)
    if not setupMode or not previewInterior then return end

    StopShellPreview()
    Wait(100)
    advanceShellSetup()
end)

RegisterCommand('shellsetup', startShellSetup, false)
