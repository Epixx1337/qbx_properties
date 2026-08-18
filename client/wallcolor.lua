local sharedConfig = require 'config.shared'
local wallColors = sharedConfig.wallColors

if not wallColors.enabled then return end

local DEFAULT_COLOR <const> = 0

local applied = {}
local currentUnit = nil

local function probeLength()
    pcall(function() SetInteriorProbeLength(wallColors.probeLength) end)
end

---@param building string?
---@param room integer?
---@return string entitySet
local function entitySetFor(building, room)
    local pattern = building and Buildings[building] and Buildings[building].wallEntitySet
    if pattern and room then return pattern:format(room) end

    return wallColors.entitySet
end

---@param interiorId integer
---@param colorIndex integer?
---@param entitySet string?
function ApplyWallColor(interiorId, colorIndex, entitySet)
    if not interiorId or interiorId == 0 or not IsValidInterior(interiorId) then return end

    entitySet = entitySet or (currentUnit and entitySetFor(currentUnit.building, currentUnit.room)) or wallColors.entitySet
    colorIndex = colorIndex or DEFAULT_COLOR

    probeLength()
    ActivateInteriorEntitySet(interiorId, entitySet)
    SetInteriorEntitySetColor(interiorId, entitySet, colorIndex)
    RefreshInterior(interiorId)

    applied[interiorId] = applied[interiorId] or {}
    applied[interiorId][entitySet] = colorIndex
end

---@param propertyId integer?
---@param building string?
---@param room integer?
function LoadWallColor(propertyId, building, room)
    currentUnit = building and room and { building = building, room = room } or nil

    local colorIndex = propertyId and lib.callback.await('qbx_properties:callback:getWallColor', false, propertyId) or nil
    local interiorId = GetInteriorFromEntity(cache.ped)
    local entitySet = entitySetFor(building, room)

    if colorIndex then
        ApplyWallColor(interiorId, colorIndex, entitySet)
        return
    end

    local previous = applied[interiorId] and applied[interiorId][entitySet]

    if previous and previous ~= DEFAULT_COLOR then
        ApplyWallColor(interiorId, DEFAULT_COLOR, entitySet)
    else
        probeLength()
    end
end

function ClearUnitWallColors()
    currentUnit = nil
end

RegisterNetEvent('qbx_properties:client:wallColor', function(propertyId, colorIndex)
    if CurrentPropertyId ~= propertyId then return end
    ApplyWallColor(GetInteriorFromEntity(cache.ped), colorIndex)
end)

RegisterNUICallback('tablet:setWallColor', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not CurrentPropertyId then return end

    local colorIndex = tonumber(data.color)
    if not colorIndex then return end

    if lib.callback.await('qbx_properties:callback:setWallColor', false, CurrentPropertyId, colorIndex) then
        ApplyWallColor(GetInteriorFromEntity(cache.ped), colorIndex)
    else
        lib.notify({ type = 'error', description = 'You cannot redecorate this property.' })
    end
end)

CreateThread(function()
    while true do
        Wait(2000)

        if applied[GetInteriorFromEntity(cache.ped)] then
            probeLength()
        end
    end
end)
