local config = require 'config.server'
local sharedConfig = require 'config.shared'

local enteredProperty = {}
local insideProperty = {}
local citizenid = {}
local ring = {}
local rentThreads = {}
local enteredInPlace = {}
local spawning = {}

---@param propertyId integer
---@return integer[]
function GetPropertyOccupants(propertyId)
    return insideProperty[propertyId] or {}
end

---@param citizenId string
---@param amount integer
---@param reason string
function PayCitizen(citizenId, amount, reason)
    if not citizenId or amount <= 0 then return end

    local player = exports.qbx_core:GetPlayerByCitizenId(citizenId)
    if player then
        player.Functions.AddMoney('bank', amount, reason)
        return
    end

    local offline = exports.qbx_core:GetOfflinePlayer(citizenId)
    if not offline then
        lib.print.warn(('unable to pay %s $%d (%s)'):format(citizenId, amount, reason))
        return
    end

    offline.PlayerData.money.bank = offline.PlayerData.money.bank + amount
    exports.qbx_core:SaveOffline(offline.PlayerData)
end

---@param account string?
---@param amount integer
---@param reason string
function PayAccount(account, amount, reason)
    if not account or amount <= 0 then return end

    local ok = pcall(function()
        exports['Renewed-Banking']:addAccountMoney(account, amount, reason)
    end)

    if not ok then lib.print.warn(('could not credit %s with $%d'):format(account, amount)) end
end

---@param propertyId integer
---@param amount integer
---@param kind string 'sale' | 'rent'
---@param reason string
---@return integer remainder
function PayCommission(propertyId, amount, kind, reason)
    local commission, remainder = SplitCommission(amount, kind)
    local realtor = MySQL.scalar.await('SELECT created_by FROM properties WHERE id = ?', {propertyId})

    if not realtor or commission <= 0 then return amount end

    PayCitizen(realtor, commission, string.format('Commission: %s', reason))
    return remainder
end

---@param property table
---@return string[]
function GetPropertyKeyholders(property)
    if not property.building then return property.keyholders and json.decode(property.keyholders) or {} end
    if not property.owner then return {} end

    local rows = MySQL.query.await('SELECT keyholder FROM properties_apartment_keyholders WHERE tenant = ?', {property.owner})
    local keyholders = {}
    for i = 1, #rows do
        keyholders[i] = rows[i].keyholder
    end
    return keyholders
end

---@param property table
---@return table
function GetPropertyDecorations(property)
    if property.building then
        return MySQL.query.await('SELECT `id`, `model`, `coords`, `rotation`, `stash_slot`, `tint` FROM `properties_apartment_decorations` WHERE `citizenid` = ? ORDER BY `id`', {property.owner})
    end
    return MySQL.query.await('SELECT `id`, `model`, `coords`, `rotation`, `stash_slot`, `tint` FROM `properties_decorations` WHERE `property_id` = ? ORDER BY `id`', {property.id})
end

---@param property table
---@param decorations table
---@return table<integer, integer> decorationId mapped to stash index
function RegisterPropertyStashes(property, decorations)
    local specs = GetFurnitureSpecs()
    local indexes = {}

    for i = 1, #decorations do
        local spec = specs[decorations[i].model]
        if spec and spec.type == 'stash' and decorations[i].stash_slot then
            exports.ox_inventory:RegisterStash(
                GetStashId(property, decorations[i].stash_slot),
                string.format('%s: %s', property.property_name, spec.label),
                spec.slots or config.apartmentStash.slots,
                spec.maxWeight or config.apartmentStash.maxWeight,
                property.owner
            )
            indexes[decorations[i].id] = decorations[i].stash_slot
        end
    end

    return indexes
end

exports.ox_inventory:registerHook('openInventory', function(payload)
    local propertyId = enteredProperty[payload.source]
    if not propertyId then return false end

    local player = exports.qbx_core:GetPlayer(payload.source)
    if not player then return false end

    local property = MySQL.single.await('SELECT id, property_name, owner, keyholders, building FROM properties WHERE id = ?', {propertyId})
    if not property or not property.owner then return false end

    local base = GetStashId(property)
    local escaped = base:gsub('%p', '%%%0')
    local inventoryId = payload.inventoryId:gsub(':[^:]+$', '')

    if inventoryId ~= base and not inventoryId:match('^' .. escaped .. '_%d+$') then return false end

    return HasPropertyAccess(player.PlayerData.citizenid, property, 'stash')
end, {
    inventoryFilter = {
        '^qbx_properties_',
    }
})

