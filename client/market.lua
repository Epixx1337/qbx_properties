local sharedConfig = require 'config.shared'

local function pushListings()
    local listings = lib.callback.await('qbx_properties:callback:getListings', false)
    SendUI('market:listings', listings)
    SendUIEmbedded('market:listings', listings)
end

RegisterNUICallback('market:refresh', function(_, cb)
    cb(1)
    pushListings()
end)

function OpenHousing()
    OpenUI('housing')
    SendUI('market:init', {
        listings = lib.callback.await('qbx_properties:callback:getListings', false),
        config = sharedConfig.market,
        sizes = sharedConfig.propertySizes,
        sizeOrder = sharedConfig.propertySizeOrder,
        gardens = sharedConfig.gardens.enabled,
        types = sharedConfig.propertyTypes,
    })

    if IsRealtor(QBX.PlayerData.job) or CanUseCreator() then
        SendRealtorData()
    end
end

RegisterNUICallback('market:bid', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end
    lib.callback.await('qbx_properties:callback:placeBid', false, data.listingId, data.amount)
    pushListings()
end)

RegisterNUICallback('market:buy', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    if lib.callback.await('qbx_properties:callback:buyListing', false, data.listingId) then
        lib.notify({ type = 'success', description = 'Property purchased.' })
    end
    pushListings()
end)

RegisterNUICallback('market:getBids', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end
    local bids = lib.callback.await('qbx_properties:callback:getListingBids', false, data.listingId)
    SendUI('market:bids', bids)
    SendUIEmbedded('market:bids', bids)
end)

RegisterNUICallback('market:getNearbyClients', function(_, cb)
    cb(1)
    SendUI('market:nearbyClients', lib.callback.await('qbx_properties:callback:getNearbyClients', false))
end)

RegisterNUICallback('market:agentBid', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    if lib.callback.await('qbx_properties:callback:agentRequestBid', false, data) then
        lib.notify({ type = 'info', description = 'Awaiting client confirmation.' })
    else
        lib.notify({ type = 'error', description = 'Could not send the bid request.' })
    end
end)

RegisterNUICallback('market:placeOffer', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    local ok, err = lib.callback.await('qbx_properties:callback:placeOffer', false, data.listingId, data.amount)
    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and 'Offer placed, the money is held until it settles.' or err or 'Could not place the offer.',
    })
    pushListings()
end)

RegisterNUICallback('market:acceptOffer', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    local ok = lib.callback.await('qbx_properties:callback:acceptOffer', false, data.listingId, data.bidId)
    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and 'Offer accepted.' or 'Could not accept the offer.',
    })
    pushListings()
end)

RegisterNUICallback('market:declineOffer', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    local ok = lib.callback.await('qbx_properties:callback:declineOffer', false, data.listingId, data.bidId)
    lib.notify({
        type = ok and 'success' or 'error',
        description = ok and 'Offer declined and refunded.' or 'Could not decline the offer.',
    })
    SendUI('market:bids', lib.callback.await('qbx_properties:callback:getListingBids', false, data.listingId))
    pushListings()
end)

RegisterNUICallback('market:cancelListing', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end

    if lib.callback.await('qbx_properties:callback:cancelListing', false, data.listingId) then
        lib.notify({ type = 'success', description = 'Listing cancelled.' })
    end
    pushListings()
end)

RegisterNetEvent('qbx_properties:client:agentBidRequest', function(data)
    local confirm = lib.alertDialog({
        header = 'Bid request',
        content = string.format(
            '**%s** wants to place a bid of **$%s** on your behalf.  \nThe money leaves your bank immediately and is returned in full if you are outbid.',
            data.agent, data.amount
        ),
        centered = true,
        cancel = true,
    })

    TriggerServerEvent('qbx_properties:server:agentBidConfirm', confirm == 'confirm')
end)

RegisterNetEvent('qbx_properties:client:openHousing', function()
    OpenHousing()
end)

exports('openHousing', OpenHousing)

RegisterNUICallback('housing:embed', function(_, cb)
    cb(1)
    OpenUIEmbedded('housing')
    SendUIEmbedded('market:init', {
        listings = lib.callback.await('qbx_properties:callback:getListings', false),
        config = sharedConfig.market,
        sizes = sharedConfig.propertySizes,
        sizeOrder = sharedConfig.propertySizeOrder,
        gardens = sharedConfig.gardens.enabled,
        types = sharedConfig.propertyTypes,
    })
end)
