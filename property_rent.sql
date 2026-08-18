ALTER TABLE `properties` ADD COLUMN IF NOT EXISTS `rent_last_paid` DATETIME DEFAULT NULL AFTER `rent_interval`;
