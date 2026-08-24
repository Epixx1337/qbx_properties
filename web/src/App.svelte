<script>
  import './lib/theme.css'
  import { applyTheme } from './lib/mantine.js'
  import { onMessage, fetchNui, isEmbedded } from './lib/nui.js'
  import { app, furniture, market, realtor, creator, tablet, placement, preview, creation, creationFormDefaults, shot } from './lib/store.svelte.js'
  import ShotStudio from './lib/screenshot/ShotStudio.svelte'
  import FurnitureApp from './lib/furniture/FurnitureApp.svelte'
  import HousingApp from './lib/HousingApp.svelte'
  import TabletApp from './lib/tablet/TabletApp.svelte'
  import PreviewApp from './lib/PreviewApp.svelte'
  import PlacementHud from './lib/PlacementHud.svelte'

  onMessage('setView', (data) => {
    app.view = data?.view ?? null
    if (data?.isRealtor !== undefined) app.isRealtor = data.isRealtor
  })

  if (isEmbedded) {
    fetchNui('housing:embed')
  }

  onMessage('furniture:init', (data) => {
    furniture.categories = data.categories ?? {}
    furniture.category = Object.keys(furniture.categories)[0] ?? null
    furniture.propertyName = data.propertyName ?? ''
    furniture.palette = data.palette ?? []
    furniture.shopEnabled = data.shopEnabled ?? true
    furniture.cdnMap = data.cdnMap ?? null
    furniture.selected = null
    furniture.placing = false
    furniture.search = ''
    furniture.placed = []
  })

  onMessage('shotstudio:open', (data) => {
    shot.active = true
    shot.total = data?.total ?? 0
    shot.index = 0
    shot.done = 0
    shot.skipped = 0
    shot.failed = 0
    shot.empty = 0
    shot.primary = 'green'
  })

  onMessage('shotstudio:progress', (data) => {
    shot.index = data?.index ?? shot.index
    shot.total = data?.total ?? shot.total
    shot.label = data?.label ?? ''
    shot.object = data?.object ?? ''
    shot.paused = data?.paused ?? false
    shot.primary = data?.primary ?? 'green'
    shot.done = data?.done ?? 0
    shot.skipped = data?.skipped ?? 0
    shot.failed = data?.failed ?? 0
    shot.empty = data?.empty ?? 0
    shot.hasImage = data?.hasImage ?? false
    shot.tuned = data?.tuned ?? false
  })

  onMessage('shotstudio:close', () => {
    shot.active = false
  })

  onMessage('screenshot:process', async (data) => {
    let result
    try {
      const { processPair } = await import('./lib/screenshot/processor.js')
      result = await processPair(data.uri1, data.uri2, data.opaque)
    } catch (err) {
      result = { ok: false, error: String(err) }
    }
    fetchNui('screenshot:processed', { id: data.id, result })
  })

  onMessage('furniture:placed', (data) => {
    furniture.placed = data ?? []
  })

  onMessage('furniture:state', (data) => {
    furniture.placing = data.placing ?? false
    furniture.freecam = data.freecam ?? false
    furniture.worldInput = data.worldInput ?? false
    furniture.mode = data.mode ?? 'translate'
    furniture.selected = data.selected ?? null
    furniture.tint = data.tint ?? 0
    furniture.tintSupported = data.tintSupported ?? false
    furniture.pickup = data.pickup ?? false
  })

  onMessage('furniture:cart', (data) => {
    furniture.cart = data?.items ?? []
    furniture.cartTotal = data?.total ?? 0
  })

  onMessage('furniture:confirmExit', () => {
    furniture.exitConfirm = true
  })

  onMessage('furniture:restorePrompt', (data) => {
    furniture.restorePrompt = data ?? null
  })

  onMessage('furniture:transform', (data) => {
    furniture.transform = data ?? null
  })

  onMessage('gizmo:sync', (data) => {
    furniture.gizmo = data ?? null
  })

  onMessage('market:init', (data) => {
    market.listings = data.listings ?? []
    if (data.config) market.config = data.config
    if (data.sizes) market.sizes = data.sizes
    if (data.sizeOrder) market.sizeOrder = data.sizeOrder
    market.gardens = data.gardens ?? false
    market.selected = null
    market.bids = []
  })

  onMessage('market:listings', (data) => {
    market.listings = data ?? []
    if (market.selected) {
      market.selected = market.listings.find((l) => l.id === market.selected.id) ?? null
    }
  })

  onMessage('market:bids', (data) => {
    market.bids = data ?? []
  })

  onMessage('market:nearbyClients', (data) => {
    market.nearbyClients = data ?? []
  })

  onMessage('realtor:init', (data) => {
    realtor.interiors = data.interiors ?? []
    realtor.buildings = data.buildings ?? []
    realtor.properties = data.properties ?? []
    realtor.building = null
    realtor.units = []
  })

  onMessage('realtor:units', (data) => {
    realtor.units = data ?? []
  })

  onMessage('realtor:properties', (data) => {
    realtor.properties = data ?? []
  })

  onMessage('tablet:init', (data) => {
    tablet.propertyName = data?.propertyName ?? ''
    tablet.wallColors = data?.wallColors ?? null
    tablet.wallColor = data?.wallColor ?? null
    tablet.access = []
    tablet.nearby = []
    tablet.utilities = null
  })

  onMessage('theme', (data) => { applyTheme(data?.color, data?.shade) })

  onMessage('tablet:access', (data) => {
    tablet.access = data?.access ?? []
    tablet.apartment = data?.apartment ?? false
  })
  onMessage('tablet:nearby', (data) => { tablet.nearby = data ?? [] })
  onMessage('tablet:utilities', (data) => { tablet.utilities = data ?? null })

  onMessage('placement:show', (data) => {
    placement.active = true
    placement.prompt = data?.prompt ?? ''
    placement.points = data?.points ?? 0
    placement.zone = data?.zone ?? false
    placement.gizmo = data?.gizmo ?? false
    placement.vehicle = data?.vehicle ?? false
    placement.height = data?.height ?? null
    placement.photo = data?.photo ?? false
    placement.capture = data?.capture ?? false
  })

  onMessage('placement:hide', () => { placement.active = false })

  onMessage('preview:state', (data) => {
    preview.interior = data?.interior ?? ''
    preview.points = data?.points ?? {}
    preview.types = data?.types ?? []
    preview.property = data?.property ?? false
    preview.setup = data?.setup ?? false
  })

  onMessage('realtor:detailData', (data) => { realtor.details = data ?? null })

  onMessage('creation:state', (data) => {
    creation.draft = data ?? null
    if (!data) creation.form = creationFormDefaults()
  })

  onMessage('housing:tab', (data) => { app.tab = data ?? 'market' })

  onMessage('creator:enabled', (data) => {
    creator.enabled = data === true
  })

  onMessage('creator:state', (data) => {
    creator.draft = data?.draft ?? null
    creator.interior = data?.interior ?? null
    creator.anchor = data?.anchor ?? null
    creator.coords = data?.coords ?? null
  })

  onMessage('creator:saved', () => {
    creator.draft = null
  })

  const FORWARDED = new Set(['escape', 'e', 'f', 'n', 'h'])

  function onKeydown(event) {
    if (!app.view) return

    const tag = event.target?.tagName
    if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') {
      if (event.key !== 'Escape') return
    }

    const key = event.key === 'Escape' ? 'Escape' : event.key.toLowerCase()

    if (app.view === 'furniture' && furniture.gizmo) {
      if (key === 't' || key === 'r') {
        event.preventDefault()
        furniture.gizmoMode = key === 't' ? 'translate' : 'rotate'
        return
      }
      if (key === 'l') {
        event.preventDefault()
        furniture.gizmoSpace =
          furniture.gizmoSpace === 'camera' ? 'world'
          : furniture.gizmoSpace === 'world' ? 'local'
          : 'camera'
        return
      }
    }

    if (!FORWARDED.has(key.toLowerCase())) return

    event.preventDefault()
    fetchNui('key', { key })
  }
</script>

<svelte:window on:keydown={onKeydown} />

{#if placement.active}
  <PlacementHud />
{/if}

{#if shot.active}
  <ShotStudio />
{/if}

{#if app.view === 'furniture'}
  <FurnitureApp />
{:else if app.view === 'housing'}
  <HousingApp />
{:else if app.view === 'tablet'}
  <TabletApp />
{:else if app.view === 'preview'}
  <PreviewApp />
{/if}
