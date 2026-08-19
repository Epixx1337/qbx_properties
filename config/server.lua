return {
    -- Property photo uploads. Without an apiKey the Take photo button stays disabled.
    imageUpload = {
        provider = 'qbox', -- 'qbox', 'fivemanage', 'fivemerr' or 'custom'
        apiKey = '',
        maxImages = 5,

        custom = { -- only used with provider = 'custom'
            url = '',
            field = 'file',
            responsePath = 'data.url', -- where the image url lives in the json response
            storagePath = nil, -- response field holding the id/path needed for deletion
            deleteUrl = nil, -- delete endpoint, %s is replaced with the stored id/path
        },
    },

    apartmentStash = {
        slots = 50,
        maxWeight = 150000
    },
    marketSociety = 'realestate', -- society that receives proceeds when a listed property has no owner, nil to disable
    governmentAccount = 'government', -- receives utility bills and the non-commission share of rent, nil to disable
}