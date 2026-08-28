local sharedConfig = require 'config.shared'
local layouts = sharedConfig.layouts

if not layouts or not layouts.enabled then return end

local CODE_CHARS <const> = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

local function generateCode()
    for _ = 1, 20 do
        local code = {}
        for i = 1, 8 do
            local index = math.random(1, #CODE_CHARS)
            code[i] = CODE_CHARS:sub(index, index)
        end
        code = table.concat(code)
        if not MySQL.scalar.await('SELECT 1 FROM properties_layouts WHERE share_code = ?', {code}) then return code end
    end
end

---@param source integer
---@return table? player, table? property
local function getEditableProperty(source)
    local player = exports.qbx_core:GetPlayer(source)
    local propertyId = GetPlayerEnteredProperty(source)
    if not player or not propertyId then return end

    local property = MySQL.single.await('SELECT id, property_name, owner, keyholders, building, type, group_name, tenant, size, stash_options FROM properties WHERE id = ?', {propertyId})
    if not property or property.building then return end
    if not HasPropertyAccess(player.PlayerData.citizenid, property, 'furniture') then return end

    return player, property
end

---@param items table
---@return integer cost, integer stashes
local function layoutCost(items)
    local specs = GetFurnitureSpecs()
    local cost, stashes = 0, 0
    local freeUsed = {}

    for i = 1, #items do
        local spec = specs[items[i].model]
        if spec then
            if spec.type == 'stash' then stashes += 1 end
            local price = spec.price or 0
            if price > 0 then
                if spec.firstFree and spec.type and not freeUsed[spec.type] then
                    freeUsed[spec.type] = true
                else
                    cost += price
                end
            end
        end
    end

    return cost, stashes
end

---@param source integer
---@param propertyId integer
local function listLayouts(source, propertyId)
    local rows = MySQL.query.await('SELECT id, name, creator, creator_name, data, share_code, UNIX_TIMESTAMP(created_at) AS createdAt FROM properties_layouts WHERE property_id = ? ORDER BY id DESC', {propertyId}) or {}
    local result = {}

    for i = 1, #rows do
        local ok, items = pcall(json.decode, rows[i].data)
        items = ok and items or {}
        local cost = layoutCost(items)

        result[i] = {
            id = rows[i].id,
            name = rows[i].name,
            creator = rows[i].creator,
            creatorName = rows[i].creator_name or rows[i].creator,
            items = #items,
            cost = cost,
            shareCode = rows[i].share_code,
            createdAt = rows[i].createdAt,
        }
    end

    return { layouts = result, max = layouts.maxPerProperty }
end

lib.callback.register('qbx_properties:callback:getLayouts', function(source)
    local player, property = getEditableProperty(source)
    if not player or not property then return end
    return listLayouts(source, property.id)
end)

lib.callback.register('qbx_properties:callback:saveLayout', function(source, name)
    local player, property = getEditableProperty(source)
    if not player or not property then return false, 'You cannot manage layouts here.' end

    if type(name) ~= 'string' then return false, 'Give the layout a name.' end
    name = name:gsub('^%s+', ''):gsub('%s+$', '')
    if #name < 2 or #name > 40 then return false, 'Names are 2 to 40 characters.' end

    local count = MySQL.scalar.await('SELECT COUNT(*) FROM properties_layouts WHERE property_id = ?', {property.id}) or 0
    if count >= layouts.maxPerProperty then
        return false, string.format('This property holds %d layouts, delete one first.', layouts.maxPerProperty)
    end

    local rows = MySQL.query.await('SELECT model, coords, rotation, tint FROM properties_decorations WHERE property_id = ? AND item IS NULL AND IFNULL(garden, 0) = 0 ORDER BY id', {property.id}) or {}
    if #rows == 0 then return false, 'There is no furniture to save.' end

    local items = {}
    for i = 1, #rows do
        items[i] = {
            model = rows[i].model,
            coords = json.decode(rows[i].coords),
            rotation = json.decode(rows[i].rotation),
            tint = rows[i].tint,
        }
    end

    local code = generateCode()
    if not code then return false, 'Try again in a moment.' end

    local charinfo = player.PlayerData.charinfo
    MySQL.insert.await('INSERT INTO properties_layouts (property_id, name, creator, creator_name, data, share_code) VALUES (?, ?, ?, ?, ?, ?)', {
        property.id, name, player.PlayerData.citizenid,
        string.format('%s %s', charinfo.firstname, charinfo.lastname),
        json.encode(items), code,
    })

    LogAction(source, 'qbx_properties:server:saveLayout', string.format('%s saved layout %s (%d pieces) for %s', player.PlayerData.citizenid, name, #items, property.property_name))
    return true
end)

lib.callback.register('qbx_properties:callback:deleteLayout', function(source, layoutId)
    local player, property = getEditableProperty(source)
    layoutId = ToId(layoutId)
    if not player or not property or not layoutId then return false end

    local layout = MySQL.single.await('SELECT id, name, creator FROM properties_layouts WHERE id = ? AND property_id = ?', {layoutId, property.id})
    if not layout then return false end

    local citizenId = player.PlayerData.citizenid
    if layout.creator ~= citizenId and property.owner ~= citizenId then
        exports.qbx_core:Notify(source, 'Only the creator or the owner can delete this layout.', 'error')
        return false
    end

    MySQL.update.await('DELETE FROM properties_layouts WHERE id = ?', {layoutId})
    LogAction(source, 'qbx_properties:server:deleteLayout', string.format('%s deleted layout %s of %s', citizenId, layout.name, property.property_name))
    return true
end)

lib.callback.register('qbx_properties:callback:previewLayoutCode', function(source, code)
    local player, property = getEditableProperty(source)
    if not player or not property then return end
    if type(code) ~= 'string' then return end

    local layout = MySQL.single.await('SELECT name, creator_name, data FROM properties_layouts WHERE share_code = ?', {code:upper():gsub('%s', '')})
    if not layout then return end

    local ok, items = pcall(json.decode, layout.data)
    items = ok and items or {}
    local cost = layoutCost(items)

    return { name = layout.name, creatorName = layout.creator_name, items = #items, cost = cost }
end)

---@param source integer
---@param player table
---@param property table
---@param layout table row with name and data
---@return boolean, string?
local function applyLayout(source, player, property, layout)
    if GetRaid and GetRaid(property.id) then
        return false, 'You cannot rearrange furniture right now.'
    end

    local ok, items = pcall(json.decode, layout.data)
    if not ok or type(items) ~= 'table' or #items == 0 then return false, 'This layout is corrupted.' end

    local specs = GetFurnitureSpecs()
    for i = 1, #items do
        if type(items[i]) ~= 'table' or not specs[items[i].model] then
            return false, 'This layout uses furniture that no longer exists.'
        end
    end

    local cost, stashes = layoutCost(items)

    local stashLimit = GetStashLimit and GetStashLimit(property)
    if stashLimit and stashes > stashLimit then
        return false, string.format('This layout needs %d stashes but the property holds %d.', stashes, stashLimit)
    end

    local current = MySQL.query.await('SELECT id, model, stash_slot FROM properties_decorations WHERE property_id = ? AND item IS NULL AND IFNULL(garden, 0) = 0', {property.id}) or {}
    for i = 1, #current do
        if DecorationHasContents and DecorationHasContents(property, current[i]) then
            local spec = specs[current[i].model]
            return false, string.format('Empty out the %s first.', spec and spec.label or 'storage')
        end
    end

    if cost > 0 then
        local reason = string.format('Layout %s for %s', layout.name, property.property_name)
        if not player.Functions.RemoveMoney('bank', cost, reason) and not player.Functions.RemoveMoney('cash', cost, reason) then
            return false, string.format('You need $%d for this layout.', cost)
        end
    end

    MySQL.update.await('DELETE FROM properties_decorations WHERE property_id = ? AND item IS NULL AND IFNULL(garden, 0) = 0', {property.id})

    local stashSlot = 0
    for i = 1, #items do
        local entry = items[i]
        local spec = specs[entry.model]
        local slot = nil
        if spec and spec.type == 'stash' then
            stashSlot += 1
            slot = stashSlot
        end

        local tint = ToId(entry.tint)
        if tint and (tint < 1 or tint > 31 or not spec.tint) then tint = nil end

        MySQL.insert.await('INSERT INTO properties_decorations (property_id, model, coords, rotation, stash_slot, tint) VALUES (?, ?, ?, ?, ?, ?)', {
            property.id, entry.model, json.encode(entry.coords), json.encode(entry.rotation), slot, tint,
        })
    end

    lib.triggerClientEvent('qbx_properties:client:reloadDecorations', GetPropertyOccupants(property.id), BuildDecorationPayload(property))

    if SyncFurnitureDoors then SyncFurnitureDoors(property) end
    if RefreshUtilities then RefreshUtilities(property.id) end

    LogAction(source, 'qbx_properties:server:applyLayout', string.format('%s applied layout %s (%d pieces, $%d) on %s', player.PlayerData.citizenid, layout.name, #items, cost, property.property_name))
    return true
end

lib.callback.register('qbx_properties:callback:applyLayout', function(source, layoutId)
    local player, property = getEditableProperty(source)
    layoutId = ToId(layoutId)
    if not player or not property or not layoutId then return false, 'You cannot manage layouts here.' end

    local layout = MySQL.single.await('SELECT id, name, data FROM properties_layouts WHERE id = ? AND property_id = ?', {layoutId, property.id})
    if not layout then return false, 'Layout not found.' end

    return applyLayout(source, player, property, layout)
end)

lib.callback.register('qbx_properties:callback:importLayout', function(source, code)
    local player, property = getEditableProperty(source)
    if not player or not property then return false, 'You cannot manage layouts here.' end
    if type(code) ~= 'string' then return false, 'Enter a share code.' end

    local layout = MySQL.single.await('SELECT id, name, data FROM properties_layouts WHERE share_code = ?', {code:upper():gsub('%s', '')})
    if not layout then return false, 'No layout matches that code.' end

    return applyLayout(source, player, property, layout)
end)
