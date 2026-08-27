<script>
  import { fetchNui, formatMoney } from '../nui.js'
  import { tablet } from '../store.svelte.js'

  let tab = $state('access')
  let citizenid = $state('')
  let modalCid = $state(null)
  let leaseTarget = $state('')
  let leaseRent = $state(500)
  let leaseInterval = $state(24)
  let leaseContract = $state(0)
  let payPeriods = $state(1)

  const rentInfo = $derived(tablet.rent)

  const dateFmt = (ts) => new Date(ts * 1000).toLocaleDateString()
  const dateTimeFmt = (ts) => new Date(ts * 1000).toLocaleString()

  const tabs = $derived([
    ['access', 'Housing Management'],
    ...(tablet.utilities ? [['utilities', 'Utilities']] : []),
    ...(tablet.rent ? [['rent', 'Rent']] : []),
    ...(tablet.doorcam ? [['doorcam', 'Doorcam']] : []),
    ...(tablet.upgrades?.length ? [['upgrades', 'Upgrades']] : []),
    ...(tablet.wallColors ? [['walls', 'Wall colour']] : []),
  ])

  const permKeys = $derived([
    ['door', 'Door', 'Unlock and lock the front door'],
    ['stash', 'Stash', 'Open every stash in the property'],
    ['furniture', 'Furniture', 'Place, move and remove furniture'],
    ...(tablet.apartment
      ? [['utilities', 'Utilities', 'See the utilities tab']]
      : [
          ['garage', 'Garage', 'Store and retrieve vehicles'],
          ['utilities', 'Utilities', 'See and pay the utility bill'],
          ['rent', 'Rent', 'See and pay the rent'],
        ]),
  ])

  const util = $derived(tablet.utilities)
  const pct = $derived(util && util.limit ? Math.min(100, Math.round((util.power / util.limit) * 100)) : 0)
  const humidityPct = $derived(util ? Math.min(100, Math.round((util.humidity / (util.humidityMax || 100)) * 100)) : 0)
  const maxDraw = $derived(util?.draws?.length ? util.draws[0].watts : 0)

  const modalEntry = $derived(modalCid ? tablet.access.find((entry) => entry.citizenid === modalCid) ?? null : null)

  function summary(entry) {
    const on = permKeys.filter(([key]) => entry[key]).map(([, label]) => label)
    return on.length ? on.join(' · ') : 'No permissions'
  }

  function grant() {
    if (!citizenid.trim()) return
    fetchNui('tablet:setAccess', { citizenid: citizenid.trim(), door: true, stash: false, furniture: false, garage: false, utilities: false, rent: false })
    modalCid = citizenid.trim()
    citizenid = ''
  }

  function revoke(entry) {
    if (modalCid === entry.citizenid) modalCid = null
    fetchNui('tablet:setAccess', { citizenid: entry.citizenid, door: false, stash: false, furniture: false, garage: false, utilities: false, rent: false })
  }

  function toggle(entry, key) {
    fetchNui('tablet:setAccess', { ...entry, [key]: !entry[key] })
  }

  function buyUpgrade(upgrade) {
    fetchNui('tablet:buyUpgrade', { name: upgrade.name })
  }

  const UPGRADE_ICONS = {
    storage: '<path d="M21 8v13H3V8"/><path d="M1 3h22v5H1z"/><path d="M10 12h4"/>',
    power: '<polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>',
    keyholders: '<path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m3 3L22 7l-3-3"/>',
    security: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
    garage: '<path d="M3 21V8l9-5 9 5v13"/><path d="M7 21v-8h10v8"/><path d="M7 17h10"/>',
    star: '<polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>',
  }

  const upgradeChain = (name) => name.replace(/_\d+$/, '')

  const visibleUpgrades = $derived((tablet.upgrades ?? []).filter((u) => u.owned || !u.locked))

  function chainInfo(upgrade) {
    const chain = upgradeChain(upgrade.name)
    const tiers = (tablet.upgrades ?? []).filter((u) => upgradeChain(u.name) === chain)
    if (tiers.length <= 1) return null
    return { owned: tiers.filter((u) => u.owned).length, total: tiers.length }
  }

  const upgradeIcon = (name) => UPGRADE_ICONS[upgradeChain(name)] ?? UPGRADE_ICONS.star

  function rentOut() {
    if (!leaseTarget) return
    fetchNui('tablet:rentOut', { citizenid: leaseTarget, rent: leaseRent, interval: leaseInterval, contract: leaseContract > 0 ? leaseContract : null })
    leaseTarget = ''
  }

  function billLine() {
    if (!util.paidUntil) return 'Nothing paid yet'
    const date = new Date(util.paidUntil * 1000).toLocaleDateString()
    if (util.overdue) return `Overdue since ${date}`
    const days = Math.max(0, Math.ceil((util.paidUntil - Date.now() / 1000) / 86400))
    return `Due in ${days} day${days === 1 ? '' : 's'} · paid until ${date}`
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
      {#each tabs as [value, label] (value)}
        <button class="tab" class:active={tab === value} onclick={() => (tab = value)}>{label}</button>
      {/each}
    </div>

    {#if tab === 'access'}
      <div class="access">
        <div class="grant-bar">
          <input class="input grow" placeholder="Citizen ID" bind:value={citizenid} />
          <button class="btn subtle" onclick={() => fetchNui('tablet:getNearby')}>Nearby</button>
          <button class="btn" disabled={!citizenid.trim()} onclick={grant}>Grant</button>
        </div>

        <div class="scroll access-body">
          {#if tablet.nearby.length}
            <div class="nearby">
              {#each tablet.nearby as person (person.citizenid)}
                <button class="chip" onclick={() => (citizenid = person.citizenid)}>{person.name}</button>
              {/each}
            </div>
          {/if}

          <div class="col-head">
            <span>PERSON &amp; ACCESS</span>
            <span>EDIT</span>
          </div>

          {#each tablet.access as entry (entry.citizenid)}
            <div class="entry">
              <span class="entry-main">
                <span class="entry-id">
                  <span class="entry-name">{entry.name}</span>
                  <span class="entry-cid">{entry.citizenid}</span>
                </span>
                <span class="entry-summary" class:none={summary(entry) === 'No permissions'}>{summary(entry)}</span>
              </span>
              <button class="pencil" title="Edit permissions" onclick={() => (modalCid = entry.citizenid)}>✎</button>
              <button class="mini danger" onclick={() => revoke(entry)}>Revoke</button>
            </div>
          {:else}
            <div class="empty">Nobody else has access</div>
          {/each}

          <span class="hint">Granting starts with door access only — the pencil opens the full permission list.</span>
        </div>
      </div>
    {:else if tab === 'utilities' && util}
      <div class="scroll body">
        <div class="stat-grid">
          <div class="stat-card">
            <span class="stat-label">POWER DRAW</span>
            <span class="stat-line">
              <span class="stat-big">{util.power.toLocaleString('en-US')}</span>
              <span class="stat-unit">/ {util.limit.toLocaleString('en-US')} W</span>
            </span>
            <span class="bar"><span class="bar-fill" class:over={util.power > util.limit} style="width: {pct}%"></span></span>
            <span class="fine">{pct}% of allowance · {util.poweredItems ?? 0} powered item{(util.poweredItems ?? 0) === 1 ? '' : 's'}</span>
          </div>
          <div class="stat-card">
            <span class="stat-label">HUMIDITY</span>
            <span class="stat-line">
              <span class="stat-big">{util.humidity}</span>
              <span class="stat-unit">%</span>
            </span>
            <span class="bar"><span class="bar-fill humid" style="width: {humidityPct}%"></span></span>
            <span class="fine">
              {util.humidityThreshold
                ? util.humidity <= util.humidityThreshold
                  ? `Comfortable · below the ${util.humidityThreshold}% threshold`
                  : `Muggy · above the ${util.humidityThreshold}% threshold`
                : 'Air conditioning and filters reduce this'}
            </span>
          </div>
        </div>

        {#if util.free}
          <div class="bill-card">
            <span class="bill-info">
              <span class="bill-title">Utilities included</span>
              <span class="bill-sub">This is an apartment — no bill, but the power cap still applies.</span>
            </span>
          </div>
        {:else}
          <div class="bill-card">
            <span class="bill-info">
              <span class="bill-title">Monthly bill</span>
              <span class="bill-sub" class:danger={util.overdue}>{billLine()}</span>
            </span>
            {#if util.overdue}
              <button class="btn" onclick={() => fetchNui('tablet:payUtilities')}>Pay {formatMoney(util.cost)}</button>
            {:else}
              <span class="bill-amount">{formatMoney(util.cost)}</span>
            {/if}
          </div>
        {/if}

        {#if !util.powered}
          <div class="trip-note">
            The breaker has tripped — stashes stay usable, but powered furniture is dead until an electrician repairs it and the load fits the limit.
          </div>
          <button class="btn wide" onclick={() => fetchNui('tablet:repairBreaker')}>Repair breaker</button>
        {/if}

        {#if util.draws?.length}
          <div class="section-title">Biggest draws</div>
          <div class="draws">
            {#each util.draws as draw (draw.name)}
              <div class="draw-row">
                <span class="draw-name">{draw.name}{draw.count > 1 ? ` ×${draw.count}` : ''}</span>
                <span class="draw-bar"><span class="draw-fill" style="width: {maxDraw ? Math.round((draw.watts / maxDraw) * 100) : 0}%"></span></span>
                <span class="draw-watts">{draw.watts.toLocaleString('en-US')} W</span>
              </div>
            {/each}
          </div>
        {/if}

        {#if util.history?.length}
          <div class="section-title">Payments</div>
          <div class="draws">
            {#each util.history as entry, i (i)}
              <div class="draw-row">
                <span class="draw-name">{entry.name ?? entry.payer}</span>
                <span class="pay-date">{dateFmt(entry.paidAt)}</span>
                <span class="draw-watts">{formatMoney(entry.amount)}</span>
              </div>
            {/each}
          </div>
        {/if}
      </div>
    {:else if tab === 'rent' && rentInfo}
      <div class="scroll body">
        {#if rentInfo.tenant}
          <div class="stat-grid">
            <div class="stat-card">
              <span class="stat-label">RENT</span>
              <span class="stat-line">
                <span class="stat-big">{formatMoney(rentInfo.rent)}</span>
                <span class="stat-unit">/ {rentInfo.interval}h</span>
              </span>
              <span class="fine">{rentInfo.role === 'owner' ? `Paid to you by ${rentInfo.tenant}` : `Paid to ${rentInfo.ownerName}`}</span>
            </div>
            <div class="stat-card">
              <span class="stat-label">PAID UNTIL</span>
              <span class="stat-line">
                <span class="stat-big date-big">{rentInfo.paidUntil ? dateTimeFmt(rentInfo.paidUntil) : '—'}</span>
              </span>
              <span class="fine">{rentInfo.contractEnd ? `Contract ends ${dateFmt(rentInfo.contractEnd)}` : 'Open-ended lease'}</span>
            </div>
          </div>

          {#if rentInfo.canPay}
            <div class="bill-card">
              <span class="bill-info">
                <span class="bill-title">Pay rent ahead</span>
                <span class="bill-sub">{payPeriods} payment{payPeriods === 1 ? '' : 's'} of {formatMoney(rentInfo.rent)} — pushes the next automatic charge back</span>
              </span>
              <span class="pay-controls">
                <button class="stepper" onclick={() => (payPeriods = Math.max(1, payPeriods - 1))}>−</button>
                <span class="pay-count">{payPeriods}</span>
                <button class="stepper" onclick={() => (payPeriods = Math.min(12, payPeriods + 1))}>+</button>
                <button class="btn" onclick={() => fetchNui('tablet:payRent', { periods: payPeriods })}>Pay {formatMoney(rentInfo.rent * payPeriods)}</button>
              </span>
            </div>
          {/if}

          {#if rentInfo.noticeEnd}
            <div class="trip-note">
              Eviction notice served — the lease ends {dateTimeFmt(rentInfo.noticeEnd)}.
            </div>
          {/if}

          {#if rentInfo.role === 'owner' || rentInfo.role === 'tenant'}
            <div class="tenancy-bar">
              <span class="tenancy-info">
                <span class="tenancy-name">{rentInfo.role === 'owner' ? `Rented to ${rentInfo.tenant}` : `You rent this from ${rentInfo.ownerName}`}</span>
                <span class="tenancy-sub">A missed automatic payment ends the lease{rentInfo.contractEnd ? '; the contract ends on its date' : ''}.</span>
              </span>
              {#if rentInfo.role === 'tenant'}
                <button class="end-btn" onclick={() => fetchNui('tablet:endTenancy')}>End tenancy</button>
              {:else if !rentInfo.noticeEnd}
                <button class="end-btn" onclick={() => fetchNui('tablet:endTenancy')}>
                  {rentInfo.noticeDays > 0 ? `Serve eviction notice (${rentInfo.noticeDays}d)` : 'End tenancy'}
                </button>
              {/if}
            </div>
          {/if}
        {:else if rentInfo.role === 'owner'}
          <div class="section-title">Offer a lease</div>
          <span class="hint">Rent this property out — the tenant gets full access and pays you automatically from their bank. The first payment is taken the moment they accept.</span>
          <div class="lease-row">
            <select class="select grow" bind:value={leaseTarget} onfocus={() => fetchNui('tablet:getNearby')}>
              <option value="">Nearby person...</option>
              {#each tablet.nearby as person (person.citizenid)}
                <option value={person.citizenid}>{person.name}</option>
              {/each}
            </select>
          </div>
          <div class="lease-row">
            <span class="lease-field">
              <span class="mini-label">Rent</span>
              <span class="money-wrap">
                <span class="money-sign">$</span>
                <input class="input mono money-input" type="number" min="1" bind:value={leaseRent} />
              </span>
            </span>
            <span class="lease-field">
              <span class="mini-label">Every (hours)</span>
              <input class="input mono" type="number" min="1" max="168" bind:value={leaseInterval} />
            </span>
            <span class="lease-field">
              <span class="mini-label">Contract (0 = open)</span>
              <input class="input mono" type="number" min="0" max="104" bind:value={leaseContract} />
            </span>
            <button class="btn lease-btn" disabled={!leaseTarget} onclick={rentOut}>Offer lease</button>
          </div>
          <span class="hint">A contract of 12 with 24h payments runs the lease for 12 days, then it ends on its own.</span>
        {/if}

        {#if rentInfo.history?.length}
          <div class="section-title">Payments</div>
          <div class="draws">
            {#each rentInfo.history as entry, i (i)}
              <div class="draw-row">
                <span class="draw-name">{entry.name ?? entry.payer}</span>
                <span class="pay-date">{dateFmt(entry.paidAt)}</span>
                <span class="draw-watts">{formatMoney(entry.amount)}</span>
              </div>
            {/each}
          </div>
        {/if}
      </div>
    {:else if tab === 'doorcam' && tablet.doorcam}
      <div class="scroll body">
        <div class="doorcam-head">
          <span class="section-title">At the door</span>
          <span class="doorcam-actions">
            <button class="btn subtle" onclick={() => fetchNui('tablet:getDoorcam')}>Refresh</button>
            {#if tablet.doorcam.cam}
              <button class="btn" onclick={() => fetchNui('tablet:showDoorcam')}>Show doorcam</button>
            {/if}
          </span>
        </div>

        {#if tablet.doorcam.ringers?.length}
          {#each tablet.doorcam.ringers as ringer (ringer.citizenid)}
            <div class="entry">
              <span class="entry-main">
                <span class="entry-name">{ringer.name}</span>
                <span class="entry-summary">Rang the doorbell</span>
              </span>
              <button class="btn" onclick={() => fetchNui('tablet:letIn', { citizenid: ringer.citizenid })}>
                {tablet.doorcam.mlo ? 'Buzz in' : 'Let in'}
              </button>
            </div>
          {/each}
          <span class="hint">
            {tablet.doorcam.mlo
              ? 'Buzzing someone in unlocks the front door for 10 seconds, then it locks again.'
              : 'Letting someone in brings them straight inside.'}
          </span>
        {:else}
          <div class="empty">Nobody is at the door</div>
        {/if}
      </div>
    {:else if tab === 'upgrades'}
      <div class="scroll body">
        <div class="upgrade-grid">
          {#each visibleUpgrades as upgrade (upgrade.name)}
            {@const chain = chainInfo(upgrade)}
            <div class="upgrade-card" class:owned-card={upgrade.owned}>
              <span class="upgrade-icon" class:owned-icon={upgrade.owned}>
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  {@html upgradeIcon(upgrade.name)}
                </svg>
              </span>
              <span class="upgrade-title">{upgrade.label}</span>
              {#if chain}
                <span class="tier-dots" title="Tier {chain.owned} of {chain.total}">
                  {#each Array(chain.total) as _, i (i)}
                    <span class="tier-dot" class:filled={i < chain.owned}></span>
                  {/each}
                </span>
              {/if}
              <span class="upgrade-desc">{upgrade.description ?? ''}</span>
              <span class="upgrade-foot">
                {#if upgrade.owned}
                  {#if upgrade.name === 'garage' && tablet.garageSpots < tablet.garageLimit}
                    <button class="btn subtle" onclick={() => fetchNui('tablet:placeGarage')}>Place spot {tablet.garageSpots + 1}</button>
                  {:else}
                    <span class="owned-tag">✓ Owned</span>
                  {/if}
                {:else if tablet.isUpgradeOwner}
                  <button class="btn mono-btn" onclick={() => buyUpgrade(upgrade)}>{formatMoney(upgrade.price)}</button>
                {:else}
                  <span class="hint mono-hint">{formatMoney(upgrade.price)} · owner only</span>
                {/if}
              </span>
            </div>
          {/each}
        </div>
      </div>
    {:else if tab === 'walls'}
      <div class="scroll body">
        <div class="walls-head">
          <span class="section-title">Wall colour</span>
          <span class="hint">Applies to this interior and is restored whenever you come back.</span>
        </div>

        <div class="swatches">
          {#each tablet.wallColors ?? [] as swatch (swatch.index)}
            <button
              class="swatch"
              class:active={tablet.wallColor === swatch.index}
              style="background: #{swatch.hex}"
              title={swatch.label}
              aria-label={swatch.label}
              onclick={() => {
                tablet.wallColor = swatch.index
                fetchNui('tablet:setWallColor', { color: swatch.index })
              }}
            ></button>
          {/each}
        </div>

        {#if tablet.wallColor !== null}
          {@const sel = (tablet.wallColors ?? []).find((c) => c.index === tablet.wallColor)}
          {#if sel}
            <div class="swatch-bar">
              <span class="swatch-preview" style="background: #{sel.hex}"></span>
              <span class="swatch-info">
                <span class="swatch-label">{sel.label}</span>
                <span class="swatch-hex">#{sel.hex}</span>
              </span>
            </div>
          {/if}
        {/if}
      </div>
    {/if}

    {#if modalEntry}
      <div class="overlay">
        <div class="modal">
          <div class="modal-head">
            <span class="modal-id">
              <span class="modal-title">Permissions</span>
              <span class="modal-sub">{modalEntry.name} · <span class="mono-cid">{modalEntry.citizenid}</span></span>
            </span>
            <button class="pencil" onclick={() => (modalCid = null)}>×</button>
          </div>
          <div class="modal-body">
            {#each permKeys as [key, label, hint] (key)}
              <button class="perm-row" onclick={() => toggle(modalEntry, key)}>
                <span class="perm-main">
                  <span class="perm-label">{label}</span>
                  <span class="perm-hint">{hint}</span>
                </span>
                <span class="pill" class:on={modalEntry[key]}>
                  <span class="knob"></span>
                </span>
              </button>
            {/each}
          </div>
          <div class="modal-foot">
            <span class="hint">Saved as you toggle</span>
            <button class="btn" onclick={() => (modalCid = null)}>Done</button>
          </div>
        </div>
      </div>
    {/if}
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
    position: relative;
    display: flex;
    flex-direction: column;
    width: 640px;
    height: 100%;
    max-height: 560px;
    overflow: hidden;
  }

  .tabs {
    display: flex;
    gap: 4px;
    padding: 10px 16px;
    border-bottom: 1px solid var(--dark-4);
    flex: none;
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

  .tab:hover {
    background: var(--dark-6);
    color: #fff;
  }

  .tab.active {
    color: #fff;
    background: var(--accent-15);
  }

  .body {
    display: flex;
    flex-direction: column;
    gap: 12px;
    flex: 1;
    padding: 18px;
    min-height: 0;
  }

  .section-title {
    font-size: 12px;
    font-weight: 700;
    color: var(--dark-0);
    margin-top: 4px;
  }

  .grow {
    flex: 1;
    min-width: 0;
  }

  .access {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
  }

  .grant-bar {
    display: flex;
    gap: 8px;
    padding: 14px 16px;
    border-bottom: 1px solid var(--dark-6);
    flex: none;
  }

  .access-body {
    display: flex;
    flex-direction: column;
    gap: 9px;
    flex: 1;
    padding: 16px;
    min-height: 0;
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

  .col-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 2px 2px;
    font-family: 'Roboto Mono', monospace;
    font-size: 10px;
    font-weight: 500;
    letter-spacing: 0.06em;
    color: var(--dark-3);
  }

  .entry {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 12px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .entry-main {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 3px;
    min-width: 0;
  }

  .entry-id {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .entry-name {
    font-size: 12px;
    color: #fff;
  }

  .entry-cid {
    font-family: 'Roboto Mono', monospace;
    font-size: 10px;
    color: var(--dark-3);
  }

  .entry-summary {
    font-size: 11px;
    color: var(--dark-2);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .entry-summary.none {
    color: var(--dark-3);
  }

  .pencil {
    flex: none;
    width: 30px;
    height: 30px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 14px;
    line-height: 1;
    color: var(--dark-1);
    background: var(--dark-5);
    border: none;
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .pencil:hover {
    background: var(--blue);
    color: #fff;
  }

  .mini {
    flex: none;
    padding: 7px 10px;
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

  .tenancy-bar {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 14px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .tenancy-info {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 3px;
    min-width: 0;
  }

  .tenancy-name {
    font-size: 13px;
    font-weight: 500;
    color: #fff;
  }

  .tenancy-sub {
    font-size: 11px;
    color: var(--dark-2);
  }

  .end-btn {
    flex: none;
    padding: 9px 14px;
    font-family: inherit;
    font-size: 12px;
    color: var(--red);
    background: var(--dark-5);
    border: none;
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .end-btn:hover {
    background: var(--red);
    color: #fff;
  }

  .lease-row {
    display: flex;
    align-items: flex-end;
    gap: 8px;
  }

  .lease-field {
    display: flex;
    flex-direction: column;
    gap: 4px;
    flex: 1;
    min-width: 0;
  }

  .mini-label {
    font-size: 11px;
    color: var(--dark-2);
  }

  .lease-btn {
    flex: none;
  }

  .money-wrap {
    position: relative;
    display: block;
    width: 100%;
  }

  .money-sign {
    position: absolute;
    left: 10px;
    top: 50%;
    transform: translateY(-50%);
    font-family: 'Roboto Mono', monospace;
    font-size: 12px;
    color: var(--dark-2);
    pointer-events: none;
  }

  .money-input {
    padding-left: 22px;
  }

  .doorcam-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    flex: none;
  }

  .doorcam-actions {
    display: flex;
    gap: 7px;
  }

  .pay-controls {
    display: flex;
    align-items: center;
    gap: 7px;
    flex: none;
  }

  .stepper {
    width: 28px;
    height: 28px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-family: inherit;
    font-size: 15px;
    line-height: 1;
    color: var(--dark-0);
    background: var(--dark-5);
    border: none;
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .stepper:hover {
    background: var(--dark-4);
    color: #fff;
  }

  .pay-count {
    min-width: 20px;
    text-align: center;
    font-family: 'Roboto Mono', monospace;
    font-size: 13px;
    font-weight: 700;
    color: #fff;
  }

  .pay-date {
    flex: none;
    font-size: 11px;
    color: var(--dark-3);
  }

  .date-big {
    font-size: 15px;
  }

  .mono {
    font-family: 'Roboto Mono', monospace;
  }

  .stat-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
    flex: none;
  }

  .stat-card {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 15px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: 8px;
  }

  .stat-label {
    font-size: 11px;
    letter-spacing: 0.08em;
    color: var(--dark-2);
  }

  .stat-line {
    display: flex;
    align-items: baseline;
    gap: 6px;
  }

  .stat-big {
    font-family: 'Roboto Mono', monospace;
    font-size: 26px;
    font-weight: 700;
    line-height: 1;
    color: #fff;
  }

  .stat-unit {
    font-size: 12px;
    color: var(--dark-2);
  }

  .bar {
    height: 8px;
    background: var(--dark-7);
    border-radius: 999px;
    overflow: hidden;
  }

  .bar-fill {
    display: block;
    height: 100%;
    background: var(--blue);
    border-radius: 999px;
    transition: width 0.2s ease;
  }

  .bar-fill.over {
    background: var(--red);
  }

  .bar-fill.humid {
    background: var(--yellow);
  }

  .fine {
    font-size: 11px;
    color: var(--dark-3);
  }

  .bill-card {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 14px;
    padding: 15px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: 8px;
    flex: none;
  }

  .bill-info {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }

  .bill-title {
    font-size: 13px;
    font-weight: 500;
    color: #fff;
  }

  .bill-sub {
    font-size: 12px;
    color: var(--dark-2);
  }

  .bill-sub.danger {
    color: var(--red);
  }

  .bill-amount {
    font-family: 'Roboto Mono', monospace;
    font-size: 15px;
    font-weight: 700;
    color: #fff;
    flex: none;
  }

  .trip-note {
    padding: 11px 13px;
    font-size: 12px;
    line-height: 1.45;
    color: var(--yellow);
    background: rgba(250, 176, 5, 0.08);
    border: 1px solid rgba(250, 176, 5, 0.35);
    border-radius: var(--radius-sm);
    flex: none;
  }

  .draws {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .draw-row {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 12px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .draw-name {
    flex: 1;
    font-size: 12px;
    color: var(--dark-0);
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .draw-bar {
    flex: none;
    width: 120px;
    height: 6px;
    background: var(--dark-7);
    border-radius: 999px;
    overflow: hidden;
  }

  .draw-fill {
    display: block;
    height: 100%;
    background: var(--dark-3);
    border-radius: 999px;
  }

  .draw-watts {
    flex: none;
    min-width: 64px;
    text-align: right;
    font-family: 'Roboto Mono', monospace;
    font-size: 12px;
    font-weight: 500;
    color: #fff;
  }

  .upgrade-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 10px;
  }

  .upgrade-card {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    padding: 16px 14px 14px;
    text-align: center;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: 8px;
  }

  .upgrade-card.owned-card {
    border-color: rgba(64, 192, 87, 0.4);
    background: rgba(64, 192, 87, 0.04);
  }

  .upgrade-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 44px;
    height: 44px;
    color: var(--blue-light);
    background: var(--accent-15);
    border-radius: 12px;
  }

  .upgrade-icon.owned-icon {
    color: var(--green);
    background: rgba(64, 192, 87, 0.15);
  }

  .upgrade-icon svg {
    width: 22px;
    height: 22px;
  }

  .upgrade-title {
    font-size: 13px;
    font-weight: 700;
    color: #fff;
  }

  .tier-dots {
    display: flex;
    gap: 5px;
  }

  .tier-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--dark-4);
  }

  .tier-dot.filled {
    background: var(--green);
  }

  .upgrade-desc {
    font-size: 11px;
    line-height: 1.45;
    color: var(--dark-2);
  }

  .upgrade-foot {
    margin-top: auto;
    padding-top: 4px;
  }

  .owned-tag {
    font-size: 12px;
    font-weight: 500;
    color: var(--green);
  }

  .mono-btn,
  .mono-hint {
    font-family: 'Roboto Mono', monospace;
  }

  .walls-head {
    display: flex;
    flex-direction: column;
    gap: 4px;
    flex: none;
  }

  .swatches {
    display: grid;
    grid-template-columns: repeat(8, 1fr);
    gap: 7px;
    flex: none;
  }

  .swatch {
    position: relative;
    aspect-ratio: 1;
    border: 2px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .swatch:hover {
    border-color: var(--dark-2);
  }

  .swatch.active::after {
    content: '';
    position: absolute;
    inset: -5px;
    border: 2px solid var(--blue);
    border-radius: 6px;
    pointer-events: none;
  }

  .swatch-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 12px 14px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    flex: none;
  }

  .swatch-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
    flex: 1;
    min-width: 0;
  }

  .swatch-preview {
    flex: none;
    width: 26px;
    height: 26px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--dark-4);
  }

  .swatch-label {
    font-size: 12px;
    color: #fff;
  }

  .swatch-hex {
    font-family: 'Roboto Mono', monospace;
    font-size: 10px;
    color: var(--dark-3);
    text-transform: uppercase;
  }

  .overlay {
    position: absolute;
    inset: 0;
    z-index: 20;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px;
    background: rgba(10, 11, 12, 0.72);
  }

  .modal {
    width: 400px;
    display: flex;
    flex-direction: column;
    background: var(--dark-7);
    border: 1px solid var(--dark-4);
    border-radius: 8px;
    box-shadow: var(--shadow);
    overflow: hidden;
  }

  .modal-head {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 12px;
    padding: 14px 16px;
    border-bottom: 1px solid var(--dark-4);
  }

  .modal-id {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .modal-title {
    font-size: 14px;
    font-weight: 700;
    color: #fff;
  }

  .modal-sub {
    font-size: 12px;
    color: var(--dark-2);
  }

  .mono-cid {
    font-family: 'Roboto Mono', monospace;
    font-size: 11px;
    color: var(--dark-3);
  }

  .modal-body {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 14px 16px;
  }

  .perm-row {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 11px 12px;
    font-family: inherit;
    text-align: left;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .perm-row:hover {
    border-color: var(--dark-3);
  }

  .perm-main {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 3px;
    min-width: 0;
  }

  .perm-label {
    font-size: 13px;
    font-weight: 500;
    color: #fff;
  }

  .perm-hint {
    font-size: 11px;
    color: var(--dark-2);
  }

  .pill {
    flex: none;
    display: flex;
    align-items: center;
    justify-content: flex-start;
    width: 38px;
    height: 22px;
    padding: 3px;
    background: var(--dark-4);
    border-radius: 999px;
    transition: background 0.12s ease;
  }

  .pill.on {
    justify-content: flex-end;
    background: var(--blue);
  }

  .knob {
    width: 16px;
    height: 16px;
    background: var(--dark-2);
    border-radius: 50%;
  }

  .pill.on .knob {
    background: #fff;
  }

  .modal-foot {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 12px 16px;
    border-top: 1px solid var(--dark-4);
  }

  .wide {
    width: 100%;
    flex: none;
  }
</style>
