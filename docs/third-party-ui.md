# Embedding the housing UI in tablets and laptops

The housing market UI can run inside any resource that embeds NUI pages in an iframe — laptop and tablet resources like [fd_laptops](https://docs.felis.gg/laptop/customapps/create-custom-app), custom phones, and similar. Players browse listings, view photos, bid and buy from the app; everything realtors do stays on the in-game tablet.

## Config options

- `housingCommand` (shared) — `false` removes the `/housing` chat command, for servers that only want the UI reachable through an app or their own keybind.
- The `openHousing` client export opens the regular in-game UI from another script:

```lua
exports.qbx_properties:openHousing()
```

## The embed URL

```
https://cfx-nui-qbx_properties/web/build/index.html?app=housing
```

The `?app=housing` parameter puts the page in embedded mode: it boots itself by calling back into qbx_properties for the market data, never grabs NUI focus, and ignores whatever the in-game tablet is doing. Bids and purchases fire the same callbacks as the normal UI, so no extra wiring is needed.

The page must be loaded from that URL directly (an iframe pointing at it, which is how laptop resources work) — the live data bridge relies on the frame sharing qbx_properties' NUI origin.

## fd_laptops example

```lua
CreateThread(function()
    while GetResourceState('fd_laptop') ~= 'started' do Wait(500) end

    exports.fd_laptop:addCustomApp({
        id = 'housing',
        name = 'Housing',
        icon = 'https://your-cdn/housing-icon.png', -- any image url, or an nui:// path from your laptop resource
        ui = 'https://cfx-nui-qbx_properties/web/build/index.html?app=housing',
    })
end)
```

Leave `keepAlive` off (the default) — each open reloads the app, which pulls fresh listings. See the [fd_laptops custom app docs](https://docs.felis.gg/laptop/customapps/create-custom-app) for icons, window sizing and the other fields.

## Behaviour details

- The app needs a logged-in character; it shows nothing on the character select screen.
- Listing refreshes triggered in-game (new listings, bids) push to the embedded app too while it is open.
- Realtor and creator tools never appear in embedded mode, whatever the player's job.
