local sharedConfig = require 'config.shared'

if not sharedConfig.gardens.enabled then return end

CurrentGardenId = nil
local zones = {}
local spawned = {}

local function unloadGarden(propertyId)
    local ids = spawned[propertyId]
    if not ids then return end

    for i = 1, #ids do
        DespawnDecoration(ids[i])
    end

    spawned[propertyId] = nil
end

local function loadGarden(propertyId)
    if spawned[propertyId] then return end
    spawned[propertyId] = {}

    local decorations = lib.callback.await('qbx_properties:callback:getGardenDecorations', false, propertyId)
    if not decorations then return end

    local ids = spawned[propertyId]
    for i = 1, #decorations do
        if SpawnDecoration(decorations[i]) then
            ids[#ids + 1] = decorations[i].id
        end
    end
end

---@param propertyId integer
---@param zone table
function RegisterGardenZone(propertyId, zone)
    local points = zone.points or zone
    local height = zone.height or sharedConfig.gardens.height
    if zones[propertyId] then zones[propertyId]:remove() end

    local vectors = {}
    local sumZ = 0
    for i = 1, #points do
        vectors[i] = vec3(points[i].x, points[i].y, points[i].z)
        sumZ = sumZ + points[i].z
    end

    zones[propertyId] = lib.zones.poly({
        points = vectors,
        thickness = height,
        debug = false,
        onEnter = function()
            CreateThread(function()
                loadGarden(propertyId)
                TriggerServerEvent('qbx_properties:server:enterGarden', propertyId)
                if lib.callback.await('qbx_properties:callback:canDecorateGarden', false, propertyId) then
                    CurrentGardenId = propertyId
                    AddDecorateRadial()
                end
            end)
        end,
        onExit = function()
            unloadGarden(propertyId)
            TriggerServerEvent('qbx_properties:server:leaveGarden')
            if CurrentGardenId == propertyId then
                CurrentGardenId = nil
                if not CurrentPropertyId then RemoveDecorateRadial() end
            end
        end,
    })
end

---@param propertyId integer
function RemoveGardenZone(propertyId)
    if zones[propertyId] then
        zones[propertyId]:remove()
        zones[propertyId] = nil
    end
    unloadGarden(propertyId)
end

RegisterNetEvent('qbx_properties:client:registerGarden', function(propertyId, zone)
    RegisterGardenZone(propertyId, zone)
end)

RegisterNetEvent('qbx_properties:client:removeGarden', function(propertyId)
    RemoveGardenZone(propertyId)
end)

RegisterNetEvent('qbx_properties:client:gardenDecoration', function(propertyId, decoration)
    local ids = spawned[propertyId]
    if not ids then return end

    for i = #ids, 1, -1 do
        if ids[i] == decoration.id then
            if decoration.removed then DespawnDecoration(ids[i]) end
            table.remove(ids, i)
        end
    end

    if decoration.removed then return end

    if SpawnDecoration(decoration) then
        ids[#ids + 1] = decoration.id
    end
end)

CreateThread(function()
    Wait(2500)
    local gardens = lib.callback.await('qbx_properties:callback:getGardens', false)
    for i = 1, #gardens do
        RegisterGardenZone(gardens[i].id, { points = gardens[i].points, height = gardens[i].height })
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    for propertyId in pairs(spawned) do
        unloadGarden(propertyId)
    end
end)
