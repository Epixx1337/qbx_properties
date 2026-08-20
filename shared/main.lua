local sharedConfig = require 'config.shared'
local crimeConfig = require 'config.crime'
local shellDefaults = require 'config.shell_defaults'
local buildings = require 'config.buildings'

Apartments = buildings
Buildings = {}

for key, entry in pairs(buildings) do
    if entry.type ~= 'interior' then Buildings[key] = entry end
end

---@param interior string|number
---@return table?
function GetInteriorPoints(interior)
    local entry = shellDefaults[interior]
    if entry then return entry end

    if type(interior) == 'number' then
        for key, points in pairs(shellDefaults) do
            if joaat(key) == interior then return points end
        end
    end
end

---@return table
function GetInteriorList()
    return shellDefaults
end

---@param buildingKey string
---@param floor integer
---@return number?
function GetFloorZ(buildingKey, floor)
    local building = buildings[buildingKey]
    if not building or floor < 1 or floor > building.floors.count then return end
    return building.floors.baseZ + building.floors.step * (floor - 1)
end

---@param buildingKey string
---@param floor integer
---@param room integer
---@return vector4?
function GetRoomCoords(buildingKey, floor, room)
    local building = buildings[buildingKey]
    if not building then return end
    local anchor = building.rooms[room]
    local z = GetFloorZ(buildingKey, floor)
    if not anchor or not z then return end
    return vec4(anchor.x, anchor.y, z + anchor.z, anchor.w)
end

---@param anchor vector4
---@param coords vector3
---@return vector3
function UnrotateOffset(anchor, coords)
    local rad = math.rad(-anchor.w)
    local cos, sin = math.cos(rad), math.sin(rad)
    local dx, dy = coords.x - anchor.x, coords.y - anchor.y
    return vec3(dx * cos - dy * sin, dx * sin + dy * cos, coords.z - anchor.z)
end

---@param anchor vector4
---@param offset vector3
---@return vector3
function RotateOffset(anchor, offset)
    local rad = math.rad(anchor.w)
    local cos, sin = math.cos(rad), math.sin(rad)
    return vec3(anchor.x + offset.x * cos - offset.y * sin, anchor.y + offset.x * sin + offset.y * cos, anchor.z + offset.z)
end

---@param buildingKey string
---@param floor integer
---@param room integer
---@return string?
function GetUnitName(buildingKey, floor, room)
    local building = buildings[buildingKey]
    if not building then return end
    return string.format('%s %d%02d', building.label, floor, room + (building.roomNumberOffset or 0))
end


---@param propertyCoords vector3 | vector4
---@param offset vector3
---@return vector4
function CalculateOffsetCoords(propertyCoords, offset)
    return vec4(propertyCoords.x + offset.x, propertyCoords.y + offset.y, (propertyCoords.z - sharedConfig.shellUndergroundOffset) + offset.z, propertyCoords.w or 0.0)
end

