ALTER TABLE `properties` ADD COLUMN IF NOT EXISTS `garden_zone` JSON DEFAULT NULL AFTER `shell_coords`;
ALTER TABLE `properties` ADD COLUMN IF NOT EXISTS `door_data` JSON DEFAULT NULL AFTER `garden_zone`;
ALTER TABLE `properties` ADD COLUMN IF NOT EXISTS `utilities_paid_until` DATETIME DEFAULT NULL AFTER `door_data`;
ALTER TABLE `properties` ADD COLUMN IF NOT EXISTS `power_limit` INT DEFAULT NULL AFTER `utilities_paid_until`;

CREATE TABLE IF NOT EXISTS `properties_access` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `property_id` INT DEFAULT NULL,
    `tenant` VARCHAR(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
    `citizenid` VARCHAR(50) COLLATE utf8mb4_unicode_ci NOT NULL,
    `door` TINYINT(1) NOT NULL DEFAULT 1,
    `stash` TINYINT(1) NOT NULL DEFAULT 0,
    `furniture` TINYINT(1) NOT NULL DEFAULT 0,
    `garage` TINYINT(1) NOT NULL DEFAULT 0,
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

ALTER TABLE `properties_decorations` ADD COLUMN IF NOT EXISTS `garden` TINYINT(1) NOT NULL DEFAULT 0;

ALTER TABLE `properties` ADD COLUMN IF NOT EXISTS `size` VARCHAR(20) DEFAULT NULL AFTER `power_limit`;
ALTER TABLE `properties` ADD COLUMN IF NOT EXISTS `created_by` VARCHAR(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL AFTER `size`;

ALTER TABLE `properties` ADD COLUMN IF NOT EXISTS `wall_color` INT DEFAULT NULL AFTER `created_by`;
