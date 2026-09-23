local sharedConfig = require 'config.shared'
local security = sharedConfig.security

if not security then return end

local doorbells = {}
local spawned = {}
local attachedTo = {}
local editable = {}
local placing = false

---@param a number
---@param b number
---@return boolean
local function sameModel(a, b)
    return a % 4294967296 == b % 4294967296
end

-- a dynamic interior swaps the door for a fresh entity as it loads, so the bell is re-hung
-- against whatever door is there now rather than once
---@param entry table
---@param object integer
---@return boolean
local function attachToDoor(entry, object)
    local door = entry.door
    if not door then return false end

    local entity = GetClosestObjectOfType(door.x, door.y, door.z, 1.5, door.model, false, false, false)
    if entity == 0 or not DoesEntityExist(entity) then return false end

    if attachedTo[entry.propertyId] == entity and IsEntityAttachedToEntity(object, entity) then
        return true
    end

    if IsEntityAttached(object) then DetachEntity(object, false, false) end
    FreezeEntityPosition(object, false)
    AttachEntityToEntity(object, entity, 0, door.ox, door.oy, door.oz, 0.0, 0.0, door.w, false, false, false, false, 2, true)
    attachedTo[entry.propertyId] = entity
    return true
end

---@param propertyId integer
local function despawnDoorbell(propertyId)
    local entity = spawned[propertyId]
    if entity and DoesEntityExist(entity) then
        exports.ox_target:removeLocalEntity(entity)
        DeleteEntity(entity)
    end
    spawned[propertyId] = nil
    attachedTo[propertyId] = nil
end

---@param propertyId integer
function ApplyDoorbellTargets(propertyId)
    local object = spawned[propertyId]
    if not object or not DoesEntityExist(object) then return end

    exports.ox_target:removeLocalEntity(object, {
        ('qbx_properties_doorbell_move_%d'):format(propertyId),
        ('qbx_properties_doorbell_remove_%d'):format(propertyId),
    })

    if not editable[propertyId] then return end

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

---@param entry table
local function spawnDoorbell(entry)
    local existing = spawned[entry.propertyId]
    if existing and DoesEntityExist(existing) then return end
    if existing then despawnDoorbell(entry.propertyId) end

    local hash = lib.requestModel(entry.model, 10000)
    if not hash then return end

    local object = CreateObjectNoOffset(hash, entry.coords.x, entry.coords.y, entry.coords.z, false, false, false)
    SetEntityHeading(object, entry.heading)
    FreezeEntityPosition(object, true)
    SetModelAsNoLongerNeeded(hash)
    spawned[entry.propertyId] = object
    attachToDoor(entry, object)
    ApplyDoorbellTargets(entry.propertyId)
end

local function refreshDoorbells()
    doorbells = lib.callback.await('qbx_properties:callback:getDoorbells', false) or {}
end

CreateThread(function()
    Wait(3000)
    refreshDoorbells()

    while true do
        local ped = GetEntityCoords(cache.ped)
        local near = false

        for i = 1, #doorbells do
            local entry = doorbells[i]
            if #(ped - entry.coords) < 60.0 then
                near = true
                spawnDoorbell(entry)

                local object = spawned[entry.propertyId]
                if entry.door and object and DoesEntityExist(object) then
                    attachToDoor(entry, object)
                end
            else
                despawnDoorbell(entry.propertyId)
            end
        end

        -- a door being swapped in should not leave a gap you can see, so watch it closely
        -- only while one is actually in range
        Wait(near and 500 or 2000)
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
        door = point.door,
    }
    doorbells[#doorbells + 1] = entry

    if #(GetEntityCoords(cache.ped) - entry.coords) < 60.0 then
        spawnDoorbell(entry)
    end
end)

local heads = {}
local headOwner = {}
local headPan = {}

---@param decorationId integer
---@return integer? the dome that sits on the mount
function GetCameraHead(decorationId)
    local head = heads[decorationId]
    if head and DoesEntityExist(head) then return head end
end

---@param entity integer
---@return integer? the camera a dome belongs to
function GetCameraHeadOwner(entity)
    return headOwner[entity]
end

