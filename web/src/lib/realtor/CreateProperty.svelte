<script>
  import { fetchNui, formatMoney } from '../nui.js'
  import { realtor, market, creation } from '../store.svelte.js'

  let search = $state('')
  let step = $state(1)

  const form = $derived(creation.form)
  const draft = $derived(creation.draft)

  const interiors = $derived(
    realtor.interiors.filter(
      (entry) => !search.trim() || entry.name.toLowerCase().includes(search.trim().toLowerCase())
    )
  )

  const sizeSpec = $derived(market.sizes[form.size])
  const typeSpec = $derived(market.types?.[form.propertyType])

  const nameOk = $derived(
    form.name.trim().length >= 4 && form.name.trim().length <= 32 && /^[\w\s]+$/.test(form.name.trim())
  )
  const priceOk = $derived(form.price >= market.config.minPrice && form.price <= market.config.maxPrice)

  const pointsBlocker = $derived(
    !draft
      ? 'Pick an interior first'
      : draft.entrance === null || draft.entrance === undefined
        ? (draft.kind === 'mlo' ? 'Capture the interior point first' : 'Set the entrance first')
        : draft.isShell && (draft.shell === null || draft.shell === undefined)
          ? 'Place the shell position'
          : draft.kind === 'shell' && !draft.hasPoints
            ? 'Capture the interaction points first'
            : null
  )

  const detailsBlocker = $derived(
    !nameOk
      ? (form.name.trim().length < 4 ? 'Name must be 4-32 characters' : !/^[\w\s]+$/.test(form.name.trim()) ? 'Name can only use letters, numbers and spaces' : 'Name must be 4-32 characters')
      : !priceOk
        ? form.price < market.config.minPrice
          ? 'Minimum price is ' + formatMoney(market.config.minPrice)
          : 'Maximum price is ' + formatMoney(market.config.maxPrice)
        : typeSpec?.groupAccess && !form.group.trim()
          ? 'Enter the gang name'
          : null
  )

  const steps = $derived([
    { n: 1, label: 'Interior', done: draft !== null },
    { n: 2, label: 'Points', done: draft !== null && !pointsBlocker },
    { n: 3, label: 'Details', done: nameOk && priceOk && !detailsBlocker },
    { n: 4, label: 'Review', done: false },
  ])

  const stepMeta = $derived(
    step === 1
      ? {
          title: 'Pick the interior',
          hint: 'An MLO already exists in the world — start there if you are standing in one. Shells are spawned and need positioning; IPL interiors only need an entrance.',
        }
      : step === 2
        ? {
            title: 'Capture the points',
            hint: 'Each capture closes this window while you place the point in the world. Come back here when it is set.',
          }
        : step === 3
          ? { title: 'Details', hint: 'Name, price and size. The summary is shown to buyers on the market page.' }
          : { title: 'Review and create', hint: 'Check everything, decide whether it goes straight onto the market, then create it.' }
  )

  const canNext = $derived(
    step === 1 ? draft !== null : step === 2 ? !pointsBlocker : step === 3 ? !detailsBlocker : true
  )

  const nextBlocker = $derived(
    step === 1 && !draft ? 'Pick an interior or start an MLO property' : step === 2 ? pointsBlocker : step === 3 ? detailsBlocker : null
  )

  function goTo(target) {
    if (target === step) return
    if (target > 1 && !draft) return
    if (target > 2 && pointsBlocker) return
    if (target > 3 && detailsBlocker) return
    step = target
  }

  function next() {
    if (step === 4) return submit()
    if (!canNext) return
    step += 1
  }

  function back() {
    if (step > 1) step -= 1
  }

  let advanceOnDraft = $state(false)

  $effect(() => {
    if (!draft && step > 1) step = 1
  })

  $effect(() => {
    if (draft && advanceOnDraft) {
      advanceOnDraft = false
      step = 2
    }
  })

  async function start(kind, interior) {
    if (draft) {
      if (draft.kind === kind && (kind === 'mlo' || draft.interior === interior)) {
        step = 2
        return
      }
      await fetchNui('creation:cancel')
    }
    advanceOnDraft = true
    fetchNui('creation:start', { kind, interior })
  }

  function cancelDraft() {
    fetchNui('creation:cancel')
    step = 1
  }

  function submit() {
    if (!draft || pointsBlocker || detailsBlocker) return
    fetchNui('creation:submit', {
      name: form.name.trim(),
      price: form.price,
      size: form.size,
      rentInterval: form.isRental ? form.rentInterval : null,
      propertyType: form.propertyType,
      group: form.group.trim() || null,
      description: form.description.trim() || null,
      listing:
        form.listingType === 'none'
          ? null
          : { type: form.listingType, price: form.price, hours: form.listingType === 'auction' ? form.auctionHours : null },
    })
  }

  function fmt(point) {
    return point ? `${point.x.toFixed(1)}, ${point.y.toFixed(1)}, ${point.z.toFixed(1)}` : null
  }

  const pointSteps = $derived(
    !draft
      ? []
      : [
          draft.kind === 'mlo'
            ? {
                key: 'interior',
                label: 'Interior point',
                value: fmt(draft.entrance) ?? 'Stand inside the MLO, then capture your position',
                done: !!draft.entrance,
                action: draft.entrance ? 'Redo' : 'Capture',
                run: () => fetchNui('creation:captureInterior'),
              }
            : {
                key: 'entrance',
                label: 'Entrance',
                value: fmt(draft.entrance) ?? 'Aim at the door with the laser',
                done: !!draft.entrance,
                action: draft.entrance ? 'Redo' : 'Set',
                run: () => fetchNui('creation:pickEntrance'),
              },
          ...(draft.isShell
            ? [
                {
                  key: 'shell',
                  label: 'Shell position',
                  value: fmt(draft.shell) ?? 'Place the shell with the gizmo',
                  done: !!draft.shell,
                  action: draft.shell ? 'Redo' : 'Set',
                  run: () => fetchNui('creation:pickShellPosition'),
                },
              ]
            : []),
          ...(draft.kind === 'shell'
            ? [
                {
                  key: 'points',
                  label: 'Interaction points',
                  value: draft.hasPoints ? 'Defaults captured for this interior' : 'Exit, stash, wardrobe and logout are not set yet',
                  done: !!draft.hasPoints,
                  action: draft.hasPoints ? 'Edit' : 'Capture',
                  run: () => fetchNui('creation:capturePoints'),
                },
              ]
            : []),
          ...(market.gardens
            ? [
                {
                  key: 'garden',
                  label: 'Garden',
                  value: draft.garden ? `${draft.garden.length} corners drawn` : 'Optional zone',
                  done: !!draft.garden,
                  action: draft.garden ? 'Redo' : 'Draw',
                  run: () => fetchNui('creation:pickGarden'),
                },
              ]
            : []),
          {
            key: 'garage',
            label: 'Garage',
            value: fmt(draft.garage) ?? 'Optional, positioned with a vehicle',
            done: !!draft.garage,
            action: draft.garage ? 'Redo' : 'Place',
            run: () => fetchNui('creation:pickGarage'),
          },
        ]
  )

  const reviewRows = $derived([
    ['Interior', !draft ? '—' : draft.kind === 'mlo' ? 'MLO — existing world interior' : draft.interior],
    ['Type', typeSpec?.label ?? form.propertyType],
    ...(typeSpec?.groupAccess ? [['Gang', form.group.trim() || '—']] : []),
    ['Size', sizeSpec ? sizeSpec.label : form.size],
    ['Sale', form.isRental ? `Rental · every ${form.rentInterval}h` : 'Full purchase'],
    ['Doors', !draft ? '—' : draft.kind === 'mlo' ? `${draft.doors.length} on the doorlock hook` : 'From interior defaults'],
    ['Garden', draft?.garden ? `${draft.garden.length} corners` : 'None'],
    ['Garage', draft?.garage ? 'Placed' : 'None'],
  ])

  const listHint = $derived(
    form.listingType === 'none'
      ? 'The property is created unlisted — list it later from Manage.'
      : form.listingType === 'sale'
        ? `Listed immediately at ${formatMoney(form.price)}.`
        : form.listingType === 'auction'
          ? `Auction starts at ${formatMoney(form.price)} and runs for ${form.auctionHours} hours.`
          : `Open to offers at ${formatMoney(form.price)} — you accept or decline each one.`
  )
