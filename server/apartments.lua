local config = require 'config.server'
local sharedConfig = require 'config.shared'

if not sharedConfig.dynamicApartments then return end

local claiming = {}

---@param playerSource integer
function ClearApartmentClaim(playerSource)
    claiming[playerSource] = nil
end

---@param layout table
---@param anchor vector4
local function buildUnitOptions(layout, anchor)
    local spawn = RotateOffset(anchor, layout.spawn)

    local interactData = {
        {
            type = 'exit',
            coords = vec4(spawn.x, spawn.y, spawn.z, (anchor.w + 180.0) % 360.0),
        },
        {
            type = 'clothing',
            coords = spawn,
        },
    }

    if sharedConfig.logoutEnabled then
        interactData[#interactData + 1] = {
            type = 'logout',
            coords = spawn,
        }
    end

    local stashData = {
        {
            coords = RotateOffset(anchor, layout.spawn),
            slots = config.apartmentStash.slots,
            maxWeight = config.apartmentStash.maxWeight,
        }
    }

    return interactData, stashData
end

---@param buildingKey string
---@return table
local function getTakenUnits(buildingKey)
    local rows = MySQL.query.await('SELECT floor, room FROM properties WHERE building = ?', {buildingKey})
    local taken = {}
    for i = 1, #rows do
        taken[rows[i].floor * 1000 + rows[i].room] = true
    end
    return taken
end

lib.callback.register('qbx_properties:callback:getBuildings', function()
    local result = {}
    for key, building in pairs(Buildings) do
        local total = building.floors.count * #building.rooms
        local used = MySQL.scalar.await('SELECT COUNT(*) FROM properties WHERE building = ?', {key}) or 0
        result[#result + 1] = {
            key = key,
            label = building.label,
            entrance = building.entrance,
            floors = building.floors.count,
            roomsPerFloor = #building.rooms,
            available = total - used,
        }
    end
    return result
end)

lib.callback.register('qbx_properties:callback:getBuildingUnits', function(_, buildingKey, floor)
    local building = Buildings[buildingKey]
    floor = ToId(floor)
    if not building or not floor or floor < 1 or floor > building.floors.count then return {} end

    local rows = MySQL.query.await([[
        SELECT p.id, p.room, p.owner, p.price, p.rent_interval, pl.charinfo
        FROM properties p
        LEFT JOIN players pl ON pl.citizenid = p.owner
        WHERE p.building = ? AND p.floor = ?
    ]], {buildingKey, floor})

    local byRoom = {}
    for i = 1, #rows do
        byRoom[rows[i].room] = rows[i]
    end

    local units = {}
    for room = 1, #building.rooms do
        local existing = byRoom[room]
        local charinfo = existing and existing.charinfo and json.decode(existing.charinfo)

        units[room] = {
            room = room,
            label = GetUnitName(buildingKey, floor, room),
            id = existing and existing.id or nil,
            owned = existing ~= nil and existing.owner ~= nil,
            owner = existing and existing.owner or nil,
            ownerName = charinfo and string.format('%s %s', charinfo.firstname, charinfo.lastname) or nil,
            online = existing and existing.owner and exports.qbx_core:GetPlayerByCitizenId(existing.owner) ~= nil or false,
            price = existing and existing.price or nil,
            rentInterval = existing and existing.rent_interval or nil,
        }
    end
    return units
end)

RegisterNetEvent('qbx_properties:server:releaseUnit', function(propertyId)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    propertyId = ToId(propertyId)
    if not player or not propertyId or not IsRealtor(player.PlayerData.job) then return end

    local property = MySQL.single.await('SELECT id, owner, property_name FROM properties WHERE id = ? AND building IS NOT NULL', {propertyId})
    if not property or not property.owner then return end

    local occupant = exports.qbx_core:GetPlayerByCitizenId(property.owner)
    if occupant then
        exports.qbx_core:Notify(occupant.PlayerData.source, string.format('Your tenancy of %s has been ended.', property.property_name), 'error')
        occupant.Functions.SetMetaData('apartmentBuilding', nil)
        occupant.Functions.SetMetaData('currentPropertyId', nil)
    end

    ReleaseRooms(property.owner)

    lib.logger(playerSource, 'qbx_properties:server:releaseUnit', string.format('%s released %s from %s', player.PlayerData.citizenid, property.property_name, property.owner))

    exports.qbx_core:Notify(playerSource, string.format('%s is now free.', property.property_name), 'success')
end)

