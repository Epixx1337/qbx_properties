<script>
  import { fetchNui, formatMoney } from '../nui.js'
  import { realtor, market } from '../store.svelte.js'

  let price = $state(50000)
  let isRental = $state(true)
  let rentInterval = $state(24)
  let selected = $state(null)
  let createOpen = $state(false)

  $effect(() => {
    if (!selected) return
    const fresh = realtor.units.find((unit) => unit.room === selected.room)
    if (fresh !== selected) selected = fresh ?? null
  })

  const building = $derived(realtor.buildings.find((entry) => entry.key === realtor.building) ?? null)
  const unassigned = $derived(realtor.units.filter((unit) => !unit.id).length)
  const occupied = $derived(realtor.units.filter((unit) => unit.owned).length)
  const free = $derived(realtor.units.filter((unit) => unit.id && !unit.owned).length)

  function selectBuilding(key) {
    realtor.building = key
    realtor.floor = 1
    selected = null
    createOpen = false
    fetchNui('realtor:getUnits', { building: key, floor: 1 })
  }

  function selectFloor(floor) {
    realtor.floor = floor
    selected = null
    createOpen = false
    fetchNui('realtor:getUnits', { building: realtor.building, floor })
  }

  function createUnits() {
    fetchNui('realtor:createUnits', {
      building: realtor.building,
      floor: realtor.floor,
      price,
      rentInterval: isRental ? rentInterval : null,
    })
    createOpen = false
  }

  function unitNo(unit) {
    return unit.label ?? `${realtor.floor}${String(unit.room).padStart(2, '0')}`
  }

  function unitState(unit) {
    if (unit.owned) return unit.ownerName ?? 'Occupied'
    if (unit.id) return `Free · ${formatMoney(unit.price)}`
    return 'Unassigned'
  }

  const selFacts = $derived(
    !selected
      ? []
      : selected.owned
        ? [
            ['Tenant', selected.ownerName ?? 'Unknown'],
            ['Citizen ID', selected.owner],
            ['Property', `#${selected.id}`],
            ...(selected.rentInterval ? [['Rent', `${formatMoney(selected.price)} / ${selected.rentInterval}h`]] : []),
          ]
        : selected.id
          ? [
              ['Property', `#${selected.id}`],
              ['Price', formatMoney(selected.price)],
              ...(selected.rentInterval ? [['Rent interval', `${selected.rentInterval}h`]] : []),
            ]
          : []
  )
</script>

