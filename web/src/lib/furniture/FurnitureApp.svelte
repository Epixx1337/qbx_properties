<script>
  import Gizmo from './Gizmo.svelte'

  let editingTransform = $state(false)

  function sendTransform(field, value) {
    const t = furniture.transform
    if (!t) return
    const next = { ...t, [field]: Number(value) }
    if (Number.isNaN(next[field])) return
    furniture.transform = next
    fetchNui('furniture:setTransform', next)
  }

  function nudge(axis, delta) {
    fetchNui('furniture:nudge', { axis, delta })
  }

  import { fetchNui } from '../nui.js'
  import { furniture } from '../store.svelte.js'

  const imgSrc = (name) => furniture.cdnMap?.[`${name}.webp`] ?? `nui://qbx_properties/screenshots/${name}.webp`

  const PLACEHOLDER = `data:image/svg+xml,${encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><g fill="none" stroke="#8b8b95" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round" opacity="0.45"><path d="M19 33v-11a7 7 0 0 1 7-7h12a7 7 0 0 1 7 7v11"/><path d="M12 33a5 5 0 0 1 5 5v3h30v-3a5 5 0 0 1 10 0v7a6 6 0 0 1-6 6H13a6 6 0 0 1-6-6v-7a5 5 0 0 1 5-5z"/><path d="M17 51v5M47 51v5"/></g></svg>`
  )}`

  const onImgError = (event) => {
    if (event.currentTarget.src !== PLACEHOLDER) event.currentTarget.src = PLACEHOLDER
  }

  let mode = $state('catalog')
  let placedSearch = $state('')

  const categories = $derived(
    Object.keys(furniture.categories).sort((a, b) => {
      if (a === 'utility') return -1
      if (b === 'utility') return 1
      return a.localeCompare(b)
    })
  )

  const modelTypes = $derived.by(() => {
    const map = {}
    for (const name of Object.keys(furniture.categories)) {
      for (const entry of furniture.categories[name] ?? []) {
        if (entry.type) map[entry.object] = entry.type
      }
    }
    return map
  })

  const placedItems = $derived(
    furniture.placed.filter(
      (item) => !placedSearch.trim() || item.label.toLowerCase().includes(placedSearch.trim().toLowerCase())
    )
  )

  const items = $derived.by(() => {
    const query = furniture.search.trim().toLowerCase()

    if (query) {
      return categories
        .flatMap((name) => furniture.categories[name] ?? [])
        .filter((item) => item.label.toLowerCase().includes(query))
        .slice(0, 120)
    }

    return furniture.categories[furniture.category] ?? []
  })

  function place(item) {
    fetchNui('furniture:place', { object: item.object, label: item.label })
  }

  function isFirstFree(item) {
    if (!item.firstFree || !item.price) return false
    const group = item.type
    const taken = (model) => model === item.object || (group && modelTypes[model] === group)
    if (furniture.placed.some((p) => taken(p.model))) return false
    return !furniture.cart.some((c) => taken(c.model))
  }

  function backToWorld() {
    fetchNui('setFocus', { focus: false })
  }
</script>

<div class="wrap">
  <aside class="panel catalog">
    <div class="panel-header">
      <div>
        <div class="panel-title">Furniture</div>
        <div class="panel-subtitle">{furniture.propertyName}</div>
      </div>
      <button class="btn subtle" onclick={() => fetchNui('close')}>Close</button>
    </div>

    <div class="modes">
      <button class="mode-btn" class:active={mode === 'catalog'} onclick={() => (mode = 'catalog')}>Catalog</button>
      <button class="mode-btn" class:active={mode === 'placed'} onclick={() => (mode = 'placed')}>
        Placed <span class="count">{furniture.placed.length}</span>
      </button>
    </div>

    {#if mode === 'catalog'}
      <div class="search">
        <input class="input" placeholder="Search furniture..." bind:value={furniture.search} />
      </div>

      {#if !furniture.search.trim()}
        <div class="tabs">
          {#each categories as name}
            <button
              class="tab"
              class:active={furniture.category === name}
              onclick={() => (furniture.category = name)}
            >
              {name}
              <span class="count">{furniture.categories[name].length}</span>
            </button>
          {/each}
        </div>
      {/if}

      <div class="grid scroll">
        {#each items as item (item.object)}
          <button class="card" onclick={() => place(item)}>
            <div class="thumb">
              <img src={imgSrc(item.object)} alt={item.label} loading="lazy" onerror={onImgError} />
              {#if item.price && furniture.shopEnabled}
                {#if isFirstFree(item)}
                  <span class="price-tag free">Free · then ${item.price.toLocaleString()}</span>
                {:else}
                  <span class="price-tag">${item.price.toLocaleString()}</span>
                {/if}
              {/if}
            </div>
            <span>{item.label}</span>
          </button>
        {:else}
          <div class="empty">No furniture found</div>
        {/each}
      </div>
    {:else}
      <div class="search">
        <input class="input" placeholder="Search placed..." bind:value={placedSearch} />
      </div>

      <div class="placed scroll">
        {#each placedItems as item (item.id)}
          <div class="placed-row" class:active={furniture.selected?.objectId === item.id}>
            <img src={item.image ?? imgSrc(item.model)} alt={item.label} loading="lazy" onerror={onImgError} />
            <span class="placed-label">{item.label}</span>
            <button class="mini" title="Edit this piece" onclick={() => fetchNui('furniture:select', { id: item.id })}>Edit</button>
            <button class="mini accent" title="Duplicate in place" onclick={() => fetchNui('furniture:clone', { id: item.id })}>Clone</button>
          </div>
        {:else}
          <div class="empty">Nothing placed here yet</div>
        {/each}
      </div>
    {/if}
  </aside>

  <section class="panel controls">
    <div class="panel-header">
      <div class="panel-title">Placement</div>
      {#if furniture.placing}
        <span class="badge blue">{furniture.gizmo ? `${furniture.gizmoMode === 'rotate' ? 'rotate' : 'move'}${furniture.gizmoSpace === 'camera' ? '' : ` · ${furniture.gizmoSpace}`}` : furniture.mode}</span>
      {/if}
    </div>

    {#if furniture.placing}
      <div class="body">
        <div class="selected">{furniture.selected?.label ?? 'Object'}</div>
        <div class="hint">Pick another item from the catalog to swap it out.</div>

        <div class="keys">
          <div><kbd>T</kbd> Move</div>
          <div><kbd>R</kbd> Rotate</div>
          <div><kbd>L</kbd> Camera / world / local</div>
          <div><kbd>G</kbd> Snap to ground</div>
          <div><kbd>H</kbd> Snap to wall</div>
          <div><kbd>F</kbd> Freecam</div>
        </div>

        <div class="actions">
          <button class="btn success" onclick={() => fetchNui('furniture:confirm')}>Confirm</button>
          <button class="btn subtle" onclick={() => fetchNui('furniture:cancel')}>Cancel</button>
        </div>

        <button class="btn subtle wide" onclick={() => fetchNui('furniture:snap')}>
          Snap to matching piece <kbd>N</kbd>
        </button>

        {#if furniture.tintSupported && furniture.palette.length}
          <div class="section-title">Colour</div>
          <div class="tints">
            <button
              class="tint default"
              class:active={furniture.tint === 0}
              title="Default"
              onclick={() => fetchNui('furniture:setTint', { tint: 0 })}
            >×</button>
            {#each furniture.palette as swatch (swatch.index)}
              {#if swatch.index > 0}
                <button
                  class="tint"
                  class:active={furniture.tint === swatch.index}
                  style="background: #{swatch.hex}"
                  title={swatch.label}
                  onclick={() => fetchNui('furniture:setTint', { tint: swatch.index })}
                  aria-label={swatch.label}
                ></button>
              {/if}
            {/each}
          </div>
        {/if}

        {#if furniture.transform}
          <div class="section-title">Fine tune</div>
          <div class="fine">
            {#each [['camx', '◀ ▶'], ['camy', '▼ ▲']] as [axis, label]}
              <div class="fine-row">
                <span class="fine-label">{label}</span>
                <button class="mini" onclick={() => nudge(axis, -0.1)}>−.1</button>
                <button class="mini" onclick={() => nudge(axis, -0.01)}>−</button>
                <span class="fine-cam">screen</span>
                <button class="mini" onclick={() => nudge(axis, 0.01)}>+</button>
                <button class="mini" onclick={() => nudge(axis, 0.1)}>+.1</button>
              </div>
            {/each}
            {#each [['x', 'X'], ['y', 'Y'], ['z', 'Z'], ['rz', 'Rot']] as [axis, label]}
              <div class="fine-row">
                <span class="fine-label">{label}</span>
                <button class="mini" onclick={() => nudge(axis, axis === 'rz' ? -5 : -0.1)}>−.1</button>
                <button class="mini" onclick={() => nudge(axis, axis === 'rz' ? -1 : -0.01)}>−</button>
                <input
                  class="input fine-input"
                  type="number"
                  step={axis === 'rz' ? 1 : 0.01}
                  value={editingTransform ? undefined : (furniture.transform[axis] ?? 0).toFixed(2)}
                  onfocus={() => (editingTransform = true)}
                  onblur={(e) => { editingTransform = false; sendTransform(axis, e.currentTarget.value) }}
                  onkeydown={(e) => { if (e.key === 'Enter') e.currentTarget.blur() }}
                />
                <button class="mini" onclick={() => nudge(axis, axis === 'rz' ? 1 : 0.01)}>+</button>
                <button class="mini" onclick={() => nudge(axis, axis === 'rz' ? 5 : 0.1)}>+.1</button>
              </div>
            {/each}
          </div>
        {/if}

        {#if furniture.pickup}
          <button class="btn subtle wide" onclick={() => fetchNui('furniture:pickup')}>Pick up into inventory</button>
        {/if}

        {#if furniture.selected?.objectId && !furniture.pickup}
          <button class="btn danger wide" onclick={() => fetchNui('furniture:remove')}>Remove object</button>
        {/if}
      </div>
    {:else}
      <div class="body">
        <div class="hint">Pick furniture from the catalog to start placing, or return to the world to fly around and select something you already placed.</div>
        <button class="btn subtle wide" onclick={backToWorld}>Back to world <kbd>E</kbd></button>
        <div class="keys">
          <div><kbd>W A S D</kbd> Fly</div>
          <div><kbd>Space</kbd> / <kbd>Ctrl</kbd> Up / down</div>
          <div><kbd>Scroll</kbd> Speed</div>
          <div><kbd>Alt</kbd> Select placed object</div>
          <div><kbd>E</kbd> Back to catalog</div>
          <div><kbd>Backspace</kbd> Exit</div>
        </div>
      </div>
    {/if}

    {#if furniture.cart.length}
      <div class="cart">
        <div class="section-title">Cart · {furniture.cart.length}</div>
        {#each furniture.cart as entry, i (i)}
          <div class="cart-row">
            <span class="cart-label">{entry.label}</span>
            <span class="cart-price">${entry.price.toLocaleString()}</span>
            <button class="mini" title="Pick it back up to move it" onclick={() => fetchNui('cart:edit', { index: i + 1 })}>Move</button>
            <button class="mini remove" title="Remove from cart" onclick={() => fetchNui('cart:remove', { index: i + 1 })}>✕</button>
          </div>
        {/each}
        <button class="btn success wide" onclick={() => fetchNui('cart:checkout')}>
          Pay ${furniture.cartTotal.toLocaleString()}
        </button>
      </div>
    {/if}
  </section>

  {#if furniture.worldInput}
    <footer class="hud">
      {#if furniture.freecam}
        <span class="mode">Freecam</span>
        <span><kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> Fly</span>
        <span><kbd>Space</kbd> Up</span>
        <span><kbd>Ctrl</kbd> Down</span>
        <span><kbd>Scroll</kbd> Speed</span>
        <span><kbd>F</kbd> Stop flying</span>
      {:else if furniture.placing}
        <span class="mode">Placing</span>
        <span><kbd>T</kbd> Move</span>
        <span><kbd>R</kbd> Rotate</span>
        <span><kbd>L</kbd> Axis space</span>
        <span><kbd>G</kbd> Snap to ground</span>
        <span><kbd>H</kbd> Snap to wall</span>
        <span><kbd>Enter</kbd> Confirm</span>
        <span><kbd>F</kbd> Freecam</span>
      {:else}
        <span><kbd>Alt</kbd> Select an object</span>
        <span><kbd>F</kbd> Freecam</span>
        <span><kbd>E</kbd> Catalog</span>
      {/if}
      <span><kbd>Backspace</kbd> Exit</span>
    </footer>
  {/if}
</div>

{#if furniture.exitConfirm}
  <div class="modal-backdrop">
    <div class="modal">
      <div class="modal-title">Leave the editor?</div>
      <p class="modal-text">
        You have {furniture.cart.length} unpaid item{furniture.cart.length === 1 ? '' : 's'} in your cart
        (${furniture.cartTotal.toLocaleString()}). They will be set aside and offered back next time you decorate here.
      </p>
      <div class="modal-actions">
        <button class="btn subtle" onclick={() => (furniture.exitConfirm = false)}>Keep decorating</button>
        <button
          class="btn danger"
          onclick={() => {
            furniture.exitConfirm = false
            fetchNui('furniture:exitChoice', { exit: true })
          }}
        >
          Exit
        </button>
      </div>
    </div>
  </div>
{/if}

{#if furniture.restorePrompt}
  <div class="modal-backdrop">
    <div class="modal">
      <div class="modal-title">Restore your cart?</div>
      <p class="modal-text">
        You set aside {furniture.restorePrompt.count} item{furniture.restorePrompt.count === 1 ? '' : 's'}
        (${(furniture.restorePrompt.total ?? 0).toLocaleString()}) last time. Restore them exactly where they were, or discard them?
      </p>
      <div class="modal-actions">
        <button
          class="btn danger"
          onclick={() => {
            furniture.restorePrompt = null
            fetchNui('furniture:restoreChoice', { restore: false })
          }}
        >
          Discard
        </button>
        <button
          class="btn success"
          onclick={() => {
            furniture.restorePrompt = null
            fetchNui('furniture:restoreChoice', { restore: true })
          }}
        >
          Restore
        </button>
      </div>
    </div>
  </div>
{/if}

<Gizmo />

<style>
  .tints {
    display: grid;
    grid-template-columns: repeat(8, 1fr);
    gap: 4px;
  }

  .tint {
    aspect-ratio: 1;
    border: 2px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
    padding: 0;
  }

  .tint.default {
    background: var(--dark-6);
    color: var(--dark-2);
    font-size: 12px;
    line-height: 1;
  }

  .tint:hover {
    border-color: var(--dark-2);
  }

  .tint.active {
    border-color: var(--blue);
    box-shadow: 0 0 0 1px var(--accent-35);
  }

  .section-title {
    font-size: 12px;
    font-weight: 700;
    margin-top: 4px;
  }

  .fine {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .fine-row {
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .fine-label {
    width: 26px;
    font-size: 11px;
    color: var(--dark-2);
  }

  .fine-cam {
    flex: 1;
    min-width: 0;
    font-size: 10px;
    text-align: center;
    color: var(--dark-3);
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .fine-input {
    flex: 1;
    min-width: 0;
    padding: 4px 6px;
    font-size: 12px;
    text-align: center;
  }

  .wide {
    width: 100%;
  }

  .wrap {
    position: relative;
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 16px;
    height: 100%;
    padding: 24px;
    pointer-events: none;
  }

  .hud {
    position: absolute;
    left: 50%;
    bottom: 20px;
    transform: translateX(-50%);
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 6px 16px;
    max-width: 70vw;
    padding: 10px 18px;
    font-size: 12px;
    color: var(--dark-1);
    background: var(--dark-7);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-md);
    box-shadow: var(--shadow);
  }

  .hud span {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    white-space: nowrap;
  }

  .hud .mode {
    padding: 2px 8px;
    font-weight: 700;
    color: #fff;
    background: var(--accent-20);
    border-radius: var(--radius-sm);
  }

  .hud kbd + kbd {
    margin-left: -2px;
  }

  .panel {
    pointer-events: auto;
  }

  .catalog {
    display: flex;
    flex-direction: column;
    width: 380px;
    max-height: 100%;
  }

  .search {
    padding: 12px 16px;
    border-bottom: 1px solid var(--dark-4);
  }

  .modes {
    display: flex;
    gap: 4px;
    padding: 10px 16px 0;
  }

  .mode-btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 7px 12px;
    font-family: inherit;
    font-size: 13px;
    color: var(--dark-1);
    background: transparent;
    border: none;
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .mode-btn:hover {
    background: var(--dark-6);
  }

  .mode-btn.active {
    color: #fff;
    background: var(--accent-15);
  }

  .placed {
    display: flex;
    flex-direction: column;
    gap: 5px;
    padding: 12px 16px;
    min-height: 0;
  }

  .placed-row {
    display: grid;
    grid-template-columns: 34px 1fr auto auto;
    align-items: center;
    gap: 8px;
    padding: 6px 8px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .placed-row.active {
    border-color: var(--blue);
  }

  .placed-row img {
    width: 34px;
    height: 34px;
    object-fit: contain;
    background: var(--dark-7);
    border-radius: var(--radius-sm);
  }

  .placed-label {
    font-size: 12px;
    color: var(--dark-0);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .mini {
    padding: 4px 9px;
    font-family: inherit;
    font-size: 11px;
    color: var(--dark-1);
    background: var(--dark-5);
    border: none;
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .mini:hover {
    background: var(--dark-4);
    color: #fff;
  }

  .mini.accent:hover {
    background: var(--blue);
    color: #fff;
  }

  .tabs {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    padding: 10px 16px;
    border-bottom: 1px solid var(--dark-4);
    flex: none;
  }

  .tab {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    flex-shrink: 0;
    padding: 6px 10px;
    font-family: inherit;
    font-size: 12px;
    color: var(--dark-1);
    background: var(--dark-6);
    border: 1px solid transparent;
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .tab:hover {
    background: var(--dark-5);
  }

  .tab.active {
    color: #fff;
    background: var(--accent-15);
    border-color: var(--blue);
  }

  .count {
    font-size: 10px;
    color: var(--dark-3);
  }

  .grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 8px;
    padding: 12px 16px;
    min-height: 0;
  }

  .card {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    padding: 8px 6px;
    font-family: inherit;
    font-size: 11px;
    color: var(--dark-1);
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: border-color 0.12s ease;
  }

  .card:hover {
    border-color: var(--blue);
    color: #fff;
  }

  .card img {
    width: 100%;
    aspect-ratio: 1;
    object-fit: contain;
    background: var(--dark-7);
    border-radius: var(--radius-sm);
  }

  .thumb {
    position: relative;
    width: 100%;
  }

  .price-tag {
    position: absolute;
    right: 3px;
    bottom: 3px;
    padding: 1px 5px;
    font-size: 10px;
    font-weight: 700;
    color: #fff;
    background: rgba(0, 0, 0, 0.65);
    border-radius: var(--radius-sm);
  }

  .price-tag.free {
    color: #6fe38f;
  }

  .cart {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 12px 16px 16px;
    border-top: 1px solid var(--dark-4);
  }

  .cart-row {
    display: grid;
    grid-template-columns: 1fr auto auto auto;
    align-items: center;
    gap: 6px;
    padding: 5px 8px;
    font-size: 12px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .cart-label {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .cart-price {
    font-weight: 700;
    color: #fff;
  }

  .mini.remove:hover {
    background: var(--red);
    color: #fff;
  }

  .modal-backdrop {
    position: fixed;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(0, 0, 0, 0.55);
    pointer-events: auto;
    z-index: 20;
  }

  .modal {
    width: 340px;
    padding: 18px;
    background: var(--dark-7);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-md);
    box-shadow: var(--shadow);
  }

  .modal-title {
    font-size: 15px;
    font-weight: 700;
    margin-bottom: 8px;
  }

  .modal-text {
    font-size: 12px;
    line-height: 1.5;
    color: var(--dark-1);
    margin-bottom: 14px;
  }

  .modal-actions {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }

  .card span {
    text-align: center;
    line-height: 1.3;
    overflow: hidden;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
  }

  .controls {
    width: 280px;
  }

  .body {
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding: 16px;
  }

  .selected {
    font-size: 13px;
    font-weight: 500;
  }

  .keys {
    display: flex;
    flex-direction: column;
    gap: 7px;
    font-size: 12px;
    color: var(--dark-2);
  }

  .actions {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }

  .wide {
    width: 100%;
  }
</style>
