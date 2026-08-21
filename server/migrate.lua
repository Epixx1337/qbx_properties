local schemaFiles = {
    'property.sql',
    'decorations.sql',
    'property_pool.sql',
    'property_apartments.sql',
    'property_apartment_walls.sql',
    'property_market.sql',
    'property_rent.sql',
    'property_utilities.sql',
    'property_garages.sql',
    'property_raids.sql',
    'property_images.sql',
    'property_stash_slots.sql',
    'property_tints.sql',
    'property_item_furniture.sql',
    'property_apartment_layouts.sql',
    'property_layout_defaults.sql',
}

local columns = {
    properties_decorations = {
        stash_slot = 'INT DEFAULT NULL',
        tint = 'INT DEFAULT NULL',
        garden = 'TINYINT(1) NOT NULL DEFAULT 0',
        item = 'VARCHAR(100) DEFAULT NULL',
        item_metadata = 'LONGTEXT DEFAULT NULL',
    },
    properties_apartment_decorations = {
        stash_slot = 'INT DEFAULT NULL',
        tint = 'INT DEFAULT NULL',
        item = 'VARCHAR(100) DEFAULT NULL',
        item_metadata = 'LONGTEXT DEFAULT NULL',
        layout = 'VARCHAR(50) DEFAULT NULL',
    },
    properties = {
        building = 'VARCHAR(50) DEFAULT NULL',
        floor = 'INT DEFAULT NULL',
        room = 'INT DEFAULT NULL',
        shell_coords = 'JSON DEFAULT NULL',
        garage = 'JSON DEFAULT NULL',
        garden_zone = 'JSON DEFAULT NULL',
        door_data = 'JSON DEFAULT NULL',
        utilities_paid_until = 'DATETIME DEFAULT NULL',
        power_limit = 'INT DEFAULT NULL',
        size = 'VARCHAR(20) DEFAULT NULL',
        created_by = 'VARCHAR(50) DEFAULT NULL',
        wall_color = 'INT DEFAULT NULL',
        images = 'LONGTEXT DEFAULT NULL',
        description = 'TEXT DEFAULT NULL',
        rent_last_paid = 'DATETIME DEFAULT NULL',
    },
    properties_raids = {
        assigned_room = 'TINYINT(1) NOT NULL DEFAULT 0',
        assigned_building = 'TINYINT(1) NOT NULL DEFAULT 0',
    },
}

MySQL.ready(function()
    for i = 1, #schemaFiles do
        local sql = LoadResourceFile(cache.resource, schemaFiles[i])
        if sql then
            for statement in sql:gmatch('[^;]+') do
                if statement:match('%S') then
                    pcall(MySQL.query.await, statement)
                end
            end
        end
    end

    local added = 0
    for tableName, defs in pairs(columns) do
        local rows = MySQL.query.await('SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', {tableName})
        if rows and #rows > 0 then
            local have = {}
            for j = 1, #rows do have[rows[j].COLUMN_NAME] = true end

            for column, definition in pairs(defs) do
                if not have[column] then
                    local ok = pcall(MySQL.query.await, ('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, column, definition))
                    if ok then
                        added += 1
                    else
                        lib.print.error(('could not add column %s.%s, run the sql files by hand'):format(tableName, column))
                    end
                end
            end
        end
    end

    if added > 0 then
        lib.print.info(('migrated the database, %d column(s) added'):format(added))
    end
end)
