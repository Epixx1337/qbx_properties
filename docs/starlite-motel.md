# Starlite Motel (zydrec-starlitemotel)

The [Starlite Motel](https://github.com/Zydrec/zydrec-starlitemotel) is a free MLO in East Vinewood with 30 rentable rooms: 3 floors of 10 rooms each, connected by exterior walkways and staircases. Each room is its own small MLO interior, so the config marks the building `perRoomInterior = true` and unit detection works exactly like the Prodigy towers.

## Setup

1. Drop the `zydrec-starlitemotel` resource on the server and `ensure` it before `qbx_properties`.
2. The `starlite` entry in `config/buildings.lua` is gated by `resource = 'zydrec-starlitemotel'` — if the map is missing the building silently stays disabled, nothing else to toggle.
3. Rooms self-provision on first claim, no database rows need to be created.

## No elevators

The motel only has staircases, so the entry sets `stairsOnly = true` and skips every elevator field (`lobbyElevators`, `elevator`, `garageElevator`). Any building can do this — the elevator fields have always been optional, the flag just makes the intent explicit, keeps the MLO Apartments Creator from dropping it on re-save, and switches the move-in message to point tenants at the stairs.

## Receptionist

The shipped `entrance`/`receptionist` coordinates are a courtyard placeholder. Stand where the desk should be and update both vec4s in `config/buildings.lua` — the motel office by the parking lot is the natural spot.

## Furniture defaults

The building uses `layout = 'starlite'`, so `/saveroom` inside any motel room saves the default furniture loadout for all 30 rooms.

## Wall colors

Not supported here — the interior ships entity sets, but their names are hashed and could not be recovered, so `wallEntitySet` is omitted and the paint option simply does not show.
