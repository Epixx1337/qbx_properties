local sharedConfig = require 'config.shared'

DecorationTints = {}
DecorationItems = {}
DecorationHealth = {}

local burnout = sharedConfig.electricity and sharedConfig.electricity.burnout == true
local targeted = {}
local lightEntities = {}
local powered = true
PlacedDecorations = {}

---@param id integer
---@return boolean
local function isBroken(id)
    return burnout and (DecorationHealth[id] or 100) <= 0
end

---@param entity number
local function refreshLight(entity)
    local id = lightEntities[entity]
    local lit = powered and not (type(id) == 'number' and isBroken(id))
    SetEntityLights(entity, not lit)
end

---@param entity number
---@param model string
---@param id integer?
local function applyPower(entity, model, id)
    local spec = GetFurnitureSpecs()[model]
    if not spec or not spec.light then return end

    lightEntities[entity] = id or true
    refreshLight(entity)
end

function SetPropertyPowered(value)
    powered = value ~= false

    for entity in pairs(lightEntities) do
        if DoesEntityExist(entity) then
            refreshLight(entity)
        else
            lightEntities[entity] = nil
        end
    end
end

RegisterNetEvent('qbx_properties:client:utilityState', function(propertyId, state)
    if CurrentPropertyId ~= propertyId then return end
    SetPropertyPowered(state.powered)
end)

RegisterNetEvent('qbx_properties:client:furnitureHealth', function(propertyId, updates)
    if CurrentPropertyId ~= propertyId or type(updates) ~= 'table' then return end

    for id, health in pairs(updates) do
        DecorationHealth[tonumber(id) or id] = health
    end

    for entity in pairs(lightEntities) do
        if DoesEntityExist(entity) then refreshLight(entity) end
    end
end)

local targetProxies = {}

local function openLockedStash(decoration, index)
    if index > 0 and sharedConfig.storagePins then
        local state = lib.callback.await('qbx_properties:callback:stashLock', false, decoration.id)
        if state and state.locked and not state.mine and not (IsPropertyBreached and IsPropertyBreached(CurrentPropertyId)) then
            local input = lib.inputDialog('Storage pin', {
                { type = 'input', label = 'Pin', password = true, required = true },
            })
            if not input then return end
            TriggerServerEvent('qbx_properties:server:openStash', index, input[1])
            return
        end
    end

    TriggerServerEvent('qbx_properties:server:openStash', index)
end

local function manageStashLock(decoration)
    local state = lib.callback.await('qbx_properties:callback:stashLock', false, decoration.id)
    if not state then return end

    if not state.canPin then
        lib.notify({ type = 'error', description = 'The Security II upgrade is needed before locks can be fitted.' })
        return
    end

    if state.locked and not state.mine then
        lib.notify({ type = 'error', description = 'Only whoever set this pin can change it.' })
        return
    end

    local input = lib.inputDialog(state.locked and 'Change pin' or 'Set pin', {
        { type = 'input', label = 'Pin (4-8 digits, empty removes it)', password = true },
    })
    if not input then return end

    local pin = input[1]
    if pin == '' then pin = nil end
    lib.callback.await('qbx_properties:callback:setStashPin', false, decoration.id, pin)
end

local function repairFurniture(decoration)
    local success = lib.skillCheck(sharedConfig.electricity and sharedConfig.electricity.repairSkillCheck or { 'medium', 'medium' })
    if not success then
        lib.notify({ type = 'error', description = 'Sparks fly, try again.' })
        return
    end

    lib.callback.await('qbx_properties:callback:repairFurniture', false, decoration.id)
end

