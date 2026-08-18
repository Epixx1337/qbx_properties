ALTER TABLE `properties_apartment_decorations` ADD COLUMN IF NOT EXISTS `tint` INT DEFAULT NULL;
ALTER TABLE `properties_decorations` ADD COLUMN IF NOT EXISTS `tint` INT DEFAULT NULL;
