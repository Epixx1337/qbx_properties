local config = require 'config.server'
local sharedConfig = require 'config.shared'

---@param value any
---@return table?
local function toPoint(value)
    if type(value) ~= 'table' then return end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    if not x or not y or not z then return end
    return { x = x, y = y, z = z, w = tonumber(value.w) or 0.0 }
end

---@param doors any
---@return table?
local function sanitiseDoors(doors)
    if doors == nil then return {} end
    if type(doors) ~= 'table' or #doors > 8 then return end

    local result = {}
    for i = 1, #doors do
        local entry = doors[i]
        if type(entry) ~= 'table' or type(entry.leaves) ~= 'table' then return end

        local leaves = {}
        for j = 1, #entry.leaves do
            local leaf = entry.leaves[j]
            local coords = toPoint(leaf and leaf.coords)
            local model = leaf and ToId(leaf.model)
            if not coords or not model then return end
            leaves[j] = { model = model, coords = coords, heading = tonumber(leaf.heading) or 0.0 }
        end

        if #leaves == 0 or #leaves > 2 then return end
        result[i] = { double = entry.double == true, leaves = leaves }
    end

    return result
end

---@param garden any
---@return table?, boolean ok
local function sanitiseGarden(garden)
    if garden == nil then return nil, true end
    if not sharedConfig.gardens.enabled then return nil, true end
    if type(garden) ~= 'table' then return nil, false end

    local raw = garden.points or garden
    if type(raw) ~= 'table' or #raw < 3 or #raw > sharedConfig.gardens.maxPoints then return nil, false end

    local points = {}
    for i = 1, #raw do
        points[i] = toPoint(raw[i])
        if not points[i] then return nil, false end
    end

    local height = tonumber(garden.height) or sharedConfig.gardens.height
    height = math.max(0.5, math.min(sharedConfig.gardens.height, height))

    return { points = points, height = height }, true
end

