-- The complete qbx_properties schema. The resource runs this automatically on boot and adds
-- any column an existing database is missing, when the database user may CREATE and ALTER;
-- run it by hand only when it may not.

CREATE TABLE IF NOT EXISTS `properties` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `property_name` VARCHAR(255) NOT NULL,
    `coords` JSON NOT NULL,
    `price` INT NOT NULL DEFAULT 0,
    `owner` VARCHAR(50) COLLATE utf8mb4_unicode_ci,
    `interior` VARCHAR(255) NOT NULL, /* IPL name, shell hash or 'mlo' */
    `building` VARCHAR(50) DEFAULT NULL,
    `floor` INT DEFAULT NULL,
    `room` INT DEFAULT NULL,
    `shell_coords` JSON DEFAULT NULL,
    `keyholders` JSON NOT NULL DEFAULT (JSON_OBJECT()),
    `rent_interval` INT DEFAULT NULL,
    `rent_last_paid` DATETIME DEFAULT NULL,
    `interact_options` JSON NOT NULL DEFAULT (JSON_OBJECT()),
    `stash_options` JSON NOT NULL DEFAULT (JSON_OBJECT()),
    `garage` JSON DEFAULT NULL,
    `garden_zone` JSON DEFAULT NULL,
    `door_data` JSON DEFAULT NULL,
    `utilities_paid_until` DATETIME DEFAULT NULL,
    `power_limit` INT DEFAULT NULL,
    `size` VARCHAR(20) DEFAULT NULL,
    `created_by` VARCHAR(50) DEFAULT NULL,
    `wall_color` INT DEFAULT NULL,
    `images` LONGTEXT DEFAULT NULL,
    `description` TEXT DEFAULT NULL,
    `type` VARCHAR(20) DEFAULT NULL,
    `group_name` VARCHAR(50) DEFAULT NULL,
    `mailbox` JSON DEFAULT NULL,
    `tenant` VARCHAR(50) DEFAULT NULL,
    `tenant_rent` INT DEFAULT NULL,
    `tenant_interval` INT DEFAULT NULL,
    `tenant_last_paid` DATETIME DEFAULT NULL,
    `tenant_paid_until` DATETIME DEFAULT NULL,
    `tenant_contract_end` DATETIME DEFAULT NULL,
    `tenant_notice_end` DATETIME DEFAULT NULL,
    `sale_authorized` TINYINT(1) NOT NULL DEFAULT 0,
    `timecycle` VARCHAR(50) DEFAULT NULL,
    `maintenance_paid_until` DATETIME DEFAULT NULL,
    `doorcam` JSON DEFAULT NULL,
    FOREIGN KEY (owner) REFERENCES `players` (`citizenid`),
    PRIMARY KEY (id)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX IF NOT EXISTS `idx_properties_owner` ON `properties` (`owner`);
CREATE UNIQUE INDEX IF NOT EXISTS `idx_properties_unit` ON `properties` (`building`, `floor`, `room`);

