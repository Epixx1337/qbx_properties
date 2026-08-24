return {
    -- Shell streaming
    shellUndergroundOffset = 50.0,
    shellStreamDistance = 60.0,

    -- Realtors
    realtorJobs = { -- job name mapped to the minimum grade level allowed to manage properties
        realestate = 0,
    },
    realtorRequiresDuty = true,
    commission = {
        sale = 0.05,
        rent = 0.10,
    },

    -- Interaction & UI
    housingCommand = true, -- false removes /housing, open it through the openHousing export or an embedded app instead
    logoutEnabled = true, -- beds and logout points let players switch character, false hides them everywhere
    targetInteractions = true, -- MLO furniture uses ox_target labels instead of floating interaction points
    freecamRange = 10.0, -- how far the decorating freecam may drift from the player
    nuiGizmo = false, -- camera-projected gizmo drawn by the UI, false uses the engine gizmo
    furnitureShop = true, -- false ignores furniture prices, everything places instantly for free
    furnitureImageSource = 'local', -- 'cdn' lazy-loads catalog thumbnails from the uploaded copies, run /screenshotfurniture upload first

    -- Apartments
    dynamicApartments = true,
    freeApartmentMoves = true, -- reception lets tenants switch buildings, false locks them to their current home
    migrationOffer = true, -- one-time login offer to relocate when other buildings have free rooms

    -- Garages
    garageSystem = 'qbx', -- 'qbx' registers with qbx_garages, any other value must match an adapter in config/garages.lua
    apartmentGarageBlip = { sprite = 357, color = 3 },
    apartmentGarageUseRadius = 1.5, -- each bay doubles as the menu and the park point; keep under half the tightest bay spacing (3.41m at Wiwang)
    apartmentGarages = { -- one garage per complex, every bay is an access point so tenants never queue for the same spot
        -- `name` is stored on every parked vehicle, never change it or those vehicles become unreachable
        {
            name = 'apartment_delperro',
            label = 'Del Perro Heights Parking',
            interiors = { 'DellPerroHeightsApt4', 'DellPerroHeightsApt7' },
            spots = {
                vec4(-1429.4, -581.19, 29.59, 116.41),
                vec4(-1436.13, -584.84, 29.66, 121.79),
                vec4(-1410.64, -531.9, 30.41, 211.2),
                vec4(-1415.44, -525.2, 30.82, 212.39),
                vec4(-1421.09, -516.8, 31.33, 214.01),
                vec4(-1426.42, -510.79, 31.69, 213.63),
                vec4(-1431.84, -502.94, 32.17, 210.48),
                vec4(-1437.03, -494.75, 32.64, 210.8),
            },
        },
        {
            name = 'apartment_integrityway',
            label = '4 Integrity Way Parking',
            interiors = { '4IntegrityWayApt28', '4IntegrityWayApt30' },
            spots = {
                vec4(-79.65, -634.43, 35.17, 339.52),
                vec4(-77.1, -626.82, 35.18, 339.94),
                vec4(-74.59, -619.9, 35.17, 339.95),
                vec4(-72.69, -613.05, 35.2, 341.3),
                vec4(-70.35, -606.28, 35.19, 340.05),
                vec4(-67.8, -599.39, 35.21, 327.17),
                vec4(-64.58, -589.79, 35.19, 332.18),
                vec4(-61.45, -580.69, 35.75, 341.18),
            },
        },
        {
            name = 'apartment_richardmajestic',
            label = 'Richard Majestic Parking',
            interiors = { 'RichardMajesticApt2' },
            spots = {
                vec4(-890.68, -392.56, 37.62, 113.05),
                vec4(-897.02, -395.26, 37.36, 100.55),
                vec4(-902.19, -397.65, 37.15, 114.89),
                vec4(-907.78, -400.29, 36.94, 105.38),
                vec4(-913.34, -402.99, 36.77, 110.06),
                vec4(-918.31, -405.44, 36.63, 116.7),
                vec4(-923.88, -408.26, 36.53, 116.63),
                vec4(-929.85, -411.38, 36.5, 117.43),
                vec4(-935.16, -414.18, 36.53, 113.08),
            },
        },
        {
            name = 'apartment_tinseltowers',
            label = 'Tinsel Towers Parking',
            interiors = { 'TinselTowersApt42' },
            spots = {
                vec4(-571.37, 10.75, 43.03, 97.58),
                vec4(-577.8, 9.2, 42.88, 83.91),
                vec4(-583.34, 8.42, 42.85, 96.07),
                vec4(-589.54, 7.64, 42.59, 85.34),
                vec4(-595.77, 6.82, 42.24, 89.16),
                vec4(-601.82, 5.96, 41.86, 93.91),
                vec4(-608.16, 5.21, 41.42, 89.11),
                vec4(-614.94, 4.36, 40.96, 97.39),
            },
        },
        {
            name = 'apartment_wiwang',
            label = 'Wiwang Hotel Parking',
            buildings = { 'wiwang' },
            spots = {
                vec4(-809.85, -768.2, 20.31, 86.68),
                vec4(-809.86, -764.19, 20.66, 85.88),
                vec4(-810.11, -760.65, 20.99, 88.6),
                vec4(-810.58, -756.85, 21.35, 86.36),
                vec4(-810.75, -753.46, 21.67, 86.49),
                vec4(-822.29, -768.11, 20.32, 267.87),
                vec4(-821.85, -764.36, 20.65, 268.75),
                vec4(-821.71, -760.57, 21.02, 271.75),
                vec4(-821.36, -757.16, 21.34, 264.34),
                vec4(-829.65, -756.89, 21.37, 77.65),
                vec4(-829.86, -760.76, 21.02, 91.05),
                vec4(-829.53, -764.31, 20.66, 87.34),
                vec4(-829.76, -768.21, 20.32, 85.77),
                vec4(-841.53, -771.99, 20.0, 264.08),
                vec4(-841.32, -768.12, 20.33, 266.91),
                vec4(-841.8, -764.24, 20.67, 268.53),
                vec4(-841.0, -760.44, 21.07, 269.47),
            },
        },
    },

    -- Market
    market = {
        minPrice = 1000,
        maxPrice = 100000000,
        minIncrement = 1000,
        auctionHours = 72,
        maxAuctionHours = 72,
        auctionDurations = { 24, 48, 72 },
        antiSnipeMinutes = 5,
        agentBidRange = 6.0,
        anonymousBids = true,
        sellRange = 5.0,
    },

    -- Gardens
    gardens = {
        enabled = true,
        furnitureLimit = 40,
        streamDistance = 80.0,
        maxPoints = 20,
        height = 2.0, -- maximum build height inside the zone
    },

    -- Property sizes
    propertySizes = {
        small = { label = 'Small', power = 5000, cost = 750 },
        medium = { label = 'Medium', power = 10000, cost = 1500 },
        large = { label = 'Large', power = 20000, cost = 3000 },
        mansion = { label = 'Mansion', power = 40000, cost = 6000 },
    },
    propertySizeOrder = { 'small', 'medium', 'large', 'mansion' },
    defaultPropertySize = 'medium',

    -- Utilities
    utilities = {
        enabled = true,
        billingDays = 30,
        gracePeriodDays = 3,

        apartment = {
            power = 4000,
            cost = 0,
        },

        humidity = {
            base = 40,
            perKilowatt = 0.004,
            max = 100,
            comfortable = 60,
        },
    },

    -- Wall colors
    wallColors = {
        enabled = true,
        entitySet = 'wall_tint',
        probeLength = 50.0, -- keeps taller interiors loaded when high up inside them
        palette = {
            { index = 0, label = 'White', hex = 'F1F1F1' },
            { index = 1, label = 'Light Beige', hex = 'DFD7CD' },
            { index = 2, label = 'Dark Beige', hex = 'E1BE8E' },
            { index = 3, label = 'Orange', hex = 'EBAB69' },
            { index = 4, label = 'Baby Blue', hex = '7E9AB1' },
            { index = 5, label = 'Satin Blue', hex = '736DD2' },
            { index = 6, label = 'Navy Blue', hex = '38356E' },
            { index = 7, label = 'Maroon Red', hex = 'A85E53' },
            { index = 8, label = 'Red', hex = 'F13B59' },
            { index = 9, label = 'Burgundy Red', hex = '8E4D58' },
            { index = 10, label = 'Earthy Green', hex = '96A08A' },
            { index = 11, label = 'Dull Green', hex = '646F69' },
            { index = 12, label = 'Purple', hex = '473C5B' },
            { index = 13, label = 'Light Pink', hex = 'D5A6DE' },
            { index = 14, label = 'Grey', hex = '6B6A6C' },
            { index = 15, label = 'Dark Grey', hex = '343435' },
            { index = 16, label = 'Light Blue', hex = 'C1CDE0' },
            { index = 17, label = 'Dark Green', hex = '023020' },
            { index = 18, label = 'Aqua Blue', hex = '4FEDE5' },
            { index = 19, label = 'Blue', hex = '62C1E5' },
            { index = 20, label = 'Geraldine Red', hex = 'FF7B7B' },
            { index = 21, label = 'Black', hex = '000000' },
            { index = 22, label = 'Yellow', hex = 'FFEE8C' },
            { index = 23, label = 'Light Grey', hex = 'C0C0C0' },
            { index = 24, label = 'Forest Green', hex = '012D21' },
            { index = 25, label = 'Pink', hex = 'E190B7' },
            { index = 26, label = 'Lime Green', hex = 'A2E783' },
            { index = 27, label = 'Green', hex = '49862E' },
            { index = 28, label = 'Deep Red', hex = '5E0606' },
            { index = 29, label = 'Brown', hex = '653E21' },
            { index = 30, label = 'Tea Green', hex = 'D5F3C6' },
            { index = 31, label = 'Light Purple', hex = 'AE4BFF' },
        },
    },
}
