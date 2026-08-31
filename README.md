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

Every active listing as a photo card with type badges and live countdowns, filterable by direct sales, auctions, open-to-offer listings and your saved listings, with sorting and a recently-viewed strip. Realtors see the same page plus their tools.

![Listing detail](.github/media/market-listing.png)

A listing opened: photo gallery with thumbnails, the realtor's pitch, property facts and running costs. Auctions show the current bid, time left, a bid box and (for realtors) the live bid feed; offer listings escrow the full amount until the realtor accepts or declines.

### New property

![Interior pick](.github/media/new-property-interiors.png)

A four-step wizard. Step one picks the interior — IPL apartments already exist in the world and only need an entrance, shells get spawned and positioned, or start an MLO property where you stand.

![Point capture](.github/media/new-property-mlo.png)

Step two captures the world points: interior point or entrance, doors with the laser, the shell position (placeable from a freecam), and optionally a garden zone and a garage spot. Each row rings green when done.

![Review](.github/media/new-property-review.png)

Steps three and four: name, price, size, type and the listing summary, then a review card with the option to list immediately as a sale, auction or open to offers.

![Creating in the world](.github/media/new-property-ingame.png)

All of it happens standing at the property, not in a config file.

### Manage

![Property list](.github/media/manage.png)

Every property on the server as a card with its photo, status and owner, searchable and filterable.

![Property details](.github/media/manage-details.png)

A selected property: edit price/size/rental/description, manage listing photos, re-place the garage, redraw the garden, set the mailbox, and for MLOs re-set the interior point or add more doors. Realtors can enter unowned properties remotely to fix their interior points — owned properties are off limits.

### Buildings

![Buildings tab](.github/media/buildings.png)

Multi-unit buildings: pick a building and floor, see every unit's occupancy at a glance, and create the remaining units in bulk with a price and rental terms.

### Housing tablet

![Tablet utilities](.github/media/tablet-utilities.png)

