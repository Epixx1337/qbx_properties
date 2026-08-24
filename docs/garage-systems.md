# Garage systems

Property and apartment garages register with [qbx_garages](https://github.com/Qbox-project/qbx_garages) out of the box. Servers running a different garage script can bridge to it instead with one config option:

```lua
garageSystem = 'qbx', -- config/shared.lua
```

Supported values:

| Value | Garage script |
| --- | --- |
| `'qbx'` | qbx_garages (default, unchanged behaviour) |
| `'jg-advancedgarages'` | [JG Advanced Garages](https://docs.jgscripts.com/advanced-garages) |
| `'cd_garage'` | [Codesign Garage](https://docs.codesign.pro/paid-scripts/garage/) |
| `'okokGarage'` | [okokGarage](https://docs.okokscripts.io/scripts/okokgarage) |
| `'custom'` | anything else — fill in the stub in `config/garages.lua` |

## How the bridge works

With any value other than `'qbx'`, qbx_properties stops registering garages with qbx_garages and creates its own access points instead — at each house's garage location and every apartment parking bay. Walking up shows a text UI: **E** stores the current vehicle or opens the third-party garage, matching how ps-housing and similar scripts integrate.

Access control stays with qbx_properties: house garages require ownership or a key with the garage permission, apartment garages require a unit in one of the linked buildings. The points only exist for players with access and refresh automatically on purchases, evictions and key changes.

Each garage passes a stable identifier to the adapter — `property_<property name>` for houses, the `name` field from `apartmentGarages` for shared parking. Systems that store vehicles per garage id (JG house garages, for example) key their storage off it, so don't rename properties casually.

## Adding another system

`config/garages.lua` maps each system to two functions:

```lua
custom = {
    open = function(garage)
        -- garage = { name, label, coords } — coords is the vec4 access point
        TriggerEvent('your-garage:client:open', garage.name, garage.coords)
    end,
    store = function(garage)
        TriggerEvent('your-garage:client:store', garage.name)
    end,
},
```

Set `garageSystem = 'custom'` (or add a new key and use that name) and check your garage script's documentation for its house/private garage events. Only systems with a drop-in event or export API can be bridged this way — garages that require building interiors through their own housing script (Quasar, loaf) are out of scope.

## Switching systems

Changing `garageSystem` does not move vehicles that are already parked: whatever system parked them still holds them under its own storage. Plan the switch on a fresh economy or migrate the `player_vehicles` garage column by hand.
