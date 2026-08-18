<script>
  import { fetchNui, formatMoney } from '../nui.js'
  import { tablet } from '../store.svelte.js'

  let tab = $state('access')

  const tabs = $derived([
    ['access', 'Room management'],
    ['utilities', 'Utilities'],
    ...(tablet.wallColors ? [['walls', 'Wall colour']] : []),
  ])
  let citizenid = $state('')
  let perms = $state({ door: true, stash: false, furniture: false, garage: false })

  const permKeys = $derived([
    ['door', 'Door', 'Door'],
    ['stash', 'Stash', 'Stash'],
    ['furniture', 'Furniture', 'Furn'],
    ...(tablet.apartment ? [] : [['garage', 'Garage', 'Gar']]),
  ])

  const util = $derived(tablet.utilities)
  const pct = $derived(util && util.limit ? Math.min(100, Math.round((util.power / util.limit) * 100)) : 0)

  function grant() {
    if (!citizenid.trim()) return
    fetchNui('tablet:setAccess', { citizenid: citizenid.trim(), ...perms })
    citizenid = ''
  }

  function revoke(entry) {
    fetchNui('tablet:setAccess', { citizenid: entry.citizenid, door: false, stash: false, furniture: false, garage: false })
  }

  function toggle(entry, key) {
    fetchNui('tablet:setAccess', { ...entry, [key]: !entry[key] })
  }
</script>

