<script>
  import { fetchNui, formatMoney } from '../nui.js'
  import { realtor, market } from '../store.svelte.js'

  let price = $state(50000)
  let isRental = $state(true)
  let rentInterval = $state(24)
  let selected = $state(null)

  $effect(() => {
    if (!selected) return
    const fresh = realtor.units.find((unit) => unit.room === selected.room)
    if (fresh !== selected) selected = fresh ?? null
  })

  const building = $derived(realtor.buildings.find((entry) => entry.key === realtor.building) ?? null)

  function selectBuilding(key) {
    realtor.building = key
    realtor.floor = 1
    fetchNui('realtor:getUnits', { building: key, floor: 1 })
  }

  function selectFloor(floor) {
    realtor.floor = floor
    fetchNui('realtor:getUnits', { building: realtor.building, floor })
  }

  function createUnits() {
    fetchNui('realtor:createUnits', {
      building: realtor.building,
      floor: realtor.floor,
      price,
      rentInterval: isRental ? rentInterval : null,
    })
  }

  const unassigned = $derived(realtor.units.filter((unit) => !unit.id).length)
</script>

<div class="layout">
  <div class="col narrow">
    <div class="section-title">Buildings</div>
    {#each realtor.buildings as entry}
      <button class="row-btn" class:active={realtor.building === entry.key} onclick={() => selectBuilding(entry.key)}>
        <span>{entry.label}</span>
        <span class="badge">{entry.available} free</span>
      </button>
    {:else}
      <div class="empty">No buildings configured</div>
    {/each}

    {#if building}
      <div class="section-title spaced">Floors</div>
      <div class="floors scroll">
        {#each Array(building.floors) as _, index}
          <button class="floor" class:active={realtor.floor === index + 1} onclick={() => selectFloor(index + 1)}>
            {index + 1}
          </button>
        {/each}
      </div>
    {/if}
  </div>

  {#if building}
    <div class="col">
      <div class="section-title">Floor {realtor.floor} · {building.roomsPerFloor} units</div>

      <div class="units scroll">
        {#each realtor.units as unit}
          <button
            class="unit"
            class:owned={unit.owned}
            class:listed={unit.id && !unit.owned}
            class:active={selected?.room === unit.room}
            onclick={() => (selected = unit)}
          >
            <span class="unit-no">{unit.label ?? `${realtor.floor}${String(unit.room).padStart(2, '0')}`}</span>
            <span class="unit-state">
              {#if unit.owned}{unit.ownerName ?? 'Occupied'}{:else if unit.id}{formatMoney(unit.price)}{:else}Unassigned{/if}
            </span>
          </button>
        {:else}
          <div class="empty">Select a floor</div>
        {/each}
      </div>

      {#if unassigned > 0}
        <div class="create">
          <div class="section-title">Create the {unassigned} unassigned units</div>

          <div class="field">
            <span class="label">Price</span>
            <input class="input" type="number" bind:value={price} min={market.config.minPrice} />
          </div>

          <label class="check">
            <input type="checkbox" bind:checked={isRental} />
            <span>Rental</span>
          </label>

          {#if isRental}
            <div class="field">
              <span class="label">Rent interval (hours)</span>
              <input class="input" type="number" bind:value={rentInterval} min="1" max="24" />
            </div>
          {/if}

          <button class="btn wide" onclick={createUnits}>Create units on floor {realtor.floor}</button>
        </div>
      {/if}
    </div>

    <div class="col side">
      {#if selected}
        <div class="detail">
          <div class="detail-head">
            <span class="section-title">{selected.label ?? `Unit ${selected.room}`}</span>
            {#if selected.owned}
              <span class="badge {selected.online ? 'green' : ''}">{selected.online ? 'Online' : 'Offline'}</span>
            {/if}
          </div>

          {#if selected.owned}
            <div class="detail-row"><span>Tenant</span><b>{selected.ownerName ?? 'Unknown'}</b></div>
            <div class="detail-row"><span>Citizen ID</span><b>{selected.owner}</b></div>
            <div class="detail-row"><span>Property ID</span><b>{selected.id}</b></div>
            {#if selected.rentInterval}
              <div class="detail-row"><span>Rent</span><b>{formatMoney(selected.price)} / {selected.rentInterval}h</b></div>
            {/if}
            <button
              class="btn danger wide"
              onclick={() => {
                fetchNui('realtor:releaseUnit', {
                  propertyId: selected.id,
                  building: realtor.building,
                  floor: realtor.floor,
                })
                selected = null
              }}
            >
              End tenancy
            </button>
          {:else if selected.id}
            <div class="detail-row"><span>Property ID</span><b>{selected.id}</b></div>
            <div class="detail-row"><span>Price</span><b>{formatMoney(selected.price)}</b></div>
            <div class="hint">Free — will be handed out by the pool on next assignment.</div>
          {:else}
            <div class="hint">This unit has never been allocated. It is created automatically the first time the pool needs it.</div>
          {/if}
        </div>
      {/if}

    </div>
  {/if}
</div>

<style>
  .layout {
    display: grid;
    grid-template-columns: 240px minmax(0, 1fr) 300px;
    gap: 18px;
    height: 100%;
    min-height: 0;
  }

  .col {
    display: flex;
    flex-direction: column;
    gap: 10px;
    min-height: 0;
  }

  .section-title {
    font-size: 13px;
    font-weight: 700;
  }

  .row-btn {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    padding: 10px 12px;
    font-family: inherit;
    font-size: 13px;
    color: var(--dark-0);
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .row-btn.active {
    border-color: var(--blue);
    background: var(--accent-8);
  }

  .floors {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(46px, 1fr));
    gap: 5px;
    align-content: start;
    min-height: 0;
  }

  .spaced {
    margin-top: 6px;
  }

  .floor {
    padding: 8px 6px;
    text-align: center;
    font-family: inherit;
    font-size: 12px;
    color: var(--dark-1);
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .floor.active {
    color: #fff;
    border-color: var(--blue);
    background: var(--accent-15);
  }

  .units {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(90px, 1fr));
    gap: 6px;
    min-height: 0;
  }

  .unit {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 3px;
    padding: 8px;
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

  .unit.active {
    border-color: var(--blue);
    background: var(--accent-8);
  }

  .side {
    padding-left: 18px;
    border-left: 1px solid var(--dark-4);
  }

  .detail {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .create {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding-top: 14px;
    border-top: 1px solid var(--dark-4);
  }

  .detail-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .detail-row {
    display: flex;
    justify-content: space-between;
    gap: 10px;
    font-size: 12px;
    color: var(--dark-2);
  }

  .detail-row b {
    color: #fff;
  }

  .unit.owned {
    border-color: var(--red);
  }

  .unit.listed {
    border-color: var(--green);
  }

  .unit-no {
    font-size: 13px;
    font-weight: 700;
  }

  .unit-state {
    font-size: 10px;
    color: var(--dark-2);
  }



  .wide {
    width: 100%;
  }
</style>
