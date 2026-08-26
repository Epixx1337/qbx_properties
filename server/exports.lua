local SAFE_COLUMNS = 'id, property_name, owner, price, rent_interval, building, floor, room, interior, size, type, group_name, coords'

exports('GetProperty', function(propertyId)
    propertyId = ToId(propertyId)
    if not propertyId then return end
    local row = MySQL.single.await(('SELECT %s FROM properties WHERE id = ?'):format(SAFE_COLUMNS), {propertyId})
    if row and row.coords then
        local ok, decoded = pcall(json.decode, row.coords)
        row.coords = ok and decoded and vec3(decoded.x, decoded.y, decoded.z) or nil
    end
    return row
end)

exports('GetProperties', function(search)
    local rows
    if type(search) == 'string' and #search > 0 then
        rows = MySQL.query.await(('SELECT %s FROM properties WHERE property_name LIKE ? LIMIT 100'):format(SAFE_COLUMNS), {'%' .. search .. '%'})
    else
        rows = MySQL.query.await(('SELECT %s FROM properties LIMIT 500'):format(SAFE_COLUMNS))
    end
    return rows or {}
end)

exports('GetFurniture', function(propertyId)
    propertyId = ToId(propertyId)
    if not propertyId then return {} end
    local property = MySQL.single.await('SELECT id, owner, building, floor, room FROM properties WHERE id = ?', {propertyId})
    if not property then return {} end
    return GetPropertyDecorations(property) or {}
end)

exports('RemoveDecoration', function(decorationId)
    decorationId = ToId(decorationId)
    if not decorationId then return false end

    local row = MySQL.single.await('SELECT id, property_id, model FROM properties_decorations WHERE id = ?', {decorationId})
    if row then
        MySQL.update.await('DELETE FROM properties_decorations WHERE id = ?', {decorationId})
        TriggerClientEvent('qbx_properties:client:removeDecoration', -1, decorationId)
        if GetFurnitureTypes()[row.model] == 'door' and SyncFurnitureDoors then
            local property = MySQL.single.await('SELECT id, building, floor, room FROM properties WHERE id = ?', {row.property_id})
            if property then SyncFurnitureDoors(property) end
        end
        if RefreshUtilities then RefreshUtilities(row.property_id) end
        return true
    end

    row = MySQL.single.await('SELECT id, citizenid, model FROM properties_apartment_decorations WHERE id = ?', {decorationId})
    if not row then return false end

    MySQL.update.await('DELETE FROM properties_apartment_decorations WHERE id = ?', {decorationId})
    TriggerClientEvent('qbx_properties:client:removeDecoration', -1, decorationId)
    return true
end)

exports('GetPlayerProperty', function(source)
    if type(source) ~= 'number' then return end
    return GetPlayerEnteredProperty and GetPlayerEnteredProperty(source) or nil
end)

exports('GetPlayersInside', function(propertyId)
    propertyId = ToId(propertyId)
    if not propertyId then return {} end
    return GetPropertyOccupants and GetPropertyOccupants(propertyId) or {}
end)
