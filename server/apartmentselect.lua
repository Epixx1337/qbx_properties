local config = require 'config.server'
local sharedConfig = require 'config.shared'

local selecting = {}

---@param playerSource integer
function ClearApartmentLock(playerSource)
    selecting[playerSource] = nil
end

-- resolved per call: building entries only exist once their map resource is started,
-- and the picker's indexes are built against the runtime list

---@param playerSource integer
---@param player table
---@param buildingKey string
local function selectBuildingUnit(playerSource, player, buildingKey)
    local building = Buildings[buildingKey]

    player.Functions.SetMetaData('apartmentBuilding', buildingKey)

    local id = AssignRoom(player, buildingKey)
    if not id then
        player.Functions.SetMetaData('apartmentBuilding', nil)
        exports.qbx_core:Notify(playerSource, 'That building is full.', 'error')
        return false
    end

    lib.logger(playerSource, 'qbx_properties:server:apartmentSelect', locale('logs.apartment_selected', player.PlayerData.citizenid, building.label, id))

    TriggerClientEvent('qbx_properties:client:addProperty', -1, building.entrance)
    EnterProperty(playerSource, id, true)
    return true
end

lib.callback.register('qbx_properties:callback:getApartmentChoices', function()
    local options = GetApartmentOptions()
    local taken = {}
    local rows = MySQL.query.await('SELECT building, COUNT(*) AS n FROM properties WHERE building IS NOT NULL AND owner IS NOT NULL GROUP BY building') or {}
    for i = 1, #rows do taken[rows[i].building] = rows[i].n end

    local result = {}
    for i = 1, #options do
        local option = options[i]
        local building = option.building and Buildings[option.building]
        local capacity = building and building.floors.count * #building.rooms or 0

        if not option.building or (taken[option.building] or 0) < capacity then
            option.index = i
            result[#result + 1] = option
        end
    end

    return result
end)

RegisterNetEvent('qbx_properties:server:apartmentSelect', function(apartmentIndex)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    if not player or selecting[playerSource] then return end
    apartmentIndex = ToId(apartmentIndex)

    local option = apartmentIndex and GetApartmentOptions()[apartmentIndex]
    if not option then
        TriggerClientEvent('qbx_properties:client:finishSpawn', playerSource)
        return
    end

    selecting[playerSource] = true

    local hasApartment = MySQL.single.await('SELECT id FROM properties WHERE owner = ?', {player.PlayerData.citizenid})
    if hasApartment then
        selecting[playerSource] = nil
        EnterProperty(playerSource, hasApartment.id, true)
        TriggerClientEvent('qbx_properties:client:finishSpawn', playerSource)
        return
    end

    if option.building then
        local assigned = Buildings[option.building] and selectBuildingUnit(playerSource, player, option.building)
        selecting[playerSource] = nil
        if not assigned then
            TriggerClientEvent('qbx_properties:client:finishSpawn', playerSource)
            return
        end
        Wait(200)
        TriggerClientEvent('qb-clothes:client:CreateFirstCharacter', playerSource)
        return
    end

    local interior = option.interior
    local interactData = {
        {
            type = 'logout',
            coords = GetInteriorPoints(interior).logout
        },
        {
            type = 'clothing',
            coords = GetInteriorPoints(interior).clothing
        },
        {
            type = 'exit',
            coords = GetInteriorPoints(interior).exit
        }
    }
    local stashData = {
        {
            coords = GetInteriorPoints(interior).stash,
            slots = config.apartmentStash.slots,
            maxWeight = config.apartmentStash.maxWeight,
        }
    }

    local result = MySQL.single.await('SELECT id FROM properties ORDER BY id DESC')
    local apartmentNumber = result?.id or 0

    ::again::

    apartmentNumber += 1
    local numberExists = MySQL.single.await('SELECT * FROM properties WHERE property_name = ?', {string.format('%s %s', option.label, apartmentNumber)})
    if numberExists then goto again end

    local id = MySQL.insert.await('INSERT INTO `properties` (`coords`, `property_name`, `owner`, `interior`, `interact_options`, `stash_options`) VALUES (?, ?, ?, ?, ?, ?)', {
        json.encode(option.enter),
        string.format('%s %s', option.label, apartmentNumber),
        player.PlayerData.citizenid,
        interior,
        json.encode(interactData),
        json.encode(stashData),
    })

    lib.logger(playerSource, 'qbx_properties:server:apartmentSelect', locale('logs.apartment_selected', player.PlayerData.citizenid, option.label, apartmentNumber))

    TriggerClientEvent('qbx_properties:client:addProperty', -1, option.enter)
    EnterProperty(playerSource, id, true)
    selecting[playerSource] = nil
    Wait(200)
    TriggerClientEvent('qb-clothes:client:CreateFirstCharacter', playerSource)
end)

local startingApartment = require '@qbx_core.config.client'.characters.startingApartment

if not startingApartment then return end

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    if not player then return end

    if player.PlayerData.metadata.apartmentBuilding then return end

    local hasApartment = MySQL.single.await('SELECT id FROM properties WHERE owner = ?', {player.PlayerData.citizenid})
    if not hasApartment then
        TriggerClientEvent('apartments:client:setupSpawnUI', playerSource)
    end
end)