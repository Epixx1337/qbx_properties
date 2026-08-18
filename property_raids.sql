CREATE TABLE IF NOT EXISTS `properties_raids` (
    `property_id` INT(11) NOT NULL,
    `officer` VARCHAR(50) NOT NULL,
    `target` VARCHAR(50) DEFAULT NULL,
    `started` DATETIME NOT NULL DEFAULT current_timestamp(),
    `breached` TINYINT(1) NOT NULL DEFAULT 0,
    `lockdown` TINYINT(1) NOT NULL DEFAULT 0,
    `previous_owner` VARCHAR(50) DEFAULT NULL,
    `assigned_room` TINYINT(1) NOT NULL DEFAULT 0,
    `assigned_building` TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (`property_id`),
    KEY `idx_raid_officer` (`officer`),
    KEY `idx_raid_target` (`target`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `properties_raids` ADD COLUMN IF NOT EXISTS `assigned_room` TINYINT(1) NOT NULL DEFAULT 0 AFTER `previous_owner`;
ALTER TABLE `properties_raids` ADD COLUMN IF NOT EXISTS `assigned_building` TINYINT(1) NOT NULL DEFAULT 0 AFTER `assigned_room`;
