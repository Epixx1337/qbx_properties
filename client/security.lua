local sharedConfig = require 'config.shared'
local security = sharedConfig.security

if not security then return end

local doorbells = {}
local spawned = {}
local editable = {}
local placing = false

---@param propertyId integer
local function despawnDoorbell(propertyId)
    local entity = spawned[propertyId]
    if entity and DoesEntityExist(entity) then
        exports.ox_target:removeLocalEntity(entity)
        DeleteEntity(entity)
    end
    spawned[propertyId] = nil
end

---@param entry table
local function spawnDoorbell(entry)
    if spawned[entry.propertyId] then return end

    local hash = lib.requestModel(entry.model, 10000)
    if not hash then return end

    local object = CreateObjectNoOffset(hash, entry.coords.x, entry.coords.y, entry.coords.z, false, false, false)
    SetEntityHeading(object, entry.heading)
    FreezeEntityPosition(object, true)
    SetModelAsNoLongerNeeded(hash)
    spawned[entry.propertyId] = object

    if not editable[entry.propertyId] then return end

    local propertyId = entry.propertyId
    exports.ox_target:addLocalEntity(object, {
        {
            name = ('qbx_properties_doorbell_move_%d'):format(propertyId),
            label = 'Move doorbell',
            icon = 'fas fa-up-down-left-right',
            distance = TargetDistance('doorbell', 1.5),
            onSelect = function() PlaceDoorbell(propertyId) end,
        },
        {
            name = ('qbx_properties_doorbell_remove_%d'):format(propertyId),
            label = 'Remove doorbell',
            icon = 'fas fa-trash',
            distance = TargetDistance('doorbell', 1.5),
            onSelect = function()
                local ok = lib.callback.await('qbx_properties:callback:removeDoorbell', false, propertyId)
                lib.notify({
                    type = ok and 'success' or 'error',
                    description = ok and 'The doorbell is removed.' or 'That did not work.',
                })
            end,
        },
    })
end

local function refreshDoorbells()
    doorbells = lib.callback.await('qbx_properties:callback:getDoorbells', false) or {}
end

CreateThread(function()
    Wait(3000)
    refreshDoorbells()

    while true do
        local ped = GetEntityCoords(cache.ped)

        for i = 1, #doorbells do
            local entry = doorbells[i]
            if #(ped - entry.coords) < 60.0 then
                spawnDoorbell(entry)
            else
                despawnDoorbell(entry.propertyId)
            end
        end

        Wait(2000)
    end
end)

RegisterNetEvent('qbx_properties:client:doorbellPlaced', function(propertyId, point)
    despawnDoorbell(propertyId)

    for i = #doorbells, 1, -1 do
        if doorbells[i].propertyId == propertyId then table.remove(doorbells, i) end
    end

    if not point then return end

    local entry = {
        propertyId = propertyId,
        model = point.model,
        coords = vec3(point.x, point.y, point.z),
        heading = tonumber(point.w) or 0.0,
    }
    doorbells[#doorbells + 1] = entry

    if #(GetEntityCoords(cache.ped) - entry.coords) < 60.0 then
        spawnDoorbell(entry)
    end
end)

---@param coords vector3
---@return integer?
function FindCameraEntity(coords)
    local entity = GetClosestObjectOfType(coords.x, coords.y, coords.z, 2.0, GetHashKey(security.cameraModel), false, false, false)
    if entity ~= 0 then return entity end
end

---@param propertyId integer? the doorbell being moved, otherwise the nearest door you may furnish
function PlaceDoorbell(propertyId)
    if placing then return end

    local target = lib.callback.await('qbx_properties:callback:canPlaceDoorbell', false, propertyId)
    if not target then
        lib.notify({ type = 'error', description = 'Stand by one of your own doors to fit a doorbell.' })
        return
    end

    placing = true
    despawnDoorbell(target.propertyId)

    local prompt = target.replacing and ('Move the doorbell of %s'):format(target.name)
        or ('Fit a doorbell at %s'):format(target.name)
    local result = FreePlaceModel(target.model, prompt)

    placing = false

    if not result then
        refreshDoorbells()
        return
    end

    local ok = lib.callback.await('qbx_properties:callback:placeDoorbell', false, target.propertyId,
        vec3(result.x, result.y, result.z), result.w)

    if ok then
        lib.notify({ type = 'success', description = 'The doorbell is fitted.' })
    else
        lib.notify({ type = 'error', description = 'That spot does not work for the doorbell.' })
    end
    refreshDoorbells()
    RefreshDoorbellSpots()
end

RegisterNetEvent('qbx_properties:client:placeDoorbell', PlaceDoorbell)

local doorPoints = {}
local atDoor = 0

local function showDoorbellRadial()
    AddPropertyRadial('qbx_properties_doorbell', {
        label = 'Place doorbell',
        icon = 'bell',
        onSelect = function() PlaceDoorbell() end,
    })
end

function RefreshDoorbellSpots()
    for i = 1, #doorPoints do doorPoints[i]:remove() end
    table.wipe(doorPoints)

    atDoor = 0
    RemovePropertyRadial('qbx_properties_doorbell')

    local spots = lib.callback.await('qbx_properties:callback:getDoorbellSpots', false) or {}
    local range = (security.doorbellRange or 2.0) + 1.0

    table.wipe(editable)
    for i = 1, #spots do editable[spots[i].propertyId] = true end

    for propertyId in pairs(spawned) do
        despawnDoorbell(propertyId)
    end

    for i = 1, #spots do
        doorPoints[#doorPoints + 1] = lib.points.new({
            coords = spots[i].coords,
            distance = range,
            onEnter = function()
                atDoor = atDoor + 1
                showDoorbellRadial()
            end,
            onExit = function()
                atDoor = math.max(atDoor - 1, 0)
                if atDoor == 0 then RemovePropertyRadial('qbx_properties_doorbell') end
            end,
        })
    end
end

RegisterNetEvent('qbx_properties:client:invalidateUnitAccess', RefreshDoorbellSpots)
RegisterNetEvent('qbx_properties:client:refreshBlips', RefreshDoorbellSpots)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', RefreshDoorbellSpots)

CreateThread(function()
    Wait(3000)
    if LocalPlayer.state.isLoggedIn then RefreshDoorbellSpots() end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    for propertyId in pairs(spawned) do
        despawnDoorbell(propertyId)
    end
    for i = 1, #doorPoints do doorPoints[i]:remove() end
end)
