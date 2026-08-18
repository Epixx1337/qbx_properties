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
    PRIMARY KEY (`id`),
    INDEX `idx_apartment_decorations_citizen` (`citizenid`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
