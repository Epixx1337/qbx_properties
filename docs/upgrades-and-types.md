# Property types, upgrades and house systems

## Property types

Every property has a type — `residential` (the default), `commercial`, `warehouse` or `gang` — picked in the creator and configured in `propertyTypes` in `config/shared.lua`. A type can change:

- `stashMultiplier` — scales the size of every stash in the property (warehouses ship at 3×)
- `robbery = false` — burglars cannot lockpick it (warehouses)
- `wardrobe = false` / `logout = false` — hides those interaction points (warehouses are storage, not homes)
- `groupAccess = true` — gang type: every member of the gang in the property's `group_name` gets full door, stash and furniture access on top of the owner and keyholders

The realtor sets the gang name at creation, types show as badges on market listings, and the shipped migration stamps every existing property `residential` so nothing changes for current saves.

## Upgrades

House owners buy upgrades from the housing tablet's **Upgrades** tab, charged to their bank. Upgrades show as badge tiles with an icon, description and tier progress dots — a locked tier stays hidden until the tier before it is bought. **Apartments have no upgrades at all** — the free unit stays basic on purpose, buying a house is the way up. Warehouse and gang properties have their **own separate catalogs** (`typeUpgrades` in `config/shared.lua`); every other type uses `upgrades`. `requires` chains tiers, so later tiers need the earlier ones.

Two base limits give upgrades their purpose:

- **Stash placements** come from the property's size: each entry in `propertySizes` sets `stashes` (tiny 1 → mansion 6), and storage tiers add on top (residential +2/+4/+6, warehouses and gangs considerably more). Properties without a size fall back to the global `stashLimit` (default 2).
- `keyholderLimit` (default 5) — keys a property can hand out; the key upgrade adds slots

The rest of the residential catalog: Wiring I–III (+5/10/20 kW on the breaker), Security I–II, **Second Garage** — every house supports one realtor-placed garage spot as standard, and the upgrade lets the owner aim and place one extra — and **Mood Lighting**, which unlocks the interior lighting themes (`timecycles` in shared config) on the tablet's Interior tab.

Security tiers do three things: harder lockpick patterns (`skillCheckSecure` in `config/crime.lua`), tier I alerts the owner and every online keyholder the moment someone starts forcing the door, and tier II additionally fires the police dispatch alert.

Scripts can check ownership with `exports.qbx_properties:HasPropertyUpgrade(propertyId, name)`.

## Electricity: tripping, burnout and repair

With `electricity.tripping` enabled, pushing a **house's** furniture power draw over its limit trips the breaker: powered furniture is dead and lights go out until it is repaired — stashes stay usable. Repairing needs the load back under the limit first (pick furniture up or buy wiring tiers), then someone from `electricity.repairJobs` (or an admin) passes the skill check on the tablet's **Repair breaker** button.

With `electricity.burnout` on top (the default), the overload also burns the wiring out of every powered furniture piece — each one keeps a health value in the database and sits dead even after the breaker hums again. Broken pieces get a **Repair wiring** target (same repair jobs, same skill check, breaker first), so an overloaded mansion means a proper electrician call-out. Fridges stop opening while broken, lamps stay dark.

Apartments never trip or burn out: they run on the flat included power cap and simply recover as soon as the load fits again.

## Renting out

Owners lease their house from the tablet's **Rent** tab: pick a nearby person, set the rent, the billing period (a dropdown from 24 hours up to a month, driven by `rentIntervals`) and an optional contract length in payments (0 = open-ended). The other player confirms the agreement in a popup — **the first payment is charged the moment they accept**, and if they cannot afford it both sides are told the lease fell through. Tenants get full access, the automatic charge runs each interval from their bank, and an open contract runs until someone ends it while a fixed contract ends itself on its last day.

The Rent tab shows the rate per interval, the paid-until date, the contract end and the **last 10 payments** with who paid and when. Tenants (and roommates given the **Rent** permission) can pay from there too, including several payments ahead — prepaying pushes the automatic charge back and shows up on the owner's tab immediately. A missed automatic payment still ends the lease on the spot.

Tenants can walk away at any time, but when the **owner** ends the lease the tenant gets an eviction notice instead of an instant eviction: they keep full access for `rentEvictionNoticeDays` (default 14) and the lease ends by itself when the notice runs out, with both sides notified up front. Set the option to `0` to end owner-terminated leases immediately.

## Roommate permissions

The permission editor on the **Housing Management** tab has two extra toggles per person: **Utilities** shows them the utilities tab and lets them pay the bill, **Rent** shows them the rent tab and lets them pay the rent. Both tabs log every payment with name, amount and date, so it is always visible who paid what.

## Offers

