return {
    -- Property photo uploads. Without an apiKey the Take photo button stays disabled.
    -- The furniture catalog screenshots use the same provider, see the readme.
    imageUpload = {
        provider = 'qbox', -- 'qbox', 'fivemanage', 'fivemerr' or 'custom'
        apiKey = '',
        maxImages = 5,
        autoUpload = false, -- upload every furniture catalog shot to the CDN as it is saved

        custom = { -- only used with provider = 'custom'
            url = '',
            field = 'file',
            responsePath = 'data.url', -- where the image url lives in the json response
            storagePath = nil, -- response field holding the id/path needed for deletion
            deleteUrl = nil, -- delete endpoint, %s is replaced with the stored id/path
        },
    },

    logging = {
        discordWebhook = '', -- set a Discord webhook url to send all action logs there instead of ox_lib's logger
    },

    apartmentStash = {
        slots = 50,
        maxWeight = 150000
    },
    marketSociety = 'realestate', -- society that receives proceeds when a listed property has no owner, nil to disable
    governmentAccount = 'government', -- receives utility bills and the non-commission share of rent, nil to disable
}