-- a camera on a wall lies on its side, so its own up axis points out along the lens and turning
-- about it would roll the picture. A pan is always about the world vertical
---@param decorationId integer
local function applyHead(decorationId)
    local head = heads[decorationId]
    local base = DecorationObjects[decorationId]
    if not head or not DoesEntityExist(head) then return end
    if not base or not DoesEntityExist(base) then return end

    local coords = GetEntityCoords(base)
    local rot = GetEntityRotation(base, 2)
    local pan = headPan[decorationId] or 0.0
    local pivot = (security.pan and security.pan.pivot) or 0.0
    local position = coords

    -- the dome turns about its own centre, otherwise it swings off the bracket like a door
    if pan ~= 0.0 and pivot ~= 0.0 then
        local centre = GetOffsetFromEntityInWorldCoords(base, 0.0, 0.0, pivot)
        local arm = coords - centre
        local angle = math.rad(pan)
        local cos, sin = math.cos(angle), math.sin(angle)
        position = centre + vec3(arm.x * cos - arm.y * sin, arm.x * sin + arm.y * cos, arm.z)
    end

    SetEntityCoordsNoOffset(head, position.x, position.y, position.z, false, false, false)
    SetEntityRotation(head, rot.x, rot.y, (rot.z + pan) % 360.0, 2, false)
end

-- the dome and the mount are separate props sharing an origin, so panning turns the dome
-- while the bracket stays on the wall
---@param decorationId integer
---@param pan number
function SetCameraPan(decorationId, pan)
    headPan[decorationId] = pan
    applyHead(decorationId)
end

---@param decorationId integer
local function removeHead(decorationId)
    local head = heads[decorationId]
    if head then headOwner[head] = nil end
    if head and DoesEntityExist(head) then DeleteEntity(head) end
    heads[decorationId] = nil
    headPan[decorationId] = nil
end

AddEventHandler('qbx_properties:client:decorationSpawned', function(decorationId, entity, model, pan)
    if model ~= security.cameraModel or not security.cameraHeadModel then return end

    pan = tonumber(pan) or 0.0

    if GetCameraHead(decorationId) then
        if headPan[decorationId] ~= pan then SetCameraPan(decorationId, pan) end
        return
    end

    removeHead(decorationId)

    local hash = lib.requestModel(security.cameraHeadModel, 10000)
    if not hash then
        lib.print.warn(('the camera dome %s did not load, the camera will not turn'):format(security.cameraHeadModel))
        return
    end

    local coords = GetEntityCoords(entity)
    local head = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    FreezeEntityPosition(head, true)
    heads[decorationId] = head
    headOwner[head] = decorationId
    SetCameraPan(decorationId, pan)
end)

-- the dome is not attached, so it follows its mount from here instead
CreateThread(function()
    while true do
        local any = false
        for id in pairs(heads) do
            any = true
            applyHead(id)
        end
        Wait(any and (IsDecorating and 0 or 500) or 1000)
    end
end)

AddEventHandler('qbx_properties:client:decorationRemoved', removeHead)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    for id in pairs(heads) do removeHead(id) end
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
    local leaves = {}
    for i = 1, #(target.doors or {}) do
        leaves[target.doors[i].model % 4294967296] = true
    end

    local result, surface = FreePlaceModel(target.model, prompt, leaves)

    placing = false

    if not result then
        refreshDoorbells()
        return
    end

    local attach
    if surface and surface ~= 0 and DoesEntityExist(surface) then
        local model = GetEntityModel(surface)
        for i = 1, #(target.doors or {}) do
            if sameModel(model, target.doors[i].model) then
                local anchor = GetEntityCoords(surface)
                local offset = GetOffsetFromEntityGivenWorldCoords(surface, result.x, result.y, result.z)
                attach = {
                    model = target.doors[i].model,
                    x = anchor.x, y = anchor.y, z = anchor.z,
                    ox = offset.x, oy = offset.y, oz = offset.z,
                    w = (result.w - GetEntityHeading(surface)) % 360.0,
                }
                break
            end
        end
    end

    local ok = lib.callback.await('qbx_properties:callback:placeDoorbell', false, target.propertyId,
        vec3(result.x, result.y, result.z), result.w, attach)

    if ok then
        lib.notify({
            type = 'success',
            description = attach and 'The doorbell is fitted to the door.' or 'The doorbell is fitted.',
        })
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
        ApplyDoorbellTargets(propertyId)
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
