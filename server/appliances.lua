local sharedConfig = require 'config.shared'

local FRIDGE_SUFFIX <const> = '_fridge_(%d+)$'
local TRASH_SUFFIX <const> = '_trash_(%d+)$'

---@param property table
---@param decorationId integer
---@return table? row
local function getDecoration(property, decorationId)
    local ok, row
    if property.building then
        ok, row = pcall(MySQL.single.await, 'SELECT id, model, health, lock_pin, lock_setter, stash_slot FROM properties_apartment_decorations WHERE id = ? AND citizenid = ?', {decorationId, property.owner})
    else
        ok, row = pcall(MySQL.single.await, 'SELECT id, model, health, lock_pin, lock_setter, stash_slot FROM properties_decorations WHERE id = ? AND property_id = ?', {decorationId, property.id})
    end
    return ok and row or nil
end

---@param playerSource integer
---@param permission string
---@return table? player, table? property
local function getEnteredProperty(playerSource, permission)
    local player = exports.qbx_core:GetPlayer(playerSource)
    local propertyId = GetPlayerEnteredProperty(playerSource)
    if not player or not propertyId then return end

    local property = MySQL.single.await('SELECT id, property_name, owner, keyholders, building, type, group_name, tenant FROM properties WHERE id = ?', {propertyId})
    if not property or not HasPropertyAccess(player.PlayerData.citizenid, property, permission) then return end

    return player, property
end

---@param propertyId integer
---@return boolean
local function propertyPowered(propertyId)
    if not GetUtilities then return true end
    local state = MySQL.single.await('SELECT powered FROM properties_utilities WHERE property_id = ?', {propertyId})
    return not state or ToBool(state.powered)
end

RegisterNetEvent('qbx_properties:server:openFridge', function(decorationId)
    local playerSource = source --[[@as number]]
    decorationId = ToId(decorationId)
    if not decorationId then return end

    local player, property = getEnteredProperty(playerSource, 'stash')
    if not player or not property then return end

    local decoration = getDecoration(property, decorationId)
    local spec = decoration and GetFurnitureSpecs()[decoration.model]
    if not spec or spec.type ~= 'fridge' then return end

    if (sharedConfig.electricity and sharedConfig.electricity.burnout) and (decoration.health or 100) <= 0 then
        exports.qbx_core:Notify(playerSource, 'The fridge is dead, its wiring burned out.', 'error')
        return
    end

    if not propertyPowered(property.id) then
        exports.qbx_core:Notify(playerSource, 'The fridge has no power.', 'error')
        return
    end

    local stashId = string.format('%s_fridge_%d', GetStashId(property), decorationId)
    exports.ox_inventory:RegisterStash(stashId, string.format('%s: %s', property.property_name, spec.label), spec.slots or 8, spec.maxWeight or 45000, property.owner)
    exports.ox_inventory:forceOpenInventory(playerSource, 'stash', stashId)
end)

RegisterNetEvent('qbx_properties:server:openTrash', function(decorationId)
    local playerSource = source --[[@as number]]
    decorationId = ToId(decorationId)
    if not decorationId then return end

    local player, property = getEnteredProperty(playerSource, 'door')
    if not player or not property then return end

    local decoration = getDecoration(property, decorationId)
    local spec = decoration and GetFurnitureSpecs()[decoration.model]
    if not spec or spec.type ~= 'trash' then return end

    local stashId = string.format('%s_trash_%d', GetStashId(property), decorationId)
    exports.ox_inventory:RegisterStash(stashId, string.format('%s: %s', property.property_name, spec.label), 10, 50000)
    exports.qbx_core:Notify(playerSource, 'Whatever you leave in the trash is destroyed when you close it.')
    exports.ox_inventory:forceOpenInventory(playerSource, 'stash', stashId)
end)

