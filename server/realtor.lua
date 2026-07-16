local config = require 'config.server'
local sharedConfig = require 'config.shared'

lib.addCommand('createproperty', {
    help = 'Create a property at your current location',
}, function(source)
    local player = exports.qbx_core:GetPlayer(source)

    if player.PlayerData.job.name ~= 'realestate' then exports.qbx_core:Notify(source, 'Not a realtor', 'error') return end

    TriggerClientEvent('qbx_properties:client:createProperty', source)
end)

RegisterNetEvent('qbx_properties:server:createProperty', function(interiorIndex, data, propertyCoords, garageCoords)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    local playerCoords = GetEntityCoords(GetPlayerPed(playerSource))

    if not player or player.PlayerData.job.name ~= 'realestate' or not player.PlayerData.job.onduty then return end
    if not sharedConfig.interiors[interiorIndex] or type(data) ~= 'table' or type(propertyCoords) ~= 'vector3' then return end
    if type(data[1]) ~= 'string' or #data[1] < 4 or #data[1] > 32
        or math.type(data[2]) ~= 'integer' or data[2] < 1 or data[2] > 100000000
        or data[3] ~= nil and (math.type(data[3]) ~= 'integer' or data[3] < 1 or data[3] > 720)
        or #(playerCoords - propertyCoords) > 5.0
        or garageCoords ~= nil and (type(garageCoords) ~= 'vector4' or #(propertyCoords - garageCoords.xyz) > 30.0)
    then
        return
    end

    local interactData = {
        {
            type = 'logout',
            coords = sharedConfig.interiors[interiorIndex].logout
        },
        {
            type = 'clothing',
            coords = sharedConfig.interiors[interiorIndex].clothing
        },
        {
            type = 'exit',
            coords = sharedConfig.interiors[interiorIndex].exit
        }
    }

    local stashData = {
        {
            coords = sharedConfig.interiors[interiorIndex].stash,
            slots = config.apartmentStash.slots,
            maxWeight = config.apartmentStash.maxWeight,
        }
    }

    local result = MySQL.single.await('SELECT id FROM properties ORDER BY id DESC', {})
    local propertyNumber = (result?.id or 0) + 1
    local propertyName = string.format('%s %s', data[1], propertyNumber)

    MySQL.insert('INSERT INTO `properties` (`coords`, `property_name`, `price`, `interior`, `interact_options`, `stash_options`, `rent_interval`, `garage`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        json.encode(propertyCoords),
        propertyName,
        data[2],
        interiorIndex,
        json.encode(interactData),
        json.encode(stashData),
        data[3],
        garageCoords and json.encode(garageCoords) or nil,
    })
    TriggerClientEvent('qbx_properties:client:addProperty', -1, propertyCoords)
end)
