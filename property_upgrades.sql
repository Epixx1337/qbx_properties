CREATE TABLE IF NOT EXISTS `properties_upgrades` (
    `property_id` INT NOT NULL,
    `upgrade` VARCHAR(50) NOT NULL,
    PRIMARY KEY (`property_id`, `upgrade`),
    FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `properties_listings` MODIFY `listing_type` ENUM('sale', 'auction', 'offer') NOT NULL;

UPDATE `properties` SET `type` = 'residential' WHERE `type` IS NULL;