---@param player table
---@param buildingKey string
---@return integer? propertyId
function AssignRoom(player, buildingKey)
    local building = Buildings[buildingKey]
    if not building then return end

    local citizenId = player.PlayerData.citizenid

    local held = MySQL.single.await('SELECT id FROM properties WHERE building = ? AND owner = ?', {buildingKey, citizenId})
    if held then return held.id end

    local free = MySQL.single.await('SELECT id FROM properties WHERE building = ? AND owner IS NULL ORDER BY floor, room LIMIT 1', {buildingKey})

    if free then
        if MySQL.update.await('UPDATE properties SET owner = ? WHERE id = ? AND owner IS NULL', {citizenId, free.id}) == 1 then
            return free.id
        end
        return AssignRoom(player, buildingKey)
    end

    local taken = getTakenUnits(buildingKey)
    for floor = 1, building.floors.count do
        for room = 1, #building.rooms do
            if not taken[floor * 1000 + room] then
                local id = CreateUnit(buildingKey, floor, room, 0, nil)
                if id and MySQL.update.await('UPDATE properties SET owner = ? WHERE id = ? AND owner IS NULL', {citizenId, id}) == 1 then
                    return id
                end
            end
        end
    end
end

---@param citizenId string
function ReleaseRooms(citizenId)
    if IsRaidTarget and IsRaidTarget(citizenId) then return end

    MySQL.update.await('UPDATE properties SET owner = NULL WHERE building IS NOT NULL AND owner = ?', {citizenId})
end

RegisterNetEvent('qbx_properties:server:ringUnit', function(buildingKey, floor, room)
    local playerSource = source --[[@as number]]
    floor, room = ToId(floor), ToId(room)
    if type(buildingKey) ~= 'string' or not Buildings[buildingKey] or not floor or not room then return end

    local anchor = GetRoomCoords(buildingKey, floor, room)
    if not anchor or #(GetEntityCoords(GetPlayerPed(playerSource)) - anchor.xyz) > 5.0 then return end

    local property = MySQL.single.await('SELECT id, owner FROM properties WHERE building = ? AND floor = ? AND room = ?', {buildingKey, floor, room})
    if not property or not property.owner then return end

    local owner = exports.qbx_core:GetPlayerByCitizenId(property.owner)
    if not owner then return end

    local caller = exports.qbx_core:GetPlayer(playerSource)
    exports.qbx_core:Notify(owner.PlayerData.source, string.format('%s is at your door.',
        caller and string.format('%s %s', caller.PlayerData.charinfo.firstname, caller.PlayerData.charinfo.lastname) or 'Someone'), 'inform')
end)

RegisterNetEvent('qbx_properties:server:setCurrentUnit', function(buildingKey, floor, room)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    if not player then return end

    if buildingKey == nil then
        LeavePropertyInPlace(playerSource)
        player.Functions.SetMetaData('currentPropertyId', nil)
        return
    end

    floor, room = ToId(floor), ToId(room)
    if type(buildingKey) ~= 'string' or not Buildings[buildingKey] or not floor or not room then return end

    local anchor = GetRoomCoords(buildingKey, floor, room)
    if not anchor or #(GetEntityCoords(GetPlayerPed(playerSource)) - anchor.xyz) > 20.0 then return end

    local property = MySQL.single.await('SELECT id FROM properties WHERE building = ? AND floor = ? AND room = ?', {buildingKey, floor, room})
    if not property then return end

    LeavePropertyInPlace(playerSource)
    EnterProperty(playerSource, property.id, false, true)
    player.Functions.SetMetaData('currentPropertyId', property.id)
end)

