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

- `stashLimit` (default 2) — stash furniture pieces a property can hold; storage tiers raise it (residential +2/+4/+6, warehouses and gangs considerably more)
- `keyholderLimit` (default 5) — keys a property can hand out; the key upgrade adds slots

The rest of the residential catalog: Wiring I–III (+5/10/20 kW on the breaker), Security I–II, and **Second Garage** — every house supports one realtor-placed garage spot as standard, and the upgrade lets the owner aim and place one extra.

Security tiers do three things: harder lockpick patterns (`skillCheckSecure` in `config/crime.lua`), tier I alerts the owner and every online keyholder the moment someone starts forcing the door, and tier II additionally fires the police dispatch alert.

Scripts can check ownership with `exports.qbx_properties:HasPropertyUpgrade(propertyId, name)`.

## Electricity: tripping and repair

With `electricity.tripping` enabled, pushing a **house's** furniture power draw over its limit trips the breaker: powered furniture is dead and lights go out until it is repaired — stashes stay usable. Repairing needs the load back under the limit first (pick furniture up or buy wiring tiers), then someone from `electricity.repairJobs` (or an admin) passes the skill check on the tablet's **Repair breaker** button.

Apartments never trip: they run on the flat included power cap and simply recover as soon as the load fits again.

## Renting out

Owners lease their house from the tablet's **Rent** tab: pick a nearby person, set the rent, the billing interval and an optional contract length in payments (0 = open-ended). The other player confirms the agreement in a popup — **the first payment is charged the moment they accept**, and if they cannot afford it both sides are told the lease fell through. Tenants get full access, the automatic charge runs each interval from their bank, and an open contract runs until someone ends it while a fixed contract ends itself on its last day.

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
