CREATE TABLE IF NOT EXISTS `properties_listings` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `property_id` INT NOT NULL,
    `listed_by` VARCHAR(50) COLLATE utf8mb4_unicode_ci NOT NULL,
    `listing_type` ENUM('sale', 'auction') NOT NULL DEFAULT 'sale',
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
