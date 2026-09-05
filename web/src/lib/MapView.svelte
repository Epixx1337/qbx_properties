<script>
  import { onMount, untrack } from 'svelte'
  import L from 'leaflet'
  import 'leaflet/dist/leaflet.css'
  import { fetchNui, formatMoney } from './nui.js'

  let { markers = [], mode = 'market', onOpen } = $props()

  let container
  let map
  let pinLayer
  let fitted = false
  const pinIndex = new Map()
  let selected = $state(null)

  const STATUS = {
    listed: { color: '#40c057', label: 'For sale' },
    owned: { color: '#fa5252', label: 'Sold' },
    unlisted: { color: '#339af0', label: 'Not listed' },
  }

  const HOUSE_PATH = 'M12 3 2 11h3v9h6v-6h2v6h6v-9h3z'

  function houseIcon(status, active) {
    const color = STATUS[status]?.color ?? STATUS.unlisted.color
    return L.divIcon({
      className: 'house-pin',
      html: `<div class="pin${active ? ' active' : ''}" style="--pin:${color}"><svg viewBox="0 0 24 24"><path d="${HOUSE_PATH}"/></svg></div>`,
      iconSize: [26, 26],
      iconAnchor: [13, 13],
    })
  }

  // linear transform between GTA world coordinates and map tile space, lat = y and lng = x
  function gtaCrs() {
    return Object.assign({}, L.CRS.Simple, {
      projection: L.Projection.LonLat,
      scale: (zoom) => Math.pow(2, zoom),
      zoom: (scale) => Math.log(scale) / Math.LN2,
      distance: (a, b) => Math.hypot(b.lng - a.lng, b.lat - a.lat),
      transformation: new L.Transformation(0.02072, 117.3, -0.0205, 172.8),
      infinite: true,
    })
  }

  function refreshIcon(id, active) {
    const item = pinIndex.get(id)
    if (item) item.pin.setIcon(houseIcon(item.entry.status, active))
  }

  function selectEntry(entry) {
    if (selected?.id === entry.id) return
    if (selected) refreshIcon(selected.id, false)
    selected = entry
    refreshIcon(entry.id, true)
  }

  function drawMarkers() {
    if (!pinLayer) return
    pinLayer.clearLayers()
    pinIndex.clear()

    for (const entry of markers) {
      if (!entry.coords) continue
      const pin = L.marker([entry.coords.y, entry.coords.x], {
        icon: houseIcon(entry.status, selected?.id === entry.id),
        title: entry.name,
      })
      pin.on('click', () => selectEntry(entry))
      pin.addTo(pinLayer)
      pinIndex.set(entry.id, { pin, entry })
    }
  }

  function fitToMarkers() {
    const points = markers.filter((m) => m.coords).map((m) => [m.coords.y, m.coords.x])
    if (!points.length) return
    fitted = true
    map.fitBounds(L.latLngBounds(points).pad(0.2), { maxZoom: 5 })
  }

  // world rectangle covered by the tile atlas, derived from the CRS transformation
  const ATLAS_BOUNDS = [[-4058.5, -5661.1], [8429.2, 6693.0]]

  onMount(() => {
    map = L.map(container, {
      crs: gtaCrs(),
      zoom: 3,
      minZoom: 1,
      maxZoom: 7,
      center: [-800, 100],
      maxBounds: ATLAS_BOUNDS,
      maxBoundsViscosity: 1,
      zoomControl: true,
      attributionControl: false,
    })

    L.tileLayer('map/styleAtlas/{z}/{x}/{y}.jpg', {
      minZoom: 0,
      maxZoom: 7,
      maxNativeZoom: 5,
      noWrap: true,
      bounds: ATLAS_BOUNDS,
    }).addTo(map)

    pinLayer = L.layerGroup().addTo(map)

    return () => map.remove()
  })

  $effect(() => {
    markers
    if (!map) return
    untrack(() => {
      drawMarkers()
      if (!fitted) fitToMarkers()
    })
  })

  function setWaypoint() {
    if (!selected?.coords) return
    fetchNui('map:setWaypoint', { x: selected.coords.x, y: selected.coords.y })
  }

  function openSelected() {
    if (!selected) return
    onOpen?.(selected)
  }

  function closeCard() {
    if (selected) refreshIcon(selected.id, false)
    selected = null
  }
</script>