<div class="wrap">
  <div class="panel shell">
    <div class="panel-header">
      <div>
        <div class="panel-title">Housing tablet</div>
        <div class="panel-subtitle">{tablet.propertyName}</div>
      </div>
      <button class="btn subtle" onclick={() => fetchNui('close')}>Close</button>
    </div>

    <div class="tabs">
      {#each tabs as [value, label]}
        <button class="tab" class:active={tab === value} onclick={() => (tab = value)}>{label}</button>
      {/each}
    </div>

    <div class="body scroll">
      {#if tab === 'access'}
        <div class="section-title">Grant access</div>
        <div class="row">
          <input class="input" placeholder="Citizen ID" bind:value={citizenid} />
          <button class="btn subtle" onclick={() => fetchNui('tablet:getNearby')}>Nearby</button>
        </div>

        {#if tablet.nearby.length}
          <div class="nearby">
            {#each tablet.nearby as person}
              <button class="chip" onclick={() => (citizenid = person.citizenid)}>{person.name}</button>
            {/each}
          </div>
        {/if}

        <div class="perms">
          {#each permKeys as [key, label]}
            <label class="check">
              <input type="checkbox" bind:checked={perms[key]} />
              <span>{label}</span>
            </label>
          {/each}
        </div>

        <button class="btn wide" disabled={!citizenid.trim()} onclick={grant}>Grant</button>

        <div class="section-title">People with access</div>
        <div class="list">
          {#each tablet.access as entry (entry.citizenid)}
            <div class="entry">
              <div class="entry-main">
                <span class="entry-name">{entry.name}</span>
                <span class="entry-cid">{entry.citizenid}</span>
              </div>
              <div class="entry-perms">
                {#each permKeys as [key, , short]}
                  <button class="perm" class:on={entry[key]} onclick={() => toggle(entry, key)}>{short}</button>
                {/each}
              </div>
              <button class="mini danger" onclick={() => revoke(entry)}>Revoke</button>
            </div>
          {:else}
            <div class="empty">Nobody else has access</div>
          {/each}
        </div>
      {:else if tab === 'walls'}
        <div class="section-title">Wall colour</div>
        <div class="hint">Applies to this interior and is restored whenever you come back.</div>

        <div class="swatches">
          {#each tablet.wallColors ?? [] as swatch (swatch.index)}
            <button
              class="swatch"
              class:active={tablet.wallColor === swatch.index}
              style="background: #{swatch.hex}"
              title={swatch.label}
              onclick={() => {
                tablet.wallColor = swatch.index
                fetchNui('tablet:setWallColor', { color: swatch.index })
              }}
              aria-label={swatch.label}
            ></button>
          {/each}
        </div>

        {#if tablet.wallColor !== null}
          <div class="hint">
            Selected: <b>{(tablet.wallColors ?? []).find((c) => c.index === tablet.wallColor)?.label ?? tablet.wallColor}</b>
          </div>
        {/if}
      {:else if util}
        <div class="section-title">Power</div>
        <div class="meter">
          <div class="meter-fill" class:over={util.power > util.limit} style="width: {pct}%"></div>
        </div>
        <div class="row-between">
          <span class="hint">{util.power} W of {util.limit} W</span>
          <span class="badge {util.powered ? 'green' : 'red'}">{util.powered ? 'Powered' : 'Cut off'}</span>
        </div>

        <div class="section-title">Humidity</div>
        <div class="meter">
          <div class="meter-fill humid" style="width: {util.humidity}%"></div>
        </div>
        <div class="hint">{util.humidity}% — air conditioning and filters reduce this.</div>

        <div class="section-title">Billing</div>
        {#if util.free}
          <div class="hint">This is an apartment. Utilities are included, but the power cap still applies.</div>
        {:else}
          <div class="fact"><span>Monthly cost</span><b>{formatMoney(util.cost)}</b></div>
          <div class="fact">
            <span>Status</span>
            <b class:danger={util.overdue}>{util.overdue ? 'Overdue' : 'Paid'}</b>
          </div>
          <button class="btn wide" onclick={() => fetchNui('tablet:payUtilities')}>Pay {formatMoney(util.cost)}</button>
        {/if}

        {#if !util.powered}
          <div class="hint warn">Power is cut off. Lighting furniture stays in place but produces no light until you pay.</div>
        {/if}
      {:else}
        <div class="empty">Loading utilities...</div>
      {/if}
    </div>
  </div>
</div>

<style>
  .wrap {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100%;
    padding: 40px;
  }

  .shell {
    display: flex;
    flex-direction: column;
    width: 640px;
    height: 100%;
    max-height: 620px;
  }

  .tabs {
    display: flex;
    gap: 4px;
    padding: 10px 16px;
    border-bottom: 1px solid var(--dark-4);
  }

  .tab {
    padding: 7px 12px;
    font-family: inherit;
    font-size: 13px;
    color: var(--dark-1);
    background: transparent;
    border: none;
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .tab.active {
    color: #fff;
    background: var(--accent-15);
  }

  .body {
    display: flex;
    flex-direction: column;
    gap: 10px;
    flex: 1;
    padding: 18px;
    min-height: 0;
  }

  .section-title {
    font-size: 13px;
    font-weight: 700;
    margin-top: 6px;
  }

  .row {
    display: flex;
    gap: 8px;
  }

  .row-between {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
  }

  .nearby {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }

  .chip {
    padding: 5px 10px;
    font-family: inherit;
    font-size: 12px;
    color: var(--dark-1);
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .chip:hover {
    border-color: var(--blue);
    color: #fff;
  }

  .perms {
    display: flex;
    flex-wrap: wrap;
    gap: 14px;
  }


  .list {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .entry {
    display: grid;
    grid-template-columns: 1fr auto auto;
    align-items: center;
    gap: 10px;
    padding: 9px 11px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .entry-main {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .entry-name {
    font-size: 13px;
    color: var(--dark-0);
  }

  .entry-cid {
    font-size: 11px;
    color: var(--dark-3);
  }

  .entry-perms {
    display: flex;
    gap: 4px;
  }

  .perm {
    padding: 4px 8px;
    font-family: inherit;
    font-size: 11px;
    color: var(--dark-3);
    background: var(--dark-5);
    border: 1px solid transparent;
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .perm.on {
    color: #fff;
    background: var(--accent-20);
    border-color: var(--blue);
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

  .mini.danger:hover {
    background: var(--red);
    color: #fff;
  }

  .meter {
    height: 10px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: 999px;
    overflow: hidden;
  }

  .meter-fill {
    height: 100%;
    background: var(--blue);
    transition: width 0.2s ease;
  }

  .meter-fill.over {
    background: var(--red);
  }

  .meter-fill.humid {
    background: var(--yellow);
  }

  .fact {
    display: flex;
    justify-content: space-between;
    font-size: 12px;
    color: var(--dark-2);
  }

  .fact b {
    color: #fff;
  }

  .fact b.danger {
    color: var(--red);
  }

  .warn {
    color: var(--yellow);
  }

  .swatches {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(44px, 1fr));
    gap: 6px;
  }

  .swatch {
    aspect-ratio: 1;
    border: 2px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: transform 0.1s ease, border-color 0.1s ease;
  }

  .swatch:hover {
    transform: scale(1.08);
    border-color: var(--dark-2);
  }

  .swatch.active {
    border-color: var(--blue);
    box-shadow: 0 0 0 2px var(--accent-35);
  }

  .wide {
    width: 100%;
  }
</style>