CREATE TABLE IF NOT EXISTS `properties_decorations` (
    `id` BIGINT NOT NULL AUTO_INCREMENT,
    `property_id` INT NOT NULL,
    `model` VARCHAR(255) NOT NULL,
    `coords` JSON NOT NULL,
    `rotation` JSON NOT NULL,
    `stash_slot` INT DEFAULT NULL,
    `tint` INT DEFAULT NULL,
    `garden` TINYINT(1) NOT NULL DEFAULT 0,
    `item` VARCHAR(100) DEFAULT NULL,
    `item_metadata` LONGTEXT DEFAULT NULL,
    `health` INT NOT NULL DEFAULT 100,
    `lock_pin` VARCHAR(8) DEFAULT NULL,
    `lock_setter` VARCHAR(50) DEFAULT NULL,
    FOREIGN KEY (property_id) REFERENCES `properties` (`id`) ON DELETE CASCADE,
    PRIMARY KEY (id)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `properties_apartment_keyholders` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `tenant` VARCHAR(50) COLLATE utf8mb4_unicode_ci NOT NULL,
    `keyholder` VARCHAR(50) COLLATE utf8mb4_unicode_ci NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_apartment_keyholder` (`tenant`, `keyholder`),
    INDEX `idx_apartment_keyholders_tenant` (`tenant`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `properties_apartment_decorations` (
    `id` BIGINT NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) COLLATE utf8mb4_unicode_ci NOT NULL,
    `model` VARCHAR(255) NOT NULL,
    `coords` JSON NOT NULL, /* stored relative to the room anchor so it can be restored into any room */
    `rotation` JSON NOT NULL, /* heading is relative to the room anchor heading */
    `stash_slot` INT DEFAULT NULL,
    `tint` INT DEFAULT NULL,
    `item` VARCHAR(100) DEFAULT NULL,
    `item_metadata` LONGTEXT DEFAULT NULL,
    `layout` VARCHAR(50) DEFAULT NULL,
    `health` INT NOT NULL DEFAULT 100,
    `lock_pin` VARCHAR(8) DEFAULT NULL,
    `lock_setter` VARCHAR(50) DEFAULT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_apartment_decorations_citizen` (`citizenid`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `properties_apartment_walls` (
    `citizenid` VARCHAR(50) NOT NULL,
    `wall_color` INT(11) NOT NULL,
    PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `properties_layout_defaults` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `layout` VARCHAR(50) NOT NULL,
    `model` VARCHAR(255) NOT NULL,
    `coords` JSON NOT NULL,
    `rotation` JSON NOT NULL,
    `tint` INT DEFAULT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_layout_defaults` (`layout`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `properties_listings` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `property_id` INT NOT NULL,
    `listed_by` VARCHAR(50) COLLATE utf8mb4_unicode_ci NOT NULL,
    `listing_type` ENUM('sale', 'auction', 'offer') NOT NULL DEFAULT 'sale',
    `status` ENUM('active', 'sold', 'expired', 'cancelled', 'finalizing') NOT NULL DEFAULT 'active',
    `price` INT NOT NULL,
    `reserve_price` INT DEFAULT NULL,
    `min_increment` INT NOT NULL DEFAULT 1000,
    `auction_end` DATETIME DEFAULT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE,
    INDEX `idx_listings_status` (`status`),
    INDEX `idx_listings_end` (`auction_end`),
    PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `properties_bids` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `listing_id` INT NOT NULL,
    `bidder` VARCHAR(50) COLLATE utf8mb4_unicode_ci NOT NULL,
    `amount` INT NOT NULL,
    `status` ENUM('active', 'outbid', 'won', 'refunded') NOT NULL DEFAULT 'active',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (`listing_id`) REFERENCES `properties_listings` (`id`) ON DELETE CASCADE,
    INDEX `idx_bids_listing` (`listing_id`, `status`),
    PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `properties_access` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `property_id` INT DEFAULT NULL,
    `tenant` VARCHAR(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
    `citizenid` VARCHAR(50) COLLATE utf8mb4_unicode_ci NOT NULL,
    `door` TINYINT(1) NOT NULL DEFAULT 1,
    `stash` TINYINT(1) NOT NULL DEFAULT 0,
    `furniture` TINYINT(1) NOT NULL DEFAULT 0,
    `garage` TINYINT(1) NOT NULL DEFAULT 0,
    `utilities` TINYINT(1) NOT NULL DEFAULT 0,
    `rent` TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_access_property` (`property_id`, `citizenid`),
    UNIQUE KEY `uk_access_tenant` (`tenant`, `citizenid`),
    INDEX `idx_access_citizen` (`citizenid`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `properties_utilities` (
    `property_id` INT NOT NULL,
    `power_used` INT NOT NULL DEFAULT 0,
    `humidity` INT NOT NULL DEFAULT 40,
    `temperature` INT NOT NULL DEFAULT 21,
    `unpaid_since` DATETIME DEFAULT NULL,
    `powered` TINYINT(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (`property_id`),
    FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `properties_raids` (
    `property_id` INT(11) NOT NULL,
    `officer` VARCHAR(50) NOT NULL,
    `target` VARCHAR(50) DEFAULT NULL,
    `started` DATETIME NOT NULL DEFAULT current_timestamp(),
    `breached` TINYINT(1) NOT NULL DEFAULT 0,
    `lockdown` TINYINT(1) NOT NULL DEFAULT 0,
    `previous_owner` VARCHAR(50) DEFAULT NULL,
    `assigned_room` TINYINT(1) NOT NULL DEFAULT 0,
    `assigned_building` TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (`property_id`),
    KEY `idx_raid_officer` (`officer`),
    KEY `idx_raid_target` (`target`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `properties_upgrades` (
    `property_id` INT NOT NULL,
    `upgrade` VARCHAR(50) NOT NULL,
    PRIMARY KEY (`property_id`, `upgrade`),
    FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `properties_payments` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `property_id` INT NOT NULL,
    `kind` ENUM('rent', 'utilities', 'maintenance') NOT NULL,
    `payer` VARCHAR(50) NOT NULL,
    `payer_name` VARCHAR(100) DEFAULT NULL,
    `amount` INT NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `property_kind` (`property_id`, `kind`, `created_at`),
    CONSTRAINT `fk_properties_payments` FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `properties_sales` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `property_id` INT NOT NULL, /* no FK on purpose, the sale history outlives the property */
    `property_name` VARCHAR(255) NOT NULL,
    `seller` VARCHAR(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL, /* NULL when the market or state sold it */
    `buyer` VARCHAR(50) COLLATE utf8mb4_unicode_ci NOT NULL,
    `price` INT NOT NULL,
    `profit` INT DEFAULT NULL, /* sale price minus what the seller paid, NULL when unknowable */
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_sales_property` (`property_id`),
    INDEX `idx_sales_buyer` (`buyer`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `properties_layouts` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `property_id` INT NOT NULL,
    `name` VARCHAR(40) NOT NULL,
    `creator` VARCHAR(50) COLLATE utf8mb4_unicode_ci NOT NULL,
    `creator_name` VARCHAR(100) DEFAULT NULL,
    `data` LONGTEXT NOT NULL,
    `share_code` VARCHAR(10) NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_layout_code` (`share_code`),
    INDEX `idx_layouts_property` (`property_id`),
    FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `properties_job_access` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `property_id` INT NOT NULL,
    `job_name` VARCHAR(50) NOT NULL,
    `min_grade` INT NOT NULL DEFAULT 0,
    `door` TINYINT(1) NOT NULL DEFAULT 1,
    `stash` TINYINT(1) NOT NULL DEFAULT 0,
    `furniture` TINYINT(1) NOT NULL DEFAULT 0,
    `garage` TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_job_access` (`property_id`, `job_name`),
    FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `properties_activity` (
    `citizenid` VARCHAR(50) COLLATE utf8mb4_unicode_ci NOT NULL,
    `last_active` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
