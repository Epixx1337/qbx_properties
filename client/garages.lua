local sharedConfig = require 'config.shared'

if sharedConfig.garageSystem == nil or sharedConfig.garageSystem == 'qbx' then return end

local adapters = require 'config.garages'
local adapter = adapters[sharedConfig.garageSystem]

if not adapter then
    lib.print.error(('garageSystem %s has no adapter in config/garages.lua'):format(sharedConfig.garageSystem))
    return
end

local points = {}
local blips = {}

local function clearGarages()
    for i = 1, #points do
        points[i]:remove()
    end
    for i = 1, #blips do
        RemoveBlip(blips[i])
    end
    table.wipe(points)
    table.wipe(blips)
end

local function createPoint(garage, coords)
    local point = lib.points.new({ coords = coords.xyz, distance = 15.0 })
    local data = { name = garage.name, label = garage.label, coords = coords }
    local shown

    function point:nearby()
        if self.currentDistance < 2.5 then
            local text = cache.vehicle and '[E] Store Vehicle' or '[E] Open Garage'
            if shown ~= text then
                shown = text
                lib.showTextUI(text)
            end

            if IsControlJustReleased(0, 38) then
                if cache.vehicle then
                    adapter.store(data)
                else
                    adapter.open(data)
                end
            end
        elseif shown then
            shown = nil
            lib.hideTextUI()
        end
    end

    function point:onExit()
        if shown then
            shown = nil
            lib.hideTextUI()
        end
    end

    return point
end

local refreshing = false

local function refreshGarages()
    if refreshing then return end
    refreshing = true

    CreateThread(function()
        Wait(1000)
        refreshing = false

        local deadline = GetGameTimer() + 30000
        while not LocalPlayer.state.isLoggedIn and GetGameTimer() < deadline do Wait(250) end
        if not LocalPlayer.state.isLoggedIn then return end

        local garages = lib.callback.await('qbx_properties:callback:getGarages', false) or {}
        clearGarages()

        for i = 1, #garages do
            local garage = garages[i]
            local spots = garage.spots or { garage.coords }

            for j = 1, #spots do
                points[#points + 1] = createPoint(garage, spots[j])
            end

            if garage.blip and spots[1] then
                local spot = spots[1]
                local blip = AddBlipForCoord(spot.x, spot.y, spot.z)
                SetBlipSprite(blip, garage.blip.sprite)
                SetBlipColour(blip, garage.blip.color)
                SetBlipScale(blip, 0.7)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentString(garage.label)
                EndTextCommandSetBlipName(blip)
                blips[#blips + 1] = blip
            end
        end
    end)
end

RegisterNetEvent('qbx_properties:client:refreshGarages', refreshGarages)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', refreshGarages)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= cache.resource then return end
    refreshGarages()
end)
