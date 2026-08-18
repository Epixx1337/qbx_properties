local robbery = require('config.crime').robbery
local dispatch = require 'config.dispatch'

if not robbery.enabled then return end

---@param coords vector3
local function soundAlarm(coords)
    local alarm = robbery.alarm
    if not alarm or not alarm.enabled then return end

    CreateThread(function()
        if alarm.bank and not RequestScriptAudioBank(alarm.bank, false) then return end

        local elapsed = 0
        while elapsed < alarm.duration do
            PlaySoundFromCoord(-1, alarm.name, coords.x, coords.y, coords.z, alarm.set, false, alarm.range or 0, false)
            Wait(alarm.interval)
            elapsed += alarm.interval
        end

        if alarm.bank then ReleaseNamedScriptAudioBank(alarm.bank) end
    end)
end

---@param propertyId integer
local function forceDoor(propertyId, entity)
    if not lib.callback.await('qbx_properties:callback:canRobDoor', false, propertyId) then
        lib.notify({ type = 'error', description = 'You cannot force this door.' })
        return
    end

    local success = lib.skillCheck(robbery.skillCheck)
    local coords = entity and DoesEntityExist(entity) and GetEntityCoords(entity) or GetEntityCoords(cache.ped)
    local name = lib.callback.await('qbx_properties:callback:robDoor', false, propertyId, success)

    if not name then
        soundAlarm(coords)
        if dispatch.enabled and dispatch.FailedBurglary then dispatch.FailedBurglary(coords, CurrentPropertyName or 'a property') end
        lib.notify({ type = 'error', description = success and 'The lock held.' or 'You broke your pick.' })
        return
    end

    if dispatch.enabled and dispatch.Burglary then dispatch.Burglary(coords, name) end
    lib.notify({ type = 'success', description = 'The lock gives way.' })
end

CreateThread(function()
    local models = {}

    for _, building in pairs(Buildings) do
        local doors = building.roomLayout and building.roomLayout.doors
        if doors then
            for i = 1, #doors do
                models[doors[i].model] = true
            end
        end
    end

    for model in pairs(models) do
        exports.ox_target:addModel(model, {
            {
                name = 'qbx_properties_force_door',
                label = 'Force lock',
                icon = 'fa-solid fa-screwdriver',
                distance = 1.5,
                canInteract = function(entity)
                    if not ResolveDoorProperty then return false end

                    local propertyId = ResolveDoorProperty(entity)
                    if not propertyId or IsPropertyBreached(propertyId) then return false end

                    return (exports.ox_inventory:GetItemCount(robbery.item) or 0) > 0
                end,
                onSelect = function(data)
                    local propertyId = ResolveDoorProperty(data.entity)
                    if propertyId then forceDoor(propertyId, data.entity) end
                end
            }
        })
    end
end)

CreateThread(function()
    local entrances = lib.callback.await('qbx_properties:callback:loadProperties') or {}

    for i = 1, #entrances do
        local coords = entrances[i]

        exports.ox_target:addSphereZone({
            coords = coords,
            radius = 1.5,
            options = {
                {
                    name = 'qbx_properties_entry_force',
                    label = 'Force lock',
                    icon = 'fa-solid fa-screwdriver',
                    distance = 2.0,
                    canInteract = function()
                        return (exports.ox_inventory:GetItemCount(robbery.item) or 0) > 0
                    end,
                    onSelect = function()
                        local propertyId = ResolveEntryProperty and ResolveEntryProperty(coords)
                        if propertyId then forceDoor(propertyId) end
                    end
                },
            },
        })
    end
end)
