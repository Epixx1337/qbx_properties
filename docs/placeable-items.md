# Placeable inventory items

Other resources can turn their inventory items into real property furniture: the item leaves the inventory (metadata intact), becomes a decoration in the property or garden the player is standing in, streams in and out with it like any other furniture, counts toward utilities, and can be picked back up into the inventory from the furniture menu.

## How it works

1. Your resource registers a furniture definition for the item's prop on **both** the client and the server.
2. When the item is used, you call the `placeItem` export. The player positions the prop with the gizmo and confirms.
3. qbx_properties verifies the player owns the property (or garden) they are standing in, removes the item from that inventory slot, stores its metadata on the decoration row, and syncs the prop to everyone inside.
4. The owner can later select the prop in the furniture menu and press **Pick up into inventory** — the row is deleted and the item returns with its stored metadata. If the definition sets `durability`, that amount is subtracted from `metadata.durability` on pickup.

Placement and pickup are owner-only, and both work in properties, apartments, building units and garden zones.

## Registering the furniture definition

Call this once on resource start, in a shared file or in both a client and a server file — the definition must exist on both sides.

```lua
exports.qbx_properties:registerFurniture({
    object = 'prop_bench_01a',   -- the prop model
    label = 'Park Bench',
    item = 'bench',              -- the ox_inventory item name
    power = 0,                   -- watts drawn while placed, counts toward the property's utilities
    humidity = 0,
    image = 'nui://ox_inventory/web/images/bench.png', -- shown in the furniture menu, defaults to the item's inventory image
    durability = 10,             -- subtracted from the durability metadata on every pickup, omit to disable
    durabilityKey = 'durability', -- which metadata field tracks it (e.g. 'uses'), defaults to 'durability'
    durabilityMax = nil,         -- starting value when the item has no such metadata yet
})
```

`power` uses the same utilities logic as built-in furniture: a placed item with `power = 150` adds 150W to the property's load, shows up on the housing tablet, and stops mattering the moment it is picked up.

## The image in the furniture menu

Placed item furniture shows an image in the furniture menu's Placed list, resolved in this order:

1. The `image` from your furniture definition — any `nui://` URL works, so you can point it at your own resource's files too, e.g. `nui://my_benches/images/bench.png`.
2. When no `image` is set, the item's ox_inventory image is used automatically: `nui://ox_inventory/web/images/<item>.png`.

So if your inventory image is simply named after the item, you don't have to set anything. Set `image` explicitly when the filename differs from the item name — the crafting bench does this because its item is `craftingbench` but its images are `craftingbench_tier1.png` and `craftingbench_tier2.png`, one per registered model.

## Example: a placeable bench item

ox_inventory item definition:

```lua
['bench'] = {
    label = 'Park Bench',
    weight = 15000,
    degrade = 20160,
    client = {
        export = 'my_benches.bench',
    },
},
```

The usable item handler in your resource (`my_benches`):

```lua
-- client
exports('bench', function(data, slot)
    exports.qbx_properties:placeItem({
        item = 'bench',
        model = 'prop_bench_01a',
        label = 'Park Bench',
        slot = slot.slot,
        metadata = slot.metadata,
    })
end)
```

That is the whole integration. `placeItem` returns `false` immediately when the player is not inside a property or garden (with a notify), when the model is invalid, or when they cancel the placement.

If your resource already has its own placement preview (like the crafting bench's raycast placement), skip the gizmo and hand over the final position instead:

```lua
exports.qbx_properties:placeItemAt({
    item = 'bench',
    model = 'prop_bench_01a',
    slot = slot.slot,
    coords = coords,   -- vector3 chosen by your placement UI
    heading = heading,
})
```

This keeps the placement feel identical whether the item lands in the world or in a property.

## Checking where the player is

Two client exports are available if you want to gate your own logic (for example, only allow the "place" option in the item's context menu while inside):

```lua
local propertyId = exports.qbx_properties:getCurrentPropertyId()
local gardenId = exports.qbx_properties:getCurrentGardenId()
```

Both return `nil` when the player is outside. `getCurrentPropertyId` covers walk-in MLO properties, shell/IPL interiors and apartment building units.

## An electric example

A placeable heater that draws power and wears out:

```lua
exports.qbx_properties:registerFurniture({
    object = 'prop_heater_01',
    label = 'Space Heater',
    item = 'heater',
    power = 1200,
    humidity = -5,
    durability = 5,
})
```

While placed it adds 1.2kW to the property (which can trip the power limit for small properties), dries the air slightly, and loses 5 durability every time it is picked back up.

## Advanced: server hooks

When an item needs its own server-side state to survive placement (a crafting bench keeping its stash, uses and recipes), register hooks instead of the simple durability fields. Each hook names an export on your resource; qbx_properties calls it at the right moment and your export controls the metadata:

```lua
exports.qbx_properties:registerFurniture({
    object = 'gr_prop_gr_bench_04a',
    label = 'Crafting Bench',
    item = 'craftingbench',
    serverHooks = {
        resource = 'ox_inventory',
        onPlace = 'propertyBenchPlace',   -- ({source, item, metadata, coords, rotation}) -> metadata | false
        onPickup = 'propertyBenchPickup', -- ({source, item, metadata}) -> metadata | 'destroy' | false
        onMove = 'propertyBenchMove',     -- ({metadata, coords}), fires when the piece is repositioned
    },
})
```

- `onPlace` runs after the item leaves the inventory. Return the (possibly extended) metadata to store — returning `false` refunds the item and aborts.
- `onPickup` runs before the item is returned. Return the metadata to hand back, `'destroy'` to delete the furniture without returning anything (the bench broke), or `false` to block the pickup (the bench is busy).
- `onMove` lets you keep external state (like a range-checked interactable) in sync when the owner repositions the piece.
- When `onPickup` is set, the built-in durability fields are ignored.

For world interactions on the placed prop, listen for the client event `qbx_properties:client:itemFurniture(action, decorationId, entity, item, metadata)` — `action` is `'spawn'` or `'remove'` — and attach/remove your ox_target options on the entity. This is how the crafting bench gets its Open and (police-only) Destroy options while placed in a property. Item-backed furniture cannot be deleted from the furniture menu, only picked up, so external destroy flows should call `exports.qbx_properties:removeItemDecoration(decorationId)` after cleaning up their own state.

## Notes

- Metadata is stored as-is on the decoration row (`item_metadata`) and returned untouched on pickup, apart from the optional durability subtraction. Serial numbers, contents, custom fields all survive.
- If the player's inventory cannot hold the item on pickup, nothing is deleted and they are told they cannot carry it.
- Placed items are plain decorations: no stash/wardrobe/logout interactions are attached, and they do not appear in the buy catalog. Add your own ox_target options against the prop model if the item should stay usable while placed.
- The `item` and `item_metadata` columns are added by the startup migrator on existing databases; fresh installs get them from `schema.sql`.