The tablet mounted in a property (the wall intercom prop by [CodexisPhantom](https://github.com/CodexisPhantom)): live power draw against the allowance, humidity, the bill, and the biggest power consumers.

![Tablet upgrades](.github/media/tablet-upgrades.png)

Property upgrades as badge tiles with tier progress — the next tier only appears once the previous one is bought. Room management, tenancy and wall colours live in the same tablet.

### MLO Apartments Creator

![Creator start](.github/media/mlo-creator-start.png)

Turns any multi-room MLO into an apartment building. It scans the interior you are standing in and detects the room naming pattern.

![Creator capture](.github/media/mlo-creator.png)

Walk the building capturing the entrance, receptionist, elevators, floor heights and one anchor per room — it validates as you go and writes `config/buildings.lua` when everything lines up.

## Features

**Properties**
- Pooled IPL apartments (Del Perro, Integrity Way, Richard Majestic, Tinsel Towers) plus multi-unit apartment buildings with per-floor rooms, doorbells and shared parking garages — the Wiwang Hotel, the four Prodigy towers ([docs/prp-apartments.md](docs/prp-apartments.md)) and the Starlite Motel ([docs/starlite-motel.md](docs/starlite-motel.md)) ship preconfigured
- Garages register with qbx_garages by default or bridge to jg-advancedgarages, cd_garage or okokGarage through one config option — see [docs/garage-systems.md](docs/garage-systems.md)
- Phone home apps hook in through secured exports (list homes, waypoint, lock doors, manage keys) — drop-in lb-phone files and an sd-phone adapter ship in [docs/phone-integrations.md](docs/phone-integrations.md)
- Property types (residential, commercial, warehouse, gang with group access), per-type purchasable upgrades (stash and key limits, wiring, security alerts, a second garage, mood lighting), breaker tripping with electrician repairs, escrowed offers and realtor-placed mailboxes — see [docs/upgrades-and-types.md](docs/upgrades-and-types.md)
- Property sizes carry real limits: each size sets the power allowance, the utility bill and the base number of stash placements (a tiny house fits one stash, a mansion six) — storage upgrades add to whatever the size allows
- An overload does more than trip the breaker: every powered furniture piece burns out and stays dead until an electrician repairs the breaker first and then rewires each piece through its target
- Maintenance: standalone properties owe a recurring ownership fee (a percentage of the price with a floor), auto-charged from the owner's bank, payable by roommates from the tablet, with seizure after too long unpaid
- Owner-to-player leasing from the tablet's Rent tab: contract periods, the first payment charged on acceptance, prepayable rent, a payment history, roommate permissions for rent and utilities, and eviction notices when the owner ends a lease
- Job access on commercial and warehouse properties: owners grant a whole job (with a minimum grade) door, stash, furniture or garage access — made for storefronts and depots, residential homes keep personal keys only
- Furniture layouts: save the current furnishing as a named snapshot, re-apply it later, or hand its share code to a friend so they can import it into their own property (applying pays for the furniture like a fresh purchase)
- Owners can authorise realtors to sell their occupied property on the market — the proceeds still come to the owner — and every ownership change lands in a sales ledger with the seller's profit
- Doorbell and doorcam: visitors ring at MLO doors, shell entrances and apartment unit doors; everyone inside gets notified, sees who is outside on the tablet's Doorcam tab, can watch a live camera over the door (multi-door houses cycle between every registered door), and lets them in — teleported inside for shells and apartments, a 10-second door unlock for MLOs. Realtors can also place an exact doorcam with the laser from the Manage tab, which overrides the automatic camera
- Tenants can relocate between buildings, gated by config: free moves at the reception, plus a one-time migration offer on login whenever new buildings open with free rooms
- Admins can furnish a unit and run `/saveroom` to save it as the default loadout for that room layout — every fresh tenant starts with those pieces already placed and fully editable
- Standalone properties using interior shells, IPL interiors or real MLO houses
- MLO properties live in the actual world: walk in through the (locked) front door, furniture and stashes load in place, and extra doors can be added at any time
- Owned properties show house and garage blips, and can be spawned into from the spawn selector

**Realtor job**
- Create properties entirely in game through a four-step wizard: pick the door with a laser pointer, capture the interior point, position shells with a gizmo and a fly-anywhere freecam, write the listing summary, and set price, size, type and rental terms
- Manage menu: server-side search, Available/Owned filters and pagination over the whole catalog (apartment units live on the Buildings tab), edit price/size/description, take property photos, place garages, draw garden zones, set mailboxes, add doors, re-capture the interior point and enter properties remotely
- `/housephotos` tours every house without a photo: teleported door to door in a freecam, frame the shot yourself, `E` to snap and move on — the result becomes the property's main market picture, saved locally or on the CDN
- Realtor access is scoped to unowned properties — owned doors, interiors and furniture are out of reach (raids are the sanctioned way in), though owners can authorise realtors to list their property for sale
- Realtors earn a configurable commission on sales and rent of properties they created

**Decorating**
- Furniture catalog with preview images, freecam and a gizmo for placement
- Catalog categories are icon tiles with hover tooltips and optional subcategory groups, fully configurable with any Font Awesome icon (`furnitureCategories` in `config/client.lua`)
- Snapping: to the ground, to the nearest wall, and modular pieces (walls, floors, stairs, arches) snap to each other; doors seat into arches
- 32 tint colours on the bundled structural props, matching the wall colour palette
- Fine-tune panel for exact coordinates and small nudges, including screen-relative movement
- Furniture can carry a `price` — priced pieces land in a shopping cart and get paid for in one go, and an unpaid cart is set aside when you leave the editor and offered back next time
- Inventory items can become furniture: scripts register their item and the player places it inside their property, metadata intact, with a pickup button in the editor to take it back. The crafting bench uses this — see [docs/placeable-items.md](docs/placeable-items.md)
- Garden zones are decoratable too — walk into your garden and the same editor opens from the radial menu
- Other players inside the property (or garden) see furniture being moved live while you edit
- Stash furniture registers real ox_inventory stashes with persistent slots, so removing and replacing a stash reconnects its contents — and storage that still has items inside refuses to be removed
- Stash furniture takes a pin code once the property owns the Security II upgrade: whoever sets the pin opens freely, everyone else (the owner included) needs the digits — privacy between roommates, void while the property stands breached
- Fridges are real appliances: their stash keeps degradable food fresh (decay runs several times slower inside), and they stop opening when the power is cut or their wiring burned out
- Trash cans open a throwaway stash that destroys whatever is left inside when it closes
- Wardrobe and logout furniture (logout can be disabled in config)
- Two housing tablet props ship — the wall intercom and the classic tablet — and either opens the tablet; the intercom's body recolours through the same tint palette as the structural props, and custom props without collision get their ox_target through an automatic fallback

**Economy**
- Market with direct sales, auctions (configurable durations, anti-snipe) and open-to-offer listings with full escrow, plus saved listings and a recently-viewed strip
- The market UI can be embedded in laptop and tablet resources (fd_laptops and similar), with `/housing` optionally disabled — see [docs/third-party-ui.md](docs/third-party-ui.md)
- Rent cycles, utility billing with power usage and humidity per property size, and a recurring maintenance fee with seizure for deadbeats
- A sales ledger records every ownership change with price and the seller's profit, and it survives the property being deleted
- Optional society/government accounts for proceeds and bills
- `house_catalog.sql` seeds 809 ready-made walk-in houses (Rancho to Vinewood, tiny to mansion, priced and typed) for realtors to list at their own pace — run it once by hand; interiors need the matching MLO house packs streamed

**Crime**
- Burglary through lockpicking with a skill check, alarm sound (native audio, replaceable) and dispatch hooks
- Police raids: search warrant at a receptionist, battering ram door breach, access to the property while the raid is active

## Dependencies

- [qbx_core](https://github.com/Qbox-project/qbx_core)
- [ox_lib](https://github.com/CommunityOx/ox_lib)
- [oxmysql](https://github.com/CommunityOx/oxmysql)
- [ox_inventory](https://github.com/CommunityOx/ox_inventory)
- [ox_target](https://github.com/CommunityOx/ox_target)
- [ox_doorlock](https://github.com/CommunityOx/ox_doorlock) for property and apartment doors — needs a few small additions, see below
- screencapture (the screenshot-basic replacement) for realtor property photos

**Optional integrations** (detected at runtime, everything works without them)

- [Renewed-Banking](https://github.com/Renewed-Scripts/Renewed-Banking) — receives the `marketSociety` and `governmentAccount` payouts; without it those payouts are skipped
- [scully_emotemenu](https://github.com/Scullyy/scully_emotemenu) — its keybinds are suspended while decorating so emote keys can't fire mid-edit

**Assets used by specific features**

- [CodexisPhantom](https://github.com/CodexisPhantom) — the `cdx_intercom_prop` wall intercom streamed with the resource and used as the housing tablet prop
- [Battering-Ram](https://github.com/Epixx1337/Battering-Ram) — the two-handed ram weapon (`WEAPON_BATTERINGRAM`) used for police door breaches, with its looping breach animation
- [wiwang_hotel](https://github.com/Epixx1337/wiwang_hotel) — our edit of the Wiwang Hotel MLO with per-room `wall_tint` entity sets, required for wall colours inside its apartments
- [prp-housing shells](https://studio.prodigyrp.net/map) — the ProdigyRP house MLOs, required for wall colours in those interiors
- The free starter shells are from [K4MB1](https://forum.cfx.re/t/free-props-starter-shells-for-housing-scripts/4826922)

## Installation

1. Remove `qbx_apartments` and `qbx_houses`
2. Either use no spawn system (the core defaults to last location) or [qbx_spawn](https://github.com/Qbox-project/qbx_spawn)
3. Start the resource once — it creates and migrates its database tables automatically from `schema.sql`, adding any missing columns on existing databases. Run `schema.sql` by hand only when the database user may not CREATE and ALTER.
4. Set your Qbox CDN API key (see below) if you want realtor photos
5. Ensure the resource starts after its dependencies

The NUI is prebuilt in `web/build`. To rebuild after changing it: `cd web && bun i && bun run build`.

## Using a different multicharacter or spawn system

Nothing here depends on a specific multicharacter UI. Apartment assignment hooks `QBCore:Server:OnPlayerLoaded`, which qbx_core fires every time a character loads — so any multicharacter that logs characters in through qbx_core triggers it unchanged.

**First-login apartments** need `characters.startingApartment = true` in qbx_core's `config/client.lua`. When a character loads with no property and no assigned unit, the apartment picker opens automatically; choosing a building grabs a free unit through the dynamic assignment (or creates an owned IPL apartment). There is no export to assign a unit because none is needed — it all happens on login. If you ever want to reopen the picker manually (say from your own intro flow), trigger the client event `apartments:client:setupSpawnUI` for that player.

**Spawn selectors** are equally swappable. Without qbx_spawn, qbx_core spawns characters at their last location and everything still works — players who logged out inside an MLO wake up where they stood, and players who logged out inside a shell or IPL interior are re-entered through their property automatically. A custom spawn selector only needs two integration points:

- To spawn a player into a property they own, trigger the server event `qbx_properties:server:enterProperty` with `{ id = propertyId }` shortly after `QBCore:Server:OnPlayerLoaded` — within the first minute after loading it is treated as a spawn, so the distance check is skipped and the screen fades in once they are inside.
- For a "last location inside their home" option, read the character's `metadata.currentPropertyId`; when it is set, pass that id through the same event instead of teleporting to raw coordinates. MLO properties don't need this — their saved position is a real-world coordinate.

The list of properties a character owns is a plain query on the `properties` table by `owner` citizenid, which is how qbx_spawn builds its spawn list.

## ox_doorlock additions

Stock ox_doorlock only manages doors through its admin UI and has no access hooks, so it needs three small additions. Without them the resource prints a warning on start and property doors are skipped.

**1. The hook system.** Copy [docs/ox_doorlock/hooks.lua](docs/ox_doorlock/hooks.lua) into ox_doorlock's `server/` folder, then wire it into `server/main.lua`. At the top of the file:

```lua
local TriggerEventHooks = require 'server.hooks'
```

And at the end of the authorisation function (right after the `::continue::` label, replacing the plain `return authorised`):

```lua
    local hookResult = TriggerEventHooks('doorAuthorization', {
        source = playerId,
        door = door,
        lockpick = lockpick,
        authorised = authorised,
    })

    if hookResult == nil then return authorised end

    return authorised or hookResult
```

qbx_properties registers a `doorAuthorization` hook on its own doors to let owners, keyholders and realtors through, and to unlock everything while a door is breached — normal ox_doorlock doors are untouched thanks to the hook's name filter.

**2. Two exports** in `server/main.lua`, slotted in after the existing ones — `createDoorProgrammatic` to register doors at runtime and `removeDoorByName` to clean them up:

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

## Property photos

Every property carries a photo gallery shown on market cards, listings and the realtor panel. Photos come from two flows:

- **Add photo** on a property in the Manage tab — captures the realtor's current view.
- **`/housephotos`** — the guided photo tour for realtors. It flies you house by house to every property that has no photo yet (`/housephotos all` revisits everything), dropping the camera at the front door, and you frame the shot yourself: fly with `WASD`, `G` takes the photo and jumps to the next house, `X` skips one, `Backspace` ends the tour. The shot becomes the property's **main picture** (first in the gallery). Framing is manual on purpose — doors face every direction, so no automatic angle gets it right. While a tour runs, `housePhotos.hideDoorSprites` (shared config, on by default) hides the ox_doorlock sprite on every property door so no lock icon ends up in a shot — each door is put back exactly how it was when the tour ends.

Photos save as **local files** in `screenshots/` out of the box, streamed to clients like the furniture thumbnails — no CDN account needed. **Local photos taken this session appear after the next resource restart** (FiveM only streams files present at start). With an upload provider configured (below) photos go to the CDN instead and appear immediately; if an upload fails the local file is kept as a fallback. Removing a photo (or deleting the property) cleans up both the CDN copy and the local file.

### Uploading to a CDN

Three providers are supported out of the box — pick one, create an API key on their dashboard, and set it in `config/server.lua`:

```lua
imageUpload = {
    provider = 'qbox', -- 'qbox', 'fivemanage', 'fivemerr' or 'custom'
    apiKey = 'YOUR_API_KEY',
    maxImages = 5,
},
```

| Provider | Get a key | Deletes on photo removal |
| --- | --- | --- |
| `qbox` | [Qbox CDN dashboard](https://docs.qbox.re/dashboard/cdn) | yes |
| `fivemanage` | [Fivemanage dashboard](https://docs.fivemanage.com) | yes |
| `fivemerr` | [Fivemerr dashboard](https://docs.fivemerr.com) | no delete API |

With the key left empty, the Take photo button reports that uploads are not configured and `/housephotos` saves local files — everything else keeps working. Any other host that accepts multipart uploads and returns a URL in its JSON response works too — set `provider = 'custom'` and fill in the `custom` block (`url`, `field`, `responsePath`, and optionally `storagePath`/`deleteUrl` if the host supports deletion).

## Configuration

| File | Contents |
| --- | --- |
| `config/shared.lua` | realtor jobs, property sizes, market rules, utilities, wall colours, apartment garages |
| `config/client.lua` | furniture catalog, interior IPL data, editor settings |
| `config/server.lua` | payouts, rent, stash sizes, image upload |
| `config/crime.lua` | robbery and raid rules, alarm sound |
| `config/dispatch.lua` | hooks to send alerts to whatever dispatch the server runs |
| `config/buildings.lua` | multi-unit apartment building layouts (written by the MLO Apartments Creator) |
| `config/garages.lua` | adapters for third-party garage systems |
| `config/shell_defaults.lua` | interaction points for the bundled shells |

Options worth knowing about:

- `realtorJobs` / `realtorRequiresDuty` (shared) — which jobs and grades get the realtor tabs, and whether they must be on duty.
- `propertyLimit` (shared) — how many properties one character may own at once, **per property type** (residential, commercial, warehouse, gang), enforced on every purchase path (buy, rent-to-own, auctions, offers, player sales). Apartments never count. `0` = unlimited for that type; a plain number instead of the table acts as one shared limit across all types.
- `prefixes` (shared) — the identifier prefixes used for ox_inventory stashes, ox_doorlock doors and garage names. Only change these on a fresh server: on a live one everything created under the old prefix (stash contents, door records, parked vehicles) keeps its old name and becomes unreachable.
- `logging` (server) — set `logging.discordWebhook` to a Discord webhook url and every action log goes there as an embed instead of ox_lib's logger.
- `logoutEnabled` (shared) — beds and logout points let players switch character; `false` hides them everywhere.
- `furnitureShop` (shared) — `false` ignores all furniture prices, so everything places instantly for free and the cart never appears.
- `furnitureCategories` (client) — icons, labels, ordering and grouping for the furniture catalog. Each category shows as an icon tile with a hover tooltip; `icon` takes any [Font Awesome free](https://fontawesome.com/icons) class (e.g. `'fa-solid fa-couch'`), `order` sorts the row, and `parent` nests a category as a subcategory of another (the bundled walls/arches/stairs/floors sit under a `structure` group). Categories without an entry get a generic icon and their capitalised key.
- `furnitureImageSource` (shared) — `'cdn'` lazy-loads the furniture catalog thumbnails from uploaded CDN copies instead of resource files, see "Regenerating catalog images".
- `apartmentChoice` (shared) — `false` skips the apartment picker at character creation and assigns the first available apartment automatically. A single active building already skips the picker on its own.
- `freeApartmentMoves` (shared) — `false` locks tenants to their apartment building; the reception refuses switching.
- `migrationOffer` (shared) — `false` disables the one-time relocation offer shown on login when other buildings have free rooms.
- `housingCommand` (shared) — `false` removes the `/housing` command; the UI stays reachable through the `openHousing` export or an embedded app, see [docs/third-party-ui.md](docs/third-party-ui.md).
- `garageSystem` (shared) — `'qbx'` uses qbx_garages; other values bridge property and apartment garages to third-party garage scripts, see [docs/garage-systems.md](docs/garage-systems.md). `prettyGarageNames` makes bridged systems show the plain property name instead of `property_fudge_ln_4`-style ids — fresh servers only, see the doc for the migration note.
- `stairsOnly` (buildings) — marks an apartment building without elevators, like the Starlite Motel: elevator fields are skipped and move-in messages point at the stairs.
- `targetInteractions` (shared) — MLO furniture uses ox_target labels instead of floating interaction points.
- `targetShellInteractions` (shared) — `true` replaces the floating drawtext on shell and IPL properties with ox_target zones, both on the interaction points inside (stash, exit, clothing, logout) and on the entrance outside.
- `targetDistances` (shared) — how close a player must stand (in metres) before each target or drawtext activates: entrances, interior interaction points, placed furniture, mailboxes, doorbells and door forcing are all tunable separately.
- `propertySizes` (shared) — each size sets the power allowance (W), the monthly utility cost and the base number of stash placements; realtors pick the size on creation. Sizes without `stashes` fall back to the global `stashLimit`.
- `propertyTypes` / `upgrades` / `keyholderLimit` / `electricity` / `mailbox` / `rentGraceHours` (shared) — property types, the upgrade catalog, breaker tripping and mailbox settings, see [docs/upgrades-and-types.md](docs/upgrades-and-types.md).
- `electricity.burnout` (shared) — an overload burns out every powered furniture piece; each needs its own "Repair wiring" target (same jobs as the breaker) after the breaker is fixed. `false` keeps the old breaker-only behaviour.
- `fridges.decayMultiplier` (shared) — how many times slower degradable items decay while inside a fridge stash.
- `storagePins` (shared) — pin-code locks on stash furniture, unlocked by the Security II upgrade; `false` removes the Manage lock target and every pin prompt.
- `maintenance` (shared) — the recurring ownership fee: interval, percentage of the property price, minimum amount, and after how many unpaid days the property is seized (`0` never seizes). `enabled = false` turns the whole system off.
- `layouts` (shared) — furniture layouts: on/off and how many snapshots one property may keep.
- `rentIntervals` (shared) — the billing periods offered in every rental dropdown, from 24 hours up to a month out of the box.
- `doorcam` (shared) — height and rotation offsets for the automatic doorbell camera on shell and IPL properties; a realtor-placed doorcam from the Manage tab always wins over these. Apartment buildings can pin an exact camera per room layout with a `doorcam` entry in `config/buildings.lua` (the Wiwang and Starlite layouts ship with one).
- `timecycles` (shared) — the interior lighting themes offered by the Mood Lighting upgrade.
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

The furniture catalog images in `screenshots/` are shot in game by the admin-only `/screenshotfurniture` command (requires the screencapture resource to be running — nothing to uncomment, nothing to install):

- `/screenshotfurniture` photographs every catalog entry that has no image yet, so interrupted runs resume where they stopped; `/screenshotfurniture overwrite` reshoots everything, `/screenshotfurniture manual` starts paused with full control per shot.
- Each item is captured twice against two backdrop colors and a difference matte solves the exact per-pixel alpha — transparent parts, glass and green furniture come out clean. The image is cropped, encoded to webp in the NUI and saved to `screenshots/`, no external image tooling involved.
- The studio panel (top right) can pause a batch at any time: navigate items with ◀ ▶, drag ←→ to rotate the piece, drag ↑↓ to raise or lower the camera, scroll to zoom, nudge the FOV, and swap the backdrop color for pieces that blend into it. **Shoot** reshoots the current item with the current framing, **Save framing** persists it to `screenshots/_tuning.json` so every future batch uses it — it overrides the `screenshotRotation`/`screenshotFov`/`screenshotCameraOffset` catalog fields, which still work as before.

### Serving the images from a CDN

`screenshots/` normally streams to every client with the resource. To serve the thumbnails over HTTP instead:

1. Configure `imageUpload` in `config/server.lua` (the same provider used for property photos). `autoUpload = true` uploads every shot as it is saved, or run `/screenshotfurniture upload` to push everything missing (`uploadall` re-uploads all) — the file → URL mapping is kept in `screenshots/_cdn.json`.
2. Set `furnitureImageSource = 'cdn'` in `config/shared.lua`. The catalog lazy-loads thumbnails from the CDN — only what is on screen is fetched — and any image without an uploaded copy falls back to the local file, so a partial upload never breaks the UI.
3. Once everything is uploaded, the `screenshots/*.webp` entry can be removed from `files {}` in `fxmanifest.lua` so clients stop downloading the images entirely.
