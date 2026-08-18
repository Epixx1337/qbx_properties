<script>
  import { fetchNui, formatMoney } from '../nui.js'
  import { realtor, market, creation } from '../store.svelte.js'

  let search = $state('')

  const form = $derived(creation.form)

  const draft = $derived(creation.draft)

  const interiors = $derived(
    realtor.interiors.filter(
      (entry) => !search.trim() || entry.name.toLowerCase().includes(search.trim().toLowerCase())
    )
  )

  const sizeSpec = $derived(market.sizes[form.size])

  const blocker = $derived(
    !draft || draft.entrance === null || draft.entrance === undefined
      ? (draft?.kind === 'mlo' ? 'Capture the interior point first' : 'Place the entrance first')
      : draft.isShell && (draft.shell === null || draft.shell === undefined)
        ? 'Place the shell position'
        : draft.kind === 'shell' && !draft.hasPoints
          ? 'Capture the interaction points first'
          : form.name.trim().length < 4 || form.name.trim().length > 32
          ? 'Name must be 4-32 characters'
          : !/^[\w\s]+$/.test(form.name.trim())
            ? 'Name can only use letters, numbers and spaces'
            : form.price < market.config.minPrice
              ? 'Minimum price is ' + formatMoney(market.config.minPrice)
              : form.price > market.config.maxPrice
                ? 'Maximum price is ' + formatMoney(market.config.maxPrice)
                : null
  )


  const ready = $derived(
    draft !== null &&
      draft.entrance !== null &&
      draft.entrance !== undefined &&
      (!draft.isShell || (draft.shell !== null && draft.shell !== undefined)) &&
      (draft.kind !== 'shell' || draft.hasPoints) &&
      form.name.trim().length >= 4 &&
      form.name.trim().length <= 32 &&
      /^[\w\s]+$/.test(form.name.trim()) &&
      form.price >= market.config.minPrice &&
      form.price <= market.config.maxPrice
  )

  function start(kind, interior) {
    fetchNui('creation:start', { kind, interior })
  }

  function submit() {
    if (!ready) return
    fetchNui('creation:submit', {
      name: form.name.trim(),
      price: form.price,
      size: form.size,
      rentInterval: form.isRental ? form.rentInterval : null,
      listing:
        form.listingType === 'none'
          ? null
          : { type: form.listingType, price: form.price, hours: form.listingType === 'auction' ? form.auctionHours : null },
    })
  }

  function fmt(point) {
    return point ? `${point.x.toFixed(1)}, ${point.y.toFixed(1)}, ${point.z.toFixed(1)}` : null
  }
</script>