lib.callback.register('qbx_properties:callback:getRoomDecorations', function(source, buildingKey, floor, room)
    floor, room = ToId(floor), ToId(room)
    if type(buildingKey) ~= 'string' or not Buildings[buildingKey] or not floor or not room then return {} end

    local property = MySQL.single.await('SELECT id, property_name, owner, building, floor, room FROM properties WHERE building = ? AND floor = ? AND room = ?', {buildingKey, floor, room})
    if not property or not property.owner then return {} end

    local anchor = GetRoomCoords(buildingKey, floor, room)
    if not anchor then return {} end

    local decorations = GetPropertyDecorations(property)
    local stashIndexes = RegisterPropertyStashes(property, decorations)
    local types = GetFurnitureTypes()
    local result = {}

    if SyncFurnitureDoors then SyncFurnitureDoors(property) end

    result.propertyId = property.id

    local player = exports.qbx_core:GetPlayer(source)
    result.access = player and GetAccessFlags(player.PlayerData.citizenid, property) or nil
    result.breached = IsBreached ~= nil and IsBreached(property.id) or false

    for i = 1, #decorations do
        local coords = json.decode(decorations[i].coords)
        local rotation = json.decode(decorations[i].rotation)

        result[i] = {
            id = decorations[i].id,
            model = decorations[i].model,
            coords = RotateOffset(anchor, vec3(coords.x, coords.y, coords.z)),
            rotation = vec3(rotation.x, rotation.y, (rotation.z + anchor.w) % 360.0),
            interaction = types[decorations[i].model],
            stashIndex = stashIndexes[decorations[i].id],
            tint = decorations[i].tint,
        }
    end

    return result
end)

lib.callback.register('qbx_properties:callback:canDecorateUnit', function(source, buildingKey, floor, room)
    local player = exports.qbx_core:GetPlayer(source)
    floor, room = ToId(floor), ToId(room)
    if not player or type(buildingKey) ~= 'string' or not Buildings[buildingKey] or not floor or not room then return false end

    local property = MySQL.single.await('SELECT id, owner, keyholders, building FROM properties WHERE building = ? AND floor = ? AND room = ?', {buildingKey, floor, room})
    if not property then return false end

    if IsRealtor(player.PlayerData.job) then return true, property.id end
    if property.owner == player.PlayerData.citizenid then return true, property.id end

    local keyholders = GetPropertyKeyholders(property)
    for i = 1, #keyholders do
        if keyholders[i] == player.PlayerData.citizenid then return true, property.id end
    end

    return false
end)

---@param buildingKey string
---@param floor integer
---@param room integer
---@param price integer
---@param rentInterval integer?
---@return integer?
function CreateUnit(buildingKey, floor, room, price, rentInterval)
    local building = Buildings[buildingKey]
    if not building then return end
    if floor < 1 or floor > building.floors.count then return end
    if room < 1 or room > #building.rooms then return end

    local anchor = GetRoomCoords(buildingKey, floor, room)
    if not anchor then return end

    local interactData, stashData = buildUnitOptions(building.roomLayout, anchor)

    local id = MySQL.insert.await([[
        INSERT INTO `properties` (`coords`, `property_name`, `price`, `interior`, `building`, `floor`, `room`, `interact_options`, `stash_options`, `rent_interval`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        json.encode(vec3(anchor.x, anchor.y, anchor.z)),
        GetUnitName(buildingKey, floor, room),
        price,
        buildingKey,
        buildingKey,
        floor,
        room,
        json.encode(interactData),
        json.encode(stashData),
        rentInterval,
    })

    if id and RegisterUnitDoors then
        RegisterUnitDoors(id, buildingKey, floor, room)
    end

    return id
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    if not player then return end

    local buildingKey = player.PlayerData.metadata.apartmentBuilding
    if not buildingKey or not Buildings[buildingKey] then return end

    local propertyId = AssignRoom(player, buildingKey)
    if not propertyId then
        exports.qbx_core:Notify(player.PlayerData.source, 'No apartments are free right now.', 'error')
    end
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(playerSource)
    local player = exports.qbx_core:GetPlayer(playerSource)
    if not player then return end
    ReleaseRooms(player.PlayerData.citizenid)
end)

AddEventHandler('playerDropped', function()
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    if not player then return end
    ReleaseRooms(player.PlayerData.citizenid)
end)

RegisterNetEvent('qbx_properties:server:moveIn', function(buildingKey)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)

    if not player or claiming[playerSource] then return end
    if type(buildingKey) ~= 'string' or not Buildings[buildingKey] then return end

    local building = Buildings[buildingKey]
    if #(GetEntityCoords(GetPlayerPed(playerSource)) - building.entrance) > 30.0 then return end

    claiming[playerSource] = true

    if player.PlayerData.metadata.apartmentBuilding == buildingKey then
        claiming[playerSource] = nil
        exports.qbx_core:Notify(playerSource, 'You already live here.', 'error')
        return
    end

    ReleaseRooms(player.PlayerData.citizenid)
    player.Functions.SetMetaData('apartmentBuilding', buildingKey)

    local propertyId = AssignRoom(player, buildingKey)
    claiming[playerSource] = nil

    if not propertyId then
        player.Functions.SetMetaData('apartmentBuilding', nil)
        exports.qbx_core:Notify(playerSource, 'No apartments are free right now.', 'error')
        return
    end

    exports.qbx_core:Notify(playerSource, string.format('You moved into %s.', building.label), 'success')

    lib.logger(playerSource, 'qbx_properties:server:moveIn', string.format('%s moved into %s (room id %d)', player.PlayerData.citizenid, buildingKey, propertyId))
end)

