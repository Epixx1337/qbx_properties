# Prodigy apartments (prp-apartments)

qbx_properties ships building configs for the four Prodigy Studios towers — `lombank1`, `lombank2`, `eclipse` and `tinsel` — as dynamic apartment buildings alongside the Wiwang Hotel. Every tower carries `resource = 'prp-apartments'`, so when the map resource is not running the buildings disappear on their own: no receptionist, no spawn option, no move-in.

## How the towers differ from Wiwang

Prodigy rooms are individual MLO interiors rather than named rooms inside one big interior, so the config marks them `perRoomInterior = true` and unit detection matches the interior you are standing in against the configured room anchors instead of interior room names.

All four towers share the same room floorplan, tagged `layout = 'prp'`. Furniture is stored per layout, which means:

- Moving between any of the four Prodigy towers keeps your furniture and stash exactly as they were.
- Moving between Wiwang and a Prodigy tower starts you with an empty room — the layouts do not match, so nothing is restored into the wrong walls. Your old furniture is kept dormant and comes back if you ever move back into a building with that layout.
- Stash contents always follow you; only the placed furniture is layout-bound.

## Setting up prp-apartments

1. Start the `prp-apartments` resource, and ensure it starts **before** qbx_properties — receptionists and gating are evaluated when qbx_properties boots.
2. Stand its door locking down — qbx_properties registers the unit doors through ox_doorlock instead, server-authoritative and keyed to owners, keyholders and raids. Do **not** remove `client/apartment.lua` from the manifest (the floor loader calls into it); add one guard at the top of its `GenerateApartments` function instead:

```lua
function GenerateApartments(floor, buildingId)
    if GetResourceState('qbx_properties') == 'started' then return end

    Wait(1000)
```

With qbx_properties stopped, prodigy's own door locking takes over again unchanged.

3. That is it — every configured room is claimable immediately. Moving in assigns a free room and creates its record on demand at no cost. If you want units to carry a price or rent instead, pre-create them as a realtor through the **Buildings** tab; pre-created units keep whatever terms you set.

## Showing the player's room in the elevator

Prodigy's elevator keeps handling floor travel — do not disable it. To make it highlight the rider's own floor and room, replace the ownership check in `client/elevator.lua`. Above `local function getFloorLabel`, add:

```lua
local qbxBuildingKeys = { 'lombank1', 'lombank2', 'eclipse', 'tinsel' }
local myUnit

CreateThread(function()
    while true do
        if GetResourceState('qbx_properties') == 'started' then
            local ok, unit = pcall(function() return exports.qbx_properties:getMyUnit() end)
            myUnit = ok and unit or nil
        end
        Wait(15000)
    end
end)
```

Then in `openElevatorMenu`, swap the `LocalPlayer.state.apartment` block for:

```lua
local isMine = myUnit
    and myUnit.building == qbxBuildingKeys[elevator]
    and myUnit.floor == getFloorNumber(floor.floor)

floorOptions[#floorOptions + 1] = {
    title = locale("FLOOR") .. " - " .. getFloorLabel(floor.floor) .. (isMine and " " .. locale("YOUR_ROOM") or ""),
    description = isCurrent and locale("CURRENTLY_ON_THIS_FLOOR") or (isMine and myUnit.label or nil),
    icon = isMine and "house" or "elevator",
    iconColor = isMine and "#40c057" or nil,
    onSelect = function()
        useElevator(floor.location, floor.heading)
    end,
    disabled = isCurrent
}
```

`getMyUnit` returns `{ building, floor, room, label }` for the unit the player owns, so the elevator shows the floor with a green house icon and the unit name underneath. The Wiwang map resource's optional `elevators.lua` uses the same export the same way.

## Migrating existing tenants

When a server adds new buildings, players who already rent an apartment get a one-time offer on their next login: a menu listing every other active building that has free units, plus a "stay where I am" option. Picking a building releases their old unit and assigns one in the new tower — stash contents follow, and furniture comes back whenever they live in a building with a matching room layout. The decision is stored in the character's metadata (`apartmentMigration`), so the menu never appears again — including for players who choose to stay.

The offer only appears when there is somewhere to go: buildings whose map resource is stopped and buildings with every room occupied are never listed.

Two shared config options control movement between buildings. `migrationOffer = false` disables the login offer entirely. `freeApartmentMoves = false` locks tenants to their building — the reception refuses moving in elsewhere — while the one-time migration offer still works, since it is the sanctioned way to relocate after an update.

## Default room furniture

Admins can give every fresh unit a starting loadout. Furnish a unit the way new tenants should receive it — a mounted housing tablet, for example — then stand inside it and run `/saveroom` (admin only). Every non-item piece in the unit is saved as the default for that room **layout**, positions and rotations relative to the room, so it lands correctly in every room, orientation and tower sharing the layout.

From then on, any character receiving their first unit in that layout gets the loadout copied in as their own furniture: it appears in their furniture list, can be recoloured, moved or removed like anything they placed themselves, and stash pieces get proper stash slots. Characters who already own furniture in the layout are never touched, and re-running `/saveroom` replaces the defaults for future tenants only.

## Database

The `layout` column on `properties_apartment_decorations` comes from `property_apartment_layouts.sql`; the startup migrator applies it automatically and stamps existing furniture as `wiwang`.