A third listing type next to sales and auctions: realtors list a property as **Open to offers** with an asking price. Buyers submit any amount at or above it — the full amount is held from their bank — and the realtor accepts or declines each offer from the listing view. Accepting transfers the property and refunds every other standing offer; declining refunds just that one.

## Mailboxes

Realtors place a property's mailbox from the manage screen: **Set mailbox** closes the tablet and hands them the laser — aim at a mailbox prop by the entrance (the target sticks to the prop) or at any spot for one. Keyed players then get a Mailbox target there: a small stash for notes and packages, usable without entering.

## Rent grace

`rentGraceHours` (shared) gives bank-rental tenants a window after a failed payment before the eviction lands. `0` keeps the old immediate eviction.

## Maintenance

Standalone owned houses owe a recurring fee: `maintenance` in shared config sets the interval in days, the percentage of the property price, a minimum amount and the seizure window. The fee auto-charges the owner's bank on the due date (online or offline); when the money is not there the owner gets warned, and `seizeAfterDays` past the due date the property is seized like an eviction. Anyone with the **Utilities** permission sees the fee on the tablet's Utilities tab and can pay it early — every payment lands in the same history as rent and utilities. Exempt: apartments of every kind (pooled units and the IPL apartments — government housing is free), anything with a price of 0, and bank rentals. Ownership changes always start a fresh cycle.

## Fridges, trash cans and pin locks

Furniture typed `fridge` opens its own stash where degradable items decay `fridges.decayMultiplier` times slower — the timer stretches on the way in and snaps back on the way out. A fridge only opens while the property has power and its own wiring is intact. Furniture typed `trash` opens a disposal stash that destroys its contents when closed.

With `storagePins` on, stash pieces carry a **Manage lock** target — but it only appears once the property owns **Security II**, so locks are the top of the security tree. Whoever sets a 4–8 digit pin opens the stash freely and is the only one who can change or remove the pin — everyone else, the owner included, has to type it. A breached property ignores pins, and an already-set pin keeps working even if the gate ever changes. Storage that still has items inside refuses to be stored or replaced by a layout, so contents can never silently vanish, and no furniture can be moved, placed or removed while the property is being raided.

## Furniture layouts

The tablet's **Layouts** tab (house properties, furniture permission) snapshots the current furnishing under a name — up to `layouts.maxPerProperty` per house. Applying a layout replaces the furniture wholesale and charges the pieces like a fresh cart purchase (first-free pieces stay free once per type); nothing applies while storage still has contents. Every layout carries a share code, and anyone can punch a friend's code into their own tablet to preview it and import it into their own house.

## Job access

Owners of **commercial and warehouse** properties grant whole jobs access from the Housing Management tab: a job name, a minimum grade and any of door, stash, furniture and garage. Everyone on that job at or above the grade carries the permissions while online — made for storefronts, mechanic shops and depots where hiring someone should not require handing out personal keys. Residential and gang properties keep personal keys only (gang properties already share through group access).

## Realtor sales of owned properties and the sales ledger

By default a realtor cannot touch an owned property. The owner flips **Authorise realtors to sell** on the Housing Management tab and realtors can list the property on the market (sale, auction or offers) — the proceeds still go to the owner, minus the usual commission. The authorisation clears on every ownership change.

Every ownership change — market sales, auctions, accepted offers, player-to-player sales and door purchases — is recorded in `properties_sales` with the property, seller, buyer, price and the seller's profit against what they originally paid. The ledger intentionally has no foreign key, so the paper trail survives even a demolished property.

## The bundled house catalog

`house_catalog.sql` in the resource root seeds 809 walk-in houses across the whole map — named, priced, typed and sized (tiny through mansion, including gang hideouts and warehouses). Nothing is listed automatically: realtors work through the catalog and put each house on the market themselves. Run it **once** by hand after the resource has booted at least once; it is deliberately not part of the automatic migrations. The doors register with ox_doorlock on the next resource start. The interiors are MLO houses: entrances whose MLO pack is not streamed on the server simply stay unenterable until the pack is added.

## Server exports

Beyond the phone API in [phone-integrations.md](phone-integrations.md):

| Export | Returns |
| --- | --- |
| `GetProperty(propertyId)` | property summary with decoded coords |
| `GetProperties(search?)` | property list, optionally name-filtered |
| `GetFurniture(propertyId)` | every decoration in the property |
| `RemoveDecoration(decorationId)` | deletes a piece and syncs clients |
| `GetPlayerProperty(source)` | the property id the player is inside, if any |
| `GetPlayersInside(propertyId)` | server ids currently inside |
| `GetListings()` | active market listings |
| `HasPropertyUpgrade(propertyId, name)` | upgrade ownership |
