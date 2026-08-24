# Phone integrations

qbx_properties exposes a small, secured API so phone resources can build a home app on top of it: list a character's properties, set waypoints, toggle door locks, and manage keys. Ready-made glue for [lb-phone](https://docs.lbscripts.com/phone/configuration/housing/) and [sd-phone](https://github.com/Samuels-Development/sd-phone) is below; the API works for any phone.

Every mutation is validated inside qbx_properties — ownership is checked server-side against the acting player, never against arguments a UI sends — so a phone app cannot be tricked into unlocking or handing out keys to someone else's property.

## Client exports

Convenience wrappers for phone client apps. The player is always the one calling; there is nothing to pass that could be spoofed.

| Export | Returns |
| --- | --- |
| `exports.qbx_properties:GetMyHomes()` | array of home objects (below) for the calling character |
| `exports.qbx_properties:GetHomeKeyholders(propertyId)` | `{ { citizenid, name } }`, or `nil` when not the owner |
| `exports.qbx_properties:AddHomeKeyholder(propertyId, targetServerId)` | `true` on success — caller must own the property and the target must be online within 10m |
| `exports.qbx_properties:RemoveHomeKeyholder(propertyId, citizenid)` | `true` on success — caller must own the property |
| `exports.qbx_properties:SetHomeLocked(propertyId, locked)` | the new lock state, or `nil` when denied or the property has no toggleable doors |
| `exports.qbx_properties:openHousing()` | opens the housing market UI |

Home object:

```lua
{
    id = 12,                    -- property id
    label = 'Lombank Tower 1 1204', -- property_name
    type = 'apartment',         -- 'apartment' (building unit) or 'house'
    building = 'lombank1',      -- building key, apartments only
    floor = 12, room = 4,       -- apartments only
    coords = vec3(...),         -- entrance (building entrance for apartments)
    price = 1250,
    rented = true,              -- has a rent interval
    locked = true,              -- nil for shell/IPL properties, they have no physical door
}
```

`locked` is `nil` for interior-shell and IPL properties: those are entered through access-checked teleports, not real doors, so there is nothing to toggle. MLO houses and apartment units have ox_doorlock doors and report and toggle normally. Hide the lock button when `locked == nil`.

## Server exports

For phone bridges that run server-side. Mutations take the **acting owner's citizenid** and re-verify ownership, so pass the citizenid of the player using the phone — not a value from their UI.

| Export | Returns |
| --- | --- |
| `exports.qbx_properties:GetPlayerProperties(citizenid)` | array of home objects |
| `exports.qbx_properties:HasAccess(citizenid, propertyId, permission?)` | `boolean` — permission is `'door'` (default), `'stash'`, `'furniture'` or `'garage'` |
| `exports.qbx_properties:GetKeyholders(propertyId, actorCid)` | keyholder list, `nil` unless actorCid owns the property |
| `exports.qbx_properties:AddKeyholder(propertyId, actorCid, targetCid)` | `true` on success |
| `exports.qbx_properties:RemoveKeyholder(propertyId, actorCid, targetCid)` | `true` on success |
| `exports.qbx_properties:GetLocked(propertyId)` | `boolean` or `nil` |
| `exports.qbx_properties:SetLocked(propertyId, actorCid, locked)` | `true` when a door changed state |

## lb-phone

lb-phone's Home app loads a housing bridge by name. Create these two files and set `Config.HouseScript = "qbx_properties"` in lb-phone's config.

`lb-phone/client/apps/framework/home/qbx_properties.lua`:

```lua
if Config.HouseScript ~= "qbx_properties" then
    return
end

RegisterNUICallback("Home", function(data, cb)
    local action = data.action
    local houseData = data.houseData

    if action == "getHomes" then
        local homes = exports.qbx_properties:GetMyHomes()
        local houses = {}
        for i = 1, #homes do
            local home = homes[i]
            local keyholders = exports.qbx_properties:GetHomeKeyholders(home.id) or {}
            local holders = {}
            for j = 1, #keyholders do
                holders[#holders + 1] = { identifier = keyholders[j].citizenid, name = keyholders[j].name }
            end
            houses[#houses + 1] = {
                id = home.id,
                label = home.label,
                locked = home.locked == true,
                keyholders = holders,
                coords = home.coords,
            }
        end
        cb(houses)
    elseif action == "addKeyholder" then
        if not exports.qbx_properties:AddHomeKeyholder(houseData.id, data.source) then
            cb(false)
            return
        end
        local keyholders = exports.qbx_properties:GetHomeKeyholders(houseData.id) or {}
        local holders = {}
        for i = 1, #keyholders do
            holders[#holders + 1] = { identifier = keyholders[i].citizenid, name = keyholders[i].name }
        end
        cb(holders)
    elseif action == "removeKeyholder" then
        if not exports.qbx_properties:RemoveHomeKeyholder(houseData.id, data.identifier) then
            cb(false)
            return
        end
        local keyholders = exports.qbx_properties:GetHomeKeyholders(houseData.id) or {}
        local holders = {}
        for i = 1, #keyholders do
            holders[#holders + 1] = { identifier = keyholders[i].citizenid, name = keyholders[i].name }
        end
        cb(holders)
    elseif action == "toggleLocked" then
        local locked = exports.qbx_properties:SetHomeLocked(houseData.id, not houseData.locked)
        cb(locked == nil and houseData.locked or locked)
    elseif action == "setWaypoint" then
        if houseData.coords then
            SetNewWaypoint(houseData.coords.x, houseData.coords.y)
        end
        cb("ok")
    end
end)
```

`lb-phone/server/apps/framework/home/qbx_properties.lua`:

```lua
if Config.HouseScript ~= "qbx_properties" then
    return
end
-- Everything runs through qbx_properties' own validated callbacks, nothing needed here.
```

## sd-phone

sd-phone's Homes app resolves housing systems through adapters in `bridge/server/housing.lua`. Add a qbx_properties adapter next to the existing ones, following the file's conventions:

```lua
ADAPTERS['qbx_properties'] = function(_source, id)
    local homes = exports.qbx_properties:GetPlayerProperties(id)
    local out = {}
    for i = 1, #homes do
        local h = homes[i]
        out[#out + 1] = home{
            id      = tostring(h.id),
            address = h.label,
            type    = h.type == 'apartment' and 'Apartment' or 'House',
            value   = h.price,
            status  = h.rented and 'rented' or 'owned',
            coords  = h.coords and { x = h.coords.x, y = h.coords.y } or nil,
            locked  = h.locked,
        }
    end
    return out
end
```

For the lock and key capabilities, wire the bridge's capability functions to the server exports — the acting player's citizenid comes from their framework identifier:

```lua
-- lock:       exports.qbx_properties:SetLocked(tonumber(id), citizenid, want)
-- keyHolders: exports.qbx_properties:GetKeyholders(tonumber(id), citizenid)
-- giveKey:    exports.qbx_properties:AddKeyholder(tonumber(id), citizenid, targetCitizenid)
-- removeKey:  exports.qbx_properties:RemoveKeyholder(tonumber(id), citizenid, holderCitizenid)
```

## Other phones and apps

Any phone with custom apps can also embed the full housing market UI as an app instead of (or next to) a home app — see [third-party-ui.md](third-party-ui.md) for the `?app=housing` embed URL, which handles bids and purchases with no extra wiring.

## Security notes

- Key management is owner-only; lock toggling needs door access (owner or a key with the door permission); property lists are self-scoped. All of it is enforced inside qbx_properties, per call, server-side.
- Adding a keyholder by server id requires the target to be online and within 10 meters of the owner.
- Granting or revoking keys also refreshes third-party garage access points when `garageSystem` is bridged.
- The player-scoped callbacks derive the acting character from the connection, never from arguments, so nothing a modified client sends can act on another player's behalf.