<div class="buildings">
  <div class="bar">
    <span class="bar-label">Building</span>
    {#each realtor.buildings as entry (entry.key)}
      <button class="b-chip" class:active={realtor.building === entry.key} onclick={() => selectBuilding(entry.key)}>
        {entry.label}
        <span class="b-free">{entry.available} free</span>
      </button>
    {:else}
      <span class="hint">No buildings configured</span>
    {/each}
  </div>

  {#if building}
    <div class="bar floors-bar">
      <span class="bar-label">Floor</span>
      {#each Array(building.floors) as _, index (index)}
        <button class="floor" class:active={realtor.floor === index + 1} onclick={() => selectFloor(index + 1)}>
          {index + 1}
        </button>
      {/each}
    </div>

    <div class="scroll body">
      <div class="floor-head">
        <span class="floor-title">Floor {realtor.floor} · {building.roomsPerFloor} units</span>
        <div class="floor-actions">
          <span class="floor-summary">{occupied} occupied · {free} free{unassigned ? ` · ${unassigned} unassigned` : ''}</span>
          {#if unassigned > 0}
            <button class="btn" onclick={() => (createOpen = !createOpen)}>Create {unassigned} unassigned units</button>
          {/if}
        </div>
      </div>

      {#if createOpen && unassigned > 0}
        <div class="create-bar">
          <div class="field">
            <span class="mini-label">Price</span>
            <input class="input mono" type="number" bind:value={price} min={market.config.minPrice} />
          </div>
          <label class="check">
            <input type="checkbox" bind:checked={isRental} />
            <span>Rental</span>
          </label>
          {#if isRental}
            <div class="field">
              <span class="mini-label">Interval (hours)</span>
              <input class="input mono" type="number" bind:value={rentInterval} min="1" max="24" />
            </div>
          {/if}
          <button class="btn push-right" onclick={createUnits}>Create on floor {realtor.floor}</button>
        </div>
      {/if}

      <div class="units">
        {#each realtor.units as unit (unit.room)}
          <button class="unit" class:selected={selected?.room === unit.room} onclick={() => (selected = unit)}>
            <span class="unit-top">
              <span class="unit-no">{unitNo(unit)}</span>
              <span class="dot" class:occupied={unit.owned} class:free={unit.id && !unit.owned}></span>
            </span>
            <span class="unit-state">{unitState(unit)}</span>
          </button>
        {:else}
          <div class="empty span-all">Select a floor</div>
        {/each}
      </div>

      {#if selected}
        <div class="unit-bar">
          <div class="unit-id">
            <span class="unit-title">Unit {unitNo(selected)}</span>
            <span class="unit-sub">
              {#if selected.owned}
                Occupied · {selected.online ? 'tenant online' : 'tenant offline'}
              {:else if selected.id}
                Free — handed out by the pool on next assignment
              {:else}
                Never allocated — created automatically when the pool needs it
              {/if}
            </span>
          </div>
          <div class="unit-facts">
            {#each selFacts as [k, v] (k)}
              <span class="unit-fact">
                <span class="fact-k">{k}</span>
                <span class="fact-v">{v}</span>
              </span>
            {/each}
          </div>
          {#if selected.owned}
            <button
              class="end-btn"
              onclick={() => {
                fetchNui('realtor:releaseUnit', { propertyId: selected.id, building: realtor.building, floor: realtor.floor })
                selected = null
              }}
            >
              End tenancy
            </button>
          {/if}
        </div>
      {/if}

      <div class="legend">
        <span class="legend-item"><span class="dot occupied"></span>Occupied</span>
        <span class="legend-item"><span class="dot free"></span>Free</span>
        <span class="legend-item"><span class="dot"></span>Unassigned</span>
      </div>
    </div>
  {/if}
</div>

<style>
  .buildings {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }

  .bar {
    display: flex;
    align-items: center;
    gap: 10px;
    padding-bottom: 14px;
    border-bottom: 1px solid var(--dark-6);
    flex: none;
    overflow-x: auto;
  }

  .floors-bar {
    gap: 6px;
    padding-top: 12px;
  }

  .bar-label {
    flex: none;
    font-size: 12px;
    color: var(--dark-2);
    margin-right: 4px;
  }

  .b-chip {
    flex: none;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    font-family: inherit;
    font-size: 12px;
    color: var(--dark-1);
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .b-chip:hover {
    color: #fff;
  }

  .b-chip.active {
    color: #fff;
    background: var(--accent-15);
    border-color: var(--blue);
  }

  .b-free {
    font-family: 'Roboto Mono', monospace;
    font-size: 11px;
    color: var(--dark-3);
  }

  .b-chip.active .b-free {
    color: var(--dark-1);
  }

  .floor {
    flex: none;
    width: 34px;
    padding: 7px 0;
    text-align: center;
    font-family: 'Roboto Mono', monospace;
    font-size: 12px;
    color: var(--dark-2);
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .floor:hover {
    color: #fff;
  }

  .floor.active {
    color: #fff;
    font-weight: 500;
    background: var(--accent-15);
    border-color: var(--blue);
  }

  .body {
    flex: 1;
    min-height: 0;
    padding-top: 16px;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .floor-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    flex: none;
  }

  .floor-title {
    font-size: 13px;
    font-weight: 700;
    color: #fff;
  }

  .floor-actions {
    display: flex;
    align-items: center;
    gap: 14px;
  }

  .floor-summary {
    font-size: 12px;
    color: var(--dark-2);
  }

  .create-bar {
    display: flex;
    align-items: flex-end;
    gap: 12px;
    padding: 12px 14px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    flex: none;
  }

  .create-bar .check {
    padding-bottom: 8px;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .mini-label {
    font-size: 11px;
    color: var(--dark-2);
  }

  .mono {
    font-family: 'Roboto Mono', monospace;
    font-size: 12px;
    width: 120px;
  }

  .push-right {
    margin-left: auto;
  }

  .units {
    display: grid;
    grid-template-columns: repeat(6, 1fr);
    gap: 8px;
    flex: none;
  }

  .span-all {
    grid-column: 1 / -1;
  }

  .unit {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 5px;
    padding: 11px;
    font-family: inherit;
    text-align: left;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .unit:hover {
    border-color: var(--dark-3);
  }

  .unit.selected {
    border-color: var(--blue);
    background: var(--accent-8);
  }

  .unit-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 6px;
    width: 100%;
  }

  .unit-no {
    font-family: 'Roboto Mono', monospace;
    font-size: 13px;
    font-weight: 700;
    color: #fff;
  }

  .dot {
    flex: none;
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--dark-3);
  }

  .dot.occupied {
    background: var(--red);
  }

  .dot.free {
    background: var(--green);
  }

  .unit-state {
    font-size: 11px;
    color: var(--dark-2);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    width: 100%;
  }

  .unit-bar {
    display: flex;
    align-items: center;
    gap: 18px;
    padding: 13px 15px;
    background: #1f2023;
    border: 1px solid var(--dark-4);
    border-radius: 8px;
    flex: none;
  }

  .unit-id {
    display: flex;
    flex-direction: column;
    gap: 3px;
    min-width: 0;
  }

  .unit-title {
    font-size: 14px;
    font-weight: 700;
    color: #fff;
  }

  .unit-sub {
    font-size: 11px;
    color: var(--dark-2);
  }

  .unit-facts {
    display: flex;
    gap: 22px;
    margin-left: auto;
  }

  .unit-fact {
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .fact-k {
    font-size: 11px;
    color: var(--dark-2);
  }

  .fact-v {
    font-size: 12px;
    font-weight: 500;
    color: #fff;
  }

  .end-btn {
    flex: none;
    padding: 9px 14px;
    font-family: inherit;
    font-size: 12px;
    color: var(--red);
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .end-btn:hover {
    background: var(--red);
    color: #fff;
  }

  .legend {
    display: flex;
    gap: 18px;
    font-size: 11px;
    color: var(--dark-3);
    flex: none;
  }

  .legend-item {
    display: flex;
    align-items: center;
    gap: 6px;
  }
</style>
