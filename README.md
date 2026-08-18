# qbx_properties

Player housing for Qbox. Apartments, shell interiors and MLO houses with an in-game realtor job, a furniture editor, a property market, rent and utilities, and police raids.

## Showcase

**Creating a property** — a realtor sets up an MLO house from the New property tab: capture the interior point, pick the doors with the laser, draw the garden zone, set price and size, list it, and another player buys it straight off the market.

[▶ Watch: creating a property](.github/media/creating-a-property.mp4)

**The furniture editor** — catalog, gizmo placement, modular walls with the 32-colour tint palette, snapping, the fine-tune panel and mounting the housing tablet on a wall.

[▶ Watch: the furniture editor](.github/media/furniture-editor.mp4)

**The housing tablet** — mounted in the property, opened through ox_target. Room management grants door/stash/furniture/garage access per citizen.

[▶ Watch: the housing tablet](.github/media/housing-tablet.mp4)

**Utilities** — the tablet's Utilities tab: live power draw against the property's allowance, humidity, and paying the monthly bill. Furniture and lighting persist across relogs.

[▶ Watch: utilities](.github/media/utilities.mp4)

**Breaching and wall colours** — police breach an apartment door with the battering ram, and the tablet's Wall colour tab repaints a unit's walls from the same 32-colour palette.

[▶ Watch: breaching and wall colours](.github/media/breaching-wall-colour.mp4)

**Police raid** — starting a raid with a warrant at the receptionist, then going through the unit and robbing the safe.

[▶ Watch: a police raid](.github/media/police-raid.mp4)

## Screenshots

### Market

![Market tab](.github/media/market.png)

Every active listing with photos and prices, filterable by direct sales or auctions. Realtors see the same page plus their tools.

![Listing detail](.github/media/market-listing.png)

A listing opened: photo gallery, the realtor's pitch, price, and the buy button. Auctions show current bid, time left and bid history instead.

### New property

![Interior list](.github/media/new-property-interiors.png)

Realtors pick a predefined interior — IPL apartments already exist in the world and only need an entrance, shells get spawned and positioned — or start an MLO property.

![IPL flow](.github/media/new-property-ipl.png)

The IPL flow: aim at the door with the laser to set the entrance; interaction points come pre-captured for known interiors and can be edited.

![MLO flow](.github/media/new-property-mlo.png)

The MLO flow: stand inside and capture the interior point, add the door(s), and optionally a garden zone and a garage spot. Price, size and rental terms on the right, with the option to list immediately.

![Creating in the world](.github/media/new-property-ingame.png)

All of it happens standing at the property, not in a config file.

### Manage

![Property list](.github/media/manage.png)

Every property on the server with owner and status, searchable and filterable.

![Property details](.github/media/manage-details.png)

A selected property: edit price/size/description, take listing photos, re-place the garage, redraw the garden, and for MLOs re-set the interior point or add more doors. Realtors can also enter the property remotely to fix its interior points.

### Buildings

![Buildings tab](.github/media/buildings.png)

Multi-unit buildings: pick a floor, see every unit and its tenant, and create the remaining units in bulk with a price and rental terms.

### MLO Apartments Creator

![Creator start](.github/media/mlo-creator-start.png)

Turns any multi-room MLO into an apartment building. It scans the interior you are standing in and detects the room naming pattern.

![Creator capture](.github/media/mlo-creator.png)

Walk the building capturing the entrance, receptionist, elevators, floor heights and one anchor per room — it validates as you go and writes `config/buildings.lua` when everything lines up.

## Features

**Properties**
- Pooled IPL apartments (Del Perro, Integrity Way, Richard Majestic, Tinsel Towers) plus multi-unit apartment buildings with per-floor rooms, doorbells and shared parking garages
- Standalone properties using interior shells, IPL interiors or real MLO houses
- MLO properties live in the actual world: walk in through the (locked) front door, furniture and stashes load in place, and extra doors can be added at any time
- Owned properties show house and garage blips, and can be spawned into from the spawn selector

**Realtor job**
- Create properties entirely in game: pick the door with a laser pointer, capture the interior point, set price, size and rental terms
- Manage menu: edit price/size/description, take property photos (uploaded to the Qbox CDN), place garages, draw garden zones, add doors, re-capture the interior point and enter properties remotely
- Realtors earn a configurable commission on sales and rent of properties they created