AddEventHandler('ox_inventory:closedInventory', function(_, inventoryId)
    if type(inventoryId) ~= 'string' or not inventoryId:find(TRASH_SUFFIX) then return end
    if inventoryId:sub(1, #GetStashPrefix()) ~= GetStashPrefix() then return end
    pcall(function() exports.ox_inventory:ClearInventory(inventoryId) end)
end)

local multiplier = sharedConfig.fridges and tonumber(sharedConfig.fridges.decayMultiplier) or 0

---@param inventoryId string|number
---@param slot integer
---@param entering boolean
local function adjustDecay(inventoryId, slot, entering)
    local item = exports.ox_inventory:GetSlot(inventoryId, slot)
    local metadata = item and item.metadata
    local durability = metadata and tonumber(metadata.durability)
    if not durability or durability <= 100 then return end

    local now = os.time()
    local remaining = durability - now

    if entering and not metadata.chilled then
        if remaining > 0 then metadata.durability = now + math.floor(remaining * multiplier) end
        metadata.chilled = true
    elseif not entering and metadata.chilled then
        if remaining > 0 then metadata.durability = now + math.floor(remaining / multiplier) end
        metadata.chilled = nil
    else
        return
    end

    exports.ox_inventory:SetMetadata(inventoryId, slot, metadata)
end

if multiplier > 1 then
    exports.ox_inventory:registerHook('swapItems', function(payload)
        local fromFridge = type(payload.fromInventory) == 'string' and payload.fromInventory:find(FRIDGE_SUFFIX) ~= nil
        local toFridge = type(payload.toInventory) == 'string' and payload.toInventory:find(FRIDGE_SUFFIX) ~= nil
        if fromFridge == toFridge then return end

        local inventoryId, slot = payload.toInventory, payload.toSlot
        SetTimeout(100, function() adjustDecay(inventoryId, slot, toFridge) end)
    end, {
        inventoryFilter = {
            '^' .. EscapePattern(GetStashPrefix()),
        }
    })
end

lib.callback.register('qbx_properties:callback:stashLock', function(source, decorationId)
    if not sharedConfig.storagePins then return end
    decorationId = ToId(decorationId)
    if not decorationId then return end

    local player, property = getEnteredProperty(source, 'stash')
    if not player or not property then return end

    local decoration = getDecoration(property, decorationId)
    if not decoration then return end

    return {
        locked = decoration.lock_pin ~= nil,
        mine = decoration.lock_setter == player.PlayerData.citizenid,
        canPin = GetSecurityTier and GetSecurityTier(property.id) >= 2 or false,
    }
end)

lib.callback.register('qbx_properties:callback:setStashPin', function(source, decorationId, pin)
    if not sharedConfig.storagePins then return false end
    decorationId = ToId(decorationId)
    if not decorationId then return false end

    local player, property = getEnteredProperty(source, 'stash')
    if not player or not property then return false end

    local decoration = getDecoration(property, decorationId)
    local spec = decoration and GetFurnitureSpecs()[decoration.model]
    if not spec or spec.type ~= 'stash' then return false end

    if not (GetSecurityTier and GetSecurityTier(property.id) >= 2) then
        exports.qbx_core:Notify(source, 'The Security II upgrade is needed before locks can be fitted.', 'error')
        return false
    end

    local citizenId = player.PlayerData.citizenid
    if decoration.lock_pin and decoration.lock_setter ~= citizenId then
        exports.qbx_core:Notify(source, 'Only whoever set this pin can change it.', 'error')
        return false
    end

    if pin ~= nil then
        pin = tostring(pin)
        if not pin:match('^%d%d%d%d+$') or #pin > 8 then
            exports.qbx_core:Notify(source, 'Pins are 4 to 8 digits.', 'error')
            return false
        end
    end

    local column = property.building and 'citizenid' or 'property_id'
    local tableName = property.building and 'properties_apartment_decorations' or 'properties_decorations'
    local keyValue = property.building and property.owner or property.id

    if pin then
        MySQL.update.await(string.format('UPDATE %s SET lock_pin = ?, lock_setter = ? WHERE id = ? AND `%s` = ?', tableName, column), {pin, citizenId, decorationId, keyValue})
    else
        MySQL.update.await(string.format('UPDATE %s SET lock_pin = NULL, lock_setter = NULL WHERE id = ? AND `%s` = ?', tableName, column), {decorationId, keyValue})
    end

    lib.triggerClientEvent('qbx_properties:client:furnitureLock', GetPropertyOccupants(property.id), decorationId, pin ~= nil, pin and citizenId or nil)
    exports.qbx_core:Notify(source, pin and 'Pin set.' or 'Pin removed.', 'success')

    LogAction(source, 'qbx_properties:server:setStashPin', string.format('%s %s the pin on furniture %d of %s', citizenId, pin and 'set' or 'removed', decorationId, property.property_name))
    return true
end)

---@param property table
---@param stashIndex integer
---@param citizenId string
---@param pin string|number|nil
---@return boolean allowed
function CheckStashPin(property, stashIndex, citizenId, pin)
    if not sharedConfig.storagePins or stashIndex == 0 then return true end
    if IsBreached and IsBreached(property.id) then return true end

    local ok, decoration
    if property.building then
        ok, decoration = pcall(MySQL.single.await, 'SELECT lock_pin, lock_setter FROM properties_apartment_decorations WHERE citizenid = ? AND stash_slot = ? AND layout = ?', {property.owner, stashIndex, GetBuildingLayout(property.building)})
    else
        ok, decoration = pcall(MySQL.single.await, 'SELECT lock_pin, lock_setter FROM properties_decorations WHERE property_id = ? AND stash_slot = ?', {property.id, stashIndex})
    end

    if not ok or not decoration or not decoration.lock_pin then return true end
    if decoration.lock_setter == citizenId then return true end

    return pin ~= nil and tostring(pin) == decoration.lock_pin
end

---@param property table needs id, property_name, owner, building
---@param row table decoration with id, model and stash_slot
---@return boolean
function DecorationHasContents(property, row)
    local spec = GetFurnitureSpecs()[row.model]
    if not spec then return false end

    local stashId
    if spec.type == 'stash' and row.stash_slot then
        stashId = GetStashId(property, row.stash_slot)
    elseif spec.type == 'fridge' then
        stashId = string.format('%s_fridge_%d', GetStashId(property), row.id)
    else
        return false
    end

    local raw = MySQL.scalar.await('SELECT data FROM ox_inventory WHERE name = ?', {stashId})
    if raw then
        local ok, items = pcall(json.decode, raw)
        if ok and type(items) == 'table' and next(items) then return true end
    end

    local live = exports.ox_inventory:GetInventoryItems(stashId)
    if live then
        for _ in pairs(live) do return true end
    end

    return false
end

---@param propertyId integer
function BreakPoweredFurniture(propertyId)
    local electricity = sharedConfig.electricity
    if not electricity or not electricity.burnout then return end

    local property = MySQL.single.await('SELECT id, owner, building FROM properties WHERE id = ?', {propertyId})
    if not property or property.building then return end

    local decorations = GetPropertyDecorations(property)
    local specs = GetFurnitureSpecs()
    local broken = {}

    for i = 1, #decorations do
        local spec = specs[decorations[i].model]
        if spec and (spec.power or 0) > 0 and (decorations[i].health or 100) > 0 then
            broken[#broken + 1] = decorations[i].id
        end
    end

    if #broken == 0 then return end

    if not pcall(MySQL.update.await, ('UPDATE properties_decorations SET health = 0 WHERE id IN (%s)'):format(table.concat(broken, ','))) then return end

    local updates = {}
    for i = 1, #broken do updates[broken[i]] = 0 end
    local occupants = GetPropertyOccupants(propertyId)
    lib.triggerClientEvent('qbx_properties:client:furnitureHealth', occupants, propertyId, updates)
    for i = 1, #occupants do
        exports.qbx_core:Notify(occupants[i], 'The overload burned out the wiring in the powered furniture.', 'error', 8000)
    end
end

lib.callback.register('qbx_properties:callback:repairFurniture', function(source, decorationId)
    local electricity = sharedConfig.electricity
    if not electricity or not electricity.burnout then return false end

    local player = exports.qbx_core:GetPlayer(source)
    decorationId = ToId(decorationId)
    local propertyId = GetPlayerEnteredProperty(source)
    if not player or not decorationId or not propertyId then return false end

    local job = player.PlayerData.job
    local requiredGrade = electricity.repairJobs and electricity.repairJobs[job.name]
    local allowed = exports.qbx_core:HasPermission(source, 'admin')
        or (requiredGrade ~= nil and job.grade.level >= requiredGrade)
    if not allowed then
        exports.qbx_core:Notify(source, 'You do not know your way around wiring.', 'error')
        return false
    end

    local property = MySQL.single.await('SELECT id, property_name, owner, building FROM properties WHERE id = ?', {propertyId})
    if not property or property.building then return false end

    local decoration = getDecoration(property, decorationId)
    local spec = decoration and GetFurnitureSpecs()[decoration.model]
    if not spec or (spec.power or 0) <= 0 then return false end
    if (decoration.health or 100) > 0 then return false end

    if not propertyPowered(propertyId) then
        exports.qbx_core:Notify(source, 'Repair the breaker before the appliances.', 'error')
        return false
    end

    MySQL.update.await('UPDATE properties_decorations SET health = 100 WHERE id = ?', {decorationId})
    lib.triggerClientEvent('qbx_properties:client:furnitureHealth', GetPropertyOccupants(propertyId), propertyId, { [decorationId] = 100 })
    exports.qbx_core:Notify(source, 'Rewired and running again.', 'success')

    LogAction(source, 'qbx_properties:server:repairFurniture', string.format('%s repaired furniture %d of %s', player.PlayerData.citizenid, decorationId, property.property_name))
    return true
end)
