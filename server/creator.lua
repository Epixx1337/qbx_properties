local config = require 'config.server'

local ACE = 'qbx_properties.creator'

local function fmtVec3(v)
    return string.format('vec3(%.2f, %.2f, %.2f)', v.x, v.y, v.z)
end

local function fmtVec4(v)
    return string.format('vec4(%.2f, %.2f, %.2f, %.1f)', v.x, v.y, v.z, v.w)
end

local function quote(value)
    return string.format('%q', value)
end

---@param buildings table<string, table>
---@return string
local function serialise(buildings)
    local lines = { 'return {' }
    local keys = {}
    for key in pairs(buildings) do keys[#keys + 1] = key end
    table.sort(keys)

    for _, key in ipairs(keys) do
        local building = buildings[key]
        lines[#lines + 1] = string.format('    [%s] = {', quote(key))
        lines[#lines + 1] = string.format('        type = %s,', quote(building.type or 'mlo'))
        lines[#lines + 1] = string.format('        label = %s,', quote(building.label))
        if building.description then lines[#lines + 1] = string.format('        description = %s,', quote(building.description)) end

        if building.type == 'interior' then
            lines[#lines + 1] = string.format('        enter = %s,', fmtVec3(building.enter))
            lines[#lines + 1] = '    },'
            goto continue
        end

        if building.resource then lines[#lines + 1] = string.format('        resource = %s,', quote(building.resource)) end
        if building.layout then lines[#lines + 1] = string.format('        layout = %s,', quote(building.layout)) end
        if building.perRoomInterior then lines[#lines + 1] = '        perRoomInterior = true,' end
        if building.stairsOnly then lines[#lines + 1] = '        stairsOnly = true,' end
        lines[#lines + 1] = string.format('        entrance = %s,', fmtVec3(building.entrance))

        if building.lobbyElevators and #building.lobbyElevators > 0 then
            lines[#lines + 1] = '        lobbyElevators = {'
            for i = 1, #building.lobbyElevators do
                lines[#lines + 1] = string.format('            %s,', fmtVec4(building.lobbyElevators[i]))
            end
            lines[#lines + 1] = '        },'
        end

        if building.receptionist then
            lines[#lines + 1] = '        receptionist = {'
            lines[#lines + 1] = string.format('            model = %d,', building.receptionist.model)
            lines[#lines + 1] = string.format('            coords = %s,', fmtVec4(building.receptionist.coords))
            lines[#lines + 1] = string.format('            scenario = %s,', quote(building.receptionist.scenario or 'WORLD_HUMAN_CLIPBOARD'))
            lines[#lines + 1] = '        },'
        end

        lines[#lines + 1] = '        floors = {'
        lines[#lines + 1] = string.format('            count = %d,', building.floors.count)
        lines[#lines + 1] = string.format('            baseZ = %.3f,', building.floors.baseZ)
        lines[#lines + 1] = string.format('            step = %.3f,', building.floors.step)
        lines[#lines + 1] = '        },'

        if building.ipl then lines[#lines + 1] = string.format('        ipl = %s,', quote(building.ipl)) end
        if building.interiorAnchor then lines[#lines + 1] = string.format('        interiorAnchor = %s,', fmtVec3(building.interiorAnchor)) end
        if building.roomName then lines[#lines + 1] = string.format('        roomName = %s,', quote(building.roomName)) end
        if building.roomNumberOffset then lines[#lines + 1] = string.format('        roomNumberOffset = %d,', building.roomNumberOffset) end
        if building.wallEntitySet then lines[#lines + 1] = string.format('        wallEntitySet = %s,', quote(building.wallEntitySet)) end
        if building.elevator then lines[#lines + 1] = string.format('        elevator = %s,', fmtVec4(building.elevator)) end
        if building.garageElevator then lines[#lines + 1] = string.format('        garageElevator = %s,', fmtVec4(building.garageElevator)) end

        lines[#lines + 1] = '        rooms = {'
        for i = 1, #building.rooms do
            lines[#lines + 1] = string.format('            %s,', fmtVec4(building.rooms[i]))
        end
        lines[#lines + 1] = '        },'

        local layout = building.roomLayout
        lines[#lines + 1] = '        roomLayout = {'
        lines[#lines + 1] = string.format('            spawn = %s,', fmtVec3(layout.spawn))
        lines[#lines + 1] = string.format('            height = %.2f,', layout.height or 3.2)
        lines[#lines + 1] = string.format('            decorateDist = %.2f,', layout.decorateDist or 5.0)
        if layout.points and #layout.points > 0 then
            lines[#lines + 1] = '            points = {'
            for i = 1, #layout.points do
                lines[#lines + 1] = string.format('                vec2(%.2f, %.2f),', layout.points[i].x, layout.points[i].y)
            end
            lines[#lines + 1] = '            },'
        end
        if layout.doors and #layout.doors > 0 then
            lines[#lines + 1] = '            doors = {'
            for i = 1, #layout.doors do
                lines[#lines + 1] = '                {'
                lines[#lines + 1] = string.format('                    coords = %s,', fmtVec3(layout.doors[i].coords))
                lines[#lines + 1] = string.format('                    model = %d,', layout.doors[i].model)
                lines[#lines + 1] = '                },'
            end
            lines[#lines + 1] = '            },'
        end
        lines[#lines + 1] = '        },'

        lines[#lines + 1] = '    },'
        ::continue::
    end

    lines[#lines + 1] = '}'
    lines[#lines + 1] = ''
    return table.concat(lines, '\n')
end

---@param value any
---@return vector3?
local function toVec3(value)
    if type(value) ~= 'table' then return end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    if not x or not y or not z then return end
    return vec3(x, y, z)
end

---@param value any
---@return vector4?
local function toVec4(value)
    if type(value) ~= 'table' then return end
    local x, y, z, w = tonumber(value.x), tonumber(value.y), tonumber(value.z), tonumber(value.w)
    if not x or not y or not z or not w then return end
    return vec4(x, y, z, w)
end

---@param payload any
---@return table?
local function validate(payload)
    if type(payload) ~= 'table' then return end
    if type(payload.key) ~= 'string' or not payload.key:match('^[%l%d_]+$') or #payload.key > 32 then return end
    if type(payload.label) ~= 'string' or #payload.label < 2 or #payload.label > 48 then return end
    if type(payload.roomName) ~= 'string' or not payload.roomName:find('%%d') or #payload.roomName > 32 then return end

    local entrance = toVec3(payload.entrance)
    if not entrance then return end

    local floors = payload.floors
    if type(floors) ~= 'table' then return end
    local count, baseZ, step = ToId(floors.count), tonumber(floors.baseZ), tonumber(floors.step)
    if not count or count < 1 or count > 100 then return end
    if not baseZ or not step or step <= 0 or step > 50 then return end

    if type(payload.rooms) ~= 'table' or #payload.rooms < 1 or #payload.rooms > 100 then return end
    local rooms = {}
    for i = 1, #payload.rooms do
        rooms[i] = toVec4(payload.rooms[i])
        if not rooms[i] then return end
    end

    local layout = type(payload.roomLayout) == 'table' and payload.roomLayout or {}
    local spawn = toVec3(layout.spawn) or vec3(0.0, -4.5, 0.5)

    local building = {
        label = payload.label,
        entrance = entrance,
        floors = { count = count, baseZ = baseZ, step = step },
        roomName = payload.roomName,
        rooms = rooms,
        roomLayout = {
            spawn = spawn,
            height = tonumber(layout.height) or 3.2,
            decorateDist = tonumber(layout.decorateDist) or 5.0,
        },
    }

    if type(payload.ipl) == 'string' and #payload.ipl <= 64 then building.ipl = payload.ipl end
    building.interiorAnchor = toVec3(payload.interiorAnchor)
    building.elevator = toVec4(payload.elevator)

    if type(payload.receptionist) == 'table' then
        local coords = toVec4(payload.receptionist.coords)
        local model = ToId(payload.receptionist.model)
        if coords and model then
            building.receptionist = {
                model = model,
                coords = coords,
                scenario = type(payload.receptionist.scenario) == 'string' and payload.receptionist.scenario or 'WORLD_HUMAN_CLIPBOARD',
            }
        end
    end

    if type(payload.lobbyElevators) == 'table' then
        local elevators = {}
        for i = 1, #payload.lobbyElevators do
            elevators[i] = toVec4(payload.lobbyElevators[i])
            if not elevators[i] then return end
        end
        building.lobbyElevators = elevators
    end

    return building
end

lib.callback.register('qbx_properties:callback:saveBuilding', function(source, payload)
    if not IsPlayerAceAllowed(source, ACE) then
        exports.qbx_core:Notify(source, 'You do not have permission to edit buildings.', 'error')
        return false
    end

    local building = validate(payload)
    if not building then
        exports.qbx_core:Notify(source, 'Building data failed validation.', 'error')
        return false
    end

    local existing = MySQL.scalar.await('SELECT COUNT(*) FROM properties WHERE building = ?', {payload.key}) or 0
    if existing > 0 and #building.rooms < (Buildings[payload.key] and #Buildings[payload.key].rooms or 0) then
        exports.qbx_core:Notify(source, 'Cannot shrink a building that already has units.', 'error')
        return false
    end

    local merged = {}
    for key, value in pairs(Buildings) do merged[key] = value end
    merged[payload.key] = building

    if not SaveResourceFile(cache.resource, 'config/buildings.lua', serialise(merged), -1) then
        exports.qbx_core:Notify(source, 'Failed to write config/buildings.lua.', 'error')
        return false
    end

    Buildings[payload.key] = building

    LogAction(source, 'qbx_properties:server:saveBuilding', string.format('%s saved building %s (%d rooms, %d floors)', GetPlayerName(source), payload.key, #building.rooms, building.floors.count))

    exports.qbx_core:Notify(source, 'Building saved. Restart the resource to apply it fully.', 'success')
    return true
end)

lib.callback.register('qbx_properties:callback:canUseCreator', function(source)
    return IsPlayerAceAllowed(source, ACE)
end)
