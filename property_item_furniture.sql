ALTER TABLE `properties_decorations`
    ADD COLUMN `item` VARCHAR(100) NULL,
    ADD COLUMN `item_metadata` LONGTEXT NULL;

ALTER TABLE `properties_apartment_decorations`
    ADD COLUMN `item` VARCHAR(100) NULL,
    ADD COLUMN `item_metadata` LONGTEXT NULL;
