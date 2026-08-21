local sharedConfig = require 'config.shared'

DecorationTints = {}
DecorationItems = {}

local targeted = {}
local lightEntities = {}
local powered = true
PlacedDecorations = {}

---@param entity number
---@param model string
local function applyPower(entity, model)
    local spec = GetFurnitureSpecs()[model]
    if not spec or not spec.light then return end

    lightEntities[entity] = true
    SetEntityLights(entity, not powered)
end

function SetPropertyPowered(value)
    powered = value ~= false

    for entity in pairs(lightEntities) do
        if DoesEntityExist(entity) then
            SetEntityLights(entity, not powered)
        else
            lightEntities[entity] = nil
        end
    end
end

RegisterNetEvent('qbx_properties:client:utilityState', function(propertyId, state)
    if CurrentPropertyId ~= propertyId then return end
    SetPropertyPowered(state.powered)
end)

local function addInteraction(entity, decoration)
    if not sharedConfig.targetInteractions or not decoration.interaction then return end

    if decoration.interaction == 'wardrobe' then
        exports.ox_target:addLocalEntity(entity, {
            {
                name = 'qbx_properties_wardrobe_' .. decoration.id,
                label = 'Change clothing',
                icon = 'fa-solid fa-shirt',
                distance = 1.5,
                onSelect = function()
                    exports['illenium-appearance']:startPlayerCustomization(function(appearance)
                        if appearance then
                            TriggerServerEvent('illenium-appearance:server:saveAppearance', appearance)
                        end
                    end, {
                        components = true,
                        componentConfig = { masks = true, upperBody = true, lowerBody = true, bags = true, shoes = true, scarfAndChains = true, bodyArmor = true, shirts = true, decals = true, jackets = true },
                        props = true,
                        propConfig = { hats = true, glasses = true, ear = true, watches = true, bracelets = true },
                        allowExit = true,
                    })
                end
            }
        })
    elseif decoration.interaction == 'tablet' then
        exports.ox_target:addLocalEntity(entity, {
            {
                name = 'qbx_properties_tablet_' .. decoration.id,
                label = 'Housing tablet',
                icon = 'fa-solid fa-tablet-screen-button',
                distance = 1.5,
                onSelect = function() OpenTablet() end
            }
        })
    elseif decoration.interaction == 'logout' then
        if not sharedConfig.logoutEnabled then return end

        exports.ox_target:addLocalEntity(entity, {
            {
                name = 'qbx_properties_logout_' .. decoration.id,
                label = 'Log out',
                icon = 'fa-solid fa-bed',
                distance = 1.5,
                onSelect = function()
                    DoScreenFadeOut(1000)
                    while not IsScreenFadedOut() do Wait(0) end
                    TriggerServerEvent('qbx_properties:server:logoutProperty')
                end
            }
        })
    elseif decoration.interaction == 'stash' then
        local index = decoration.stashIndex or 0
        exports.ox_target:addLocalEntity(entity, {
            {
                name = 'qbx_properties_stash_' .. decoration.id,
                label = string.format('Open stash %d', index),
                icon = 'fa-solid fa-box-archive',
                distance = 1.5,
                canInteract = function() return PropertyAccess.stash or (IsPropertyBreached and IsPropertyBreached(CurrentPropertyId)) end,
                onSelect = function() TriggerServerEvent('qbx_properties:server:openStash', index) end
            }
        })
    else
        return
    end

    targeted[decoration.id] = entity
end

