local config = require 'config.server'
local sharedConfig = require 'config.shared'
local market = sharedConfig.market

local pendingAgentBids = {}

if sharedConfig.housingCommand ~= false then
    lib.addCommand('housing', {
        help = 'Open the housing market',
    }, function(source)
        TriggerClientEvent('qbx_properties:client:openHousing', source)
    end)
end

---@param citizenId string
---@param amount integer
---@param reason string
local function payOut(citizenId, amount, reason)
    if amount <= 0 then return end
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

---@param listingId integer
---@return table?
local function getActiveListing(listingId)
    return MySQL.single.await("SELECT * FROM properties_listings WHERE id = ? AND status = 'active'", {listingId})
end

---@param listingId integer
---@return table?
local function getTopBid(listingId)
    return MySQL.single.await("SELECT * FROM properties_bids WHERE listing_id = ? AND status = 'active' ORDER BY amount DESC LIMIT 1", {listingId})
end

---@param propertyId integer
---@param buyerCid string
---@param amount integer
local function transferProperty(propertyId, buyerCid, amount)
    local property = MySQL.single.await('SELECT owner, property_name, type FROM properties WHERE id = ?', {propertyId})
    if not property then return false end
    if not CanOwnAnotherProperty(buyerCid, property.type) then return false end

    MySQL.update.await('UPDATE properties SET owner = ?, keyholders = JSON_OBJECT() WHERE id = ?', {buyerCid, propertyId})

    TriggerClientEvent('qbx_properties:client:refreshBlips', -1)

    local reason = string.format('Sale of %s', property.property_name)
    local remainder = PayCommission(propertyId, amount, 'sale', reason)

    if property.owner then
        payOut(property.owner, remainder, reason)
    else
        PayAccount(config.marketSociety, remainder, reason)
    end

    return true
end

local function fetchListings()
    local listings = MySQL.query.await([[
        SELECT l.id, l.property_id, l.listing_type, l.price, l.min_increment, l.reserve_price,
               UNIX_TIMESTAMP(l.auction_end) AS auction_end, p.property_name, p.coords, p.rent_interval, p.images, p.description, p.type, p.size,
               (SELECT MAX(amount) FROM properties_bids b WHERE b.listing_id = l.id AND b.status = 'active') AS top_bid
        FROM properties_listings l
        JOIN properties p ON p.id = l.property_id
        WHERE l.status = 'active'
        ORDER BY l.created_at DESC
    ]])

    for i = 1, #listings do
        listings[i].images = PropertyImageUrls(listings[i].images)
    end

    return listings
end

lib.callback.register('qbx_properties:callback:getListings', fetchListings)

exports('GetListings', fetchListings)

