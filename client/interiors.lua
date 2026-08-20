local walkInProperties = {}
local unitAccess = {}
local currentKey = nil
local currentWalkIn = nil

---@param interiorId integer
---@return integer? propertyId
local function resolveWalkIn(interiorId)
    local coords = GetEntityCoords(cache.ped)

    for i = 1, #walkInProperties do
        local property = walkInProperties[i]
        if #(coords - property.coords) < 60.0 and GetInteriorAtCoords(property.coords.x, property.coords.y, property.coords.z) == interiorId then
            return property.id
        end
    end
end

local function leaveWalkIn()
    if not currentWalkIn then return end
    currentWalkIn = nil
    CurrentPropertyId = nil
    if SetPropertyAccess then SetPropertyAccess(nil) end
    RemoveDecorateRadial()
    TriggerServerEvent('qbx_properties:server:leaveWalkIn')
end

CreateThread(function()
    while true do
        Wait(750)

        local buildingKey, floor, room
        if ResolveCurrentUnit then buildingKey, floor, room = ResolveCurrentUnit() end
        local key = buildingKey and floor and room and string.format('%s:%d:%d', buildingKey, floor, room) or nil

        if key then
            if key ~= currentKey then
                leaveWalkIn()
                currentKey = key
                RemoveDecorateRadial()
                TriggerServerEvent('qbx_properties:server:setCurrentUnit', buildingKey, floor, room)

                local decorations = lib.callback.await('qbx_properties:callback:getRoomDecorations', false, buildingKey, floor, room)
                CurrentPropertyId = decorations.propertyId
                if SetPropertyAccess then SetPropertyAccess(decorations.access) end
                if SetRaidState then SetRaidState(decorations.propertyId, decorations.breached) end
                LoadRoomFurniture(decorations)
                if LoadWallColor then LoadWallColor(CurrentPropertyId, buildingKey, room) end

                if unitAccess[key] == nil then
                    unitAccess[key] = lib.callback.await('qbx_properties:callback:canDecorateUnit', false, buildingKey, floor, room) or false
                end
                if unitAccess[key] then AddDecorateRadial() end
            end
        else
            if currentKey then
                currentKey = nil
                CurrentPropertyId = nil
                if SetPropertyAccess then SetPropertyAccess(nil) end
                RemoveDecorateRadial()
                UnloadRoomFurniture()
                if ClearUnitWallColors then ClearUnitWallColors() end
                TriggerServerEvent('qbx_properties:server:setCurrentUnit', nil)
            end

            local interiorId = GetInteriorFromEntity(cache.ped)
            local propertyId = interiorId ~= 0 and resolveWalkIn(interiorId) or nil

            if propertyId ~= currentWalkIn then
                leaveWalkIn()

                if propertyId then
                    currentWalkIn = propertyId
                    CurrentPropertyId = propertyId
                    if LoadWallColor then LoadWallColor(propertyId) end
                    TriggerServerEvent('qbx_properties:server:enterWalkIn', propertyId)
                    if lib.callback.await('qbx_properties:callback:checkAccess', false) then
                        AddDecorateRadial()
                    end
                end
            end
        end
    end
end)

local function refresh()
    walkInProperties = lib.callback.await('qbx_properties:callback:getWalkInProperties', false) or {}
    table.wipe(unitAccess)
    currentKey = nil
    currentWalkIn = nil
end

RegisterNetEvent('qbx_properties:client:invalidateUnitAccess', refresh)

CreateThread(function()
    Wait(2000)
    refresh()
end)