</script>

<div class="wizard">
  <div class="stepbar">
    {#each steps as s (s.n)}
      <button
        class="step-tab"
        class:done={s.done && step !== s.n}
        class:current={step === s.n}
        onclick={() => goTo(s.n)}
      >
        <span class="step-n">{s.n}</span>
        <span class="step-label">{s.label}</span>
      </button>
    {/each}
  </div>

  <div class="scroll stage">
    <div class="inner">
      <div class="stage-head">
        <span class="stage-title">{stepMeta.title}</span>
        <span class="stage-hint">{stepMeta.hint}</span>
      </div>

      {#if step === 1}
        <div class="pick">
          <button class="mlo-card" class:picked={draft?.kind === 'mlo'} onclick={() => start('mlo', 'mlo')}>
            <span class="mlo-thumb"></span>
            <span class="mlo-info">
              <span class="mlo-title">MLO property — where you are standing</span>
              <span class="mlo-sub">The interior already exists in the world. Nothing to pick: capture the interior point and select the doors with the laser.</span>
            </span>
          </button>

          <div class="interior-block">
            <div class="interior-head">
              <span class="block-title">Predefined interior</span>
              <input class="input search" placeholder="Search interiors..." bind:value={search} />
            </div>
            <div class="interior-list">
              {#each interiors as entry (entry.name)}
                <div class="interior-row" class:picked={draft?.kind === 'shell' && draft?.interior === entry.name}>
                  <span class="interior-thumb"></span>
                  <span class="interior-name">{entry.name}</span>
                  <span class="badge {entry.isShell ? 'blue' : 'green'}">{entry.isShell ? 'Shell' : 'IPL'}</span>
                  <button class="mini" onclick={() => fetchNui('realtor:preview', { interior: entry.name })}>Preview</button>
                  <button class="mini accent" onclick={() => start('shell', entry.name)}>Use</button>
                </div>
              {:else}
                <div class="empty">No interiors configured</div>
              {/each}
            </div>
          </div>

          {#if draft}
            <div class="picked-bar">
              <span>Working on <b>{draft.kind === 'mlo' ? 'an MLO property' : draft.interior}</b></span>
              <button class="mini danger" onclick={cancelDraft}>Cancel draft</button>
            </div>
          {/if}
        </div>
      {:else if step === 2}
        <div class="points">
          {#each pointSteps as p (p.key)}
            <div class="point-row" class:done={p.done}>
              <span class="point-main">
                <span class="point-label">{p.label}</span>
                <span class="point-value">{p.value}</span>
              </span>
              <button class="mini accent" onclick={p.run}>{p.action}</button>
            </div>
          {/each}

          {#if draft?.kind === 'mlo'}
            <div class="point-row" class:done={draft.doors.length > 0}>
              <span class="point-main">
                <span class="point-label">Doors</span>
                <span class="point-value">{draft.doors.length} on the doorlock hook</span>
              </span>
              <span class="door-actions">
                <button class="mini accent" onclick={() => fetchNui('creation:pickDoor', { double: false })}>Single</button>
                <button class="mini accent" onclick={() => fetchNui('creation:pickDoor', { double: true })}>Double</button>
              </span>
            </div>
            {#each draft.doors as door, index (index)}
              <div class="door-row">
                <span>Door {index + 1}{door.double ? ' (double)' : ''}</span>
                <button class="mini danger" onclick={() => fetchNui('creation:removeDoor', { index: index + 1 })}>&times;</button>
              </div>
            {/each}
          {/if}

          <div class="note">Garden and garage are optional. Everything captured here can be redone later from Manage.</div>
        </div>
      {:else if step === 3}
        <div class="details">
          <div class="field">
            <span class="label">Property name</span>
            <input class="input" bind:value={form.name} maxlength="32" placeholder="Mirror Park Villa" />
            <span class="hint">4-32 characters. A unit number is appended automatically.</span>
          </div>

          <div class="two-col">
            <div class="field">
              <span class="label">Price</span>
              <input class="input mono" type="number" bind:value={form.price} min={market.config.minPrice} max={market.config.maxPrice} />
              <span class="hint">{formatMoney(form.price)}</span>
            </div>
            <div class="field">
              <span class="label">Rent interval</span>
              <div class="rent-row">
                <label class="check">
                  <input type="checkbox" bind:checked={form.isRental} />
                  <span>Rental</span>
                </label>
                {#if form.isRental}
                  <input class="input mono" type="number" bind:value={form.rentInterval} min="1" max="24" />
                {/if}
              </div>
              <span class="hint">{form.isRental ? 'Hours between rent charges' : 'Sold outright'}</span>
            </div>
          </div>

          <div class="field">
            <span class="label">Size</span>
            <div class="size-grid">
              {#each market.sizeOrder as key (key)}
                <button class="size-card" class:active={form.size === key} onclick={() => (form.size = key)}>
                  <span class="size-label">{market.sizes[key]?.label ?? key}</span>
                  <span class="size-spec">{market.sizes[key] ? `${market.sizes[key].power.toLocaleString('en-US')} W · ${formatMoney(market.sizes[key].cost)}/mo` : ''}</span>
                </button>
              {/each}
            </div>
          </div>

          <div class="field">
            <span class="label">Type</span>
            <div class="type-chips">
              {#each Object.entries(market.types ?? {}) as [key, spec] (key)}
                <button class="chip" class:active={form.propertyType === key} onclick={() => (form.propertyType = key)}>
                  {spec.label ?? key}
                </button>
              {/each}
            </div>
          </div>

          {#if typeSpec?.groupAccess}
            <div class="field">
              <span class="label">Gang name</span>
              <input class="input" placeholder="gang name from qbx_core" bind:value={form.group} />
              <span class="hint">Every member of this gang gets full access to the property.</span>
            </div>
          {/if}

          <div class="field">
            <span class="label">Listing summary</span>
            <textarea class="input summary" rows="3" maxlength="500" bind:value={form.description}
              placeholder="Hillside villa above Mirror Park. Walled garden, two-car drive and a view over the lake."></textarea>
            <span class="hint">Shown on the market card and the listing page. 500 characters max.</span>
          </div>
        </div>
      {:else}
        <div class="review">
          <div class="summary-card">
            <span class="summary-thumb"><span class="photo-label">NO PHOTOS YET</span></span>
            <span class="summary-info">
              <span class="summary-name">{form.name.trim() || 'Unnamed property'}</span>
              <span class="summary-meta">
                {draft?.kind === 'mlo' ? 'MLO' : draft?.interior} · {sizeSpec?.label ?? form.size}{sizeSpec ? ` · ${sizeSpec.power.toLocaleString('en-US')} W allowance` : ''}
              </span>
              <span class="summary-price">{formatMoney(form.price)}</span>
              <span class="summary-sub">
                {form.isRental ? `Rental, charged every ${form.rentInterval} hours` : 'Full purchase'}{sizeSpec ? ` · ${formatMoney(sizeSpec.cost)} monthly utilities` : ''}
              </span>
            </span>
          </div>

          <div class="review-grid">
            {#each reviewRows as [k, v] (k)}
              <div class="review-row">
                <span class="review-k">{k}</span>
                <span class="review-v">{v}</span>
              </div>
            {/each}
          </div>

          <div class="field">
            <span class="label">List immediately</span>
            <div class="type-chips">
              {#each [['none', 'Do not list'], ['sale', 'Direct sale'], ['auction', 'Auction'], ['offer', 'Open to offers']] as [value, label] (value)}
                <button class="chip" class:active={form.listingType === value} onclick={() => (form.listingType = value)}>{label}</button>
              {/each}
            </div>
            {#if form.listingType === 'auction'}
              <div class="type-chips">
                {#each market.config.auctionDurations ?? [24, 48, 72] as hours (hours)}
                  <button class="chip" class:active={form.auctionHours === hours} onclick={() => (form.auctionHours = hours)}>{hours}h</button>
                {/each}
              </div>
            {/if}
            <span class="hint">{listHint}</span>
          </div>
        </div>
      {/if}
    </div>
  </div>

  <div class="footer">
    <button class="btn subtle" disabled={step === 1} onclick={back}>Back</button>
    <span class="footer-mid">
      {#if nextBlocker}{nextBlocker}{:else}Step {step} of 4{/if}
    </span>
    <button class="btn" disabled={!canNext} onclick={next}>{step === 4 ? 'Create property' : 'Next'}</button>
  </div>
</div>

<style>
  .wizard {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }

  .stepbar {
    display: flex;
    gap: 8px;
    padding-bottom: 16px;
    border-bottom: 1px solid var(--dark-6);
    flex: none;
  }

  .step-tab {
    flex: 1;
    display: flex;
    align-items: center;
    gap: 9px;
    padding: 11px 13px;
    font-family: inherit;
    text-align: left;
    background: #1f2023;
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .step-tab:hover {
    border-color: var(--dark-3);
  }

  .step-n {
    flex: none;
    width: 20px;
    height: 20px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-family: 'Roboto Mono', monospace;
    font-size: 11px;
    font-weight: 500;
    color: var(--dark-3);
    background: var(--dark-5);
    border-radius: 50%;
  }

  .step-label {
    font-size: 12px;
    color: var(--dark-3);
  }

  .step-tab.done {
    background: var(--dark-6);
    border-color: var(--green);
  }

  .step-tab.done .step-n {
    color: #0a0b0c;
    background: var(--green);
    font-weight: 700;
  }

  .step-tab.done .step-label {
    color: var(--dark-0);
  }

  .step-tab.current {
    background: var(--accent-15);
    border-color: var(--blue);
  }

  .step-tab.current .step-n {
    color: #fff;
    background: var(--blue);
    font-weight: 700;
  }

  .step-tab.current .step-label {
    color: #fff;
    font-weight: 500;
  }

  .stage {
    flex: 1;
    min-height: 0;
    padding: 22px 0;
  }

  .inner {
    max-width: 640px;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: 18px;
  }

  .stage-head {
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .stage-title {
    font-size: 18px;
    font-weight: 700;
    color: #fff;
  }

  .stage-hint {
    font-size: 13px;
    line-height: 1.55;
    color: var(--dark-2);
  }

  .pick {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .mlo-card {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 15px;
    font-family: inherit;
    text-align: left;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: 8px;
    cursor: pointer;
  }

  .mlo-card:hover {
    border-color: var(--blue);
  }

  .mlo-card.picked {
    border-color: var(--blue);
    background: var(--accent-8);
  }

  .mlo-thumb {
    flex: none;
    width: 44px;
    height: 44px;
    border-radius: var(--radius-sm);
    background: repeating-linear-gradient(135deg, var(--dark-4) 0 6px, var(--dark-5) 6px 12px);
  }

  .mlo-info {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .mlo-title {
    font-size: 14px;
    font-weight: 500;
    color: #fff;
  }

  .mlo-sub {
    font-size: 12px;
    line-height: 1.45;
    color: var(--dark-2);
  }

  .interior-block {
    display: flex;
    flex-direction: column;
    gap: 9px;
  }

  .interior-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .block-title {
    font-size: 12px;
    font-weight: 700;
    color: var(--dark-0);
  }

  .search {
    width: 220px;
  }

  .interior-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .interior-row {
    display: flex;
    align-items: center;
    gap: 11px;
    padding: 9px 11px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .interior-row.picked {
    border-color: var(--blue);
    background: var(--accent-8);
  }

  .interior-thumb {
    flex: none;
    width: 44px;
    height: 32px;
    border-radius: 3px;
    background: repeating-linear-gradient(135deg, var(--dark-4) 0 5px, var(--dark-5) 5px 10px);
  }

  .interior-name {
    flex: 1;
    font-size: 13px;
    color: var(--dark-0);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .picked-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 11px 13px;
    font-size: 12px;
    color: var(--dark-1);
    background: var(--accent-8);
    border: 1px solid var(--accent-35);
    border-radius: var(--radius-sm);
  }

  .picked-bar b {
    color: #fff;
  }

  .points {
    display: flex;
    flex-direction: column;
    gap: 7px;
  }

  .point-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 13px 14px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .point-row.done {
    border-color: var(--green);
  }

  .point-main {
    display: flex;
    flex-direction: column;
    gap: 3px;
    min-width: 0;
  }

  .point-label {
    font-size: 13px;
    color: #fff;
  }

  .point-value {
    font-family: 'Roboto Mono', monospace;
    font-size: 11px;
    line-height: 1.3;
    color: var(--dark-2);
  }

  .mini {
    flex: none;
    padding: 5px 10px;
    font-family: inherit;
    font-size: 11px;
    color: var(--dark-0);
    background: var(--dark-5);
    border: none;
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .mini:hover:not(:disabled) {
    background: var(--dark-4);
    color: #fff;
  }

  .mini.accent:hover:not(:disabled) {
    background: var(--blue);
    color: #fff;
  }

  .mini.danger:hover:not(:disabled) {
    background: var(--red);
    color: #fff;
  }

  .mini:disabled {
    opacity: 0.45;
    cursor: not-allowed;
  }

  .door-actions {
    display: flex;
    gap: 5px;
    flex: none;
  }

  .door-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    margin-left: 18px;
    padding: 8px 11px;
    font-size: 12px;
    color: var(--dark-2);
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .note {
    margin-top: 6px;
    padding: 11px 13px;
    font-size: 12px;
    line-height: 1.45;
    color: var(--yellow);
    background: rgba(250, 176, 5, 0.08);
    border: 1px solid rgba(250, 176, 5, 0.35);
    border-radius: var(--radius-sm);
  }

  .details {
    display: flex;
    flex-direction: column;
    gap: 15px;
  }

  .two-col {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
  }

  .mono {
    font-family: 'Roboto Mono', monospace;
  }

  .rent-row {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .rent-row .input {
    width: 80px;
  }

  .size-grid {
    display: flex;
    gap: 6px;
  }

  .size-card {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 3px;
    padding: 10px;
    font-family: inherit;
    text-align: left;
    color: var(--dark-1);
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .size-card:hover {
    border-color: var(--dark-3);
  }

  .size-card.active {
    color: #fff;
    background: var(--accent-15);
    border-color: var(--blue);
  }

  .size-label {
    font-size: 12px;
    font-weight: 500;
  }

  .size-spec {
    font-size: 11px;
    color: var(--dark-3);
  }

  .size-card.active .size-spec {
    color: var(--dark-1);
  }

  .type-chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }

  .chip {
    flex: 1;
    min-width: 90px;
    padding: 9px;
    font-family: inherit;
    font-size: 12px;
    color: var(--dark-2);
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .chip:hover {
    color: #fff;
  }

  .chip.active {
    color: #fff;
    background: var(--accent-15);
    border-color: var(--blue);
  }

  .summary {
    resize: vertical;
    min-height: 66px;
    line-height: 1.5;
  }

  .review {
    display: flex;
    flex-direction: column;
    gap: 15px;
  }

  .summary-card {
    display: flex;
    gap: 14px;
    padding: 15px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: 8px;
  }

  .summary-thumb {
    flex: none;
    width: 150px;
    height: 104px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: repeating-linear-gradient(135deg, var(--dark-4) 0 8px, var(--dark-5) 8px 16px);
    border-radius: var(--radius-sm);
  }

  .photo-label {
    font-family: 'Roboto Mono', monospace;
    font-size: 10px;
    font-weight: 500;
    letter-spacing: 0.1em;
    color: var(--dark-3);
  }

  .summary-info {
    display: flex;
    flex-direction: column;
    gap: 6px;
    min-width: 0;
  }

  .summary-name {
    font-size: 16px;
    font-weight: 700;
    color: #fff;
  }

  .summary-meta {
    font-size: 12px;
    color: var(--dark-2);
  }

  .summary-price {
    margin-top: auto;
    font-size: 22px;
    font-weight: 700;
    color: #fff;
  }

  .summary-sub {
    font-size: 11px;
    color: var(--dark-3);
  }

  .review-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0 24px;
  }

  .review-row {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 12px;
    padding: 8px 0;
    border-bottom: 1px solid var(--dark-6);
  }

  .review-k {
    font-size: 12px;
    color: var(--dark-2);
  }

  .review-v {
    font-size: 12px;
    font-weight: 500;
    color: #fff;
    text-align: right;
  }

  .footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding-top: 16px;
    border-top: 1px solid var(--dark-6);
    flex: none;
  }

  .footer-mid {
    font-size: 12px;
    color: var(--dark-3);
    text-align: center;
  }
</style>
