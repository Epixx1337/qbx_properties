local config = require 'config.server'
local sharedConfig = require 'config.shared'

local pendingOffers = {}

lib.callback.register('qbx_properties:callback:offerProperty', function(source, data)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or type(data) ~= 'table' then return false, 'Invalid request.' end

    local propertyId = ToId(data.propertyId)
    local price = ToId(data.price)
    if not propertyId or not price or price < 0 then return false, 'Invalid request.' end

    local property = MySQL.single.await('SELECT id, owner, property_name FROM properties WHERE id = ?', {propertyId})
    if not property then return false, 'Property not found.' end

    local isRealtor = IsRealtor(player.PlayerData.job)
    if property.owner ~= player.PlayerData.citizenid and not (isRealtor and not property.owner) then
        return false, 'You cannot sell this property.'
    end

    local target
    if data.serverId then
        local id = ToId(data.serverId)
        target = id and exports.qbx_core:GetPlayer(id)
    elseif type(data.citizenid) == 'string' then
        target = exports.qbx_core:GetPlayerByCitizenId(data.citizenid)
    end

    if not target then return false, 'That person is not available.' end
    if target.PlayerData.citizenid == player.PlayerData.citizenid then return false, 'You cannot sell to yourself.' end

    local targetSource = target.PlayerData.source
    if #(GetEntityCoords(GetPlayerPed(source)) - GetEntityCoords(GetPlayerPed(targetSource))) > sharedConfig.market.sellRange then
        return false, 'They are too far away.'
    end

    pendingOffers[targetSource] = {
        propertyId = propertyId,
        price = price,
        sellerSource = source,
        sellerCid = player.PlayerData.citizenid,
        expires = os.time() + 60,
    }

    TriggerClientEvent('qbx_properties:client:propertyOffer', targetSource, {
        seller = string.format('%s %s', player.PlayerData.charinfo.firstname, player.PlayerData.charinfo.lastname),
        property = property.property_name,
        price = price,
    })

    return true
end)

RegisterNetEvent('qbx_properties:server:respondToOffer', function(accepted)
    local playerSource = source --[[@as number]]
    local offer = pendingOffers[playerSource]
    pendingOffers[playerSource] = nil

    if not offer or os.time() > offer.expires then return end

    local buyer = exports.qbx_core:GetPlayer(playerSource)
    local sellerOnline = GetPlayerName(offer.sellerSource) ~= nil
    if not buyer then return end

    if not accepted then
        if sellerOnline then exports.qbx_core:Notify(offer.sellerSource, 'The offer was declined.', 'error') end
        return
    end

    local property = MySQL.single.await('SELECT id, owner, property_name, type FROM properties WHERE id = ?', {offer.propertyId})
    local stillValid = property ~= nil and (property.owner == offer.sellerCid or property.owner == nil)

    if not stillValid then
        exports.qbx_core:Notify(playerSource, 'That property is no longer available.', 'error')
        if sellerOnline then exports.qbx_core:Notify(offer.sellerSource, 'That property is no longer available.', 'error') end
        return
    end

    if not CanOwnAnotherProperty(buyer.PlayerData.citizenid, property.type) then
        exports.qbx_core:Notify(playerSource, 'You already own the maximum number of properties of this type.', 'error')
        if sellerOnline then exports.qbx_core:Notify(offer.sellerSource, 'The buyer already owns the maximum number of properties of this type.', 'error') end
        return
    end

    local account = buyer.PlayerData.money.cash >= offer.price and 'cash' or 'bank'
    if buyer.PlayerData.money[account] < offer.price then
        exports.qbx_core:Notify(playerSource, 'You do not have enough money for this property.', 'error')
        if sellerOnline then
            exports.qbx_core:Notify(offer.sellerSource, 'The buyer did not have enough money.', 'error')
        end
        return
    end

    if not buyer.Functions.RemoveMoney(account, offer.price, string.format('Purchased %s', property.property_name)) then
        exports.qbx_core:Notify(playerSource, 'You do not have enough money for this property.', 'error')
        if sellerOnline then
            exports.qbx_core:Notify(offer.sellerSource, 'The buyer did not have enough money.', 'error')
        end
        return
    end

    RecordPropertySale(offer.propertyId, property.owner, buyer.PlayerData.citizenid, offer.price)

    if MySQL.update.await('UPDATE properties SET owner = ?, keyholders = JSON_OBJECT(), sale_authorized = 0, maintenance_paid_until = NULL WHERE id = ?', {buyer.PlayerData.citizenid, offer.propertyId}) ~= 1 then
        buyer.Functions.AddMoney(account, offer.price, 'Property purchase refund')
        return
    end

    if property.owner then
        local seller = exports.qbx_core:GetPlayerByCitizenId(property.owner)
        if seller then
            seller.Functions.AddMoney('bank', offer.price, string.format('Sold %s', property.property_name))
        end
    elseif config.marketSociety then
        pcall(function()
            exports['Renewed-Banking']:addAccountMoney(config.marketSociety, offer.price, string.format('Sold %s', property.property_name))
        end)
    end

    exports.qbx_core:Notify(playerSource, string.format('You bought %s.', property.property_name), 'success')
    if sellerOnline then
        exports.qbx_core:Notify(offer.sellerSource, string.format('%s bought %s.', buyer.PlayerData.charinfo.firstname, property.property_name), 'success')
    end

    TriggerClientEvent('qbx_properties:client:refreshTargets', -1)

    LogAction(playerSource, 'qbx_properties:server:sellProperty', string.format('%s sold %s to %s for $%d', offer.sellerCid, property.property_name, buyer.PlayerData.citizenid, offer.price))
end)

AddEventHandler('playerDropped', function()
    pendingOffers[source] = nil
end)

lib.callback.register('qbx_properties:callback:getUnownedProperties', function()
    local rows = MySQL.query.await('SELECT id, property_name, coords, price FROM properties WHERE owner IS NULL AND building IS NULL')
    local result = {}

    for i = 1, #rows do
        local coords = json.decode(rows[i].coords)
        result[i] = {
            id = rows[i].id,
            name = rows[i].property_name,
            price = rows[i].price,
            coords = vec3(coords.x, coords.y, coords.z),
        }
    end

    return result
end)
