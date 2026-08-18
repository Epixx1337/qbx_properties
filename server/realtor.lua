local config = require 'config.server'
local sharedConfig = require 'config.shared'

RegisterNetEvent('qbx_properties:server:createProperty', function(interiorIndex, data, propertyCoords, garageCoords)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    local playerCoords = GetEntityCoords(GetPlayerPed(playerSource))

    if not player or not IsRealtor(player.PlayerData.job) then return end
    if not GetInteriorPoints(interiorIndex) or type(data) ~= 'table' or type(propertyCoords) ~= 'vector3' then return end
    if type(data[1]) ~= 'string' or #data[1] < 4 or #data[1] > 32 or data[1]:find('[^%w%s]') then return end
    if math.type(data[2]) ~= 'integer' or data[2] < 1 or data[2] > 100000000 then return end
    if data[3] ~= nil and (math.type(data[3]) ~= 'integer' or data[3] < 1 or data[3] > 24) then return end
    if #(playerCoords - propertyCoords) > 5.0 then return end
    if garageCoords ~= nil and (type(garageCoords) ~= 'vector4' or #(propertyCoords - garageCoords.xyz) > 50.0) then return end

    local interactData = {
        {
            type = 'logout',
            coords = GetInteriorPoints(interiorIndex).logout
        },
        {
            type = 'clothing',
            coords = GetInteriorPoints(interiorIndex).clothing
        },
        {
            type = 'exit',
            coords = GetInteriorPoints(interiorIndex).exit
        }
    }

    local stashData = {
        {
            coords = GetInteriorPoints(interiorIndex).stash,
            slots = config.apartmentStash.slots,
            maxWeight = config.apartmentStash.maxWeight,
        }
    }

    local result = MySQL.single.await('SELECT id FROM properties ORDER BY id DESC', {})
    local propertyNumber = result?.id or 0
    local propertyName

    repeat
        propertyNumber += 1
        propertyName = string.format('%s %s', data[1], propertyNumber)
    until not MySQL.single.await('SELECT id FROM properties WHERE property_name = ?', {propertyName})

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