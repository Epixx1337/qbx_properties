local sharedConfig = require 'config.shared'

local streamedShells = {}
local shellZones = {}

---@param model number|string
---@param origin vector3
---@return vector4?
function PlaceShell(model, origin)
    local hash = lib.requestModel(model, 60000)
    if not hash then return end

    local shell = CreateObject(hash, origin.x, origin.y, origin.z, false, false, false)
    SetEntityCollision(shell, false, false)
    SetEntityAlpha(shell, 180, false)
    FreezeEntityPosition(shell, true)
    SetModelAsNoLongerNeeded(hash)

    lib.showTextUI('[T] Move  \n [R] Rotate  \n [L] World / local  \n [ENTER] Confirm  \n [BACKSPACE] Cancel')

    local confirmed = false
    local cancelled = false

    while not confirmed and not cancelled do
        Wait(0)

        local matrixBuffer = MakeGizmoMatrix(shell)
        if Citizen.InvokeNative(0xEB2EDCA2, matrixBuffer:Buffer(), 'ShellPlacement', Citizen.ReturnResultAnyway()) then
            ApplyGizmoMatrix(shell, matrixBuffer)
        end

        if IsControlJustPressed(0, 191) then confirmed = true end
        if IsControlJustPressed(0, 202) then cancelled = true end
    end

    lib.hideTextUI()

    local coords = GetEntityCoords(shell)
    local heading = GetEntityHeading(shell)
    DeleteEntity(shell)

    if cancelled then return end
    return vec4(coords.x, coords.y, coords.z, heading)
end

---@param propertyId integer
---@param model number|string
---@param coords vector4
local function createShell(propertyId, model, coords)
    if streamedShells[propertyId] then return end

    local hash = lib.requestModel(model, 60000)
    if not hash then return end

    local shell = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(shell, coords.w)
    FreezeEntityPosition(shell, true)
    SetModelAsNoLongerNeeded(hash)

    streamedShells[propertyId] = shell
end

---@param propertyId integer
local function removeShell(propertyId)
    local shell = streamedShells[propertyId]
    if not shell then return end

    if DoesEntityExist(shell) then DeleteEntity(shell) end
    streamedShells[propertyId] = nil
end

---@param propertyId integer
---@param model number|string
---@param coords vector4
function RegisterShellZone(propertyId, model, coords)
    if shellZones[propertyId] then shellZones[propertyId]:remove() end

    shellZones[propertyId] = lib.zones.sphere({
        coords = vec3(coords.x, coords.y, coords.z),
        radius = sharedConfig.shellStreamDistance or 60.0,
        onEnter = function() createShell(propertyId, model, coords) end,
        onExit = function() removeShell(propertyId) end,
    })
end

---@param propertyId integer
function RemoveShellZone(propertyId)
    if shellZones[propertyId] then
        shellZones[propertyId]:remove()
        shellZones[propertyId] = nil
    end
    removeShell(propertyId)
end

RegisterNetEvent('qbx_properties:client:registerShell', function(propertyId, model, coords)
    RegisterShellZone(propertyId, model, coords)
end)

RegisterNetEvent('qbx_properties:client:removeShell', function(propertyId)
    RemoveShellZone(propertyId)
end)

RegisterNetEvent('qbx_properties:client:loadShells', function(shells)
    for i = 1, #shells do
        RegisterShellZone(shells[i].id, shells[i].model, shells[i].coords)
    end
end)

CreateThread(function()
    Wait(2000)
    local shells = lib.callback.await('qbx_properties:callback:getShells', false)
    for i = 1, #shells do
        RegisterShellZone(shells[i].id, shells[i].model, shells[i].coords)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    for propertyId in pairs(streamedShells) do
        removeShell(propertyId)
    end
end)
