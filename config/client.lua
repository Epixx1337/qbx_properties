return {
    -- Icons, labels and grouping for the furniture catalog categories. Keys match the category
    -- names under `furniture` below. `icon` takes any Font Awesome free class (fontawesome.com/icons),
    -- `order` sorts the icon row (lower first), and `parent` turns a category into a subcategory of
    -- another entry — parents that hold no furniture themselves (like structure) only need icon/label.
    -- Categories without an entry here fall back to a generic icon and their capitalised key.
    furnitureCategories = {
        utility = { label = 'Utility', icon = 'fa-solid fa-screwdriver-wrench', order = 1 },
        kitchen = { label = 'Kitchen', icon = 'fa-solid fa-utensils', order = 2 },
        lighting = { label = 'Lighting', icon = 'fa-solid fa-lightbulb', order = 3 },
        couches = { label = 'Couches', icon = 'fa-solid fa-couch', order = 4 },
        tables = { label = 'Tables', icon = 'fa-solid fa-table', order = 5 },
        beds = { label = 'Beds', icon = 'fa-solid fa-bed', order = 6 },
        structure = { label = 'Structure', icon = 'fa-solid fa-cubes', order = 7 },
        walls = { label = 'Walls', icon = 'fa-solid fa-grip-lines-vertical', parent = 'structure' },
        arches = { label = 'Arches', icon = 'fa-solid fa-archway', parent = 'structure' },
        stairs = { label = 'Stairs', icon = 'fa-solid fa-stairs', parent = 'structure' },
        floors = { label = 'Floors', icon = 'fa-solid fa-border-all', parent = 'structure' },
    },

    exteriorHashs = { -- Used for hiding the exterior when inside of an apartment IPL
        ['DellPerroHeightsApt4'] = {`sm_14_emissive`, `hei_sm_14_bld2`},
        ['DellPerroHeightsApt7'] = {`sm_14_emissive`, `hei_sm_14_bld2`},
        ['4IntegrityWayApt28'] = {`hei_dt1_03_build1x`, `DT1_Emissive_DT1_03_b1`, `dt1_03_dt1_Emissive_b1`},
        ['4IntegrityWayApt30'] = {`hei_dt1_03_build1x`, `DT1_Emissive_DT1_03_b1`, `dt1_03_dt1_Emissive_b1`},
        ['RichardMajesticApt2'] = {`hei_bh1_08_bld2`, `bh1_emissive_bh1_08`, `bh1_08_bld2_LOD`, `hei_bh1_08_bld2`, `bh1_08_em`},
        ['TinselTowersApt42'] = {`apa_ss1_02_building01`, `SS1_02_Building01_LOD`},
    },
    furniture = {
        utility = {
            {
                object = 'v_res_tre_wardrobe',
                label = 'Wardrobe',
                type = 'wardrobe',
                price = 1000,
                firstFree = true,
                power = 1200,
                humidity = -25,
            },
            {
                object = 'prop_ld_int_safe_01',
                label = 'Safe',
                type = 'stash',
                price = 2500,
                firstFree = true,
                slots = 15,
                maxWeight = 30000,
            },
            {
                object = 'prop_toolchest_05',
                label = 'Tool Chest',
                type = 'stash',
                slots = 50,
                maxWeight = 100000,
            },
            {
                object = 'cdx_intercom_prop',
                label = 'Housing Intercom',
                type = 'tablet',
                price = 500,
                firstFree = true,
                power = 20,
                tint = true, -- body recolours through the wall palette, tint 0 is the white default
            },
            {
                object = 'reh_prop_reh_tablet_01a',
                label = 'Housing Tablet',
                type = 'tablet',
                price = 500,
                firstFree = true,
                power = 20,
                screenshotCameraOffset = vec3(0.0, -1.66, 5.0),
                screenshotFov = 4.0,
            },
            {
                object = 'apa_v_ilev_fh_bedrmdoor',
                label = 'Bedroom Door',
                type = 'door',
            },
        },

        kitchen = {
            {
                object = 'prop_fridge_03',
                label = 'Double Fridge',
                type = 'fridge',
                price = 900,
                power = 450,
                slots = 10,
                maxWeight = 60000,
            },
            {
                object = 'v_res_tt_fridge',
                label = 'Retro Fridge',
                type = 'fridge',
                price = 650,
                power = 400,
                slots = 8,
                maxWeight = 45000,
            },
            {
                object = 'prop_trailr_fridge',
                label = 'Compact Fridge',
                type = 'fridge',
                price = 450,
                power = 350,
                slots = 6,
                maxWeight = 30000,
            },
            {
                object = 'prop_bin_01a',
                label = 'Wheelie Bin',
                type = 'trash',
                price = 100,
            },
            {
                object = 'prop_bin_07b',
                label = 'Steel Bin',
                type = 'trash',
                price = 150,
            },
        },

        lighting = {
            {
                object = 'ba_prop_battle_lights_wall_l_a',
                label = 'Garden Wall Lamp',
                power = 300,
                light = true,
            },
            {
                object = 'h4_prop_battle_lights_ceiling_l_c',
                label = 'Long Ceiling Lamp',
                power = 300,
                light = true,
            },
            {
                object = 'apa_mp_h_lit_floorlampnight_07',
                label = 'Blue Floor Lamp',
                power = 300,
                light = true,
            },
            {
                object = 'apa_mp_h_lit_floorlamp_17',
                label = 'Tripod Floor Lamp',
                power = 300,
                light = true,
            },
        },

        couches = {
            {
                object = 'prop_couch_sm_02',
                label = 'Medium Couch',
            },
            {
                object = 'v_res_tre_sofa_mess_a',
                label = 'Messy Couch 1',
            },
            {
                object = 'v_res_tre_sofa_mess_b',
                label = 'Messy Couch 2',
            },
            {
                object = 'v_res_tre_sofa_mess_c',
                label = 'Messy Couch 3',
            },
            {
                object = 'prop_couch_01',
                label = 'Pillow Couch',
            },
            {
                object = 'prop_couch_03',
                label = 'Old School Couch',
            },
            {
                object = 'prop_couch_04',
                label = 'Pillow & Blanket Couch',
            },
        },

        tables = {
            {
                object = 'hei_heist_tab_sidelrg_02',
                label = 'Glass Coffee Table',
            },
            {
                object = 'v_res_fh_diningtable',
                label = 'Dining Table',
            },
            {
                object = 'v_res_j_coffeetable',
                label = 'Wooden Coffee Table',
            },
        },

        beds = {
            {
                object = 'h4_mp_h_yacht_bed_02',
                label = 'Luxurious Bed',
                type = 'logout',
            },
            {
                object = 'v_res_tre_bed1',
                label = 'Normal Bed 1',
                type = 'logout',
            },
            {
                object = 'v_res_tre_bed2',
                label = 'Normal Bed 2',
                type = 'logout',
            },
            {
                object = 'v_res_tre_bed1_messy',
                label = 'Messy Normal Bed 2',
                type = 'logout',
            },
        },

        walls = {
            { object = 'qbx_wall_plaster_100', label = 'Plaster Wall 1m', price = 250, tint = true, snapGroup = 'structure' },
            { object = 'qbx_wall_brick_100', label = 'Brick Wall 1m', price = 250, tint = true, snapGroup = 'structure' },
            { object = 'qbx_wall_wood_100', label = 'Wood Wall 1m', price = 250, tint = true, snapGroup = 'structure' },
            { object = 'qbx_wall_concrete_100', label = 'Concrete Wall 1m', price = 250, tint = true, snapGroup = 'structure' },
            { object = 'qbx_wall_plaster_200', label = 'Plaster Wall 2m', price = 250, tint = true, snapGroup = 'structure' },
            { object = 'qbx_wall_brick_200', label = 'Brick Wall 2m', price = 250, tint = true, snapGroup = 'structure' },
            { object = 'qbx_wall_wood_200', label = 'Wood Wall 2m', price = 250, tint = true, snapGroup = 'structure' },
            { object = 'qbx_wall_concrete_200', label = 'Concrete Wall 2m', price = 250, tint = true, snapGroup = 'structure' },
            { object = 'qbx_wall_plaster_400', label = 'Plaster Wall 4m', price = 250, tint = true, snapGroup = 'structure' },
            { object = 'qbx_wall_brick_400', label = 'Brick Wall 4m', price = 250, tint = true, snapGroup = 'structure' },
            { object = 'qbx_wall_wood_400', label = 'Wood Wall 4m', price = 250, tint = true, snapGroup = 'structure' },
            { object = 'qbx_wall_concrete_400', label = 'Concrete Wall 4m', price = 250, tint = true, snapGroup = 'structure' },
            { object = 'qbx_wall_panelled_200', label = 'Panelled Wall 2m', price = 250, tint = true, snapGroup = 'structure' },
            { object = 'qbx_wall_trim_200', label = 'Trimmed Wall 2m', price = 250, tint = true, snapGroup = 'structure' },
        },

        arches = {
            { object = 'qbx_arch_door_plaster', label = 'Plaster Door Arch', price = 400, tint = true, snapGroup = 'arch' },
            { object = 'qbx_arch_door_brick', label = 'Brick Door Arch', price = 400, tint = true, snapGroup = 'arch' },
            { object = 'qbx_arch_wide_plaster', label = 'Plaster Wide Arch', price = 400, tint = true, snapGroup = 'arch' },
            { object = 'qbx_arch_wide_brick', label = 'Brick Wide Arch', price = 400, tint = true, snapGroup = 'arch' },
        },

        stairs = {
            { object = 'qbx_stairs_concrete', label = 'Concrete Stairs', price = 750, tint = true, snapGroup = 'structure' },
            { object = 'qbx_stairs_wood', label = 'Wooden Stairs', price = 750, tint = true, snapGroup = 'structure' },
            { object = 'qbx_stairs_wide_concrete', label = 'Wide Concrete Stairs', price = 750, tint = true, snapGroup = 'structure' },
            { object = 'qbx_stairs_lshape_concrete', label = 'L-Shaped Stairs', price = 750, tint = true, snapGroup = 'structure' },
            { object = 'qbx_stairs_spiral_concrete', label = 'Concrete Spiral Stairs', price = 750, tint = true, snapGroup = 'structure' },
            { object = 'qbx_stairs_spiral_wood', label = 'Wooden Spiral Stairs', price = 750, tint = true, snapGroup = 'structure' },
        },

        -- floors are 8cm thick, so the default camera sits at slab level and shoots the
        -- edge. these look down on the surface instead, scaled to each slab's size.
        floors = {
            { object = 'qbx_floor_tile_200', label = 'Tile Floor 2m', price = 350, tint = true, snapGroup = 'structure', screenshotCameraOffset = vec3(0.0, -0.9, 2.7) },
            { object = 'qbx_floor_wood_200', label = 'Wood Floor 2m', price = 350, tint = true, snapGroup = 'structure', screenshotCameraOffset = vec3(0.0, -0.9, 2.7) },
            { object = 'qbx_floor_concrete_200', label = 'Concrete Floor 2m', price = 350, tint = true, snapGroup = 'structure', screenshotCameraOffset = vec3(0.0, -0.9, 2.7) },
            { object = 'qbx_floor_tile_400', label = 'Tile Floor 4m', price = 350, tint = true, snapGroup = 'structure', screenshotCameraOffset = vec3(0.0, -1.8, 5.4) },
            { object = 'qbx_floor_wood_400', label = 'Wood Floor 4m', price = 350, tint = true, snapGroup = 'structure', screenshotCameraOffset = vec3(0.0, -1.8, 5.4) },
            { object = 'qbx_floor_concrete_400', label = 'Concrete Floor 4m', price = 350, tint = true, snapGroup = 'structure', screenshotCameraOffset = vec3(0.0, -1.8, 5.4) },
        },
    }
}