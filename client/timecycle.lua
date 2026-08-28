local sharedConfig = require 'config.shared'

if not sharedConfig.timecycles or #sharedConfig.timecycles == 0 then return end

local applied = nil
local watched = nil

local function applyTimecycle(value)
    if applied == value then return end
    applied = value

    if value then
        SetTimecycleModifier(value)
    else
        ClearTimecycleModifier()
    end
end

CreateThread(function()
    while true do
        Wait(1000)

        local propertyId = CurrentPropertyId

        if propertyId ~= watched then
            watched = propertyId

            if propertyId then
                local data = lib.callback.await('qbx_properties:callback:getTimecycle', false, propertyId)
                if CurrentPropertyId == propertyId then
                    applyTimecycle(data and data.current or nil)
                end
            else
                applyTimecycle(nil)
            end
        end
    end
end)

RegisterNetEvent('qbx_properties:client:timecycle', function(propertyId, value)
    if CurrentPropertyId ~= propertyId then return end
    applyTimecycle(value)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    if applied then ClearTimecycleModifier() end
end)
