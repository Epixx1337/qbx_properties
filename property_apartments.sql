ALTER TABLE `properties` ADD COLUMN IF NOT EXISTS `building` VARCHAR(50) DEFAULT NULL AFTER `interior`;
ALTER TABLE `properties` ADD COLUMN IF NOT EXISTS `floor` INT DEFAULT NULL AFTER `building`;
ALTER TABLE `properties` ADD COLUMN IF NOT EXISTS `room` INT DEFAULT NULL AFTER `floor`;
ALTER TABLE `properties` ADD COLUMN IF NOT EXISTS `shell_coords` JSON DEFAULT NULL AFTER `room`;

CREATE INDEX IF NOT EXISTS `idx_properties_owner` ON `properties` (`owner`);
CREATE UNIQUE INDEX IF NOT EXISTS `idx_properties_unit` ON `properties` (`building`, `floor`, `room`);