lib.callback.register('qbx_properties:callback:getRealtorProperties', function(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or not IsRealtor(player.PlayerData.job) then return {} end

    local rows = MySQL.query.await([[
        SELECT p.id, p.property_name, p.owner, p.price, p.rent_interval, p.building, p.interior, p.images,
               p.interior REGEXP '^-?[0-9]+$' AS shell,
               pl.charinfo AS owner_charinfo,
               EXISTS(SELECT 1 FROM properties_listings l WHERE l.property_id = p.id AND l.status IN ('active','finalizing')) AS listed
        FROM properties p
        LEFT JOIN players pl ON pl.citizenid = p.owner
        ORDER BY p.property_name
        LIMIT 500
    ]])

    for i = 1, #rows do
        local urls = PropertyImageUrls(rows[i].images)
        rows[i].images = nil
        rows[i].thumb = urls[1]
    end

    return rows
end)

RegisterNetEvent('qbx_properties:server:repossess', function(propertyId)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    propertyId = ToId(propertyId)
    if not player or not propertyId or not IsRealtor(player.PlayerData.job) then return end

    local property = MySQL.single.await('SELECT id, owner, property_name FROM properties WHERE id = ? AND building IS NULL', {propertyId})
    if not property or not property.owner then return end

    local owner = exports.qbx_core:GetPlayerByCitizenId(property.owner)
    if owner then
        exports.qbx_core:Notify(owner.PlayerData.source, string.format('%s has been repossessed.', property.property_name), 'error')
        owner.Functions.SetMetaData('currentPropertyId', nil)
    end

    MySQL.update.await('UPDATE properties SET owner = NULL, keyholders = JSON_OBJECT(), wall_color = NULL WHERE id = ?', {propertyId})

    LogAction(playerSource, 'qbx_properties:server:repossess', string.format('%s repossessed %s from %s', player.PlayerData.citizenid, property.property_name, property.owner))

    exports.qbx_core:Notify(playerSource, string.format('%s repossessed.', property.property_name), 'success')
end)

lib.callback.register('qbx_properties:callback:getListingBids', function(source, listingId)
    local player = exports.qbx_core:GetPlayer(source)
    listingId = ToId(listingId)
    if not player or not listingId or not IsRealtor(player.PlayerData.job) then return {} end

    local bids = MySQL.query.await([[
        SELECT b.id, b.amount, b.status, b.created_at, pl.charinfo
        FROM properties_bids b
        LEFT JOIN players pl ON pl.citizenid = b.bidder
        WHERE b.listing_id = ?
        ORDER BY b.amount DESC
    ]], {listingId})

    local result = {}
    for i = 1, #bids do
        local charinfo = bids[i].charinfo and json.decode(bids[i].charinfo)
        result[i] = {
            id = bids[i].id,
            amount = bids[i].amount,
            status = bids[i].status,
            createdAt = bids[i].created_at,
            bidder = market.anonymousBids and 'Anonymous'
                or (charinfo and string.format('%s %s', charinfo.firstname, charinfo.lastname) or 'Unknown'),
        }
    end
    return result
end)

---@param source integer
---@param player table
---@param propertyId integer
---@param listing table
---@return boolean
function CreateListingInternal(source, player, propertyId, listing)
    local price = ToId(listing.price)
    if not price or price < market.minPrice or price > market.maxPrice then return false end
    if listing.type ~= 'sale' and listing.type ~= 'auction' and listing.type ~= 'offer' then return false end

    local existing = MySQL.scalar.await("SELECT id FROM properties_listings WHERE property_id = ? AND status IN ('active','finalizing')", {propertyId})
    if existing then return false end

    local auctionEnd, reserve, increment
    if listing.type == 'auction' then
        local hours = ToId(listing.hours) or market.auctionHours
        if not lib.table.contains(market.auctionDurations, hours) then return false end
        auctionEnd = os.date('%Y-%m-%d %H:%M:%S', os.time() + hours * 3600)

        reserve = listing.reserve and ToId(listing.reserve) or nil
        if reserve and (reserve < price or reserve > market.maxPrice) then return false end

        increment = listing.increment and ToId(listing.increment) or market.minIncrement
        if increment < 1 or increment > market.maxPrice then return false end
    end

    return MySQL.insert.await([[
        INSERT INTO `properties_listings` (`property_id`, `listed_by`, `listing_type`, `price`, `reserve_price`, `min_increment`, `auction_end`)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {propertyId, player.PlayerData.citizenid, listing.type, price, reserve, increment or market.minIncrement, auctionEnd}) ~= nil
end

lib.callback.register('qbx_properties:callback:createListing', function(source, data)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or type(data) ~= 'table' then return false end
    if not IsRealtor(player.PlayerData.job) then return false end

    local propertyId = ToId(data.propertyId)
    local price = ToId(data.price)
    if not propertyId or not price then return false end
    if price < market.minPrice or price > market.maxPrice then return false end
    if data.listingType ~= 'sale' and data.listingType ~= 'auction' and data.listingType ~= 'offer' then return false end

    local property = MySQL.single.await('SELECT id, property_name, owner FROM properties WHERE id = ?', {propertyId})
    if not property then return false end
    if property.owner then
        exports.qbx_core:Notify(source, 'That property already has an owner.', 'error')
        return false
    end

    local existing = MySQL.scalar.await("SELECT id FROM properties_listings WHERE property_id = ? AND status IN ('active','finalizing')", {propertyId})
    if existing then return false end

    local auctionEnd, reserve, increment
    if data.listingType == 'auction' then
        local hours = ToId(data.auctionHours) or market.auctionHours
        if hours < 1 or hours > market.maxAuctionHours then return false end
        auctionEnd = os.date('%Y-%m-%d %H:%M:%S', os.time() + hours * 3600)

        reserve = data.reservePrice and ToId(data.reservePrice) or nil
        if reserve and (reserve < price or reserve > market.maxPrice) then return false end

        increment = data.minIncrement and ToId(data.minIncrement) or market.minIncrement
        if increment < 1 or increment > market.maxPrice then return false end
    end

    local listingId = MySQL.insert.await([[
        INSERT INTO `properties_listings` (`property_id`, `listed_by`, `listing_type`, `price`, `reserve_price`, `min_increment`, `auction_end`)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {propertyId, player.PlayerData.citizenid, data.listingType, price, reserve, increment or market.minIncrement, auctionEnd})

    LogAction(source, 'qbx_properties:server:createListing', string.format('%s listed %s as %s for $%d', player.PlayerData.citizenid, property.property_name, data.listingType, price))

    return listingId ~= nil
end)

---@param listingId integer
---@param status string
local function refundActiveBids(listingId, status)
    local bids = MySQL.query.await("SELECT id, bidder, amount FROM properties_bids WHERE listing_id = ? AND status = 'active'", {listingId})
    for i = 1, #bids do
        MySQL.update.await("UPDATE properties_bids SET status = 'refunded' WHERE id = ?", {bids[i].id})
        payOut(bids[i].bidder, bids[i].amount, string.format('Auction refund (listing %d)', listingId))
    end
    MySQL.update.await('UPDATE properties_listings SET status = ? WHERE id = ?', {status, listingId})
end

lib.callback.register('qbx_properties:callback:cancelListing', function(source, listingId)
    local player = exports.qbx_core:GetPlayer(source)
    listingId = ToId(listingId)
    if not player or not listingId or not IsRealtor(player.PlayerData.job) then return false end

    local listing = getActiveListing(listingId)
    if not listing then return false end

    refundActiveBids(listingId, 'cancelled')

    LogAction(source, 'qbx_properties:server:cancelListing', string.format('%s cancelled listing %d', player.PlayerData.citizenid, listingId))

    return true
end)

lib.callback.register('qbx_properties:callback:buyListing', function(source, listingId)
    local player = exports.qbx_core:GetPlayer(source)
    listingId = ToId(listingId)
    if not player or not listingId then return false end

    local listing = getActiveListing(listingId)
    if not listing or listing.listing_type ~= 'sale' then
        exports.qbx_core:Notify(source, 'That listing is no longer available.', 'error')
        return false
    end

    local property = MySQL.single.await('SELECT coords, owner, type FROM properties WHERE id = ?', {listing.property_id})
    if not property then return false end

    if property.owner == player.PlayerData.citizenid then
        exports.qbx_core:Notify(source, 'This property is already yours.', 'error')
        return false
    end

    if not CanOwnAnotherProperty(player.PlayerData.citizenid, property.type) then
        exports.qbx_core:Notify(source, 'You already own the maximum number of properties of this type.', 'error')
        return false
    end

    local coords = json.decode(property.coords)
    if #(GetEntityCoords(GetPlayerPed(source)) - vec3(coords.x, coords.y, coords.z)) > 30.0 then
        exports.qbx_core:Notify(source, 'You are too far away — go to the property to buy it.', 'error')
        return false
    end

    if MySQL.update.await("UPDATE properties_listings SET status = 'finalizing' WHERE id = ? AND status = 'active'", {listingId}) ~= 1 then return false end

    local account = player.PlayerData.money.cash >= listing.price and 'cash' or 'bank'
    if not player.Functions.RemoveMoney(account, listing.price, string.format('Purchased listing %d', listingId)) then
        MySQL.update.await("UPDATE properties_listings SET status = 'active' WHERE id = ?", {listingId})
        exports.qbx_core:Notify(source, 'Not enough money to purchase property.', 'error')
        return false
    end

    if not transferProperty(listing.property_id, player.PlayerData.citizenid, listing.price) then
        player.Functions.AddMoney(account, listing.price, 'Property purchase refund')
        MySQL.update.await("UPDATE properties_listings SET status = 'active' WHERE id = ?", {listingId})
        return false
    end

    MySQL.update.await("UPDATE properties_listings SET status = 'sold' WHERE id = ?", {listingId})

    LogAction(source, 'qbx_properties:server:buyListing', string.format('%s bought listing %d for $%d', player.PlayerData.citizenid, listingId, listing.price))

    return true
end)

---@param playerSource integer
---@param citizenId string
---@param listingId integer
---@param amount integer
---@return boolean, string?
lib.callback.register('qbx_properties:callback:placeOffer', function(source, listingId, amount)
    local player = exports.qbx_core:GetPlayer(source)
    listingId = ToId(listingId)
    amount = ToId(amount)
    if not player or not listingId or not amount then return false, 'Invalid offer.' end

    local citizenId = player.PlayerData.citizenid
    local offerType = MySQL.scalar.await('SELECT p.type FROM properties_listings l JOIN properties p ON p.id = l.property_id WHERE l.id = ?', {listingId})
    if not CanOwnAnotherProperty(citizenId, offerType) then return false, 'You already own the maximum number of properties of this type.' end

    local listing = getActiveListing(listingId)
    if not listing or listing.listing_type ~= 'offer' then return false, 'Listing not found.' end
    if listing.listed_by == citizenId then return false, 'You cannot make an offer on your own listing.' end
    if amount < listing.price then return false, string.format('Offers start at $%d.', listing.price) end
    if amount > market.maxPrice then return false, 'That offer is too high.' end

    local previous = MySQL.single.await("SELECT id, amount FROM properties_bids WHERE listing_id = ? AND bidder = ? AND status = 'active'", {listingId, citizenId})

    if player.PlayerData.money.bank < amount then return false, 'Not enough money in your bank.' end
    if not player.Functions.RemoveMoney('bank', amount, string.format('Offer on listing %d', listingId)) then
        return false, 'Not enough money in your bank.'
    end

    if previous then
        MySQL.update.await("UPDATE properties_bids SET status = 'refunded' WHERE id = ?", {previous.id})
        payOut(citizenId, previous.amount, string.format('Replaced offer (listing %d)', listingId))
    end

    MySQL.insert.await("INSERT INTO `properties_bids` (`listing_id`, `bidder`, `amount`) VALUES (?, ?, ?)", {listingId, citizenId, amount})

    LogAction(source, 'qbx_properties:server:placeOffer', string.format('%s offered $%d on listing %d', citizenId, amount, listingId))

    return true
end)

---@param source integer
---@param listingId integer?
---@param bidId integer?
---@param accept boolean
---@return boolean
local function settleOffer(source, listingId, bidId, accept)
    local player = exports.qbx_core:GetPlayer(source)
    listingId = ToId(listingId)
    bidId = ToId(bidId)
    if not player or not listingId or not bidId or not IsRealtor(player.PlayerData.job) then return false end

    local listing = getActiveListing(listingId)
    if not listing or listing.listing_type ~= 'offer' then return false end

    local bid = MySQL.single.await("SELECT id, bidder, amount FROM properties_bids WHERE id = ? AND listing_id = ? AND status = 'active'", {bidId, listingId})
    if not bid then return false end

    if not accept then
        MySQL.update.await("UPDATE properties_bids SET status = 'refunded' WHERE id = ?", {bid.id})
        payOut(bid.bidder, bid.amount, string.format('Offer declined (listing %d)', listingId))

        local bidder = exports.qbx_core:GetPlayerByCitizenId(bid.bidder)
        if bidder then
            exports.qbx_core:Notify(bidder.PlayerData.source, 'Your property offer was declined and refunded.', 'error')
        end
        LogAction(source, 'qbx_properties:server:declineOffer', string.format('declined offer %d on listing %d', bid.id, listingId))
        return true
    end

    if MySQL.update.await("UPDATE properties_listings SET status = 'finalizing' WHERE id = ? AND status = 'active'", {listingId}) ~= 1 then return false end

    MySQL.update.await("UPDATE properties_bids SET status = 'won' WHERE id = ?", {bid.id})

    if not transferProperty(listing.property_id, bid.bidder, bid.amount) then
        MySQL.update.await("UPDATE properties_bids SET status = 'refunded' WHERE id = ?", {bid.id})
        payOut(bid.bidder, bid.amount, string.format('Offer failed (listing %d)', listingId))
        MySQL.update.await("UPDATE properties_listings SET status = 'active' WHERE id = ?", {listingId})

        local bidder = exports.qbx_core:GetPlayerByCitizenId(bid.bidder)
        if bidder then
            exports.qbx_core:Notify(bidder.PlayerData.source, 'Your offer could not be completed and was refunded — you may own the maximum number of properties.', 'error')
        end
        exports.qbx_core:Notify(source, 'The sale could not be completed, the buyer may own too many properties already.', 'error')
        return false
    end

    refundActiveBids(listingId, 'refunded')
    MySQL.update.await("UPDATE properties_listings SET status = 'sold' WHERE id = ?", {listingId})

    local buyer = exports.qbx_core:GetPlayerByCitizenId(bid.bidder)
    if buyer then
        exports.qbx_core:Notify(buyer.PlayerData.source, string.format('Your offer of $%d was accepted, the property is yours.', bid.amount), 'success')
    end

    LogAction(source, 'qbx_properties:server:acceptOffer', string.format('%s accepted offer %d ($%d) on listing %d', player.PlayerData.citizenid, bid.id, bid.amount, listingId))

    return true
end

lib.callback.register('qbx_properties:callback:acceptOffer', function(source, listingId, bidId)
    return settleOffer(source, listingId, bidId, true)
end)

lib.callback.register('qbx_properties:callback:declineOffer', function(source, listingId, bidId)
    return settleOffer(source, listingId, bidId, false)
end)

local bidLocks = {}
local executeBidLocked

local function executeBid(playerSource, citizenId, listingId, amount)
    amount = ToId(amount)
    if not amount or amount <= 0 then return false, 'Invalid bid amount.' end

    local propertyType = MySQL.scalar.await('SELECT p.type FROM properties_listings l JOIN properties p ON p.id = l.property_id WHERE l.id = ?', {listingId})
    if not CanOwnAnotherProperty(citizenId, propertyType) then return false, 'You already own the maximum number of properties of this type.' end

    if bidLocks[listingId] then return false, 'Another bid is being processed, try again.' end
    bidLocks[listingId] = true

    local ok, err = executeBidLocked(playerSource, citizenId, listingId, amount)
    bidLocks[listingId] = nil
    return ok, err
end

executeBidLocked = function(playerSource, citizenId, listingId, amount)
    local listing = getActiveListing(listingId)
    if not listing or listing.listing_type ~= 'auction' then return false, 'Auction not found.' end
    if listing.listed_by == citizenId then return false, 'You cannot bid on your own listing.' end

    local endTime = MySQL.scalar.await('SELECT UNIX_TIMESTAMP(auction_end) FROM properties_listings WHERE id = ?', {listingId})
    if not endTime or os.time() >= endTime then return false, 'This auction has ended.' end

    local top = getTopBid(listingId)
    local minimum = (top and top.amount or listing.price) + listing.min_increment
    if amount < minimum then return false, string.format('Minimum bid is $%d.', minimum) end

    local player = exports.qbx_core:GetPlayer(playerSource)
    if not player then return false, 'Player not found.' end
    if player.PlayerData.money.bank < amount then return false, 'Not enough money in your bank.' end

    if MySQL.scalar.await("SELECT status FROM properties_listings WHERE id = ?", {listingId}) ~= 'active' then
        return false, 'This auction has ended.'
    end

    if not player.Functions.RemoveMoney('bank', amount, string.format('Auction bid (listing %d)', listingId)) then
        return false, 'Not enough money in your bank.'
    end

    if top then
        MySQL.update.await("UPDATE properties_bids SET status = 'outbid' WHERE id = ?", {top.id})
        payOut(top.bidder, top.amount, string.format('Outbid refund (listing %d)', listingId))

        local outbidPlayer = exports.qbx_core:GetPlayerByCitizenId(top.bidder)
        if outbidPlayer and top.bidder ~= citizenId then
            exports.qbx_core:Notify(outbidPlayer.PlayerData.source, string.format('You were outbid on listing %d. Your $%d has been returned.', listingId, top.amount), 'warning')
        end
    end

    MySQL.insert.await("INSERT INTO `properties_bids` (`listing_id`, `bidder`, `amount`) VALUES (?, ?, ?)", {listingId, citizenId, amount})

    local remaining = endTime - os.time()
    if remaining < market.antiSnipeMinutes * 60 then
        MySQL.update.await('UPDATE properties_listings SET auction_end = ? WHERE id = ?', {
            os.date('%Y-%m-%d %H:%M:%S', os.time() + market.antiSnipeMinutes * 60), listingId
        })
    end

    LogAction(playerSource, 'qbx_properties:server:placeBid', string.format('%s bid $%d on listing %d', citizenId, amount, listingId))

    return true
end

lib.callback.register('qbx_properties:callback:placeBid', function(source, listingId, amount)
    local player = exports.qbx_core:GetPlayer(source)
    listingId, amount = ToId(listingId), ToId(amount)
    if not player or not listingId or not amount or amount <= 0 then return false end

    local ok, err = executeBid(source, player.PlayerData.citizenid, listingId, amount)
    if not ok and err then exports.qbx_core:Notify(source, err, 'error') end
    if ok then exports.qbx_core:Notify(source, 'Bid placed.', 'success') end
    return ok
end)

lib.callback.register('qbx_properties:callback:getNearbyClients', function(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or not IsRealtor(player.PlayerData.job) then return {} end

    local coords = GetEntityCoords(GetPlayerPed(source))
    local nearby = {}
    for _, playerId in ipairs(GetPlayers()) do
        local id = tonumber(playerId) --[[@as number]]
        if id ~= source and #(GetEntityCoords(GetPlayerPed(id)) - coords) <= market.agentBidRange then
            local target = exports.qbx_core:GetPlayer(id)
            if target then
                nearby[#nearby + 1] = {
                    serverId = id,
                    name = string.format('%s %s', target.PlayerData.charinfo.firstname, target.PlayerData.charinfo.lastname),
                }
            end
        end
    end
    return nearby
end)

lib.callback.register('qbx_properties:callback:agentRequestBid', function(source, data)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or type(data) ~= 'table' or not IsRealtor(player.PlayerData.job) then return false end

    local listingId, amount, target = ToId(data.listingId), ToId(data.amount), ToId(data.targetServerId)
    if not listingId or not amount or not target or amount <= 0 then return false end
    if not GetPlayerName(target) then return false end
    if #(GetEntityCoords(GetPlayerPed(source)) - GetEntityCoords(GetPlayerPed(target))) > market.agentBidRange then return false end
    if not getActiveListing(listingId) then return false end

    pendingAgentBids[target] = {
        listingId = listingId,
        amount = amount,
        agentSource = source,
        expires = os.time() + 60,
    }

    TriggerClientEvent('qbx_properties:client:agentBidRequest', target, {
        agent = string.format('%s %s', player.PlayerData.charinfo.firstname, player.PlayerData.charinfo.lastname),
        amount = amount,
        listingId = listingId,
    })

    return true
end)

RegisterNetEvent('qbx_properties:server:agentBidConfirm', function(accepted)
    local playerSource = source --[[@as number]]
    local request = pendingAgentBids[playerSource]
    pendingAgentBids[playerSource] = nil

    if not request or os.time() > request.expires then return end

    local agentOnline = GetPlayerName(request.agentSource) ~= nil
    if not accepted then
        if agentOnline then exports.qbx_core:Notify(request.agentSource, 'Your client declined the bid.', 'error') end
        return
    end

    if not agentOnline or #(GetEntityCoords(GetPlayerPed(request.agentSource)) - GetEntityCoords(GetPlayerPed(playerSource))) > market.agentBidRange then
        exports.qbx_core:Notify(playerSource, 'The realtor is no longer nearby.', 'error')
        return
    end

    local player = exports.qbx_core:GetPlayer(playerSource)
    if not player then return end

    local ok, err = executeBid(playerSource, player.PlayerData.citizenid, request.listingId, request.amount)
    if ok then
        exports.qbx_core:Notify(playerSource, string.format('Bid of $%d placed.', request.amount), 'success')
        if agentOnline then exports.qbx_core:Notify(request.agentSource, 'Bid placed for your client.', 'success') end
    else
        if err then exports.qbx_core:Notify(playerSource, err, 'error') end
        if agentOnline then exports.qbx_core:Notify(request.agentSource, err or 'The bid could not be placed.', 'error') end
    end
end)

AddEventHandler('playerDropped', function()
    pendingAgentBids[source] = nil
end)

local function finalizeAuctions()
    AwaitMigration()
    MySQL.update.await("UPDATE properties_listings SET status = 'finalizing' WHERE listing_type = 'auction' AND status = 'active' AND auction_end <= NOW()")
    local ended = MySQL.query.await("SELECT * FROM properties_listings WHERE listing_type = 'auction' AND status = 'finalizing'")

    for i = 1, #ended do
        local listing = ended[i]
        local ok, err = pcall(function()
            local top = getTopBid(listing.id)
            local reserveMet = top and (not listing.reserve_price or top.amount >= listing.reserve_price)

            if not top or not reserveMet then
                if top then
                    MySQL.update.await("UPDATE properties_bids SET status = 'refunded' WHERE id = ?", {top.id})
                    payOut(top.bidder, top.amount, string.format('Reserve not met (listing %d)', listing.id))
                end
                MySQL.update.await("UPDATE properties_listings SET status = 'expired' WHERE id = ? AND status = 'finalizing'", {listing.id})
                return
            end

            if MySQL.update.await("UPDATE properties_listings SET status = 'sold' WHERE id = ? AND status = 'finalizing'", {listing.id}) ~= 1 then return end

            MySQL.update.await("UPDATE properties_bids SET status = 'won' WHERE id = ?", {top.id})

            if not transferProperty(listing.property_id, top.bidder, top.amount) then
                MySQL.update.await("UPDATE properties_bids SET status = 'refunded' WHERE id = ?", {top.id})
                payOut(top.bidder, top.amount, string.format('Auction refund (listing %d)', listing.id))
                MySQL.update.await("UPDATE properties_listings SET status = 'expired' WHERE id = ?", {listing.id})

                local refunded = exports.qbx_core:GetPlayerByCitizenId(top.bidder)
                if refunded then
                    exports.qbx_core:Notify(refunded.PlayerData.source, 'You already own the maximum number of properties — your winning bid was refunded.', 'error')
                end
                return
            end

            local winner = exports.qbx_core:GetPlayerByCitizenId(top.bidder)
            if winner then
                exports.qbx_core:Notify(winner.PlayerData.source, string.format('You won the auction for $%d.', top.amount), 'success')
            end

            LogAction(0, 'qbx_properties:server:auctionWon', string.format('%s won listing %d for $%d', top.bidder, listing.id, top.amount))
        end)

        if not ok then lib.print.warn(('failed to finalize listing %d: %s'):format(listing.id, err)) end
    end
end

lib.cron.new('* * * * *', finalizeAuctions)
