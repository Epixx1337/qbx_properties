fx_version 'cerulean'
game 'gta5'

name 'qbx_properties'
description 'Hopefully one day a feature rich property system'
repository 'https://github.com/Qbox-project/qbx_properties'
version '0.0.7'

ox_lib 'locale'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'shared/main.lua',
}

ui_page 'web/build/index.html'

client_scripts {
    '@qbx_core/modules/playerdata.lua',
    'client/nui.lua',
    'client/radial.lua',
    'client/apartmentselect.lua',
    'client/property.lua',
    'client/realtor.lua',
    'client/dataview.lua',
    'client/decorating.lua',
    'client/apartments.lua',
    'client/roomfurniture.lua',
    'client/doorbell.lua',
    'client/interiors.lua',
    'client/shells.lua',
    'client/market.lua',
    'client/garages.lua',
    'client/placement.lua',
    'client/preview.lua',
    'client/creation.lua',
    'client/sales.lua',
    'client/gardens.lua',
    'client/raids.lua',
    'client/robbery.lua',
    'client/wallcolor.lua',
    'client/tablet.lua',
    'client/creator.lua',
    'client/items.lua',
    'client/screenshot.lua',
    'client/phone.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/migrate.lua',
    'server/apartmentselect.lua',
    'server/property.lua',
    'server/realtor.lua',
    'server/access.lua',
    'server/doors.lua',
    'server/apartments.lua',
    'server/garages.lua',
    'server/market.lua',
    'server/shells.lua',
    'server/shelldefaults.lua',
    'server/creation.lua',
    'server/sales.lua',
    'server/gardens.lua',
    'server/raids.lua',
    'server/robbery.lua',
    'server/wallcolor.lua',
    'server/utilities.lua',
    'server/creator.lua',
    'server/screenshot.lua',
    'server/screenshot.js',
    'server/phone.lua',
    'server/upgrades.lua',
    'server/tenancy.lua',
    'server/exports.lua',
}

files {
    'config/client.lua',
    'config/shared.lua',
    'config/garages.lua',
    'config/dispatch.lua',
    'config/crime.lua',
    'config/shell_defaults.lua',
    'config/buildings.lua',
    'locales/*.json',
    'screenshots/*.webp',
    'web/build/index.html',
    'web/build/**/*',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
    'ox_inventory',
    'ox_target',
}

lua54 'yes'
use_experimental_fxv2_oal 'true'

files {
    'stream/audiodirectory/qbx_properties_sounds.awc',
    'stream/data/qbx_properties_sounds.dat54.rel',
    'stream/props/qbx_props.ytyp',
    'stream/props/cdx_intercom_prop.ytyp',
}

data_file 'AUDIO_WAVEPACK' 'stream/audiodirectory'
data_file 'AUDIO_SOUNDDATA' 'stream/data/qbx_properties_sounds.dat'
data_file 'DLC_ITYP_REQUEST' 'stream/props/qbx_props.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/props/cdx_intercom_prop.ytyp'
