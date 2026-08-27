local sharedConfig = require 'config.shared'

if not sharedConfig.dynamicApartments then return end

local accessCache = {}
local unitProperty = {}

---@param entity number
---@return string? buildingKey, integer? floor, integer? room
local function resolveDoorUnit(entity)
    local coords = GetEntityCoords(entity)

    for key, building in pairs(Buildings) do
        local layout = building.roomLayout
        if layout and layout.doors then
            local floor = math.floor((coords.z - building.floors.baseZ) / building.floors.step + 0.5) + 1

            if floor >= 1 and floor <= building.floors.count then
                for room = 1, #building.rooms do
                    local anchor = GetRoomCoords(key, floor, room)
                    if anchor and #(coords - RotateOffset(anchor, layout.doors[1].coords)) < 1.5 then
                        return key, floor, room
                    end
                end
            end
        end
    end
end

---@param entity number
---@return boolean
local function lacksKey(entity)
    local buildingKey, floor, room = resolveDoorUnit(entity)
    if not buildingKey or not floor or not room then return false end

    local key = string.format('%s:%d:%d', buildingKey, floor, room)
    if accessCache[key] == nil then
        accessCache[key] = lib.callback.await('qbx_properties:callback:canDecorateUnit', false, buildingKey, floor, room) or false
    end

    return not accessCache[key]
end

CreateThread(function()
    local models = {}

    for _, building in pairs(Buildings) do
        local doors = building.roomLayout and building.roomLayout.doors
        if doors then
            for i = 1, #doors do
                models[doors[i].model] = true
            end
        end
    end

    for model in pairs(models) do
        exports.ox_target:addModel(model, {
            {
                name = 'qbx_properties_doorbell',
                label = 'Ring doorbell',
                icon = 'fa-solid fa-bell',
                distance = TargetDistance('doorbell', 1.5),
                canInteract = function(entity) return lacksKey(entity) end,
                onSelect = function(data)
                    local buildingKey, floor, room = resolveDoorUnit(data.entity)
                    if not buildingKey then return end
                    TriggerServerEvent('qbx_properties:server:ringUnit', buildingKey, floor, room)
                    lib.notify({ type = 'info', description = 'You rang the doorbell.' })
                end
            }
        })
    end
end)

---@param entity number
---@return integer? propertyId
function ResolveDoorProperty(entity)
    local buildingKey, floor, room = resolveDoorUnit(entity)
    if not buildingKey or not floor or not room then return end

    local key = string.format('%s:%d:%d', buildingKey, floor, room)
    if unitProperty[key] == nil then
        unitProperty[key] = lib.callback.await('qbx_properties:callback:getUnitProperty', false, buildingKey, floor, room) or false
    end

    return unitProperty[key] or nil
end

RegisterNetEvent('qbx_properties:client:invalidateUnitAccess', function()
    table.wipe(accessCache)
    table.wipe(unitProperty)
end)
