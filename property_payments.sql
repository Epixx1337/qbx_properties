CREATE TABLE IF NOT EXISTS `properties_payments` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `property_id` INT NOT NULL,
    `kind` ENUM('rent','utilities') NOT NULL,
    `payer` VARCHAR(50) NOT NULL,
    `payer_name` VARCHAR(100) DEFAULT NULL,
    `amount` INT NOT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `property_kind` (`property_id`, `kind`, `created_at`),
    CONSTRAINT `fk_properties_payments` FOREIGN KEY (`property_id`) REFERENCES `properties` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
