local sharedConfig = require 'config.shared'

if not sharedConfig.gardens.enabled then return end

lib.callback.register('qbx_properties:callback:getGardens', function()
    local rows = MySQL.query.await('SELECT id, garden_zone FROM properties WHERE garden_zone IS NOT NULL')
    local result = {}

    for i = 1, #rows do
        local zone = json.decode(rows[i].garden_zone)
        result[i] = {
            id = rows[i].id,
            points = zone.points or zone,
            height = zone.height or sharedConfig.gardens.height,
        }
    end

    return result
end)

lib.callback.register('qbx_properties:callback:getGardenDecorations', function(_, propertyId)
    propertyId = ToId(propertyId)
    if not propertyId then return end

    local property = MySQL.single.await('SELECT id, owner, building, garden_zone FROM properties WHERE id = ?', {propertyId})
    if not property or not property.garden_zone then return end

    local rows = MySQL.query.await('SELECT id, model, coords, rotation, tint, item, item_metadata FROM properties_decorations WHERE property_id = ? AND garden = 1', {propertyId})
    local result = {}

    for i = 1, #rows do
        local coords = json.decode(rows[i].coords)
        local rotation = json.decode(rows[i].rotation)
        result[i] = {
            id = rows[i].id,
            model = rows[i].model,
            coords = vec3(coords.x, coords.y, coords.z),
            rotation = vec3(rotation.x, rotation.y, rotation.z),
            tint = rows[i].tint,
            item = rows[i].item,
            metadata = rows[i].item_metadata and json.decode(rows[i].item_metadata) or nil,
        }
    end

    return result
end)

---@param propertyId integer
---@return boolean
function CanPlaceGardenFurniture(propertyId)
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM properties_decorations WHERE property_id = ? AND garden = 1', {propertyId}) or 0
    return count < sharedConfig.gardens.furnitureLimit
end

local inGarden = {}

RegisterNetEvent('qbx_properties:server:enterGarden', function(propertyId)
    local playerSource = source --[[@as number]]
    propertyId = ToId(propertyId)
    if not propertyId then return end

    local property = MySQL.single.await('SELECT coords FROM properties WHERE id = ? AND garden_zone IS NOT NULL', {propertyId})
    if not property then return end

    local coords = json.decode(property.coords)
    if #(GetEntityCoords(GetPlayerPed(playerSource)) - vec3(coords.x, coords.y, coords.z)) > sharedConfig.gardens.streamDistance + 50.0 then return end

    inGarden[playerSource] = propertyId
end)

RegisterNetEvent('qbx_properties:server:leaveGarden', function()
    inGarden[source] = nil
end)

---@param playerSource integer
---@return integer?
function GetPlayerGarden(playerSource)
    return inGarden[playerSource]
end

