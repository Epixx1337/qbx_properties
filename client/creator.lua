local draft = nil
local canUse = false

function CanUseCreator()
    return canUse
end

local function pedVec4()
    local coords = GetEntityCoords(cache.ped)
    return { x = coords.x, y = coords.y, z = coords.z, w = GetEntityHeading(cache.ped) }
end

local function pedVec3()
    local coords = GetEntityCoords(cache.ped)
    return { x = coords.x, y = coords.y, z = coords.z }
end

---@return string? pattern, integer? count, string[] names
local function scanInterior()
    local interiorId = GetInteriorFromEntity(cache.ped)
    if interiorId == 0 then return nil, nil, {} end

    local names = {}
    local numbered = {}

    for index = 0, GetInteriorRoomCount(interiorId) - 1 do
        local name = GetInteriorRoomName(interiorId, index)
        if name then
            names[#names + 1] = name
            local prefix, number = name:match('^(.-)(%d+)$')
            if prefix and number then
                numbered[prefix] = numbered[prefix] or {}
                numbered[prefix][#numbered[prefix] + 1] = tonumber(number)
            end
        end
    end

    local bestPrefix, bestCount
    for prefix, numbers in pairs(numbered) do
        if not bestCount or #numbers > bestCount then
            bestPrefix, bestCount = prefix, #numbers
        end
    end

    if not bestPrefix then return nil, nil, names end
    return bestPrefix .. '%d', bestCount, names
end

local function currentRoomName()
    local interiorId = GetInteriorFromEntity(cache.ped)
    if interiorId == 0 then return end

    local key = GetRoomKeyFromEntity(cache.ped)
    for index = 0, GetInteriorRoomCount(interiorId) - 1 do
        local name = GetInteriorRoomName(interiorId, index)
        if name and GetHashKey(name) == key then return name end
    end
end

local function nearestAnchor()
    local coords = GetEntityCoords(cache.ped)
    local bestKey, bestIndex, bestFloor, bestDist

    for key, building in pairs(Buildings) do
        for floor = 1, building.floors.count do
            for room = 1, #building.rooms do
                local anchor = GetRoomCoords(key, floor, room)
                if anchor then
                    local dist = #(coords - anchor.xyz)
                    if not bestDist or dist < bestDist then
                        bestKey, bestIndex, bestFloor, bestDist = key, room, floor, dist
                    end
                end
            end
        end
    end

    return bestKey, bestIndex, bestFloor, bestDist
end

local function pushDraft()
    local pattern, count, names = scanInterior()
    local anchorBuilding, anchorIndex, anchorFloor, anchorDist = nearestAnchor()

    SendUI('creator:state', {
        draft = draft,
        interior = {
            id = GetInteriorFromEntity(cache.ped),
            pattern = pattern,
            roomCount = count,
            names = names,
            currentRoom = currentRoomName(),
        },
        anchor = anchorBuilding and {
            building = anchorBuilding,
            index = anchorIndex,
            floor = anchorFloor,
            distance = math.floor(anchorDist * 100) / 100,
        } or nil,
        coords = pedVec4(),
    })
end

RegisterNUICallback('creator:open', function(_, cb)
    cb(1)
    if not canUse then return end
    pushDraft()
end)

RegisterNUICallback('creator:newBuilding', function(data, cb)
    cb(1)
    if not canUse or type(data) ~= 'table' then return end

    local pattern, count = scanInterior()

    draft = {
        key = tostring(data.key or ''):lower():gsub('[^%l%d_]', ''),
        label = data.label or '',
        entrance = pedVec3(),
        roomName = pattern or 'Room.%d',
        floors = { count = 1, baseZ = GetEntityCoords(cache.ped).z, step = 3.8 },
        rooms = {},
        roomLayout = { spawn = { x = 0.0, y = -4.5, z = 0.5 }, height = 3.2, decorateDist = 5.0 },
        expectedRooms = count,
    }

    pushDraft()
end)

RegisterNUICallback('creator:loadBuilding', function(data, cb)
    cb(1)
    if not canUse or type(data) ~= 'table' then return end

    local building = Buildings[data.key]
    if not building then return end

    local rooms = {}
    for i = 1, #building.rooms do
        local room = building.rooms[i]
        rooms[i] = { x = room.x, y = room.y, z = room.z, w = room.w }
    end

    draft = {
        key = data.key,
        label = building.label,
        entrance = { x = building.entrance.x, y = building.entrance.y, z = building.entrance.z },
        roomName = building.roomName,
        floors = { count = building.floors.count, baseZ = building.floors.baseZ, step = building.floors.step },
        rooms = rooms,
        roomLayout = {
            spawn = { x = building.roomLayout.spawn.x, y = building.roomLayout.spawn.y, z = building.roomLayout.spawn.z },
            height = building.roomLayout.height,
            decorateDist = building.roomLayout.decorateDist,
        },
        ipl = building.ipl,
    }

    pushDraft()
end)

RegisterNUICallback('creator:capture', function(data, cb)
    cb(1)
    if not canUse or not draft or type(data) ~= 'table' then return end

    local what = data.what

    if what == 'entrance' then
        draft.entrance = pedVec3()
    elseif what == 'receptionist' then
        draft.receptionist = draft.receptionist or { model = GetHashKey('a_m_y_business_01'), scenario = 'WORLD_HUMAN_CLIPBOARD' }
        draft.receptionist.coords = pedVec4()
    elseif what == 'elevator' then
        draft.elevator = pedVec4()
    elseif what == 'lobbyElevator' then
        draft.lobbyElevators = draft.lobbyElevators or {}
        draft.lobbyElevators[#draft.lobbyElevators + 1] = pedVec4()
    elseif what == 'room' then
        draft.rooms[#draft.rooms + 1] = pedVec4()
    elseif what == 'baseZ' then
        draft.floors.baseZ = GetEntityCoords(cache.ped).z
    elseif what == 'step' then
        local step = GetEntityCoords(cache.ped).z - draft.floors.baseZ
        if step > 0.5 then draft.floors.step = step end
    elseif what == 'spawn' then
        local anchor = draft.rooms[#draft.rooms]
        if anchor then
            local coords = GetEntityCoords(cache.ped)
            local rad = math.rad(anchor.w)
            local dx, dy = coords.x - anchor.x, coords.y - anchor.y
            draft.roomLayout.spawn = {
                x = dx * math.cos(-rad) - dy * math.sin(-rad),
                y = dx * math.sin(-rad) + dy * math.cos(-rad),
                z = coords.z - anchor.z,
            }
        end
    end

    pushDraft()
end)

RegisterNUICallback('creator:removeRoom', function(data, cb)
    cb(1)
    if not canUse or not draft or type(data) ~= 'table' then return end

    local index = tonumber(data.index)
    if index and draft.rooms[index] then table.remove(draft.rooms, index) end
    pushDraft()
end)

RegisterNUICallback('creator:update', function(data, cb)
    cb(1)
    if not canUse or not draft or type(data) ~= 'table' then return end

    if data.label ~= nil then draft.label = data.label end
    if data.roomName ~= nil then draft.roomName = data.roomName end
    if data.ipl ~= nil then draft.ipl = data.ipl end
    if data.floorCount ~= nil then draft.floors.count = tonumber(data.floorCount) or draft.floors.count end
    if data.step ~= nil then draft.floors.step = tonumber(data.step) or draft.floors.step end
    if data.baseZ ~= nil then draft.floors.baseZ = tonumber(data.baseZ) or draft.floors.baseZ end

    pushDraft()
end)

RegisterNUICallback('creator:save', function(_, cb)
    cb(1)
    if not canUse or not draft then return end

    if lib.callback.await('qbx_properties:callback:saveBuilding', false, draft) then
        SendUI('creator:saved', true)
    end
end)

RegisterNUICallback('creator:teleport', function(data, cb)
    cb(1)
    if not canUse or not draft or type(data) ~= 'table' then return end

    local index = tonumber(data.index)
    local anchor = index and draft.rooms[index]
    if not anchor then return end

    SetEntityCoords(cache.ped, anchor.x, anchor.y, anchor.z, false, false, false, false)
    SetEntityHeading(cache.ped, anchor.w)
end)

CreateThread(function()
    Wait(3000)
    canUse = lib.callback.await('qbx_properties:callback:canUseCreator', false) or false
    if canUse then SendUI('creator:enabled', true) end
end)