lib.callback.register('qbx_properties:callback:createProperty', function(source, data)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or type(data) ~= 'table' then return false end
    if not IsRealtor(player.PlayerData.job) then return false end

    if data.kind ~= 'shell' and data.kind ~= 'mlo' then return false end
    if type(data.name) ~= 'string' or #data.name < 4 or #data.name > 32 or data.name:find('[^%w%s]') then return false end

    local price = ToId(data.price)
    if not price or price < sharedConfig.market.minPrice or price > sharedConfig.market.maxPrice then return false end

    local rentInterval = data.rentInterval and ToId(data.rentInterval) or nil
    if rentInterval and not IsValidRentInterval(rentInterval) then return false end

    local entrance = toPoint(data.entrance)
    if not entrance then return false end

    local playerCoords = GetEntityCoords(GetPlayerPed(source))
    if #(playerCoords - vec3(entrance.x, entrance.y, entrance.z)) > 60.0 then return false end

    local doors = sanitiseDoors(data.doors)
    if not doors then return false end

    local garden, gardenOk = sanitiseGarden(data.garden)
    if not gardenOk then return false end

    local garage = data.garage and toPoint(data.garage) or nil
    if garage and #(vec3(entrance.x, entrance.y, entrance.z) - vec3(garage.x, garage.y, garage.z)) > 100.0 then return false end

    local interior = data.kind == 'shell' and tostring(data.interior) or tostring(data.interior or 'mlo')
    if data.kind == 'shell' and data.isShell == true and not tonumber(interior) then
        interior = tostring(joaat(interior))
    end
    if data.kind == 'shell' and not GetInteriorPoints(tonumber(interior) or interior) then return false end

    if data.kind == 'shell' then
        local defaults = GetShellDefaults(interior)
        if not defaults or not defaults.exit then return false end
    end

    local shellCoords = data.kind == 'shell' and toPoint(data.shell) or nil

    local interactData = {}
    local stashPoint = nil
    if data.kind == 'shell' then
        local defaults = GetShellDefaults(interior)
        if defaults then
            for kind, point in pairs(defaults) do
                if kind == 'stash' then
                    stashPoint = point
                else
                    interactData[#interactData + 1] = { type = kind, coords = point }
                end
            end
        end
    end

    local stashData = stashPoint and {
        {
            coords = stashPoint,
            slots = config.apartmentStash.slots,
            maxWeight = config.apartmentStash.maxWeight,
        }
    } or {}

    local result = MySQL.single.await('SELECT id FROM properties ORDER BY id DESC', {})
    local number = result?.id or 0
    local propertyName

    repeat
        number += 1
        propertyName = string.format('%s %s', data.name, number)
    until not MySQL.single.await('SELECT id FROM properties WHERE property_name = ?', {propertyName})

    local size = IsValidPropertySize(data.size) and data.size or sharedConfig.defaultPropertySize

    local propertyType = type(data.propertyType) == 'string' and sharedConfig.propertyTypes[data.propertyType] and data.propertyType or nil
    if propertyType == 'residential' then propertyType = nil end
    local description = type(data.description) == 'string' and data.description:sub(1, 500) or nil
    if description == '' then description = nil end
    local groupName = nil
    if propertyType and sharedConfig.propertyTypes[propertyType].groupAccess and type(data.group) == 'string' and #data.group > 0 and #data.group <= 50 then
        groupName = data.group:lower()
    end

    local propertyId = MySQL.insert.await([[
        INSERT INTO `properties`
            (`coords`, `property_name`, `price`, `interior`, `interact_options`, `stash_options`, `rent_interval`, `garage`, `shell_coords`, `garden_zone`, `door_data`, `size`, `created_by`, `type`, `group_name`, `description`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        json.encode({ x = entrance.x, y = entrance.y, z = entrance.z }),
        propertyName,
        price,
        interior,
        json.encode(interactData),
        json.encode(stashData),
        rentInterval,
        garage and json.encode(garage) or nil,
        shellCoords and json.encode(shellCoords) or nil,
        garden and json.encode(garden) or nil,
        #doors > 0 and json.encode(doors) or nil,
        size,
        player.PlayerData.citizenid,
        propertyType,
        groupName,
        description,
    })

    if not propertyId then return false end

    if #doors > 0 and SyncPropertyDoors then SyncPropertyDoors(propertyId, doors) end
    if shellCoords then
        TriggerClientEvent('qbx_properties:client:registerShell', -1, propertyId, tonumber(interior), vec4(shellCoords.x, shellCoords.y, shellCoords.z, shellCoords.w))
    end
    if garden then
        TriggerClientEvent('qbx_properties:client:registerGarden', -1, propertyId, garden)
    end

    if interior ~= 'mlo' then
        TriggerClientEvent('qbx_properties:client:addProperty', -1, vec3(entrance.x, entrance.y, entrance.z))
    end
    TriggerClientEvent('qbx_properties:client:invalidateUnitAccess', -1)

    if type(data.listing) == 'table' and data.listing.type then
        CreateListingInternal(source, player, propertyId, data.listing)
    end

    LogAction(source, 'qbx_properties:server:createProperty', string.format('%s created %s (%s)', player.PlayerData.citizenid, propertyName, data.kind))

    return true
end)

local POINT_KINDS <const> = { exit = true, clothing = true, logout = true, stash = true }

---@param property table needs coords, interior, interact_options, stash_options
---@return table
function BuildPropertyInteractions(property)
    local coords = json.decode(property.coords)
    local origin = vec3(coords.x, coords.y, coords.z)
    local isShell = tonumber(property.interior) ~= nil
    local interactions = {}

    local stashes = json.decode(property.stash_options) or {}
    for i = 1, #stashes do
        local point = isShell and CalculateOffsetCoords(origin, stashes[i].coords) or stashes[i].coords
        interactions[#interactions + 1] = { type = 'stash', coords = vec3(point.x, point.y, point.z) }
    end

    local interact = json.decode(property.interact_options) or {}
    for i = 1, #interact do
        local point = isShell and CalculateOffsetCoords(origin, interact[i].coords) or interact[i].coords
        interactions[#interactions + 1] = {
            type = interact[i].type,
            coords = interact[i].type == 'exit' and vec4(point.x, point.y, point.z, point.w or 0.0) or vec3(point.x, point.y, point.z),
        }
    end

    return interactions
end

---@param raw string?
---@return string[]
function PropertyImageUrls(raw)
    if not raw then return {} end

    local decoded = json.decode(raw)
    if type(decoded) ~= 'table' then return {} end

    local urls = {}
    for i = 1, #decoded do
        local entry = decoded[i]
        if type(entry) == 'table' then
            urls[i] = entry.url or (entry.file and ('nui://%s/screenshots/%s'):format(cache.resource, entry.file)) or ''
        else
            urls[i] = entry
        end
    end
    return urls
end

lib.callback.register('qbx_properties:callback:getPropertyDetails', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId or not IsRealtor(player.PlayerData.job) then return end

    local property = MySQL.single.await([[
        SELECT p.*, UNIX_TIMESTAMP(p.utilities_paid_until) AS paidUntil, pl.charinfo AS owner_charinfo, cr.charinfo AS creator_charinfo
        FROM properties p
        LEFT JOIN players pl ON pl.citizenid = p.owner
        LEFT JOIN players cr ON cr.citizenid = p.created_by
        WHERE p.id = ?
    ]], {propertyId})
    if not property then return end

    local function charName(raw, fallback)
        local info = raw and json.decode(raw)
        return info and string.format('%s %s', info.firstname, info.lastname) or fallback
    end

    local utilities = MySQL.single.await('SELECT power_used, humidity, powered FROM properties_utilities WHERE property_id = ?', {propertyId})
    local listing = MySQL.single.await([[
        SELECT listing_type, price, UNIX_TIMESTAMP(auction_end) AS auctionEnd FROM properties_listings
        WHERE property_id = ? AND status IN ('active','finalizing') LIMIT 1
    ]], {propertyId})

    local keyholders = {}
    local holderIds = GetPropertyKeyholders(property)
    for i = 1, #holderIds do
        local info = MySQL.scalar.await('SELECT charinfo FROM players WHERE citizenid = ?', {holderIds[i]})
        keyholders[#keyholders + 1] = { citizenid = holderIds[i], name = charName(info, holderIds[i]) }
    end

    return {
        id = property.id,
        name = property.property_name,
        owner = property.owner,
        ownerName = charName(property.owner_charinfo, property.owner),
        createdBy = charName(property.creator_charinfo, property.created_by),
        price = property.price,
        size = property.size or sharedConfig.defaultPropertySize,
        rentInterval = property.rent_interval,
        rentLastPaid = property.rent_last_paid,
        interior = property.interior,
        images = PropertyImageUrls(property.images),
        description = property.description,
        hasGarden = property.garden_zone ~= nil,
        hasGarage = property.garage ~= nil,
        hasDoorcam = property.doorcam ~= nil,
        wallColor = property.wall_color,
        utilities = {
            paidUntil = property.paidUntil,
            overdue = property.paidUntil ~= nil and property.paidUntil < os.time(),
            power = utilities and utilities.power_used or 0,
            humidity = utilities and utilities.humidity or 0,
            powered = utilities == nil or ToBool(utilities.powered),
            limit = GetPowerLimit(property),
            cost = GetUtilityCost(property),
        },
        access = GetPropertyAccessList(property),
        keyholders = keyholders,
        listing = listing and {
            type = listing.listing_type,
            price = listing.price,
            auctionEnd = listing.auctionEnd,
        } or nil,
    }
end)

lib.callback.register('qbx_properties:callback:updateProperty', function(source, propertyId, data)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId or type(data) ~= 'table' or not IsRealtor(player.PlayerData.job) then return false end

    local property = MySQL.single.await('SELECT id, property_name, owner, garage FROM properties WHERE id = ?', {propertyId})
    if not property then return false end

    local price = ToId(data.price)
    if not price or price < sharedConfig.market.minPrice or price > sharedConfig.market.maxPrice then return false end

    local size = IsValidPropertySize(data.size) and data.size or sharedConfig.defaultPropertySize
    local rentInterval = data.rentInterval and ToId(data.rentInterval) or nil
    if rentInterval and not IsValidRentInterval(rentInterval) then return false end

    local description = type(data.description) == 'string' and data.description:sub(1, 500) or nil

    MySQL.update.await('UPDATE properties SET price = ?, size = ?, rent_interval = ?, description = ? WHERE id = ?', {price, size, rentInterval, description, propertyId})

    LogAction(source, 'qbx_properties:server:updateProperty', string.format('%s updated %s (price %d, size %s)', player.PlayerData.citizenid, property.property_name, price, size))

    return true
end)

lib.callback.register('qbx_properties:callback:updatePropertyZones', function(source, propertyId, data)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId or type(data) ~= 'table' or not IsRealtor(player.PlayerData.job) then return false end

    local property = MySQL.single.await('SELECT id, property_name, owner, coords FROM properties WHERE id = ? AND building IS NULL', {propertyId})
    if not property then return false end

    if data.garage ~= nil then
        local garage = toPoint(data.garage)
        if not garage then return false end

        local entrance = json.decode(property.coords)
        if #(vec3(entrance.x, entrance.y, entrance.z) - vec3(garage.x, garage.y, garage.z)) > 100.0 then return false end

        MySQL.update.await('UPDATE properties SET garage = ? WHERE id = ?', {json.encode(garage), propertyId})
        if property.owner and RegisterPropertyGarage then
            RegisterPropertyGarage(propertyId, property.property_name, garage)
        end
    end

    if data.garden ~= nil then
        local garden, ok = sanitiseGarden(data.garden)
        if not ok or not garden then return false end

        MySQL.update.await('UPDATE properties SET garden_zone = ? WHERE id = ?', {json.encode(garden), propertyId})
        TriggerClientEvent('qbx_properties:client:registerGarden', -1, propertyId, garden)
    end

    LogAction(source, 'qbx_properties:server:updatePropertyZones', string.format('%s updated zones on %s', player.PlayerData.citizenid, property.property_name))

    return true
end)

lib.callback.register('qbx_properties:callback:getPropertyPoints', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId or not IsRealtor(player.PlayerData.job) then return end

    local property = MySQL.single.await('SELECT id, property_name, interior, coords, interact_options, stash_options FROM properties WHERE id = ? AND building IS NULL', {propertyId})
    if not property then return end

    local isShell = tonumber(property.interior) ~= nil
    local points = {}

    local interact = json.decode(property.interact_options) or {}
    for i = 1, #interact do
        if POINT_KINDS[interact[i].type] then points[interact[i].type] = interact[i].coords end
    end

    local stashes = json.decode(property.stash_options) or {}
    if stashes[1] then points.stash = stashes[1].coords end

    return {
        label = property.property_name,
        isShell = isShell,
        origin = json.decode(property.coords),
        points = points,
    }
end)

lib.callback.register('qbx_properties:callback:savePropertyPoints', function(source, propertyId, points)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId or type(points) ~= 'table' or not IsRealtor(player.PlayerData.job) then return false end

    local property = MySQL.single.await('SELECT id, property_name, interact_options, stash_options FROM properties WHERE id = ? AND building IS NULL', {propertyId})
    if not property then return false end

    local interactData = {}
    local stashPoint = nil

    for kind in pairs(POINT_KINDS) do
        local point = toPoint(points[kind])
        if point then
            if kind == 'stash' then
                stashPoint = point
            else
                interactData[#interactData + 1] = { type = kind, coords = point }
            end
        end
    end

    if #interactData == 0 and not stashPoint then return false end

    local stashes = json.decode(property.stash_options) or {}
    if stashPoint then
        stashes[1] = stashes[1] or { slots = config.apartmentStash.slots, maxWeight = config.apartmentStash.maxWeight }
        stashes[1].coords = stashPoint
    end

    MySQL.update.await('UPDATE properties SET interact_options = ?, stash_options = ? WHERE id = ?',
        {json.encode(interactData), json.encode(stashes), propertyId})

    local fresh = MySQL.single.await('SELECT id, coords, interior, interact_options, stash_options FROM properties WHERE id = ?', {propertyId})
    if fresh then
        local interactions = BuildPropertyInteractions(fresh)
        local occupants = GetPropertyOccupants(propertyId)
        for i = 1, #occupants do
            TriggerClientEvent('qbx_properties:client:refreshInteractions', occupants[i], interactions)
        end
    end

    LogAction(source, 'qbx_properties:server:savePropertyPoints', string.format('%s updated interaction points on %s', player.PlayerData.citizenid, property.property_name))

    return true
end)

local function urlEncode(value)
    return value:gsub('([^%w%-%_%.%~])', function(c) return string.format('%%%02X', string.byte(c)) end)
end

local imageProviders = {
    qbox = {
        url = 'https://api.qbox.re/v1/file',
        field = 'file',
        responsePath = 'data.url',
        storagePath = 'data.path',
        deleteUrl = 'https://api.qbox.re/v1/file/%s',
    },
    fivemanage = {
        url = 'https://api.fivemanage.com/api/v3/file',
        field = 'file',
        responsePath = 'data.url',
        storagePath = 'data.id',
        deleteUrl = 'https://api.fivemanage.com/api/v3/file/%s',
    },
    fivemerr = {
        url = 'https://api.fivemerr.com/v1/media/images',
        field = 'file',
        responsePath = 'url',
    },
}

local function imageProvider()
    local cfg = config.imageUpload
    if not cfg or not cfg.apiKey or cfg.apiKey == '' then return end

    local provider = cfg.provider == 'custom' and cfg.custom or imageProviders[cfg.provider]
    if not provider or not provider.url or provider.url == '' then return end

    return provider
end

local function responseField(result, path)
    local value = result
    for key in path:gmatch('[^%.]+') do
        if type(value) ~= 'table' then return end
        value = value[key]
    end
    return type(value) == 'string' and value or nil
end

---@param source integer whose screen is captured
---@param filename string without extension, [%w_-] only
---@return table? entry image entry for the images column, nil on failure
---@return string? err
local function capturePropertyPhoto(source, filename)
    if GetResourceState('screencapture') ~= 'started' then
        return nil, 'The screencapture resource is not running.'
    end

    local provider = imageProvider()

    if provider then
        local result

        exports.screencapture:remoteUpload(source, provider.url, {
            encoding = 'webp',
            headers = { Authorization = config.imageUpload.apiKey },
            formField = provider.field or 'file',
            filename = filename,
        }, function(responseData)
            result = responseData or false
        end, 'blob')

        local ok = pcall(function()
            lib.waitFor(function()
                if result ~= nil then return true end
            end, 'upload timed out', 15000)
        end)

        local url = ok and type(result) == 'table' and responseField(result, provider.responsePath or 'url') or nil
        if not url then return nil, 'The upload failed.' end

        return { url = url, path = provider.storagePath and responseField(result, provider.storagePath) or nil }
    end

    local captured
    local started = pcall(function()
        exports.screencapture:serverCapture(source, { encoding = 'webp', quality = 0.8 }, function(data)
            captured = data or false
        end, 'base64')
    end)
    if not started then return nil, 'screencapture is missing the serverCapture export.' end

    local waited = pcall(function()
        lib.waitFor(function()
            if captured ~= nil then return true end
        end, 'capture timed out', 15000)
    end)
    if not waited or type(captured) ~= 'string' then return nil, 'The screenshot failed.' end
    if #captured > 2000000 then return nil, 'The screenshot is too large.' end

    local written = RequestShotOp and RequestShotOp('qbx_properties:internal:shotWrite', filename, captured)
    if not written or not written.ok then
        return nil, written and written.error or 'Could not save the screenshot.'
    end

    return { file = written.file }
end

---@param entry table decoded image entry
local function deleteLocalImage(entry)
    if type(entry) == 'table' and entry.file and RequestShotOp then
        RequestShotOp('qbx_properties:internal:shotDelete', entry.file)
    end
end

local tourSources = {}
local tourHiddenDoors = nil

local function spritesConfigured()
    return sharedConfig.housePhotos and sharedConfig.housePhotos.hideDoorSprites
        and GetResourceState('ox_doorlock') == 'started'
end

local function hideTourDoorSprites()
    if not spritesConfigured() or tourHiddenDoors then return end
    tourHiddenDoors = {}

    CreateThread(function()
        local rows = MySQL.query.await('SELECT id, data FROM ox_doorlock WHERE name LIKE ?', {GetDoorPrefix():gsub('[%%_\\]', '\\%0') .. '%'}) or {}

        for i = 1, #rows do
            local ok, data = pcall(json.decode, rows[i].data)
            if ok and type(data) == 'table' and not data.hideUi then
                tourHiddenDoors[#tourHiddenDoors + 1] = rows[i].id
                pcall(function() exports.ox_doorlock:editDoor(rows[i].id, { hideUi = true }) end)
                if i % 100 == 0 then Wait(0) end
            end
        end
    end)
end

local function restoreTourDoorSprites()
    if not tourHiddenDoors then return end
    local hidden = tourHiddenDoors
    tourHiddenDoors = nil

    CreateThread(function()
        for i = 1, #hidden do
            pcall(function() exports.ox_doorlock:editDoor(hidden[i], { hideUi = false }) end)
            if i % 100 == 0 then Wait(0) end
        end
    end)
end

local function endPhotoTour(source)
    if not tourSources[source] then return end
    tourSources[source] = nil
    if not next(tourSources) then restoreTourDoorSprites() end
end

RegisterNetEvent('qbx_properties:server:photoTourEnd', function()
    endPhotoTour(source --[[@as number]])
end)

AddEventHandler('playerDropped', function()
    endPhotoTour(source --[[@as number]])
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource or not tourHiddenDoors then return end

    for i = 1, #tourHiddenDoors do
        pcall(function() exports.ox_doorlock:editDoor(tourHiddenDoors[i], { hideUi = false }) end)
    end
    tourHiddenDoors = nil
end)

lib.callback.register('qbx_properties:callback:getPhotoTour', function(source, mode)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or not IsRealtor(player.PlayerData.job) then return end

    local rows = MySQL.query.await([[
        SELECT id, property_name, coords, door_data, images FROM properties
        WHERE building IS NULL ORDER BY property_name
    ]]) or {}

    local tour = {}
    for i = 1, #rows do
        local hasImages = rows[i].images ~= nil and rows[i].images ~= '[]'
        if mode == 'all' or not hasImages then
            local coords = json.decode(rows[i].coords)
            local inside = { x = coords.x, y = coords.y, z = coords.z }

            local door
            if rows[i].door_data then
                local ok, doors = pcall(json.decode, rows[i].door_data)
                local leaf = ok and type(doors) == 'table' and doors[1] and doors[1].leaves and doors[1].leaves[1]
                if leaf and leaf.coords then door = { x = leaf.coords.x, y = leaf.coords.y, z = leaf.coords.z } end
            end

            tour[#tour + 1] = { id = rows[i].id, name = rows[i].property_name, door = door or inside, inside = inside }
        end
    end

    if #tour > 0 then
        tourSources[source] = true
        hideTourDoorSprites()
    end

    return tour
end)

lib.callback.register('qbx_properties:callback:savePropertyPhoto', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId or not IsRealtor(player.PlayerData.job) then return false end

    local property = MySQL.single.await('SELECT id, property_name, images FROM properties WHERE id = ? AND building IS NULL', {propertyId})
    if not property then return false end

    local images = property.images and json.decode(property.images) or {}
    if #images >= (config.imageUpload.maxImages or 5) then return false, 'This property already has the maximum number of photos.' end

    local entry, err = capturePropertyPhoto(source, string.format('house_%d_%d', propertyId, os.time()))
    if not entry then return false, err end

    table.insert(images, 1, entry)
    MySQL.update.await('UPDATE properties SET images = ? WHERE id = ?', {json.encode(images), propertyId})

    LogAction(source, 'qbx_properties:server:savePropertyPhoto', string.format('%s photographed %s (%s)', player.PlayerData.citizenid, property.property_name, entry.url and 'cdn' or 'local'))

    return true, entry.url and 'cdn' or 'local'
end)

lib.addCommand('housephotos', {
    help = 'Tour every house missing a photo and frame its main picture',
    params = {
        { name = 'mode', help = "'all' also revisits houses that already have photos", type = 'string', optional = true },
    },
}, function(source, args)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or not IsRealtor(player.PlayerData.job) then
        exports.qbx_core:Notify(source, 'Only realtors can run the photo tour.', 'error')
        return
    end

    TriggerClientEvent('qbx_properties:client:housePhotoTour', source, args.mode)
end)

lib.callback.register('qbx_properties:callback:addPropertyImage', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId or not IsRealtor(player.PlayerData.job) then return false end

    local property = MySQL.single.await('SELECT id, property_name, images FROM properties WHERE id = ?', {propertyId})
    if not property then return false end

    local images = property.images and json.decode(property.images) or {}
    if #images >= (config.imageUpload.maxImages or 5) then return false, 'This property already has the maximum number of photos.' end

    local entry, err = capturePropertyPhoto(source, string.format('property_%d_%d', propertyId, os.time()))
    if not entry then return false, err end

    images[#images + 1] = entry
    MySQL.update.await('UPDATE properties SET images = ? WHERE id = ?', {json.encode(images), propertyId})

    LogAction(source, 'qbx_properties:server:addPropertyImage', string.format('%s added a photo to %s', player.PlayerData.citizenid, property.property_name))

    return true
end)

lib.callback.register('qbx_properties:callback:removePropertyImage', function(source, propertyId, index)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    index = ToId(index)
    if not player or not propertyId or not index or not IsRealtor(player.PlayerData.job) then return false end

    local property = MySQL.single.await('SELECT id, images FROM properties WHERE id = ?', {propertyId})
    if not property or not property.images then return false end

    local images = json.decode(property.images)
    if not images[index] then return false end

    local removed = images[index]
    local provider = imageProvider()
    if type(removed) == 'table' and removed.path and provider and provider.deleteUrl then
        PerformHttpRequest(provider.deleteUrl:format(urlEncode(removed.path)), function(status)
            if status ~= 200 then lib.print.warn(('CDN delete returned %s for %s'):format(status, removed.path)) end
        end, 'DELETE', '', { Authorization = config.imageUpload.apiKey })
    end
    deleteLocalImage(removed)

    table.remove(images, index)
    MySQL.update.await('UPDATE properties SET images = ? WHERE id = ?', {#images > 0 and json.encode(images) or nil, propertyId})

    return true
end)

---@param images table decoded images column
function DeletePropertyImagesRemote(images)
    local provider = imageProvider()

    for i = 1, #images do
        local image = images[i]
        if type(image) == 'table' and image.path and provider and provider.deleteUrl then
            PerformHttpRequest(provider.deleteUrl:format(urlEncode(image.path)), function(status)
                if status ~= 200 then lib.print.warn(('CDN delete returned %s for %s'):format(status, image.path)) end
            end, 'DELETE', '', { Authorization = config.imageUpload.apiKey })
        end
        deleteLocalImage(image)
    end
end

lib.callback.register('qbx_properties:callback:setDoorcam', function(source, propertyId, point)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId or not IsRealtor(player.PlayerData.job) then return false end
    if type(point) ~= 'table' or type(point.x) ~= 'number' or type(point.y) ~= 'number' or type(point.z) ~= 'number' then return false end

    local property = MySQL.single.await('SELECT id, property_name, coords FROM properties WHERE id = ? AND building IS NULL', {propertyId})
    if not property then return false end

    local coords = json.decode(property.coords)
    if #(vec3(coords.x, coords.y, coords.z) - vec3(point.x, point.y, point.z)) > 100.0 then return false end

    local payload = {
        x = point.x, y = point.y, z = point.z,
        w = (tonumber(point.w) or 0.0) % 360.0,
        p = math.max(-89.0, math.min(89.0, tonumber(point.p) or 0.0)),
    }
    MySQL.update.await('UPDATE properties SET doorcam = ? WHERE id = ?', {json.encode(payload), propertyId})

    LogAction(source, 'qbx_properties:server:setDoorcam', string.format('%s placed the doorcam of %s', player.PlayerData.citizenid, property.property_name))
    return true
end)

lib.callback.register('qbx_properties:callback:clearDoorcam', function(source, propertyId)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId or not IsRealtor(player.PlayerData.job) then return false end

    local property = MySQL.single.await('SELECT id, property_name FROM properties WHERE id = ? AND building IS NULL', {propertyId})
    if not property then return false end

    MySQL.update.await('UPDATE properties SET doorcam = NULL WHERE id = ?', {propertyId})

    LogAction(source, 'qbx_properties:server:clearDoorcam', string.format('%s cleared the doorcam of %s', player.PlayerData.citizenid, property.property_name))
    return true
end)

lib.callback.register('qbx_properties:callback:recaptureInterior', function(source, propertyId, point)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId or not IsRealtor(player.PlayerData.job) then return false end

    local coords = toPoint(point)
    if not coords then return false end

    local property = MySQL.single.await('SELECT id, property_name, interior FROM properties WHERE id = ? AND building IS NULL', {propertyId})
    if not property then return false end

    if #(GetEntityCoords(GetPlayerPed(source)) - vec3(coords.x, coords.y, coords.z)) > 10.0 then return false end

    if property.interior == 'mlo' then
        MySQL.update.await("UPDATE properties SET coords = ?, stash_options = '[]' WHERE id = ?",
            {json.encode({ x = coords.x, y = coords.y, z = coords.z }), propertyId})
    else
        MySQL.update.await('UPDATE properties SET coords = ? WHERE id = ?',
            {json.encode({ x = coords.x, y = coords.y, z = coords.z }), propertyId})
    end

    TriggerClientEvent('qbx_properties:client:invalidateUnitAccess', -1)
    TriggerClientEvent('qbx_properties:client:refreshBlips', -1)

    LogAction(source, 'qbx_properties:server:recaptureInterior', string.format('%s re-captured the interior point of %s', player.PlayerData.citizenid, property.property_name))

    return true
end)

lib.callback.register('qbx_properties:callback:addPropertyDoor', function(source, propertyId, door)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId or not IsRealtor(player.PlayerData.job) then return false end

    local sanitised = sanitiseDoors({ door })
    if not sanitised or #sanitised ~= 1 then return false end

    local property = MySQL.single.await('SELECT id, property_name, door_data FROM properties WHERE id = ? AND building IS NULL', {propertyId})
    if not property then return false end

    local doors = property.door_data and json.decode(property.door_data) or {}
    doors[#doors + 1] = sanitised[1]

    MySQL.update.await('UPDATE properties SET door_data = ? WHERE id = ?', {json.encode(doors), propertyId})

    if SyncPropertyDoors then SyncPropertyDoors(propertyId, doors) end

    LogAction(source, 'qbx_properties:server:addPropertyDoor', string.format('%s added a door to %s', player.PlayerData.citizenid, property.property_name))

    return true
end)
