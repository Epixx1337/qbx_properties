exports('getCurrentPropertyId', function()
    return CurrentPropertyId
end)

exports('getCurrentGardenId', function()
    return CurrentGardenId
end)

local function validPlacement(data)
    if type(data) ~= 'table' or type(data.item) ~= 'string' or type(data.model) ~= 'string' or not tonumber(data.slot) then return false end
    if IsDecorating then return false end

    if not CurrentPropertyId and not CurrentGardenId then
        lib.notify({ type = 'error', description = 'You can only place this inside a property or garden.' })
        return false
    end

    return IsModelValid(joaat(data.model))
end

exports('placeItem', function(data)
    if not validPlacement(data) then return false end

    local coords = GetEntityCoords(cache.ped) + GetEntityForwardVector(cache.ped) * 1.5
    local placed = PlaceModelWithGizmo(data.model, coords, ('Position the %s'):format(data.label or data.item))
    if not placed then return false end

    TriggerServerEvent('qbx_properties:server:placeItemDecoration', data.item, tonumber(data.slot), data.model, vec3(placed.x, placed.y, placed.z), placed.w)
    return true
end)

exports('placeItemAt', function(data)
    if not validPlacement(data) then return false end
    if type(data.coords) ~= 'vector3' then return false end

    TriggerServerEvent('qbx_properties:server:placeItemDecoration', data.item, tonumber(data.slot), data.model, data.coords, tonumber(data.heading) or 0.0)
    return true
end)
