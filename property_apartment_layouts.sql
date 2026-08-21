ALTER TABLE `properties_apartment_decorations`
    ADD COLUMN IF NOT EXISTS `layout` VARCHAR(50) DEFAULT NULL;

UPDATE `properties_apartment_decorations` SET `layout` = 'wiwang' WHERE `layout` IS NULL;