---@param playerSource integer
---@return integer?, integer[]?
function GetGardenOccupants(playerSource)
    local gardenId = inGarden[playerSource]
    if not gardenId then return end

    local occupants = {}
    for src, id in pairs(inGarden) do
        if id == gardenId then occupants[#occupants + 1] = src end
    end

    return gardenId, occupants
end

AddEventHandler('playerDropped', function()
    inGarden[source] = nil
end)

lib.callback.register('qbx_properties:callback:canDecorateGarden', function(source, propertyId)
    propertyId = ToId(propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    if not propertyId or not player then return false end

    local property = MySQL.single.await('SELECT id, owner, keyholders, building FROM properties WHERE id = ? AND garden_zone IS NOT NULL', {propertyId})
    return property ~= nil and CanEditFurniture(player, property)
end)

RegisterNetEvent('qbx_properties:server:addGardenDecoration', function(hash, coords, rotation, objectId, tint)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    local propertyId = inGarden[playerSource]
    if not player or not propertyId then return end
    if (type(hash) ~= 'string' and type(hash) ~= 'number') or type(coords) ~= 'vector3' or type(rotation) ~= 'vector3' then return end

    local property = MySQL.single.await('SELECT id, owner, keyholders, building FROM properties WHERE id = ? AND garden_zone IS NOT NULL', {propertyId})
    if not property or not CanEditFurniture(player, property) then return end

    if not ToId(objectId) and (GetFurnitureSpecs()[hash] or {}).item then return end

    local paid = false
    if not ToId(objectId) then
        local existing
        if IsFirstFreeFurniture(hash) then
            local models, placeholders = FirstFreeModels(hash)
            local params = { propertyId }
            for i = 1, #models do params[#params + 1] = models[i] end
            existing = MySQL.scalar.await(('SELECT COUNT(*) FROM properties_decorations WHERE property_id = ? AND model IN (%s) AND garden = 1'):format(placeholders), params)
        end

        local ok, usedCredit = ConsumeFurnitureCredit(playerSource, hash, existing)
        if not ok then
            exports.qbx_core:Notify(playerSource, 'This piece has to be paid for through the cart.', 'error')
            return
        end
        paid = usedCredit
    end
    if not paid and #(GetEntityCoords(GetPlayerPed(playerSource)) - coords) > 15.0 then return end

    tint = ToId(tint)
    if tint and (tint < 1 or tint > 31 or not (GetFurnitureSpecs()[hash] or {}).tint) then tint = nil end

    objectId = ToId(objectId)
    if objectId then
        local updated = MySQL.update.await('UPDATE properties_decorations SET coords = ?, rotation = ?, tint = ? WHERE id = ? AND property_id = ? AND garden = 1',
            {json.encode(coords), json.encode(rotation), tint, objectId, propertyId})
        if updated ~= 1 then return end

        local movedSpec = GetFurnitureSpecs()[hash]
        local moveHooks = movedSpec and movedSpec.item and movedSpec.serverHooks
        if moveHooks and moveHooks.onMove then
            local metaRow = MySQL.scalar.await('SELECT item_metadata FROM properties_decorations WHERE id = ?', {objectId})
            local resource = exports[moveHooks.resource]
            pcall(resource[moveHooks.onMove], resource, { metadata = metaRow and json.decode(metaRow) or nil, coords = coords })
        end
    else
        if not CanPlaceGardenFurniture(propertyId) then
            exports.qbx_core:Notify(playerSource, 'The garden furniture limit is reached.', 'error')
            return
        end

        objectId = MySQL.insert.await('INSERT INTO properties_decorations (property_id, model, coords, rotation, tint, garden) VALUES (?, ?, ?, ?, ?, 1)',
            {propertyId, hash, json.encode(coords), json.encode(rotation), tint})
        if not objectId then return end
    end

    TriggerClientEvent('qbx_properties:client:gardenDecoration', -1, propertyId, {
        id = objectId,
        model = hash,
        coords = coords,
        rotation = rotation,
        tint = tint,
    })

    LogAction(playerSource, 'qbx_properties:server:addGardenDecoration', locale('logs.add_decoration', player.PlayerData.citizenid, hash, propertyId))
end)

RegisterNetEvent('qbx_properties:server:removeGardenDecoration', function(objectId)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    local propertyId = inGarden[playerSource]
    objectId = ToId(objectId)
    if not player or not propertyId or not objectId then return end

    local property = MySQL.single.await('SELECT id, owner, keyholders, building FROM properties WHERE id = ? AND garden_zone IS NOT NULL', {propertyId})
    if not property or not CanEditFurniture(player, property) then return end

    local deleted = MySQL.update.await('DELETE FROM properties_decorations WHERE id = ? AND property_id = ? AND garden = 1 AND item IS NULL', {objectId, propertyId})
    if deleted ~= 1 then return end

    TriggerClientEvent('qbx_properties:client:gardenDecoration', -1, propertyId, { id = objectId, removed = true })

    LogAction(playerSource, 'qbx_properties:server:removeGardenDecoration', locale('logs.remove_decoration', player.PlayerData.citizenid, objectId, propertyId))
end)
