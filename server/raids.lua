local config = require 'config.server'
local police = require('config.crime').police

if not police.enabled then return end

local raids = {}

---@param propertyId integer
---@return table?
function GetRaid(propertyId)
    return raids[propertyId]
end

---@param citizenId string
---@return boolean
function IsRaidTarget(citizenId)
    for _, raid in pairs(raids) do
        if raid.target == citizenId then return true end
    end
    return false
end

---@param propertyId integer
---@return boolean
function IsBreached(propertyId)
    local raid = raids[propertyId]
    return raid ~= nil and raid.breached
end

---@param target string?
local function releaseAssignedBuilding(target)
    if not target then return end

    local player = exports.qbx_core:GetPlayerByCitizenId(target)
    if player then
        player.Functions.SetMetaData('apartmentBuilding', nil)
        return
    end

    local offline = exports.qbx_core:GetOfflinePlayer(target)
    if offline then
        offline.PlayerData.metadata.apartmentBuilding = nil
        exports.qbx_core:SaveOffline(offline.PlayerData)
    end
end

local function clearStaleRaids()
    local rows = MySQL.query.await('SELECT property_id, target, lockdown, previous_owner, assigned_room, assigned_building FROM properties_raids')
    if #rows == 0 then return end

    for i = 1, #rows do
        local row = rows[i]

        if ToBool(row.lockdown) and row.previous_owner then
            MySQL.update.await('UPDATE properties SET owner = ? WHERE id = ?', {row.previous_owner, row.property_id})
        elseif ToBool(row.assigned_room) then
            MySQL.update.await('UPDATE properties SET owner = NULL WHERE id = ? AND building IS NOT NULL', {row.property_id})
        end

        if ToBool(row.assigned_building) then releaseAssignedBuilding(row.target) end
    end

    MySQL.update.await('DELETE FROM properties_raids')
    lib.print.info(('cleared %d stale raid(s)'):format(#rows))
end

---@param propertyId integer
local function pushAccessFlags(propertyId)
    local property = MySQL.single.await('SELECT id, owner, keyholders, building FROM properties WHERE id = ?', {propertyId})
    if not property then return end

    local occupants = GetPropertyOccupants(propertyId)
    for i = 1, #occupants do
        local occupant = exports.qbx_core:GetPlayer(occupants[i])
        if occupant then
            TriggerClientEvent('qbx_properties:client:accessFlags', occupants[i], GetAccessFlags(occupant.PlayerData.citizenid, property))
        end
    end
end

---@param propertyId integer
local function pushRaidState(propertyId)
    local raid = raids[propertyId]
    TriggerClientEvent('qbx_properties:client:raidState', -1, propertyId, raid and {
        breached = raid.breached,
        lockdown = raid.lockdown,
    } or nil)
end

---@param player table
---@param item string?
---@param equipped boolean?
---@return boolean
local function hasItem(player, item, equipped)
    if not item then return true end

    if equipped then
        local weapon = exports.ox_inventory:GetCurrentWeapon(player.PlayerData.source)
        return weapon ~= nil and weapon.name == item
    end

    return (exports.ox_inventory:GetItemCount(player.PlayerData.source, item) or 0) > 0
end

---@param source integer
---@return table? player
local function getOfficer(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or not IsPolice(player.PlayerData.job) then return end
    return player
end

lib.callback.register('qbx_properties:callback:canRaid', function(source, buildingKey)
    local player = getOfficer(source)
    if not player then return false end

    for _, raid in pairs(raids) do
        if raid.building == buildingKey then return true, true end
    end

    return hasItem(player, police.warrantItem), false
end)

lib.callback.register('qbx_properties:callback:startRaid', function(source, buildingKey, citizenId)
    local player = getOfficer(source)
    if not player or type(citizenId) ~= 'string' or not Buildings[buildingKey] then return end
    if not hasItem(player, police.warrantItem) then return false, 'You need a warrant.' end

    citizenId = citizenId:upper()
    if not MySQL.scalar.await('SELECT citizenid FROM players WHERE citizenid = ?', {citizenId}) then
        return false, 'No citizen with that ID.'
    end

    if IsRaidTarget(citizenId) then return false, 'That citizen is already being raided.' end

    local property = MySQL.single.await(
        'SELECT id, property_name, floor, room FROM properties WHERE building = ? AND owner = ?',
        {buildingKey, citizenId}
    )

    local assignedRoom, assignedBuilding = false, false

    if not property then
        local target = exports.qbx_core:GetPlayerByCitizenId(citizenId)
        local offline = target or exports.qbx_core:GetOfflinePlayer(citizenId)
        if not offline then return false, 'No citizen with that ID.' end

        local propertyId = AssignRoom(offline, buildingKey)
        if not propertyId then return false, 'No free unit in this building.' end
        assignedRoom = true

        if not offline.PlayerData.metadata.apartmentBuilding then
            assignedBuilding = true
            if target then
                target.Functions.SetMetaData('apartmentBuilding', buildingKey)
            else
                offline.PlayerData.metadata.apartmentBuilding = buildingKey
                exports.qbx_core:SaveOffline(offline.PlayerData)
            end
        end

        property = MySQL.single.await('SELECT id, property_name, floor, room FROM properties WHERE id = ?', {propertyId})
        if not property then return false, 'Could not reserve a unit.' end
    end

    raids[property.id] = {
        propertyId = property.id,
        officer = player.PlayerData.citizenid,
        target = citizenId,
        building = buildingKey,
        breached = false,
        lockdown = false,
        assignedRoom = assignedRoom,
        assignedBuilding = assignedBuilding,
    }

    MySQL.insert.await([[
        INSERT INTO properties_raids (property_id, officer, target, assigned_room, assigned_building) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE officer = VALUES(officer), target = VALUES(target), breached = 0, lockdown = 0,
            assigned_room = VALUES(assigned_room), assigned_building = VALUES(assigned_building)
    ]], {property.id, player.PlayerData.citizenid, citizenId, assignedRoom and 1 or 0, assignedBuilding and 1 or 0})

    lib.logger(source, 'qbx_properties:server:startRaid', string.format('%s opened a raid on %s (%s)', player.PlayerData.citizenid, property.property_name, citizenId))

    pushRaidState(property.id)
    return true, property.property_name, property.floor, property.room
end)

lib.callback.register('qbx_properties:callback:getActiveRaids', function(source, buildingKey)
    if not getOfficer(source) then return {} end

    local result = {}
    for propertyId, raid in pairs(raids) do
        if not buildingKey or raid.building == buildingKey then
            local property = MySQL.single.await('SELECT property_name FROM properties WHERE id = ?', {propertyId})
            result[#result + 1] = {
                propertyId = propertyId,
                label = property and property.property_name or tostring(propertyId),
                target = raid.target,
                breached = raid.breached,
                lockdown = raid.lockdown,
            }
        end
    end
    return result
end)

---@param propertyId integer
---@param citizenId string who forced the door
---@return boolean
function MarkBreached(propertyId, citizenId)
    local raid = raids[propertyId]

    if not raid then
        raid = { propertyId = propertyId, officer = citizenId, breached = false, lockdown = false }
        raids[propertyId] = raid

        MySQL.insert.await([[
            INSERT INTO properties_raids (property_id, officer) VALUES (?, ?)
            ON DUPLICATE KEY UPDATE officer = VALUES(officer)
        ]], {propertyId, citizenId})
    end

    if raid.breached then return true end

    raid.breached = true
    MySQL.update.await('UPDATE properties_raids SET breached = 1 WHERE property_id = ?', {propertyId})

    if SetPropertyDoorsBreached then SetPropertyDoorsBreached(propertyId, true) end
    pushAccessFlags(propertyId)
    pushRaidState(propertyId)

    return true
end

---@param propertyId integer
---@param source integer?
function EndRaid(propertyId, source)
    local raid = raids[propertyId]
    if not raid then return false end

    raids[propertyId] = nil
    MySQL.update.await('DELETE FROM properties_raids WHERE property_id = ?', {propertyId})

    if raid.lockdown and raid.previousOwner then
        MySQL.update.await('UPDATE properties SET owner = ? WHERE id = ?', {raid.previousOwner, propertyId})
    elseif raid.assignedRoom then
        MySQL.update.await('UPDATE properties SET owner = NULL WHERE id = ? AND building IS NOT NULL', {propertyId})
    end

    if raid.assignedBuilding then releaseAssignedBuilding(raid.target) end

    if SetPropertyDoorsBreached then SetPropertyDoorsBreached(propertyId, false) end
    pushAccessFlags(propertyId)
    pushRaidState(propertyId)

    lib.logger(source or 0, 'qbx_properties:server:endRaid', string.format('Raid on property %d ended', propertyId))

    return true
end

lib.callback.register('qbx_properties:callback:endRaid', function(source, propertyId)
    local player = getOfficer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return false end

    return EndRaid(propertyId, source)
end)

lib.callback.register('qbx_properties:callback:breachDoor', function(source, propertyId)
    local player = getOfficer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return false end
    if not hasItem(player, police.breachItem, police.breachRequiresEquipped) then return false end

    local property = MySQL.single.await('SELECT id, property_name, building FROM properties WHERE id = ?', {propertyId})
    if not property then return false end

    if not raids[propertyId] and property.building then return false end
    if not MarkBreached(propertyId, player.PlayerData.citizenid) then return false end

    lib.logger(source, 'qbx_properties:server:breachDoor', string.format('%s breached %s', player.PlayerData.citizenid, property.property_name))

    return true
end)

lib.callback.register('qbx_properties:callback:lockdownProperty', function(source, propertyId)
    local player = getOfficer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return false end

    local raid = raids[propertyId]
    if not raid or not raid.breached then return false end
    if raid.lockdown then return false end

    local property = MySQL.single.await('SELECT id, owner, property_name FROM properties WHERE id = ?', {propertyId})
    if not property or not property.owner then return false end

    raid.lockdown = true
    raid.previousOwner = property.owner

    MySQL.update.await('UPDATE properties_raids SET lockdown = 1, previous_owner = ? WHERE property_id = ?', {property.owner, propertyId})
    MySQL.update.await('UPDATE properties SET owner = NULL WHERE id = ?', {propertyId})

    if SetPropertyDoorsBreached then SetPropertyDoorsBreached(propertyId, false) end
    pushAccessFlags(propertyId)
    pushRaidState(propertyId)

    lib.logger(source, 'qbx_properties:server:lockdownProperty', string.format('%s locked down %s (owner %s)', player.PlayerData.citizenid, property.property_name, property.owner))

    return true
end)

lib.callback.register('qbx_properties:callback:returnProperty', function(source, propertyId, citizenId)
    local player = exports.qbx_core:GetPlayer(source)
    propertyId = ToId(propertyId)
    if not player or not propertyId or type(citizenId) ~= 'string' then return false, 'Invalid request.' end
    if not IsPolice(player.PlayerData.job) and not IsRealtor(player.PlayerData.job) then return false, 'Not authorised.' end

    local raid = raids[propertyId]
    if not raid then return false, 'This property is not under a raid.' end
    if not raid.lockdown or not raid.previousOwner then return false, 'This property is not under lockdown.' end
    if raid.previousOwner ~= citizenId:upper() then return false, 'That is not the registered owner.' end

    EndRaid(propertyId, source)

    return true, 'Property returned to its owner.'
end)

CreateThread(function()
    AwaitMigration()
    clearStaleRaids()
end)

lib.callback.register('qbx_properties:callback:getRaidZones', function(source)
    if not getOfficer(source) then return {} end

    local result = {}
    for propertyId, raid in pairs(raids) do
        local property = MySQL.single.await('SELECT id, property_name, building, floor, room, coords FROM properties WHERE id = ?', {propertyId})
        if property then
            local coords

            if property.building then
                local building = Buildings[property.building]
                local layout = building and building.roomLayout
                local anchor = GetRoomCoords(property.building, property.floor, property.room)
                if anchor and layout and layout.doors and layout.doors[1] then
                    coords = RotateOffset(anchor, layout.doors[1].coords)
                end
            else
                local stored = json.decode(property.coords)
                coords = vec3(stored.x, stored.y, stored.z)
            end

            if coords then
                result[#result + 1] = {
                    propertyId = propertyId,
                    label = property.property_name,
                    building = property.building,
                    coords = vec3(coords.x, coords.y, coords.z),
                    breached = raid.breached,
                    lockdown = raid.lockdown,
                }
            end
        end
    end
    return result
end)
