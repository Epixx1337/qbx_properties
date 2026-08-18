return {
    -- Qbox CDN (https://docs.qbox.re/dashboard/cdn). Set your own API key or photos stay disabled.
    imageUpload = {
        url = 'https://api.qbox.re/v1/file',
        field = 'file',
        headers = {
            Authorization = '', -- your Qbox CDN API key
        },
        responsePath = 'data.url',
        maxImages = 5,
    },

    apartmentStash = {
        slots = 50,
        maxWeight = 150000
    },
    marketSociety = 'realestate', -- society that receives proceeds when a listed property has no owner, nil to disable
    governmentAccount = 'government', -- receives utility bills and the non-commission share of rent, nil to disable
}