---@return table[]
function GetApartmentOptions()
    local options = {}
    local keys = {}

    for key in pairs(Apartments) do keys[#keys + 1] = key end
    table.sort(keys)

    for i = 1, #keys do
        local entry = Apartments[keys[i]]

        if entry.type == 'interior' then
            options[#options + 1] = {
                interior = keys[i],
                label = entry.label,
                description = entry.description,
                enter = entry.enter,
            }
        elseif sharedConfig.dynamicApartments then
            options[#options + 1] = {
                building = keys[i],
                label = entry.label,
                description = entry.description or string.format('An apartment in %s.', entry.label),
                enter = entry.entrance,
            }
        end
    end

    return options
end

local furnitureTypes
local furnitureSpecs

local function buildFurnitureIndex()
    if furnitureSpecs then return end

    furnitureTypes = {}
    furnitureSpecs = {}
    local furniture = require 'config.client'.furniture

    for _, category in pairs(furniture) do
        for i = 1, #category do
            local entry = category[i]
            if entry.type then furnitureTypes[entry.object] = entry.type end
            furnitureSpecs[entry.object] = {
                label = entry.label,
                type = entry.type,
                tint = entry.tint == true,
                snapGroup = entry.snapGroup,
                power = entry.power or 0,
                humidity = entry.humidity or 0,
                light = entry.light or false,
                slots = entry.slots,
                maxWeight = entry.maxWeight,
                price = sharedConfig.furnitureShop ~= false and tonumber(entry.price) or nil,
                firstFree = entry.firstFree == true,
            }
        end
    end
end

---@param entry table
---@return boolean
function RegisterFurniture(entry)
    if type(entry) ~= 'table' or type(entry.object) ~= 'string' then return false end
    buildFurnitureIndex()

    if entry.type then furnitureTypes[entry.object] = entry.type end
    furnitureSpecs[entry.object] = {
        label = entry.label or entry.object,
        type = entry.type,
        tint = entry.tint == true,
        snapGroup = entry.snapGroup,
        power = entry.power or 0,
        humidity = entry.humidity or 0,
        light = entry.light or false,
        slots = entry.slots,
        maxWeight = entry.maxWeight,
        price = sharedConfig.furnitureShop ~= false and tonumber(entry.price) or nil,
        firstFree = entry.firstFree == true,
        item = entry.item,
        durability = tonumber(entry.durability),
        durabilityKey = entry.durabilityKey,
        durabilityMax = tonumber(entry.durabilityMax),
        serverHooks = type(entry.serverHooks) == 'table' and entry.serverHooks or nil,
    }
    return true
end

exports('registerFurniture', RegisterFurniture)

---@return table<string, string>
function GetFurnitureTypes()
    buildFurnitureIndex()
    return furnitureTypes
end

---@return table<string, table>
function GetFurnitureSpecs()
    buildFurnitureIndex()
    return furnitureSpecs
end

---@param decorations table
---@return integer power, integer humidity
function CalculateUtilityLoad(decorations)
    local specs = GetFurnitureSpecs()
    local power, humidity = 0, 0

    for i = 1, #decorations do
        local spec = specs[decorations[i].model]
        if spec then
            power += spec.power
            humidity += spec.humidity
        end
    end

    return power, humidity
end

---@param size string?
---@return table
function GetPropertySize(size)
    return sharedConfig.propertySizes[size]
        or sharedConfig.propertySizes[sharedConfig.defaultPropertySize]
end

---@param size any
---@return boolean
function IsValidPropertySize(size)
    return type(size) == 'string' and sharedConfig.propertySizes[size] ~= nil
end

---@param property table
---@return integer
function GetPowerLimit(property)
    if property.power_limit then return property.power_limit end
    if property.building then return sharedConfig.utilities.apartment.power end
    return GetPropertySize(property.size).power
end

---@param property table
---@return integer
function GetUtilityCost(property)
    if property.building then return sharedConfig.utilities.apartment.cost end
    return GetPropertySize(property.size).cost
end

---@param amount integer
---@param kind string 'sale' | 'rent'
---@return integer commission, integer remainder
function SplitCommission(amount, kind)
    local rate = sharedConfig.commission[kind] or 0
    local commission = math.floor(amount * rate)
    return commission, amount - commission
end

---@param property table
---@param index integer? zero based; nil or 0 is the primary stash
---@return string
function GetStashId(property, index)
    local base = (property.building and property.owner)
        and string.format('qbx_properties_apartment_%s', property.owner)
        or string.format('qbx_properties_%s', property.property_name)

    if not index or index == 0 then return base end
    return string.format('%s_%d', base, index)
end

---@param value any
---@return integer?
function ToId(value)
    local number = tonumber(value)
    return number and math.tointeger(number) or nil
end

---@param value any
---@return boolean
function ToBool(value)
    return value == true or value == 1
end

---@param job PlayerJob?
---@return boolean
function IsRealtor(job)
    if not job then return false end
    local minGrade = sharedConfig.realtorJobs[job.name]
    if not minGrade then return false end
    if sharedConfig.realtorRequiresDuty and not job.onduty then return false end
    return job.grade.level >= minGrade
end

---@param job PlayerJob?
---@return boolean
function IsPolice(job)
    local police = crimeConfig.police
    if not job or not police.enabled then return false end
    local minGrade = police.jobs[job.name]
    if not minGrade then return false end
    if police.requiresDuty and not job.onduty then return false end
    return job.grade.level >= minGrade
end