---@param playerSource integer
---@param id integer
---@param isSpawn boolean?
---@param inPlace boolean? entered by walking into the interior, so do not teleport or spawn a shell
function EnterProperty(playerSource, id, isSpawn, inPlace)
    if enteredProperty[playerSource] then return end
    local property = MySQL.single.await('SELECT * FROM properties WHERE id = ?', {id})
    if not property then return end -- Lua and its stupid need check nil warnings
    local propertyCoords = json.decode(property.coords)
    propertyCoords = vec3(propertyCoords.x, propertyCoords.y, propertyCoords.z)
    local playerCoords = GetEntityCoords(GetPlayerPed(playerSource))
    if not isSpawn and not inPlace and #(playerCoords - propertyCoords) > 8.0 then return end

    if property.interior == 'mlo' and not inPlace then -- MLOs are in the real world, walking back in re-enters them
        if isSpawn then
            SetEntityCoords(GetPlayerPed(playerSource), propertyCoords.x, propertyCoords.y, propertyCoords.z, false, false, false, false)
            TriggerClientEvent('qbx_properties:client:finishSpawn', playerSource)
        end
        return
    end

    local player = exports.qbx_core:GetPlayer(playerSource)
    if not player then return end
    citizenid[playerSource] = player.PlayerData.citizenid

    local interactions = {}
    local isInteriorShell = tonumber(property.interior) ~= nil
    local isBuildingUnit = property.building ~= nil and sharedConfig.targetInteractions
    local stashes = json.decode(property.stash_options)
    for i = 1, #stashes do
        local stashCoords = isInteriorShell and CalculateOffsetCoords(propertyCoords, stashes[i].coords) or stashes[i].coords
        if not isBuildingUnit then
            interactions[#interactions + 1] = {
                type = 'stash',
                coords = vec3(stashCoords.x, stashCoords.y, stashCoords.z)
            }
            exports.ox_inventory:RegisterStash(GetStashId(property), string.format('Property: %s', property.property_name), stashes[i].slots, stashes[i].maxWeight, property.owner)
        end
    end

    if isInteriorShell and not inPlace then
        TriggerClientEvent('qbx_properties:client:createInterior', playerSource, tonumber(property.interior), vec3(propertyCoords.x, propertyCoords.y, propertyCoords.z - sharedConfig.shellUndergroundOffset))
    end

    if property.building then
        if not inPlace then
            local anchor = GetRoomCoords(property.building, property.floor, property.room)
            local layout = Buildings[property.building] and Buildings[property.building].roomLayout

            if anchor and layout then
                local spawn = RotateOffset(anchor, layout.spawn)
                SetEntityCoords(GetPlayerPed(playerSource), spawn.x, spawn.y, spawn.z, false, false, false, false)
                SetEntityHeading(GetPlayerPed(playerSource), anchor.w)
            end
        end
    else
        local interactData = json.decode(property.interact_options)
        for i = 1, #interactData do
            local coords = isInteriorShell and CalculateOffsetCoords(propertyCoords, interactData[i].coords) or interactData[i].coords
            interactions[#interactions + 1] = {
                type = interactData[i].type,
                coords = vec3(coords.x, coords.y, coords.z)
            }
            if interactData[i].type == 'exit' and not inPlace then
                SetEntityCoords(GetPlayerPed(playerSource), coords.x, coords.y, coords.z, false, false, false, false)
                SetEntityHeading(GetPlayerPed(playerSource), coords.w)
            end
        end
    end

    enteredProperty[playerSource] = id
    enteredInPlace[playerSource] = inPlace or nil
    insideProperty[id] = insideProperty[id] or {}
    insideProperty[id][#insideProperty[id] + 1] = playerSource

    if not isBuildingUnit then
        lib.triggerClientEvent('qbx_properties:client:concealPlayers', insideProperty[id], insideProperty[id])
    end

    player.Functions.SetMetaData('currentPropertyId', id)

    if isBuildingUnit then
        RegisterPropertyStashes(property, GetPropertyDecorations(property))
    else
        local decorations = GetPropertyDecorations(property)
        local indexes = RegisterPropertyStashes(property, decorations)
        local types = GetFurnitureTypes()

        for i = 1, #decorations do
            local temp = json.decode(decorations[i].coords)
            decorations[i].coords = isInteriorShell and CalculateOffsetCoords(propertyCoords, vec3(temp.x, temp.y, temp.z)) or vec3(temp.x, temp.y, temp.z)
            temp = json.decode(decorations[i].rotation)
            decorations[i].rotation = vec3(temp.x, temp.y, temp.z)
            decorations[i].interaction = types[decorations[i].model]
            decorations[i].stashIndex = indexes[decorations[i].id]
        end

        TriggerClientEvent('qbx_properties:client:loadDecorations', playerSource, decorations)
    end

    TriggerClientEvent('qbx_properties:client:updateInteractions', playerSource, interactions, property.interior, type(property.rent_interval) == 'number', id)
    TriggerClientEvent('qbx_properties:client:accessFlags', playerSource, GetAccessFlags(player.PlayerData.citizenid, property))

    lib.logger(playerSource, 'qbx_properties:server:enterProperty', locale('logs.enter_property', player.PlayerData.citizenid, property.property_name))
end

---@param playerSource integer
local function exitProperty(playerSource, isLogout)
    local propertyId = enteredProperty[playerSource]
    if not propertyId then return end

    TriggerClientEvent('qbx_properties:client:unloadProperty', playerSource)
    TriggerClientEvent('qbx_properties:client:revealPlayers', playerSource)

    if not isLogout and not enteredInPlace[playerSource] then
        local property = MySQL.single.await('SELECT coords FROM properties WHERE id = ?', {propertyId})
        if property then
            local enterCoords = json.decode(property.coords)
            SetEntityCoords(GetPlayerPed(playerSource), enterCoords.x, enterCoords.y, enterCoords.z, false, false, false, false)
        end
    end

    enteredInPlace[playerSource] = nil

    local occupants = insideProperty[propertyId] or {}
    for i = 1, #occupants do
        if occupants[i] == playerSource then
            table.remove(occupants, i)
            break
        end
    end

    lib.triggerClientEvent('qbx_properties:client:concealPlayers', occupants, occupants)
    local logPropertyId = propertyId
    enteredProperty[playerSource] = nil

    local player = exports.qbx_core:GetPlayer(playerSource)
    if not player then return end

    if isLogout then
        local row = MySQL.single.await('SELECT building, interior FROM properties WHERE id = ?', {propertyId})
        if row and (row.building or row.interior == 'mlo') then
            player.Functions.SetMetaData('currentPropertyId', nil)
        end
        return
    end

    player.Functions.SetMetaData('currentPropertyId', nil)

    lib.logger(playerSource, 'qbx_properties:server:exitProperty', locale('logs.exit_property', player.PlayerData.citizenid, logPropertyId))
end

RegisterNetEvent('qbx_properties:server:exitProperty', function()
    exitProperty(source --[[@as number]])
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(source)
    exitProperty(source, true)
end)

lib.callback.register('qbx_properties:callback:loadProperties', function()
    local result = MySQL.query.await("SELECT coords FROM properties WHERE building IS NULL AND interior <> 'mlo' GROUP BY coords")
    local properties = {}
    for i = 1, #result do
        local coords = json.decode(result[i].coords)
        properties[i] = vec3(coords.x, coords.y, coords.z)
    end

    return properties
end)

lib.callback.register('qbx_properties:callback:requestProperties', function(source, propertyCoords)
    if type(propertyCoords) ~= 'vector3' or #(GetEntityCoords(GetPlayerPed(source)) - propertyCoords) > 8.0 then return {} end

    local rows = MySQL.query.await("SELECT property_name, owner, id, price, rent_interval, keyholders, coords FROM properties WHERE building IS NULL AND interior <> 'mlo'")
    local result = {}

    for i = 1, #rows do
        local coords = json.decode(rows[i].coords)
        if coords and #(propertyCoords - vec3(coords.x, coords.y, coords.z)) < 1.0 then
            rows[i].coords = nil
            result[#result + 1] = rows[i]
        end
    end

    return result
end)

local function hasAccess(citizenId, propertyId, permission)
    if type(citizenId) ~= 'string' or not ToId(propertyId) then return false end
    local property = MySQL.single.await('SELECT id, owner, keyholders, building FROM properties WHERE id = ?', {propertyId})
    if not property then return false end

    return HasPropertyAccess(citizenId, property, permission or 'door')
end

lib.callback.register('qbx_properties:callback:getWalkInProperties', function()
    local rows = MySQL.query.await("SELECT id, coords FROM properties WHERE building IS NULL AND interior NOT REGEXP '^-?[0-9]+$'")
    local result = {}
    for i = 1, #rows do
        local coords = json.decode(rows[i].coords)
        result[i] = { id = rows[i].id, coords = vec3(coords.x, coords.y, coords.z) }
    end
    return result
end)

RegisterNetEvent('qbx_properties:server:enterWalkIn', function(propertyId)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return end
    if not hasAccess(player.PlayerData.citizenid, propertyId) then return end

    local property = MySQL.single.await('SELECT coords FROM properties WHERE id = ?', {propertyId})
    if not property then return end

    local coords = json.decode(property.coords)
    if #(GetEntityCoords(GetPlayerPed(playerSource)) - vec3(coords.x, coords.y, coords.z)) > 60.0 then return end

    EnterProperty(playerSource, propertyId, false, true)
end)

---@param playerSource integer
function LeavePropertyInPlace(playerSource)
    if not enteredInPlace[playerSource] then return end
    exitProperty(playerSource)
end

RegisterNetEvent('qbx_properties:server:leaveWalkIn', function()
    LeavePropertyInPlace(source --[[@as number]])
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local playerSource = source --[[@as number]]
    spawning[playerSource] = true
    SetTimeout(60000, function() spawning[playerSource] = nil end)
end)

RegisterNetEvent('qbx_properties:server:enterProperty', function(data)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    if not player or type(data) ~= 'table' then return end

    local propertyId = ToId(data.id)
    local isSpawn = spawning[playerSource] or nil
    spawning[playerSource] = nil

    if data.remote == true and IsRealtor(player.PlayerData.job) then
        isSpawn = true

        if enteredProperty[playerSource] then
            exitProperty(playerSource)
        end
    end

    if propertyId then
        local target = MySQL.single.await('SELECT building FROM properties WHERE id = ?', {propertyId})

        if target and target.building then
            local own = MySQL.single.await('SELECT id FROM properties WHERE building = ? AND owner = ?', {target.building, player.PlayerData.citizenid})

            if own then
                propertyId = own.id
            elseif isSpawn then
                local entrance = Buildings[target.building] and Buildings[target.building].entrance
                if entrance then
                    SetEntityCoords(GetPlayerPed(playerSource), entrance.x, entrance.y, entrance.z, false, false, false, false)
                end
                TriggerClientEvent('qbx_properties:client:finishSpawn', playerSource)
                return
            end
        end
    end

    if not propertyId or (not hasAccess(player.PlayerData.citizenid, propertyId) and not IsRealtor(player.PlayerData.job)) then
        if isSpawn then TriggerClientEvent('qbx_properties:client:finishSpawn', playerSource) end
        return
    end

    EnterProperty(playerSource, propertyId, isSpawn)
end)

RegisterNetEvent('qbx_properties:server:ringProperty', function(data)
    local playerSource = source --[[@as number]]
    local propertyId = type(data) == 'table' and ToId(data.id)
    if not propertyId then return end
    local property = MySQL.single.await('SELECT owner, coords FROM properties WHERE id = ?', {propertyId})
    if not property or not property.owner then return end
    local propertyCoords = json.decode(property.coords)
    if #(GetEntityCoords(GetPlayerPed(playerSource)) - vec3(propertyCoords.x, propertyCoords.y, propertyCoords.z)) > 8.0 then return end
    local owner = exports.qbx_core:GetPlayerByCitizenId(property.owner)

    ring[propertyId] = ring[propertyId] or {}
    if not lib.table.contains(ring[propertyId], playerSource) then
        ring[propertyId][#ring[propertyId] + 1] = playerSource
        SetTimeout(300000, function()
            local ringers = ring[propertyId]
            if not ringers then return end
            for i = 1, #ringers do
                if ringers[i] == playerSource then
                    table.remove(ringers, i)
                    break
                end
            end
        end)
    end
    if owner and enteredProperty[owner.PlayerData.source] == propertyId then
        exports.qbx_core:Notify(owner.PlayerData.source, locale('notify.someone_at_door'))
    end
end)

lib.callback.register('qbx_properties:callback:requestKeyHolders', function(source)
    local propertyId = enteredProperty[source]
    if not propertyId then return end
    local result = MySQL.single.await('SELECT id, owner, keyholders, building FROM properties WHERE id = ?', {propertyId})
    local player = exports.qbx_core:GetPlayer(source)

    if not result or not player or player.PlayerData.citizenid ~= result.owner then return end

    local keyholders = GetPropertyKeyholders(result)
    local currentholders = {}
    for i = 1, #keyholders do
        local offlinePlayer = exports.qbx_core:GetOfflinePlayer(keyholders[i])
        if offlinePlayer then
            currentholders[#currentholders + 1] = {
                citizenid = offlinePlayer.PlayerData.citizenid,
                name = offlinePlayer.PlayerData.charinfo.firstname .. ' ' .. offlinePlayer.PlayerData.charinfo.lastname
            }
        end
    end
    return currentholders
end)

lib.callback.register('qbx_properties:callback:requestPotentialKeyholders', function(source)
    local propertyId = enteredProperty[source]
    if not propertyId then return end
    local result = MySQL.single.await('SELECT owner FROM properties WHERE id = ?', {propertyId})
    local owner = exports.qbx_core:GetPlayer(source)

    if not result or not owner or owner.PlayerData.citizenid ~= result.owner then return end

    local players = insideProperty[propertyId] or {}
    local insidePlayers = {}
    for i = 1, #players do
        local player = exports.qbx_core:GetPlayer(players[i])
        if player and not hasAccess(player.PlayerData.citizenid, propertyId) then
            insidePlayers[#insidePlayers + 1] = {
                citizenid = player.PlayerData.citizenid,
                name = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
            }
        end
    end
    return insidePlayers
end)

lib.callback.register('qbx_properties:callback:requestRingers', function(source)
    local propertyId = enteredProperty[source]
    local owner = exports.qbx_core:GetPlayer(source)
    local property = propertyId and MySQL.single.await('SELECT owner FROM properties WHERE id = ?', {propertyId})
    if not owner or not property or owner.PlayerData.citizenid ~= property.owner then return {} end

    local players = ring[propertyId] or {}
    local ringers = {}
    for i = 1, #players do
        local ringer = exports.qbx_core:GetPlayer(players[i])
        if ringer then
            ringers[#ringers + 1] = {
                citizenid = ringer.PlayerData.citizenid,
                name = ringer.PlayerData.charinfo.firstname .. ' ' .. ringer.PlayerData.charinfo.lastname
            }
        end
    end
    return ringers
end)

lib.callback.register('qbx_properties:callback:checkAccess', function(source)
    local propertyId = enteredProperty[source]
    if not propertyId then return false end
    local result = MySQL.single.await('SELECT owner FROM properties WHERE id = ?', {propertyId})
    local player = exports.qbx_core:GetPlayer(source)
    return result ~= nil and player ~= nil and result.owner == player.PlayerData.citizenid
end)

RegisterNetEvent('qbx_properties:server:letRingerIn', function(visitorCid)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    local propertyId = enteredProperty[playerSource]
    if not player or not propertyId then return end
    local result = MySQL.single.await('SELECT owner, interior FROM properties WHERE id = ?', {propertyId})

    if not result or player.PlayerData.citizenid ~= result.owner then return end

    local visitor = exports.qbx_core:GetPlayerByCitizenId(visitorCid)
    if not visitor then return end

    local ringers = ring[propertyId] or {}
    local visitorIndex
    for i = 1, #ringers do
        if ringers[i] == visitor.PlayerData.source then visitorIndex = i break end
    end
    if not visitorIndex then return end

    table.remove(ringers, visitorIndex)
    EnterProperty(visitor.PlayerData.source, propertyId)
end)

RegisterNetEvent('qbx_properties:server:addKeyholder', function(keyholderCid)
    local playerSource = source --[[@as number]]
    local owner = exports.qbx_core:GetPlayer(playerSource)
    local propertyId = enteredProperty[playerSource]
    if not owner or not propertyId then return end
    local result = MySQL.single.await('SELECT id, owner, keyholders, building FROM properties WHERE id = ?', {propertyId})

    if not result or owner.PlayerData.citizenid ~= result.owner then return end

    local keyholders = GetPropertyKeyholders(result)
    if lib.table.contains(keyholders, keyholderCid) then return end
    local keyholder = exports.qbx_core:GetPlayerByCitizenId(keyholderCid)
    if not keyholder or not lib.table.contains(insideProperty[propertyId] or {}, keyholder.PlayerData.source) then return end

    if result.building then
        MySQL.insert.await('INSERT IGNORE INTO properties_apartment_keyholders (tenant, keyholder) VALUES (?, ?)', {result.owner, keyholderCid})
    else
        keyholders[#keyholders + 1] = keyholderCid
        MySQL.update.await('UPDATE properties SET keyholders = ? WHERE id = ?', {json.encode(keyholders), propertyId})
    end

    exports.qbx_core:Notify(playerSource, keyholder.PlayerData.charinfo.firstname.. locale('notify.keyholder'))
    exports.qbx_core:Notify(keyholder.PlayerData.source, locale('notify.added_as_keyholder'))

    lib.logger(playerSource, 'qbx_properties:server:addKeyholder', locale('logs.added_keyholder', keyholderCid, propertyId))
end)

RegisterNetEvent('qbx_properties:server:removeKeyholder', function(keyholderCid)
    local playerSource = source --[[@as number]]
    local owner = exports.qbx_core:GetPlayer(playerSource)
    local propertyId = enteredProperty[playerSource]
    if not owner or not propertyId then return end

    local result = MySQL.single.await('SELECT id, owner, keyholders, building FROM properties WHERE id = ?', {propertyId})
    if not result or owner.PlayerData.citizenid ~= result.owner then return end

    local keyholders = GetPropertyKeyholders(result)
    if not lib.table.contains(keyholders, keyholderCid) then return end

    if result.building then
        MySQL.update.await('DELETE FROM properties_apartment_keyholders WHERE tenant = ? AND keyholder = ?', {result.owner, keyholderCid})
    else
        for i = 1, #keyholders do
            if keyholders[i] == keyholderCid then
                table.remove(keyholders, i)
                break
            end
        end
        MySQL.update.await('UPDATE properties SET keyholders = ? WHERE id = ?', {json.encode(keyholders), propertyId})
    end
    local keyholder = exports.qbx_core:GetOfflinePlayer(keyholderCid)
    if keyholder then
        exports.qbx_core:Notify(playerSource, keyholder.PlayerData.charinfo.firstname.. locale('notify.removed_as_keyholder'))
    end

    lib.logger(playerSource, 'qbx_properties:server:removeKeyholder', locale('logs.removed_keyholder', keyholderCid, propertyId))
end)

RegisterNetEvent('qbx_properties:server:logoutProperty', function()
    local playerSource = source --[[@as number]]
    local propertyId = enteredProperty[playerSource]
    if not propertyId then return end

    local result = MySQL.single.await('SELECT owner, coords FROM properties WHERE id = ?', {propertyId})
    local player = exports.qbx_core:GetPlayer(playerSource)
    if not result or not player or player.PlayerData.citizenid ~= result.owner then return end

    TriggerClientEvent('qbx_properties:client:unloadProperty', playerSource)
    TriggerClientEvent('qbx_properties:client:revealPlayers', playerSource)
    local occupants = insideProperty[propertyId] or {}
    for i = 1, #occupants do
        if occupants[i] == playerSource then
            table.remove(occupants, i)
            break
        end
    end

    lib.triggerClientEvent('qbx_properties:client:concealPlayers', occupants, occupants)
    enteredProperty[playerSource] = nil
    exports.qbx_core:Logout(playerSource)
    Wait(50)
    local coords = json.decode(result.coords)
    MySQL.update('UPDATE players SET position = ? WHERE citizenid = ?', { json.encode(vec4(coords.x, coords.y, coords.z, 0.0)), player.PlayerData.citizenid })
end)

RegisterNetEvent('qbx_properties:server:openStash', function(stashIndex)
    local playerSource = source --[[@as number]]
    local propertyId = enteredProperty[playerSource]
    local player = exports.qbx_core:GetPlayer(playerSource)


    if not player or not hasAccess(player.PlayerData.citizenid, propertyId, 'stash') then return end

    local property = MySQL.single.await('SELECT id, property_name, building, floor, room, owner FROM properties WHERE id = ?', {propertyId})
    if not property then return end

    stashIndex = ToId(stashIndex) or 0
    if stashIndex > 0 then
        local indexes = RegisterPropertyStashes(property, GetPropertyDecorations(property))
        local valid = false
        for _, index in pairs(indexes) do
            if index == stashIndex then valid = true break end
        end
        if not valid then return end
    end

    exports.ox_inventory:forceOpenInventory(playerSource, 'stash', { id = GetStashId(property, stashIndex) })
end)

AddEventHandler('playerDropped', function ()
    local playerSource = source --[[@as number]]
    local propertyId = enteredProperty[playerSource]
    local playerCitizenId = citizenid[playerSource]

    enteredProperty[playerSource] = nil
    citizenid[playerSource] = nil
    enteredInPlace[playerSource] = nil
    spawning[playerSource] = nil
    if ClearApartmentLock then ClearApartmentLock(playerSource) end
    if ClearApartmentClaim then ClearApartmentClaim(playerSource) end

    if not propertyId then return end

    local occupants = insideProperty[propertyId] or {}
    for i = 1, #occupants do
        if occupants[i] == playerSource then
            table.remove(occupants, i)
            break
        end
    end

    lib.triggerClientEvent('qbx_properties:client:concealPlayers', occupants, occupants)

    if not playerCitizenId then return end
    local property = MySQL.single.await('SELECT coords FROM properties WHERE id = ?', {propertyId})
    if not property then return end
    local coords = json.decode(property.coords)
    MySQL.update('UPDATE players SET position = ? WHERE citizenid = ?', { json.encode(vec4(coords.x, coords.y, coords.z, 0.0)), playerCitizenId })
end)

local function registerGarage(propertyId, name, garage)
    local garageName = 'property_' .. string.gsub(string.lower(name), ' ', '_')
    exports.qbx_garages:RegisterGarage(garageName, {
        label = name,
        vehicleType = 'car',
        accessPoints = {
            {
                coords = vec4(garage.x, garage.y, garage.z, garage.w),
            }
        },
        canAccess = function(source)
            local player = exports.qbx_core:GetPlayer(source)
            return player ~= nil and hasAccess(player.PlayerData.citizenid, propertyId, 'garage')
        end
    })
end

function RegisterPropertyGarage(propertyId, name, garage)
    registerGarage(propertyId, name, garage)
end

local function registerGarages()
    local properties = MySQL.query.await('SELECT id, property_name, garage FROM properties WHERE owner IS NOT NULL AND garage IS NOT NULL')
    if not properties then return end
    for i = 1, #properties do
        local property = properties[i]
        registerGarage(property.id, property.property_name, json.decode(property.garage))
    end
end

local function evictProperty(propertyId)
    MySQL.update.await('UPDATE properties SET owner = NULL, keyholders = JSON_OBJECT(), wall_color = NULL WHERE id = ?', {propertyId})

    local occupants = insideProperty[propertyId] or {}
    for _ = 1, #occupants do
        exitProperty(occupants[1])
    end
end

local function startRentThread(propertyId)
    if rentThreads[propertyId] then return end
    rentThreads[propertyId] = true

    CreateThread(function()
        while true do
            local property = MySQL.single.await('SELECT owner, price, rent_interval, property_name, UNIX_TIMESTAMP(rent_last_paid) AS lastPaid FROM properties WHERE id = ?', {propertyId})
            if not property or not property.owner or not property.rent_interval then break end

            local due = (property.lastPaid or os.time()) + property.rent_interval * 3600
            local remaining = due - os.time()
            if remaining > 0 then Wait(remaining * 1000) end

            property = MySQL.single.await('SELECT owner, price, property_name FROM properties WHERE id = ?', {propertyId})
            if not property or not property.owner then break end

            local player = exports.qbx_core:GetPlayerByCitizenId(property.owner) or exports.qbx_core:GetOfflinePlayer(property.owner)
            if not player then print(string.format('%s does not exist anymore, consider checking property id %s', property.owner, propertyId)) break end

            if player.Offline then
                if player.PlayerData.money.bank < property.price then break end
                player.PlayerData.money.bank = player.PlayerData.money.bank - property.price
                exports.qbx_core:SaveOffline(player.PlayerData)
            else
                if not player.Functions.RemoveMoney('bank', property.price, string.format('Rent for %s', property.property_name)) then
                    exports.qbx_core:Notify(player.PlayerData.source, string.format('Not enough money to pay rent for %s', property.property_name), 'error')
                    break
                end
            end

            local reason = string.format('Rent for %s', property.property_name)
            PayAccount(config.governmentAccount, PayCommission(propertyId, property.price, 'rent', reason), reason)

            MySQL.update.await('UPDATE properties SET rent_last_paid = NOW() WHERE id = ?', {propertyId})
        end

        rentThreads[propertyId] = nil
        evictProperty(propertyId)
    end)
end

RegisterNetEvent('qbx_properties:server:rentProperty', function(propertyId)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return end
    local playerCoords = GetEntityCoords(GetPlayerPed(playerSource))
    local property = MySQL.single.await('SELECT owner, price, property_name, coords, rent_interval, garage FROM properties WHERE id = ?', {propertyId})
    if not property or type(property.price) ~= 'number' or property.price <= 0 then return end
    local propertyCoords = json.decode(property.coords)
    if #(playerCoords - vec3(propertyCoords.x, propertyCoords.y, propertyCoords.z)) > 8.0 then return end
    if property.owner then return end
    if not property.rent_interval then return end

    if player.PlayerData.money.bank < property.price then
        exports.qbx_core:Notify(playerSource, 'Not enough money to rent property.', 'error')
        return
    end

    if MySQL.update.await('UPDATE properties SET owner = ?, rent_last_paid = NOW() WHERE id = ? AND owner IS NULL', {player.PlayerData.citizenid, propertyId}) ~= 1 then return end

    if not player.Functions.RemoveMoney('bank', property.price, string.format('Rent for %s', property.property_name)) then
        MySQL.update.await('UPDATE properties SET owner = NULL, rent_last_paid = NULL WHERE id = ?', {propertyId})
        exports.qbx_core:Notify(playerSource, 'Not enough money to rent property.', 'error')
        return
    end

    if property.garage then
        registerGarage(propertyId, property.property_name, json.decode(property.garage))
    end

    exports.qbx_core:Notify(playerSource, string.format('Successfully started renting %s', property.property_name), 'success')
    startRentThread(propertyId)

    lib.logger(playerSource, 'qbx_properties:server:rentProperty', locale('logs.rent_property', player.PlayerData.citizenid, propertyId))
end)

RegisterNetEvent('qbx_properties:server:buyProperty', function(propertyId)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    propertyId = ToId(propertyId)
    if not player or not propertyId then return end
    local playerCoords = GetEntityCoords(GetPlayerPed(playerSource))
    local property = MySQL.single.await('SELECT owner, price, property_name, coords, garage FROM properties WHERE id = ?', {propertyId})
    if not property or type(property.price) ~= 'number' or property.price <= 0 then return end
    local propertyCoords = json.decode(property.coords)

    if #(playerCoords - vec3(propertyCoords.x, propertyCoords.y, propertyCoords.z)) > 8.0 or property.owner then return end

    local account = player.PlayerData.money.cash >= property.price and 'cash' or 'bank'
    if not player.Functions.RemoveMoney(account, property.price, string.format('Purchased %s', property.property_name)) then
        exports.qbx_core:Notify(playerSource, 'Not enough money to purchase property.', 'error')
        return
    end

    if MySQL.update.await('UPDATE properties SET owner = ? WHERE id = ? AND owner IS NULL', {player.PlayerData.citizenid, propertyId}) ~= 1 then
        player.Functions.AddMoney(account, property.price, string.format('Refund for %s', property.property_name))
        return
    end

    if property.garage then
        registerGarage(propertyId, property.property_name, json.decode(property.garage))
    end

    TriggerClientEvent('qbx_properties:client:refreshBlips', -1)
    exports.qbx_core:Notify(playerSource, string.format('Successfully purchased %s for $%s', property.property_name, property.price))

    lib.logger(playerSource, 'qbx_properties:server:buyProperty', locale('logs.buy_property', player.PlayerData.citizenid, propertyId))
end)

---@param file string
local function runMigration(file)
    local contents = LoadResourceFile(cache.resource, file)
    if not contents then return end

    contents = contents:gsub('/%*.-%*/', ' '):gsub('%-%-[^\n]*', ' ')

    for statement in contents:gmatch('[^;]+') do
        if statement:find('%S') then
            MySQL.query.await(statement)
        end
    end
end

Citizen.CreateThreadNow(function()
    runMigration('property.sql')
    runMigration('decorations.sql')
    runMigration('property_garages.sql')
    runMigration('property_rent.sql')
    runMigration('property_apartments.sql')
    runMigration('property_market.sql')
    runMigration('property_pool.sql')
    runMigration('property_utilities.sql')

    local properties = MySQL.query.await('SELECT id FROM properties WHERE owner IS NOT NULL AND rent_interval IS NOT NULL')
    for i = 1, #properties do
        startRentThread(properties[i].id)
    end

    registerGarages()
end)

RegisterNetEvent('qbx_properties:server:stopRenting', function()
    local player = exports.qbx_core:GetPlayer(source)
    local propertyId = enteredProperty[source]
    if not player or not propertyId then return end
    local property = MySQL.single.await('SELECT owner, property_name FROM properties WHERE id = ?', {propertyId})
    if not property or player.PlayerData.citizenid ~= property.owner then return end

    exports.qbx_core:Notify(player.PlayerData.source, string.format('You stopped your rental contract for %s', property.property_name), 'success')
    evictProperty(propertyId)

    lib.logger(player.PlayerData.source, 'qbx_properties:server:stopRenting', locale('logs.stop_renting', player.PlayerData.citizenid, propertyId))
end)

RegisterNetEvent('qbx_properties:server:addDecoration', function(hash, coords, rotation, objectId, tint)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    local propertyId = enteredProperty[playerSource]
    if not player or not propertyId then return end
    local property = MySQL.single.await('SELECT owner, property_name, building, floor, room FROM properties WHERE id = ?', {propertyId})
    if not property or player.PlayerData.citizenid ~= property.owner then return end
    if (type(hash) ~= 'string' and type(hash) ~= 'number') or type(coords) ~= 'vector3' or type(rotation) ~= 'vector3' then return end
    if #(GetEntityCoords(GetPlayerPed(playerSource)) - coords) > 15.0 then return end

    local anchor = property.building and GetRoomCoords(property.building, property.floor, property.room)
    local storedCoords = anchor and UnrotateOffset(anchor, coords) or coords
    local storedRotation = anchor and vec3(rotation.x, rotation.y, (rotation.z - anchor.w) % 360.0) or rotation
    local interaction = GetFurnitureTypes()[hash]

    tint = ToId(tint)
    if tint and (tint < 1 or tint > 31 or not (GetFurnitureSpecs()[hash] or {}).tint) then tint = nil end

    local stashSlot = nil
    if interaction == 'stash' and not objectId then
        local used = anchor
            and MySQL.query.await('SELECT stash_slot FROM properties_apartment_decorations WHERE citizenid = ? AND stash_slot IS NOT NULL', {property.owner})
            or MySQL.query.await('SELECT stash_slot FROM properties_decorations WHERE property_id = ? AND stash_slot IS NOT NULL', {propertyId})

        local taken = {}
        for i = 1, #used do taken[used[i].stash_slot] = true end

        stashSlot = 1
        while taken[stashSlot] do stashSlot += 1 end
    end

    if objectId then
        objectId = ToId(objectId)
        if not objectId then return end

        local updated = anchor
            and MySQL.update.await('UPDATE properties_apartment_decorations SET coords = ?, rotation = ?, tint = ? WHERE id = ? AND citizenid = ?', { json.encode(storedCoords), json.encode(storedRotation), tint, objectId, property.owner })
            or MySQL.update.await('UPDATE properties_decorations SET coords = ?, rotation = ?, tint = ? WHERE id = ? AND property_id = ?', { json.encode(storedCoords), json.encode(storedRotation), tint, objectId, propertyId })
        if updated ~= 1 then return end

        property.id = propertyId
        local stashIndex = interaction == 'stash'
            and RegisterPropertyStashes(property, GetPropertyDecorations(property))[objectId] or nil

        lib.triggerClientEvent('qbx_properties:client:removeDecoration', insideProperty[propertyId], objectId)
        lib.triggerClientEvent('qbx_properties:client:addDecoration', insideProperty[propertyId], objectId, hash, coords, rotation, interaction, stashIndex, tint)
    else
        local id = anchor
            and MySQL.insert.await('INSERT INTO `properties_apartment_decorations` (citizenid, model, coords, rotation, stash_slot, tint) VALUES (?, ?, ?, ?, ?, ?)', {property.owner, hash, json.encode(storedCoords), json.encode(storedRotation), stashSlot, tint})
            or MySQL.insert.await('INSERT INTO `properties_decorations` (property_id, model, coords, rotation, stash_slot, tint) VALUES (?, ?, ?, ?, ?, ?)', {propertyId, hash, json.encode(storedCoords), json.encode(storedRotation), stashSlot, tint})

        property.id = propertyId
        local stashIndex = interaction == 'stash'
            and RegisterPropertyStashes(property, GetPropertyDecorations(property))[id] or nil

        lib.triggerClientEvent('qbx_properties:client:addDecoration', insideProperty[propertyId], id, hash, coords, rotation, interaction, stashIndex, tint)
    end

    if interaction == 'door' and SyncFurnitureDoors then
        SyncFurnitureDoors(property)
    end

    lib.logger(player.PlayerData.source, 'qbx_properties:server:addDecoration', locale('logs.add_decoration', player.PlayerData.citizenid, hash, propertyId))
end)

local movingAuth = {}

RegisterNetEvent('qbx_properties:server:decorationMoving', function(objectId, coords, rotation)
    local playerSource = source --[[@as number]]
    objectId = ToId(objectId)
    if not objectId or type(coords) ~= 'vector3' or type(rotation) ~= 'vector3' then return end

    local propertyId = enteredProperty[playerSource]
    local targets

    if propertyId then
        targets = insideProperty[propertyId]
    elseif GetGardenOccupants then
        propertyId, targets = GetGardenOccupants(playerSource)
    end

    if not propertyId or not targets or #targets < 2 then return end

    local auth = movingAuth[playerSource]
    if not auth or auth.propertyId ~= propertyId then
        local player = exports.qbx_core:GetPlayer(playerSource)
        local owner = MySQL.scalar.await('SELECT owner FROM properties WHERE id = ?', {propertyId})
        auth = { propertyId = propertyId, allowed = player ~= nil and owner == player.PlayerData.citizenid }
        movingAuth[playerSource] = auth
    end
    if not auth.allowed then return end

    for i = 1, #targets do
        if targets[i] ~= playerSource then
            TriggerClientEvent('qbx_properties:client:decorationMoving', targets[i], objectId, coords, rotation)
        end
    end
end)

AddEventHandler('playerDropped', function()
    movingAuth[source] = nil
end)

RegisterNetEvent('qbx_properties:server:removeDecoration', function(objectId)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    local propertyId = enteredProperty[playerSource]
    objectId = ToId(objectId)
    if not player or not propertyId or not objectId then return end
    local property = MySQL.single.await('SELECT owner, building FROM properties WHERE id = ?', {propertyId})
    if not property or player.PlayerData.citizenid ~= property.owner then return end

    local deleted = property.building
        and MySQL.update.await('DELETE FROM properties_apartment_decorations WHERE id = ? AND citizenid = ?', {objectId, property.owner})
        or MySQL.update.await('DELETE FROM properties_decorations WHERE id = ? AND property_id = ?', {objectId, propertyId})
    if deleted ~= 1 then return end
    lib.triggerClientEvent('qbx_properties:client:removeDecoration', insideProperty[propertyId], objectId)

    if SyncFurnitureDoors then
        property.id = propertyId
        SyncFurnitureDoors(property)
    end

    lib.logger(player.PlayerData.source, 'qbx_properties:server:removeDecoration', locale('logs.remove_decoration', player.PlayerData.citizenid, objectId, propertyId))
end)

lib.callback.register('qbx_properties:callback:getMyBlips', function(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return {} end

    local rows = MySQL.query.await('SELECT property_name, coords, garage FROM properties WHERE owner = ? AND building IS NULL', {player.PlayerData.citizenid})
    local result = {}

    for i = 1, #rows do
        local coords = json.decode(rows[i].coords)
        result[#result + 1] = {
            name = rows[i].property_name,
            coords = vec3(coords.x, coords.y, coords.z),
            garage = rows[i].garage and json.decode(rows[i].garage) or nil,
        }
    end

    return result
end)