**Decorating**
- Furniture catalog with preview images, freecam and a gizmo for placement
- Snapping: to the ground, to the nearest wall, and modular pieces (walls, floors, stairs, arches) snap to each other; doors seat into arches
- 32 tint colours on the bundled structural props, matching the wall colour palette
- Fine-tune panel for exact coordinates and small nudges, including screen-relative movement
- Garden zones are decoratable too — walk into your garden and the same editor opens from the radial menu
- Other players inside the property (or garden) see furniture being moved live while you edit
- Stash furniture registers real ox_inventory stashes with persistent slots, so removing and replacing a stash reconnects its contents
- Wardrobe and logout furniture (logout can be disabled in config)

**Economy**
- Market with direct sales and auctions (configurable durations, anti-snipe)
- Rent cycles and utility billing with power usage and humidity per property size
- Optional society/government accounts for proceeds and bills

**Crime**
- Burglary through lockpicking with a skill check, alarm sound (native audio, replaceable) and dispatch hooks
- Police raids: search warrant at a receptionist, battering ram door breach, access to the property while the raid is active

## Dependencies

- [qbx_core](https://github.com/Qbox-project/qbx_core)
- [ox_lib](https://github.com/CommunityOx/ox_lib)
- [oxmysql](https://github.com/CommunityOx/oxmysql)
- [ox_inventory](https://github.com/CommunityOx/ox_inventory)
- [ox_target](https://github.com/CommunityOx/ox_target)
- [ox_doorlock](https://github.com/CommunityOx/ox_doorlock) for property and apartment doors — needs one added export, see below
- screencapture (the screenshot-basic replacement) for realtor property photos

**Assets used by specific features**

- [Battering-Ram](https://github.com/Epixx1337/Battering-Ram) — the two-handed ram weapon (`WEAPON_BATTERINGRAM`) used for police door breaches, with its looping breach animation
- [wiwang_hotel](https://github.com/Epixx1337/wiwang_hotel) — our edit of the Wiwang Hotel MLO with per-room `wall_tint` entity sets, required for wall colours inside its apartments
- [prp-housing shells](https://studio.prodigyrp.net/map) — the ProdigyRP house MLOs, required for wall colours in those interiors
- The free starter shells are from [K4MB1](https://forum.cfx.re/t/free-props-starter-shells-for-housing-scripts/4826922)

## Installation

1. Remove `qbx_apartments` and `qbx_houses`
2. Either use no spawn system (the core defaults to last location) or [qbx_spawn](https://github.com/Qbox-project/qbx_spawn)
3. Run every `.sql` file in the resource root against your database
4. Set your Qbox CDN API key (see below) if you want realtor photos
5. Ensure the resource starts after its dependencies

The NUI is prebuilt in `web/build`. To rebuild after changing it: `cd web && bun i && bun run build`.

## ox_doorlock exports

Property doors are registered and removed at runtime, but stock ox_doorlock only manages doors through its admin UI. Add these two exports to ox_doorlock's `server/main.lua` (they slot in right after the other exports) — without them the resource prints a warning on start and doors are skipped:

```lua
exports('removeDoorByName', function(name)
    local results = MySQL.query.await('SELECT id FROM ox_doorlock WHERE name LIKE ?', { name .. '%' })
    if not results then return end

    for _, row in ipairs(results) do
        MySQL.update('DELETE FROM ox_doorlock WHERE id = ?', { row.id })
        doors[row.id] = nil
        TriggerClientEvent('ox_doorlock:editDoorlock', -1, row.id, nil)
    end
end)

exports('createDoorProgrammatic', function(data)
    if not data or not data.name or not data.coords then return end

    if type(data.coords) ~= 'vector3' then
        data.coords = vector3(data.coords.x, data.coords.y, data.coords.z)
    end

    if not data.state then data.state = 1 end

    local insertId = MySQL.insert.await('INSERT INTO ox_doorlock (name, data) VALUES (?, ?)',
        { data.name, encodeData(data) })
    if not insertId then return end

    local door = createDoor(insertId, data, data.name)
    TriggerClientEvent('ox_doorlock:setState', -1, door.id, door.state, false, door)

    return insertId
end)
```

`createDoorProgrammatic` inserts the door into the `ox_doorlock` table, registers it live and syncs it to every client, defaulting to locked. `removeDoorByName` deletes every door whose name starts with the given prefix, which is how a property's furniture and extra doors are cleaned up before re-syncing. qbx_properties uses them for apartment unit doors, MLO property doors and placeable door furniture, and only creates a door when no door with that name exists yet.

## CDN key for property photos

Realtor photos are uploaded to the [Qbox CDN](https://docs.qbox.re/dashboard/cdn). Create an API key in your Qbox dashboard and put it in `config/server.lua`:

```lua
imageUpload = {
    url = 'https://api.qbox.re/v1/file',
    field = 'file',
    headers = {
        Authorization = 'YOUR_API_KEY',
    },
    responsePath = 'data.url',
    maxImages = 5,
},
```

With the key left empty, the Take photo button reports that uploads are not configured and everything else keeps working. Any other upload endpoint that accepts multipart uploads and returns a URL in its JSON response works too — point `url`, `field` and `responsePath` at it.

## Configuration

| File | Contents |
| --- | --- |
| `config/shared.lua` | realtor jobs, property sizes, market rules, utilities, wall colours, apartment garages |
| `config/client.lua` | furniture catalog, interior IPL data, editor settings |
| `config/server.lua` | payouts, rent, stash sizes, image upload |
| `config/crime.lua` | robbery and raid rules, alarm sound |
| `config/dispatch.lua` | hooks to send alerts to whatever dispatch the server runs |
| `config/buildings.lua` | multi-unit apartment building layouts (written by the MLO Apartments Creator) |
| `config/shell_defaults.lua` | interaction points for the bundled shells |

Options worth knowing about:

- `realtorJobs` / `realtorRequiresDuty` (shared) — which jobs and grades get the realtor tabs, and whether they must be on duty.
- `logoutEnabled` (shared) — beds and logout points let players switch character; `false` hides them everywhere.
- `targetInteractions` (shared) — MLO furniture uses ox_target labels instead of floating interaction points.
- `propertySizes` (shared) — each size sets the power allowance (W) and the monthly utility cost; realtors pick the size on creation.
- `utilities` (shared) — billing period, grace period, and the humidity model (base level, effect per kilowatt, comfort threshold).
- `commission` (shared) — the cut of sales and rent paid to the realtor who created the property.
- `market` (shared) — price bounds, auction durations, anti-snipe window, whether bids are anonymous, and how close an agent must be to bid on a client's behalf.
- `gardens` (shared) — furniture limit, zone corner cap and maximum build height for garden zones.
- `wallColors` (shared) — the 32-colour palette and the `entitySet` name the tinted wall meshes use. Interiors need tint-capable walls (see the asset list above); the same palette drives furniture tints.
- `apartmentGarages` (shared) — one garage per complex, every bay doubles as menu and park point. The `name` is stored on parked vehicles, never change it or those vehicles become unreachable.
- `robbery` (crime) — restrict burglary to MLO properties or include apartments (`allowApartments`), the lockpick item, skill check pattern, cooldown, and the alarm (a native audio file you can replace).
- `raids` (crime) — which jobs can raid, the warrant item checked at the receptionist, and the breach weapon (`WEAPON_BATTERINGRAM` from the asset list, optionally required in hand).
- `marketSociety` / `governmentAccount` (server) — society accounts receiving ownerless sale proceeds, utility bills and the non-commission share of rent; `nil` disables them.

## Setting up shells

`/shellsetup` walks a realtor through every shell that still needs its points (exit, stash, wardrobe, logout) using the laser pointer, and `/shellsetup all` re-runs every shell and IPL. Points are saved to the database and override `config/shell_defaults.lua`.

## Editor controls

While decorating: `E` toggles between the catalog and the world, **hold `F` to fly the freecam**, `Alt` selects a placed object. With an object held: `T`/`R` switch the gizmo between move and rotate, `L` switches world/local axes, `G` snaps to the ground, `H` snaps to the nearest wall, `N` snaps modular pieces together, `Enter` confirms. `Backspace` exits.

## Regenerating catalog images

The furniture catalog images in `screenshots/` are generated with a dev tool that is disabled by default. To regenerate them after adding furniture:

1. Uncomment `'server/decorating.js'` in `fxmanifest.lua`
2. Uncomment the `/screenshotfurniture` command block at the bottom of `client/decorating.lua`
3. Run `bun i` in the resource root and make sure the screencapture resource is running
4. Restart the resource and run `/screenshotfurniture` in game — it spawns a green screen, photographs every catalog entry and writes cropped transparent `.webp` files to `screenshots/`
5. Comment both blocks back out when you are done

Per-item camera tweaks (`screenshotRotation`, `screenshotFov`, `screenshotCameraOffset`) can be set on entries in the furniture catalog.
