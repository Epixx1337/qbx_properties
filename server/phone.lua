local PROPERTY_COLUMNS = 'id, owner, keyholders, building, floor, room, property_name, coords, price, rent_interval, interior, door_data, type, group_name, tenant'

---@param propertyId any
---@return table? row
local function getRow(propertyId)
    propertyId = ToId(propertyId)
    if not propertyId then return end
    return MySQL.single.await(('SELECT %s FROM properties WHERE id = ?'):format(PROPERTY_COLUMNS), {propertyId})
end

---@param row table
---@return boolean
local function doorlockReady(row)
    return (row.building ~= nil or row.door_data ~= nil) and GetResourceState('ox_doorlock') == 'started'
end

---@param row table
---@return string[]
local function propertyDoorNames(row)
    local names = {}
    if row.building then
        local building = Buildings[row.building]
        local doors = building and building.roomLayout and building.roomLayout.doors
        for i = 1, doors and #doors or 0 do
            names[#names + 1] = ('qbx_properties:%d:%d'):format(row.id, i)
        end
    elseif row.door_data then
        local ok, doors = pcall(json.decode, row.door_data)
        if ok and type(doors) == 'table' then
            for i = 1, #doors do
                names[#names + 1] = ('qbx_properties:%d:d%d'):format(row.id, i)
            end
        end
    end
    return names
end

---@param row table
---@return boolean? locked, nil when the property has no real doors
local function getLocked(row)
    if not doorlockReady(row) then return nil end
    local names = propertyDoorNames(row)
    for i = 1, #names do
        local ok, door = pcall(function() return exports.ox_doorlock:getDoorFromName(names[i]) end)
        if ok and door then return door.state == 1 end
    end
    return nil
end

---@param row table
---@param locked boolean
---@return boolean changed
local function setLocked(row, locked)
    if not doorlockReady(row) then return false end
    local state = locked and 1 or 0
    local changed = false
    local names = propertyDoorNames(row)
    for i = 1, #names do
        local ok, door = pcall(function() return exports.ox_doorlock:getDoorFromName(names[i]) end)
        if ok and door then
            pcall(function() exports.ox_doorlock:setDoorState(door.id, state) end)
            changed = true
        end
    end
    return changed
end

---@param citizenid string
---@return string?
local function characterName(citizenid)
    local player = exports.qbx_core:GetPlayerByCitizenId(citizenid) or exports.qbx_core:GetOfflinePlayer(citizenid)
    local charinfo = player and player.PlayerData.charinfo
    return charinfo and ('%s %s'):format(charinfo.firstname, charinfo.lastname) or nil
end

---@param row table
---@return { citizenid: string, name: string }[]
local function keyholderList(row)
    local holders = GetPropertyKeyholders(row)
    local out = {}
    for i = 1, #holders do
        out[#out + 1] = { citizenid = holders[i], name = characterName(holders[i]) or holders[i] }
    end
    return out
end

---@param row table
---@param targetCid string
---@return boolean
local function addKeyholder(row, targetCid)
    local keyholders = GetPropertyKeyholders(row)
    if lib.table.contains(keyholders, targetCid) then return false end

    local keyLimit = GetKeyholderLimit and GetKeyholderLimit(row.id)
    if keyLimit and #keyholders >= keyLimit then return false end

    if row.building then
        MySQL.insert.await('INSERT IGNORE INTO properties_apartment_keyholders (tenant, keyholder) VALUES (?, ?)', {row.owner, targetCid})
    else
        keyholders[#keyholders + 1] = targetCid
        MySQL.update.await('UPDATE properties SET keyholders = ? WHERE id = ?', {json.encode(keyholders), row.id})
    end

    RefreshCustomGarages()
    return true
end

---@param row table
---@param targetCid string
---@return boolean
local function removeKeyholder(row, targetCid)
    local keyholders = GetPropertyKeyholders(row)
    if not lib.table.contains(keyholders, targetCid) then return false end

    if row.building then
        MySQL.update.await('DELETE FROM properties_apartment_keyholders WHERE tenant = ? AND keyholder = ?', {row.owner, targetCid})
    else
        for i = 1, #keyholders do
            if keyholders[i] == targetCid then
                table.remove(keyholders, i)
                break
            end
        end
        MySQL.update.await('UPDATE properties SET keyholders = ? WHERE id = ?', {json.encode(keyholders), row.id})
    end

    RefreshCustomGarages()
    return true
end

---@param citizenid string
---@return table[]
local function playerProperties(citizenid)
    local rows = MySQL.query.await(('SELECT %s FROM properties WHERE owner = ?'):format(PROPERTY_COLUMNS), {citizenid}) or {}
    local out = {}

    for i = 1, #rows do
        local row = rows[i]
        local building = row.building and Buildings[row.building]
        local coords

        if building and building.entrance then
            coords = vec3(building.entrance.x, building.entrance.y, building.entrance.z)
        elseif row.coords then
            local ok, decoded = pcall(json.decode, row.coords)
            if ok and decoded then coords = vec3(decoded.x, decoded.y, decoded.z) end
        end

        out[#out + 1] = {
            id = row.id,
            label = row.property_name,
            type = row.building and 'apartment' or 'house',
            building = row.building,
            floor = row.floor,
            room = row.room,
            coords = coords,
            price = row.price,
            rented = type(row.rent_interval) == 'number',
            locked = getLocked(row),
        }
    end

    return out
end

exports('GetPlayerProperties', function(citizenid)
    if type(citizenid) ~= 'string' then return {} end
    return playerProperties(citizenid)
end)

exports('HasAccess', function(citizenid, propertyId, permission)
    if type(citizenid) ~= 'string' then return false end
    local row = getRow(propertyId)
    return row ~= nil and HasPropertyAccess(citizenid, row, permission or 'door')
end)

exports('GetKeyholders', function(propertyId, actorCid)
    local row = getRow(propertyId)
    if not row or type(actorCid) ~= 'string' or row.owner ~= actorCid then return end
    return keyholderList(row)
end)

exports('AddKeyholder', function(propertyId, actorCid, targetCid)
    local row = getRow(propertyId)
    if not row or type(actorCid) ~= 'string' or type(targetCid) ~= 'string' then return false end
    if row.owner ~= actorCid or targetCid == actorCid then return false end
    return addKeyholder(row, targetCid)
end)

exports('RemoveKeyholder', function(propertyId, actorCid, targetCid)
    local row = getRow(propertyId)
    if not row or type(actorCid) ~= 'string' or type(targetCid) ~= 'string' then return false end
    if row.owner ~= actorCid then return false end
    return removeKeyholder(row, targetCid)
end)

exports('GetLocked', function(propertyId)
    local row = getRow(propertyId)
    return row and getLocked(row) or nil
end)

exports('SetLocked', function(propertyId, actorCid, locked)
    local row = getRow(propertyId)
    if not row or type(actorCid) ~= 'string' then return false end
    if not HasPropertyAccess(actorCid, row, 'door') then return false end
    return setLocked(row, locked == true)
end)

lib.callback.register('qbx_properties:callback:phoneHomes', function(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return {} end
    return playerProperties(player.PlayerData.citizenid)
end)

lib.callback.register('qbx_properties:callback:phoneKeyholders', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    local row = getRow(propertyId)
    if not player or not row or row.owner ~= player.PlayerData.citizenid then return end
    return keyholderList(row)
end)

lib.callback.register('qbx_properties:callback:phoneAddKeyholder', function(source, propertyId, targetServerId)
    local player = exports.qbx_core:GetPlayer(source)
    local target = type(targetServerId) == 'number' and exports.qbx_core:GetPlayer(targetServerId)
    local row = getRow(propertyId)
    if not player or not target or not row then return false end
    if row.owner ~= player.PlayerData.citizenid then return false end

    local targetCid = target.PlayerData.citizenid
    if targetCid == row.owner then return false end
    if #(GetEntityCoords(GetPlayerPed(source)) - GetEntityCoords(GetPlayerPed(targetServerId))) > 10.0 then return false end

    if not addKeyholder(row, targetCid) then return false end
    exports.qbx_core:Notify(target.PlayerData.source, locale('notify.added_as_keyholder'))
    lib.logger(source, 'qbx_properties:phone:addKeyholder', locale('logs.added_keyholder', targetCid, row.id))
    return true
end)

lib.callback.register('qbx_properties:callback:phoneRemoveKeyholder', function(source, propertyId, citizenid)
    local player = exports.qbx_core:GetPlayer(source)
    local row = getRow(propertyId)
    if not player or not row or type(citizenid) ~= 'string' then return false end
    if row.owner ~= player.PlayerData.citizenid then return false end

    if not removeKeyholder(row, citizenid) then return false end
    lib.logger(source, 'qbx_properties:phone:removeKeyholder', locale('logs.removed_keyholder', citizenid, row.id))
    return true
end)

lib.callback.register('qbx_properties:callback:phoneSetLocked', function(source, propertyId, locked)
    local player = exports.qbx_core:GetPlayer(source)
    local row = getRow(propertyId)
    if not player or not row then return nil end
    if not HasPropertyAccess(player.PlayerData.citizenid, row, 'door') then return nil end
    if not setLocked(row, locked == true) then return nil end
    return locked == true
end)