---@param decoration table
---@return number?
function SpawnDecoration(decoration)
    local existing = DecorationObjects[decoration.id]
    if existing and DoesEntityExist(existing) and GetEntityArchetypeName(existing) == decoration.model then
        SetEntityCoordsNoOffset(existing, decoration.coords.x, decoration.coords.y, decoration.coords.z, false, false, false)
        SetEntityRotation(existing, decoration.rotation.x, decoration.rotation.y, decoration.rotation.z, 2, false)
        SetEntityDrawOutline(existing, false)
        DecorationTints[decoration.id] = decoration.tint
        SetObjectTextureVariation(existing, 0)
        if decoration.tint and decoration.tint > 0 then
            SetObjectTextureVariation(existing, decoration.tint)
        end
        if IsDecorating then PushPlacedDecorations() end
        return existing
    end

    DespawnDecoration(decoration.id)

    if not IsModelValid(GetHashKey(decoration.model)) then
        lib.print.warn(('decoration %s uses missing model %s'):format(decoration.id, decoration.model))
        return
    end

    local model = lib.requestModel(decoration.model, 60000)
    if not model then return end

    local entity = CreateObjectNoOffset(model, decoration.coords.x, decoration.coords.y, decoration.coords.z, false, false, false)
    SetEntityRotation(entity, decoration.rotation.x, decoration.rotation.y, decoration.rotation.z, 2, false)
    SetEntityCollision(entity, true, true)
    SetEntityDrawOutline(entity, false)

    DecorationTints[decoration.id] = decoration.tint
    if decoration.tint and decoration.tint > 0 then
        SetEntityAlpha(entity, 0, false)
        SetObjectTextureVariation(entity, 0)
        SetObjectTextureVariation(entity, decoration.tint)
        SetTimeout(100, function()
            if not DoesEntityExist(entity) then return end
            ResetEntityAlpha(entity)
            SetObjectTextureVariation(entity, 0)
            SetObjectTextureVariation(entity, decoration.tint)
        end)
    end
    FreezeEntityPosition(entity, true)
    SetModelAsNoLongerNeeded(model)

    DecorationObjects[decoration.id] = entity
    PlacedDecorations[decoration.id] = decoration.model
    DecorationItems[decoration.id] = decoration.item

    if decoration.item then
        local meta = decoration.metadata or (type(decoration.item_metadata) == 'string' and json.decode(decoration.item_metadata)) or nil
        TriggerEvent('qbx_properties:client:itemFurniture', 'spawn', decoration.id, entity, decoration.item, meta)
    end
    addInteraction(entity, decoration)
    applyPower(entity, decoration.model)

    if IsDecorating then PushPlacedDecorations() end

    return entity
end

---@param id integer
function DespawnDecoration(id)
    local entity = DecorationObjects[id]
    if not entity then return end

    if DecorationItems[id] then
        TriggerEvent('qbx_properties:client:itemFurniture', 'remove', id, entity)
    end

    if DoesEntityExist(entity) then
        if targeted[id] then exports.ox_target:removeLocalEntity(entity) end
        DeleteEntity(entity)
    end

    targeted[id] = nil
    lightEntities[entity] = nil
    DecorationObjects[id] = nil
    PlacedDecorations[id] = nil
    DecorationItems[id] = nil

    if IsDecorating then PushPlacedDecorations() end
end

---@param decorations table
function LoadRoomFurniture(decorations)
    UnloadRoomFurniture()

    for i = 1, #decorations do
        SpawnDecoration(decorations[i])
    end
end

function UnloadRoomFurniture()
    for id in pairs(DecorationObjects) do
        DespawnDecoration(id)
    end
end

local liveTargets = {}
local liveThread = false

local function lerpAngle(from, to, factor)
    return from + (((to - from + 180.0) % 360.0) - 180.0) * factor
end

RegisterNetEvent('qbx_properties:client:decorationMoving', function(objectId, coords, rotation)
    if not DecorationObjects[objectId] then return end

    liveTargets[objectId] = { coords = coords, rotation = rotation }
    if liveThread then return end
    liveThread = true

    CreateThread(function()
        while next(liveTargets) do
            Wait(0)
            local factor = math.min(GetFrameTime() * 12.0, 1.0)

            for id, target in pairs(liveTargets) do
                local entity = DecorationObjects[id]
                if not entity or not DoesEntityExist(entity) then
                    liveTargets[id] = nil
                else
                    local pos = GetEntityCoords(entity)
                    local rot = GetEntityRotation(entity, 2)

                    if #(target.coords - pos) < 0.01 and math.abs(((target.rotation.z - rot.z + 180.0) % 360.0) - 180.0) < 0.5 then
                        SetEntityCoordsNoOffset(entity, target.coords.x, target.coords.y, target.coords.z, false, false, false)
                        SetEntityRotation(entity, target.rotation.x, target.rotation.y, target.rotation.z, 2, false)
                        liveTargets[id] = nil
                    else
                        local lerped = pos + (target.coords - pos) * factor
                        SetEntityCoordsNoOffset(entity, lerped.x, lerped.y, lerped.z, false, false, false)
                        SetEntityRotation(entity,
                            lerpAngle(rot.x, target.rotation.x, factor),
                            lerpAngle(rot.y, target.rotation.y, factor),
                            lerpAngle(rot.z, target.rotation.z, factor), 2, false)
                    end
                end
            end
        end

        liveThread = false
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    UnloadRoomFurniture()
end)
