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