{#if !draft}
  <div class="layout">
    <div class="col">
      <div class="section-title">Predefined interior</div>
      <div class="hint">Shells are spawned in the world and need positioning. IPL interiors already exist and only need an entrance.</div>
      <input class="input" placeholder="Search interiors..." bind:value={search} />

      <div class="list scroll">
        {#each interiors as entry (entry.name)}
          <div class="row">
            <span class="row-name">{entry.name}</span>
            <span class="badge {entry.isShell ? 'blue' : 'green'}">{entry.isShell ? 'Shell' : 'IPL'}</span>
            <button class="mini" title="Preview interior" onclick={() => fetchNui('realtor:preview', { interior: entry.name })}>
              &#128065;
            </button>
            <button class="mini accent" onclick={() => start('shell', entry.name)}>Use</button>
          </div>
        {:else}
          <div class="empty">No interiors configured</div>
        {/each}
      </div>
    </div>

    <div class="col">
      <div class="section-title">MLO property</div>
      <div class="hint">
        MLOs already exist in the world, so there is nothing to pick. Start here and select the doors with the laser.
      </div>
      <button class="btn wide" onclick={() => start('mlo', 'mlo')}>Start MLO property</button>
    </div>
  </div>
{:else}
  <div class="layout">
    <div class="col">
      <div class="head">
        <span class="section-title">{draft.kind === 'shell' ? draft.interior : 'MLO property'}</span>
        <button class="mini" onclick={() => fetchNui('creation:cancel')}>Cancel</button>
      </div>

      <div class="steps scroll">
        {#if draft.kind === 'mlo'}
          <div class="step" class:done={draft.entrance}>
            <div class="step-main">
              <span class="step-title">Interior point</span>
              <span class="step-sub">{fmt(draft.entrance) ?? 'Stand inside the MLO, then capture your position'}</span>
            </div>
            <button class="mini accent" onclick={() => fetchNui('creation:captureInterior')}>
              {draft.entrance ? 'Redo' : 'Capture'}
            </button>
          </div>
        {:else}
          <div class="step" class:done={draft.entrance}>
            <div class="step-main">
              <span class="step-title">Entrance</span>
              <span class="step-sub">{fmt(draft.entrance) ?? 'Aim at the door with the laser'}</span>
            </div>
            <button class="mini accent" onclick={() => fetchNui('creation:pickEntrance')}>
              {draft.entrance ? 'Redo' : 'Set'}
            </button>
          </div>
        {/if}

        {#if draft.kind === 'shell'}
          <div class="step" class:done={draft.hasPoints}>
            <div class="step-main">
              <span class="step-title">Interaction points</span>
              <span class="step-sub">{draft.hasPoints ? 'Defaults captured for this interior' : 'Exit, stash, wardrobe and logout are not set yet'}</span>
            </div>
            <button class="mini accent" onclick={() => fetchNui('creation:capturePoints')}>
              {draft.hasPoints ? 'Edit' : 'Capture'}
            </button>
          </div>
        {/if}

        {#if draft.isShell}
          <div class="step" class:done={draft.shell}>
            <div class="step-main">
              <span class="step-title">Shell position</span>
              <span class="step-sub">{fmt(draft.shell) ?? 'Place the shell with the gizmo'}</span>
            </div>
            <button class="mini accent" onclick={() => fetchNui('creation:pickShellPosition')}>
              {draft.shell ? 'Redo' : 'Set'}
            </button>
          </div>
        {/if}

        {#if draft.kind === 'mlo'}
          <div class="step" class:done={draft.doors.length > 0}>
            <div class="step-main">
              <span class="step-title">Doors</span>
              <span class="step-sub">{draft.doors.length} selected</span>
            </div>
            <div class="step-actions">
              <button class="mini accent" onclick={() => fetchNui('creation:pickDoor', { double: false })}>Single</button>
              <button class="mini accent" onclick={() => fetchNui('creation:pickDoor', { double: true })}>Double</button>
            </div>
          </div>

          {#each draft.doors as door, index}
            <div class="door">
              <span>Door {index + 1}{door.double ? ' (double)' : ''}</span>
              <button class="mini danger" onclick={() => fetchNui('creation:removeDoor', { index: index + 1 })}>&times;</button>
            </div>
          {/each}
        {/if}

        {#if market.gardens}
          <div class="step" class:done={draft.garden}>
            <div class="step-main">
              <span class="step-title">Garden</span>
              <span class="step-sub">{draft.garden ? `${draft.garden.length} corners` : 'Optional zone'}</span>
            </div>
            <button class="mini accent" onclick={() => fetchNui('creation:pickGarden')}>
              {draft.garden ? 'Redo' : 'Draw'}
            </button>
          </div>
        {/if}

        <div class="step" class:done={draft.garage}>
          <div class="step-main">
            <span class="step-title">Garage</span>
            <span class="step-sub">{fmt(draft.garage) ?? 'Optional, positioned with a vehicle'}</span>
          </div>
          <button class="mini accent" onclick={() => fetchNui('creation:pickGarage')}>
            {draft.garage ? 'Redo' : 'Place'}
          </button>
        </div>
      </div>
    </div>

    <div class="col">
      <div class="section-title">Details</div>

      <div class="field">
        <span class="label">Property name</span>
        <input class="input" bind:value={form.name} maxlength="32" placeholder="Grove Street Home" />
        <span class="hint">4-32 characters. A unit number is appended automatically.</span>
      </div>

      <div class="field">
        <span class="label">Price</span>
        <input class="input" type="number" bind:value={form.price} min={market.config.minPrice} max={market.config.maxPrice} />
        <span class="hint">{formatMoney(form.price)}</span>
      </div>

      <div class="field">
        <span class="label">Size</span>
        <div class="chips">
          {#each market.sizeOrder as key}
            <button class="chip" class:active={form.size === key} onclick={() => (form.size = key)}>
              {market.sizes[key]?.label ?? key}
            </button>
          {/each}
        </div>
        {#if sizeSpec}
          <span class="hint">{sizeSpec.power} W allowance · {formatMoney(sizeSpec.cost)} per month</span>
        {/if}
      </div>

      <label class="check">
        <input type="checkbox" bind:checked={form.isRental} />
        <span>Rental property</span>
      </label>

      {#if form.isRental}
        <div class="field">
          <span class="label">Rent interval (hours)</span>
          <input class="input" type="number" bind:value={form.rentInterval} min="1" max="24" />
        </div>
      {/if}

      <div class="field">
        <span class="label">List immediately</span>
        <div class="chips">
          {#each [['none', 'Do not list'], ['sale', 'Direct sale'], ['auction', 'Auction']] as [value, label]}
            <button class="chip" class:active={form.listingType === value} onclick={() => (form.listingType = value)}>{label}</button>
          {/each}
        </div>
      </div>

      {#if form.listingType === 'auction'}
        <div class="field">
          <span class="label">Duration</span>
          <div class="chips">
            {#each market.config.auctionDurations ?? [24, 48, 72] as hours}
              <button class="chip" class:active={form.auctionHours === hours} onclick={() => (form.auctionHours = hours)}>
                {hours}h
              </button>
            {/each}
          </div>
        </div>
      {/if}

      {#if blocker}<div class="hint warn">{blocker}</div>{/if}
      <button class="btn wide push" disabled={!ready} onclick={submit}>Create property</button>
    </div>
  </div>
{/if}

<style>
  .layout {
    display: grid;
    grid-template-columns: 1fr 320px;
    gap: 22px;
    height: 100%;
    min-height: 0;
  }

  .col {
    display: flex;
    flex-direction: column;
    gap: 10px;
    min-height: 0;
  }

  .head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
  }

  .section-title {
    font-size: 13px;
    font-weight: 700;
  }

  .list,
  .steps {
    display: flex;
    flex-direction: column;
    gap: 6px;
    min-height: 0;
  }

  .row,
  .step,
  .door {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 9px 11px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .row {
    justify-content: space-between;
  }

  .row-name {
    flex: 1;
    font-size: 13px;
    color: var(--dark-0);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .step {
    justify-content: space-between;
  }

  .step.done {
    border-color: var(--green);
  }

  .step-main {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .step-title {
    font-size: 13px;
    color: var(--dark-0);
  }

  .step-sub {
    font-size: 11px;
    color: var(--dark-2);
    font-variant-numeric: tabular-nums;
  }

  .step-actions {
    display: flex;
    gap: 5px;
  }

  .door {
    justify-content: space-between;
    margin-left: 18px;
    font-size: 12px;
    color: var(--dark-2);
  }

  .mini {
    padding: 5px 10px;
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

  .mini.danger:hover {
    background: var(--red);
    color: #fff;
  }

  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 5px;
  }

  .chip {
    flex: 1;
    min-width: 64px;
    padding: 6px 8px;
    font-family: inherit;
    font-size: 12px;
    color: var(--dark-1);
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .chip.active {
    color: #fff;
    border-color: var(--blue);
    background: var(--accent-15);
  }


  .wide {
    width: 100%;
  }

  .push {
    margin-top: auto;
  }
</style>