<div class="map-wrap">
  <div class="map" bind:this={container}></div>

  <div class="legend">
    {#each Object.entries(STATUS) as [key, status] (key)}
      {#if mode === 'manage' || key === 'listed'}
        <span class="legend-item"><span class="dot" style="--pin:{status.color}"></span>{status.label}</span>
      {/if}
    {/each}
  </div>

  {#if selected}
    <div class="map-card">
      <div class="map-card-head">
        <span class="map-card-id">
          <span class="map-card-name">{selected.name}</span>
          <span class="map-card-meta">
            <span class="dot" style="--pin:{STATUS[selected.status]?.color}"></span>
            {STATUS[selected.status]?.label}{selected.meta ? ` · ${selected.meta}` : ''}
          </span>
        </span>
        <button class="pencil" onclick={closeCard}>×</button>
      </div>

      <div class="map-card-body">
        {#if selected.price}
          <span class="map-card-price">{formatMoney(selected.price)}</span>
        {/if}
        {#if selected.ownerName}
          <span class="map-card-owner">Owned by {selected.ownerName}</span>
        {/if}
      </div>

      <div class="map-card-actions">
        <button class="btn subtle" onclick={setWaypoint}>Set waypoint</button>
        {#if mode === 'manage'}
          <button class="btn" onclick={openSelected}>Open in Manage</button>
        {:else if selected.listingId}
          <button class="btn" onclick={openSelected}>View listing</button>
        {/if}
      </div>
    </div>
  {/if}
</div>

<style>
  .map-wrap {
    position: relative;
    flex: 1;
    min-height: 0;
    border-radius: var(--radius-md);
    overflow: hidden;
    border: 1px solid var(--dark-4);
  }

  .map {
    position: absolute;
    inset: 0;
    background: #29bae7;
  }

  .legend {
    position: absolute;
    top: 10px;
    right: 10px;
    z-index: 500;
    display: flex;
    gap: 10px;
    padding: 7px 11px;
    font-size: 11px;
    color: var(--dark-0);
    background: var(--dark-7);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .legend-item {
    display: inline-flex;
    align-items: center;
    gap: 5px;
  }

  .dot {
    width: 9px;
    height: 9px;
    border-radius: 50%;
    background: var(--pin);
    flex: none;
  }

  .map-card {
    position: absolute;
    left: 12px;
    bottom: 12px;
    z-index: 500;
    width: 290px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 13px 14px;
    background: var(--dark-7);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-md);
    box-shadow: var(--shadow);
  }

  .map-card-head {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 10px;
  }

  .map-card-id {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }

  .map-card-name {
    font-size: 14px;
    font-weight: 700;
    color: #fff;
  }

  .map-card-meta {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 11px;
    color: var(--dark-2);
  }

  .pencil {
    flex: none;
    width: 26px;
    height: 26px;
    font-size: 14px;
    color: var(--dark-1);
    background: var(--dark-5);
    border: none;
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .pencil:hover {
    background: var(--dark-4);
    color: #fff;
  }

  .map-card-body {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 10px;
  }

  .map-card-price {
    font-family: 'Roboto Mono', monospace;
    font-size: 16px;
    font-weight: 700;
    color: #fff;
  }

  .map-card-owner {
    font-size: 11px;
    color: var(--dark-2);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .map-card-actions {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }

  :global(.house-pin) {
    background: none;
    border: none;
  }

  :global(.house-pin .pin) {
    width: 26px;
    height: 26px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--pin);
    border: 2px solid rgba(255, 255, 255, 0.9);
    border-radius: 50%;
    box-shadow: 0 2px 6px rgba(0, 0, 0, 0.45);
    cursor: pointer;
  }

  :global(.house-pin .pin.active) {
    outline: 3px solid rgba(255, 255, 255, 0.55);
  }

  :global(.house-pin .pin svg) {
    width: 15px;
    height: 15px;
    fill: #fff;
  }

  :global(.leaflet-container) {
    background: #29bae7;
    font-family: inherit;
  }

  :global(.leaflet-bar) {
    border: 1px solid var(--dark-4) !important;
    box-shadow: var(--shadow);
  }

  :global(.leaflet-bar a) {
    background: var(--dark-7);
    color: var(--dark-0);
    border-bottom: 1px solid var(--dark-4);
  }

  :global(.leaflet-bar a:hover) {
    background: var(--dark-5);
    color: #fff;
  }
</style>
