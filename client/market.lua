local sharedConfig = require 'config.shared'

local function pushListings()
    SendUI('market:listings', lib.callback.await('qbx_properties:callback:getListings', false))
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
    SendUI('market:bids', lib.callback.await('qbx_properties:callback:getListingBids', false, data.listingId))
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