RegisterNetEvent('qbx_properties:server:moveOut', function()
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    if not player or not player.PlayerData.metadata.apartmentBuilding then return end

    ReleaseRooms(player.PlayerData.citizenid)
    MySQL.update.await('DELETE FROM properties_apartment_keyholders WHERE tenant = ?', {player.PlayerData.citizenid})
    player.Functions.SetMetaData('apartmentBuilding', nil)
    player.Functions.SetMetaData('currentPropertyId', nil)

    exports.qbx_core:Notify(playerSource, 'You moved out.', 'success')
end)

RegisterNetEvent('qbx_properties:server:createUnits', function(buildingKey, floor, price, rentInterval)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    floor, price, rentInterval = ToId(floor), ToId(price), rentInterval and ToId(rentInterval) or nil

    if not player or not IsRealtor(player.PlayerData.job) then return end
    if type(buildingKey) ~= 'string' or not Buildings[buildingKey] or not floor or not price then return end
    if price < sharedConfig.market.minPrice or price > sharedConfig.market.maxPrice then return end
    if rentInterval and (rentInterval < 1 or rentInterval > 24) then return end

    local building = Buildings[buildingKey]
    if floor < 1 or floor > building.floors.count then return end

    local taken = getTakenUnits(buildingKey)
    local created = 0
    for room = 1, #building.rooms do
        if not taken[floor * 1000 + room] and CreateUnit(buildingKey, floor, room, price, rentInterval) then
            created += 1
        end
    end

    exports.qbx_core:Notify(playerSource, string.format('Created %d units on floor %d of %s', created, floor, building.label), 'success')

    lib.logger(playerSource, 'qbx_properties:server:createUnits', string.format('%s created %d units on %s floor %d', player.PlayerData.citizenid, created, buildingKey, floor))
end)

lib.callback.register('qbx_properties:callback:getMyUnit', function(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return end

    local row = MySQL.single.await(
        'SELECT building, floor, room, property_name FROM properties WHERE owner = ? AND building IS NOT NULL LIMIT 1',
        {player.PlayerData.citizenid}
    )
    if not row then return end

    return { building = row.building, floor = row.floor, room = row.room, label = row.property_name }
end)

lib.callback.register('qbx_properties:callback:getUnitProperty', function(_, buildingKey, floor, room)
    floor, room = ToId(floor), ToId(room)
    if type(buildingKey) ~= 'string' or not Buildings[buildingKey] or not floor or not room then return end

    return MySQL.scalar.await('SELECT id FROM properties WHERE building = ? AND floor = ? AND room = ?', {buildingKey, floor, room})
end)
