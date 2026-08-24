# Starlite Motel (zydrec-starlitemotel)

The [Starlite Motel](https://github.com/Zydrec/zydrec-starlitemotel) is a free MLO in East Vinewood with 30 rentable rooms: 3 floors of 10 rooms each, connected by exterior walkways and staircases. Each room is its own small MLO interior, so the config marks the building `perRoomInterior = true` and unit detection works exactly like the Prodigy towers.

## Setup

1. Drop the `zydrec-starlitemotel` resource on the server and `ensure` it before `qbx_properties`.
2. The `starlite` entry in `config/buildings.lua` is gated by `resource = 'zydrec-starlitemotel'` — if the map is missing the building silently stays disabled, nothing else to toggle.
3. Rooms self-provision on first claim, no database rows need to be created.

## No elevators

The motel only has staircases, so the entry sets `stairsOnly = true` and skips every elevator field (`lobbyElevators`, `elevator`, `garageElevator`). Any building can do this — the elevator fields have always been optional, the flag just makes the intent explicit, keeps the MLO Apartments Creator from dropping it on re-save, and switches the move-in message to point tenants at the stairs.

## Room doors

The swinging room door is **not** the MLO's base child entity (`3735113502` — that one is a static filler piece). The real door (`1474746819`, hinge at the frame corner) lives inside the interior's **entity sets** — every room variant set places it at the same interior-local spot — so the shipped config targets that:

```lua
doors = {
    {
        coords = vec3(4.454, -1.707, -0.399),
        model = 1474746819,
        headingOffset = 90.0,
    },
},
```

No map edits are needed. If a door ever registers on the wrong entity, the quickest diagnostic is to create a door on it through ox_doorlock's own UI and compare the stored `model`/`coords` with the programmatic record.

## Receptionist

The shipped `entrance`/`receptionist` coordinates are a courtyard placeholder. Stand where the desk should be and update both vec4s in `config/buildings.lua` — the motel office by the parking lot is the natural spot.

## Furniture defaults

The building uses `layout = 'starlite'`, so `/saveroom` inside any motel room saves the default furniture loadout for all 30 rooms.

## Wall colors

Not supported here — the interior ships entity sets, but their names are hashed and could not be recovered, so `wallEntitySet` is omitted and the paint option simply does not show.
