local sharedConfig = require 'config.shared'

UsesCustomGarages = sharedConfig.garageSystem ~= nil and sharedConfig.garageSystem ~= 'qbx'

local customGarages = {}

---@param key string
---@param garage { name: string, label: string, coords: vector4?, spots: vector4[]?, blip: table?, canAccess: fun(source: integer): boolean }
function RegisterCustomGarage(key, garage)
    customGarages[key] = garage
    TriggerClientEvent('qbx_properties:client:refreshGarages', -1)
end

function RefreshCustomGarages()
    if not UsesCustomGarages then return end
    TriggerClientEvent('qbx_properties:client:refreshGarages', -1)
end

lib.callback.register('qbx_properties:callback:getGarages', function(source)
    local result = {}
    for _, garage in pairs(customGarages) do
        if garage.canAccess(source) then
            result[#result + 1] = {
                name = garage.name,
                label = garage.label,
                coords = garage.coords,
                spots = garage.spots,
                blip = garage.blip,
            }
        end
    end
    return result
end)

local garages = sharedConfig.apartmentGarages

if not garages or #garages == 0 then return end

---@param garage table
---@return string? query, string[] values
local function buildResidencyQuery(garage)
    local clauses = {}
    local values = {}

    for column, list in pairs({ interior = garage.interiors, building = garage.buildings }) do
        if #list > 0 then
            clauses[#clauses + 1] = string.format('`%s` IN (%s)', column, string.rep('?', #list, ', '))
            for i = 1, #list do values[#values + 1] = list[i] end
        end
    end

    if #clauses == 0 then return nil, values end

    return string.format('SELECT 1 FROM properties WHERE owner = ? AND (%s)', table.concat(clauses, ' OR ')), values
end

---@param query string
---@param values string[]
---@return fun(source: integer): boolean
local function residentCheck(query, values)
    return function(source)
        local player = exports.qbx_core:GetPlayer(source)
        if not player then return false end

        local params = { player.PlayerData.citizenid }
        for i = 1, #values do params[i + 1] = values[i] end

        return MySQL.scalar.await(query, params) ~= nil
    end
end

CreateThread(function()
    for i = 1, #garages do
        local garage = garages[i]
        local query, values = buildResidencyQuery(garage)

        if not query then
            lib.print.warn(('apartment garage %s lists no interiors or buildings, skipping'):format(garage.name))
        elseif UsesCustomGarages then
            RegisterCustomGarage(garage.name, {
                name = garage.name,
                label = garage.label,
                spots = garage.spots,
                blip = sharedConfig.apartmentGarageBlip,
                canAccess = residentCheck(query, values),
            })
        else
            local accessPoints = {}
            for j = 1, #garage.spots do
                accessPoints[j] = {
                    coords = garage.spots[j],
                    useRadius = sharedConfig.apartmentGarageUseRadius,
                    blip = j == 1 and sharedConfig.apartmentGarageBlip or nil,
                }
            end

            exports.qbx_garages:RegisterGarage(garage.name, {
                label = garage.label,
                vehicleType = 'car',
                accessPoints = accessPoints,
                canAccess = residentCheck(query, values),
            })
        end
    end
end)
