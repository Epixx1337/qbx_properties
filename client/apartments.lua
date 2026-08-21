local sharedConfig = require 'config.shared'

if not sharedConfig.dynamicApartments then return end

local roomCache = {}

---@param interiorId integer
---@return table
local function getInteriorRooms(interiorId)
    if roomCache[interiorId] then return roomCache[interiorId] end

    local rooms = {}
    for index = 0, GetInteriorRoomCount(interiorId) - 1 do
        local name = GetInteriorRoomName(interiorId, index)
        if name then rooms[GetHashKey(name)] = { index = index, name = name } end
    end

    roomCache[interiorId] = rooms
    return rooms
end

---@return string? buildingKey, integer? floor, integer? room
function ResolveCurrentUnit()
    local interiorId = GetInteriorFromEntity(cache.ped)
    if interiorId == 0 then return end

    local ix, iy, iz = GetInteriorPosition(interiorId)
    for key, building in pairs(Buildings) do
        if building.perRoomInterior and building.rooms then
            for roomNumber = 1, #building.rooms do
                local anchor = building.rooms[roomNumber]
                if math.abs(anchor.x - ix) < 2.0 and math.abs(anchor.y - iy) < 2.0 then
                    local floor = math.floor((iz - building.floors.baseZ) / building.floors.step + 0.5) + 1
                    if floor >= 1 and floor <= building.floors.count then
                        return key, floor, roomNumber
                    end
                end
            end
        end
    end

    local rooms = getInteriorRooms(interiorId)
    local current = rooms[GetRoomKeyFromEntity(cache.ped)]
    if not current then return end

    local coords = GetEntityCoords(cache.ped)

    for key, building in pairs(Buildings) do
        local roomNumber = building.roomName and building.rooms
            and current.name:match('^' .. building.roomName:gsub('%%d', '(%%d+)') .. '$')
        roomNumber = roomNumber and tonumber(roomNumber)

        if roomNumber and building.rooms[roomNumber] then
            for floor = 1, building.floors.count do
                local anchor = GetRoomCoords(key, floor, roomNumber)
                if anchor and math.abs(coords.z - anchor.z) < building.floors.step * 0.5 then
                    return key, floor, roomNumber
                end
            end
        end
    end
end


local function openReception(buildingKey)
    local building = Buildings[buildingKey]
    local livesHere = QBX.PlayerData.metadata.apartmentBuilding == buildingKey
    local options = {}

    if livesHere then
        options[#options + 1] = {
            title = 'Move out',
            description = 'Give up your apartment here',
            icon = 'right-from-bracket',
            onSelect = function()
                local alert = lib.alertDialog({
                    header = building.label,
                    content = 'Move out? Your furniture and stash stay with you, but you will lose access until you move back in.',
                    centered = true,
                    cancel = true
                })
                if alert == 'confirm' then TriggerServerEvent('qbx_properties:server:moveOut') end
            end
        }
    else
        local lockedElsewhere = not sharedConfig.freeApartmentMoves
            and QBX.PlayerData.metadata.apartmentBuilding
            and QBX.PlayerData.metadata.apartmentBuilding ~= buildingKey

        options[#options + 1] = {
            title = 'Move in',
            description = lockedElsewhere and 'You already have a home elsewhere' or 'Get an apartment in this building',
            icon = 'key',
            disabled = lockedElsewhere or nil,
            onSelect = function() TriggerServerEvent('qbx_properties:server:moveIn', buildingKey) end
        }
    end

    if GetRaidOptions then
        local raidOptions = GetRaidOptions(buildingKey)
        for i = 1, #raidOptions do
            options[#options + 1] = raidOptions[i]
        end
    end

    lib.registerContext({ id = 'qbx_properties_reception', title = building.label, options = options })
    lib.showContext('qbx_properties_reception')
end

CreateThread(function()
    for key, building in pairs(Buildings) do
        if building.receptionist and (not building.resource or GetResourceState(building.resource) == 'started') then
            local ped = building.receptionist
            lib.requestModel(ped.model, 60000)

            local entity = CreatePed(4, ped.model, ped.coords.x, ped.coords.y, ped.coords.z, ped.coords.w, false, false)
            FreezeEntityPosition(entity, true)
            SetEntityInvincible(entity, true)
            SetBlockingOfNonTemporaryEvents(entity, true)
            if ped.scenario then TaskStartScenarioInPlace(entity, ped.scenario, 0, true) end
            SetModelAsNoLongerNeeded(ped.model)

            exports.ox_target:addLocalEntity(entity, {
                {
                    name = 'qbx_properties_reception_' .. key,
                    label = 'Ask about apartments',
                    icon = 'fa-solid fa-building',
                    distance = 2.5,
                    onSelect = function() openReception(key) end
                }
            })
        end
    end
end)

exports('getMyUnit', function()
    return lib.callback.await('qbx_properties:callback:getMyUnit', false)
end)

RegisterNetEvent('qbx_properties:client:offerMigration', function(options, currentLabel)
    while IsScreenFadedOut() or not LocalPlayer.state.isLoggedIn do Wait(500) end
    Wait(3000)

    local menu = {}

    for i = 1, #options do
        local option = options[i]
        menu[#menu + 1] = {
            title = option.label,
            description = option.description,
            icon = 'building',
            arrow = true,
            onSelect = function()
                local alert = lib.alertDialog({
                    header = option.label,
                    content = ('Move from %s to %s? Your stash follows you, and your furniture is restored whenever you live in a building with the same room layout. This choice is final.'):format(currentLabel, option.label),
                    centered = true,
                    cancel = true,
                })
                if alert == 'confirm' then
                    TriggerServerEvent('qbx_properties:server:chooseMigration', option.key)
                else
                    lib.showContext('qbx_properties_migration')
                end
            end
        }
    end

    menu[#menu + 1] = {
        title = ('Stay at %s'):format(currentLabel),
        description = 'Keep your current apartment',
        icon = 'house',
        onSelect = function()
            TriggerServerEvent('qbx_properties:server:chooseMigration', 'stay')
        end
    }

    lib.registerContext({
        id = 'qbx_properties_migration',
        title = 'New apartments available',
        canClose = false,
        options = menu,
    })
    lib.showContext('qbx_properties_migration')
end)