local function interactionOptions(decoration)
    local options = {}

    if decoration.interaction == 'wardrobe' then
        options[#options + 1] = {
            name = 'qbx_properties_wardrobe_' .. decoration.id,
            label = 'Change clothing',
            icon = 'fa-solid fa-shirt',
            distance = TargetDistance('furniture', 1.5),
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
    elseif decoration.interaction == 'tablet' then
        options[#options + 1] = {
            name = 'qbx_properties_tablet_' .. decoration.id,
            label = 'Housing tablet',
            icon = 'fa-solid fa-tablet-screen-button',
            distance = TargetDistance('furniture', 1.5),
            onSelect = function() OpenTablet() end
        }
    elseif decoration.interaction == 'logout' then
        if sharedConfig.logoutEnabled then
            options[#options + 1] = {
                name = 'qbx_properties_logout_' .. decoration.id,
                label = 'Log out',
                icon = 'fa-solid fa-bed',
                distance = TargetDistance('furniture', 1.5),
                onSelect = function()
                    DoScreenFadeOut(1000)
                    while not IsScreenFadedOut() do Wait(0) end
                    TriggerServerEvent('qbx_properties:server:logoutProperty')
                end
            }
        end
    elseif decoration.interaction == 'stash' then
        local index = decoration.stashIndex or 0
        options[#options + 1] = {
            name = 'qbx_properties_stash_' .. decoration.id,
            label = string.format('Open stash %d', index),
            icon = 'fa-solid fa-box-archive',
            distance = TargetDistance('furniture', 1.5),
            canInteract = function() return PropertyAccess.stash or (IsPropertyBreached and IsPropertyBreached(CurrentPropertyId)) end,
            onSelect = function() openLockedStash(decoration, index) end
        }

        if sharedConfig.storagePins then
            options[#options + 1] = {
                name = 'qbx_properties_stashlock_' .. decoration.id,
                label = 'Manage lock',
                icon = 'fa-solid fa-lock',
                distance = TargetDistance('furniture', 1.5),
                canInteract = function() return PropertyAccess.stash and PropertyAccess.pins end,
                onSelect = function() manageStashLock(decoration) end
            }
        end
    elseif decoration.interaction == 'fridge' then
        options[#options + 1] = {
            name = 'qbx_properties_fridge_' .. decoration.id,
            label = 'Open fridge',
            icon = 'fa-solid fa-snowflake',
            distance = TargetDistance('furniture', 1.5),
            canInteract = function() return PropertyAccess.stash or (IsPropertyBreached and IsPropertyBreached(CurrentPropertyId)) end,
            onSelect = function() TriggerServerEvent('qbx_properties:server:openFridge', decoration.id) end
        }
    elseif decoration.interaction == 'trash' then
        options[#options + 1] = {
            name = 'qbx_properties_trash_' .. decoration.id,
            label = 'Open trash',
            icon = 'fa-solid fa-trash-can',
            distance = TargetDistance('furniture', 1.5),
            canInteract = function() return PropertyAccess.door end,
            onSelect = function() TriggerServerEvent('qbx_properties:server:openTrash', decoration.id) end
        }
    end

    local spec = GetFurnitureSpecs()[decoration.model]
    if burnout and spec and (spec.power or 0) > 0 then
        options[#options + 1] = {
            name = 'qbx_properties_repair_' .. decoration.id,
            label = 'Repair wiring',
            icon = 'fa-solid fa-screwdriver-wrench',
            distance = TargetDistance('furniture', 1.5),
            canInteract = function() return isBroken(decoration.id) end,
            onSelect = function() repairFurniture(decoration) end
        }
    end

    if #options == 0 then return end
    return options
end

local PROXY_MODEL <const> = `prop_cs_tablet`

local function removeInteraction(id)
    local proxy = targetProxies[id]
    if proxy then
        if DoesEntityExist(proxy) then
            exports.ox_target:removeLocalEntity(proxy)
            DeleteEntity(proxy)
        end
        targetProxies[id] = nil
    end
end

local function addInteraction(entity, decoration)
    if not sharedConfig.targetInteractions then return end

    local options = interactionOptions(decoration)
    if not options then return end

    local spec = GetFurnitureSpecs()[decoration.model]
    local useProxy = (spec and spec.targetZone) or not DoesEntityHavePhysics(entity)

    if useProxy then
        local model = lib.requestModel(PROXY_MODEL, 10000)
        if not model then return end

        local coords = GetEntityCoords(entity)
        local rotation = GetEntityRotation(entity, 2)
        local proxy = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, false, false, false)
        SetEntityRotation(proxy, rotation.x, rotation.y, rotation.z, 2, false)
        SetEntityAlpha(proxy, 0, false)
        SetEntityInvincible(proxy, true)
        FreezeEntityPosition(proxy, true)
        SetModelAsNoLongerNeeded(model)

        exports.ox_target:addLocalEntity(proxy, options)
        targetProxies[decoration.id] = proxy
    else
        exports.ox_target:addLocalEntity(entity, options)
        targeted[decoration.id] = entity
    end
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
        local proxy = targetProxies[decoration.id]
        if proxy and DoesEntityExist(proxy) then
            SetEntityCoordsNoOffset(proxy, decoration.coords.x, decoration.coords.y, decoration.coords.z, false, false, false)
            SetEntityRotation(proxy, decoration.rotation.x, decoration.rotation.y, decoration.rotation.z, 2, false)
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
    DecorationHealth[decoration.id] = tonumber(decoration.health) or 100

    if decoration.item then
        local meta = decoration.metadata or (type(decoration.item_metadata) == 'string' and json.decode(decoration.item_metadata)) or nil
        TriggerEvent('qbx_properties:client:itemFurniture', 'spawn', decoration.id, entity, decoration.item, meta)
    end
    addInteraction(entity, decoration)
    applyPower(entity, decoration.model, decoration.id)

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

    removeInteraction(id)
    targeted[id] = nil
    lightEntities[entity] = nil
    DecorationObjects[id] = nil
    PlacedDecorations[id] = nil
    DecorationItems[id] = nil
    DecorationHealth[id] = nil

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
