CREATE TABLE IF NOT EXISTS `properties_apartment_walls` (
    `citizenid` VARCHAR(50) NOT NULL,
    `wall_color` INT(11) NOT NULL,
    PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
