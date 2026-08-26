<script>
  import { fetchNui, formatMoney } from '../nui.js'
  import { realtor, market } from '../store.svelte.js'
  import Lightbox from '../Lightbox.svelte'

  let selected = $state(null)
  let editPrice = $state(0)
  let editSize = $state('medium')
  let editRental = $state(false)
  let editRentInterval = $state(24)
  let editDescription = $state('')
  let lightboxIndex = $state(null)
  let deleteArmed = $state(false)
  let search = $state('')
  let filter = $state('all')

  let listingType = $state('sale')
  let price = $state(50000)
  let auctionHours = $state(72)
  let reservePrice = $state(0)
  let minIncrement = $state(1000)

  const details = $derived(realtor.details && selected && realtor.details.id === selected.id ? realtor.details : null)

  const visible = $derived(
    realtor.properties.filter((property) => {
      if (filter === 'owned' && !property.owner) return false
      if (filter === 'free' && property.owner) return false
      if (search.trim()) {
        const q = search.trim().toLowerCase()
        if (!property.property_name.toLowerCase().includes(q) && !(ownerName(property) ?? '').toLowerCase().includes(q)) return false
      }
      return true
    })
  )

  function select(property) {
    if (selected?.id === property.id) return
    selected = property
    realtor.details = null
    deleteArmed = false
    fetchNui('realtor:details', { propertyId: property.id })
  }

  function deleteProperty() {
    fetchNui('realtor:deleteProperty', { propertyId: selected.id })
    selected = null
    deleteArmed = false
  }

  $effect(() => {
    if (!details) return
    editPrice = details.price
    editSize = details.size
    editRental = details.rentInterval !== null && details.rentInterval !== undefined
    editRentInterval = details.rentInterval ?? 24
    editDescription = details.description ?? ''
  })

  $effect(() => {
    if (!selected) return
    const fresh = realtor.properties.find((p) => p.id === selected.id)
    if (fresh !== selected) selected = fresh ?? null
  })

  $effect(() => {
    if (selected && !selected.owner) {
      price = selected.price || market.config.minPrice
      minIncrement = market.config.minIncrement
      auctionHours = market.config.auctionHours
    }
  })

  function saveEdits() {
    fetchNui('realtor:updateProperty', {
      propertyId: selected.id,
      price: editPrice,
      size: editSize,
      rentInterval: editRental ? editRentInterval : null,
      description: editDescription.trim() || null,
    })
  }

  function paidLabel(utilities) {
    if (!utilities.paidUntil) return 'Nothing due yet'
    const date = new Date(utilities.paidUntil * 1000).toLocaleDateString()
    return utilities.overdue ? `Overdue since ${date}` : `Paid until ${date}`
  }

  function ownerName(property) {
    if (!property.owner) return null
    if (!property.owner_charinfo) return property.owner
    try {
      const info = JSON.parse(property.owner_charinfo)
      return `${info.firstname} ${info.lastname}`
    } catch {
      return property.owner
    }
  }

  function kindLabel(property) {
    return property.building ? 'Apartment' : property.shell ? 'Shell' : 'MLO'
  }

  const valid = $derived(
    selected !== null &&
      !selected.owner &&
      price >= market.config.minPrice &&
      price <= market.config.maxPrice &&
      (listingType === 'sale' ||
        listingType === 'offer' ||
        (auctionHours >= 1 &&
          auctionHours <= market.config.maxAuctionHours &&
          minIncrement >= 1 &&
          (reservePrice === 0 || reservePrice >= price)))
  )

  function createListing() {
    if (!valid) return
    fetchNui('realtor:createListing', {
      propertyId: selected.id,
      listingType,
      price,
      auctionHours: listingType === 'auction' ? auctionHours : null,
      reservePrice: listingType === 'auction' && reservePrice > 0 ? reservePrice : null,
      minIncrement: listingType === 'auction' ? minIncrement : null,
    })
    selected = null
  }

  const worldEdits = $derived(
    !details || selected?.building
      ? []
      : [
          { label: details.hasGarage ? 'Re-place garage' : 'Add garage', run: () => fetchNui('realtor:editGarage', { propertyId: selected.id }) },
          { label: details.hasGarden ? 'Redraw garden' : 'Add garden', run: () => fetchNui('realtor:editGarden', { propertyId: selected.id }) },
          ...(details.interior === 'mlo'
            ? [
                { label: 'Re-set interior point', run: () => fetchNui('realtor:recaptureInterior', { propertyId: selected.id }) },
                { label: 'Add door', run: () => fetchNui('realtor:addDoor', { propertyId: selected.id, double: false }) },
                { label: 'Add double door', run: () => fetchNui('realtor:addDoor', { propertyId: selected.id, double: true }) },
              ]
            : []),
          { label: 'Set mailbox', run: () => fetchNui('realtor:setMailbox', { propertyId: selected.id }) },
          ...(selected.owner ? [] : [{ label: 'Enter property', run: () => fetchNui('realtor:enterProperty', { propertyId: selected.id }) }]),
        ]
  )

  const statusRows = $derived(
    !details
      ? []
      : [
          ['Created by', details.createdBy ?? 'Unknown'],
          ['Interior', details.interior],
          ['Garden', details.hasGarden ? 'Yes' : 'No'],
          ['Garage', details.hasGarage ? 'Yes' : 'No'],
          ...(selected?.building
            ? []
            : [
                ['Utilities', paidLabel(details.utilities)],
                ['Power', `${details.utilities.power} / ${details.utilities.limit} W${details.utilities.powered ? '' : ' · CUT OFF'}`],
                ['Monthly cost', formatMoney(details.utilities.cost)],
              ]),
        ]
  )
</script>

<div class="manage">
  <div class="toolbar">
    <input class="input grow" placeholder="Search properties or owners..." bind:value={search} />
    <div class="chips">
      {#each [['all', 'All'], ['free', 'Available'], ['owned', 'Owned']] as [value, label] (value)}
        <button class="chip" class:active={filter === value} onclick={() => (filter = value)}>{label}</button>
      {/each}
    </div>
  </div>

  <div class="scroll body">
    <div class="grid">
      {#each visible as property (property.id)}
        <button class="card" class:selected={selected?.id === property.id} onclick={() => select(property)}>
          <span class="thumb">
            {#if property.thumb}<img src={property.thumb} alt="" loading="lazy" />{/if}
          </span>
          <span class="card-info">
            <span class="card-name">{property.property_name}</span>
            <span class="card-meta">
              {kindLabel(property)}{#if property.rent_interval} · Rental {property.rent_interval}h{/if}{#if property.listed} · Listed{/if}
            </span>
            <span class="card-owner">{property.owner ? ownerName(property) : `Available · ${formatMoney(property.price)}`}</span>
          </span>
        </button>
      {:else}
        <div class="empty span-all">No properties match</div>
      {/each}
    </div>

    {#if selected}
      <div class="detail">
        <div class="detail-head">
          <span class="detail-name">{selected.property_name}</span>
          <div class="detail-badges">
            {#if selected.listed}<span class="badge yellow">Listed</span>{/if}
            {#if selected.owner}<span class="badge red">Owned</span>{:else}<span class="badge green">Free</span>{/if}
            <span class="badge">ID {selected.id}</span>
          </div>
        </div>

        {#if !details}
          <div class="empty">Loading details...</div>
        {:else}
          <div class="detail-grid">
            <div class="pane">
              {#if !selected.building}
                <span class="pane-title">Edit</span>
                <div class="edit-inputs">
                  <div class="field">
                    <span class="mini-label">Price</span>
                    <input class="input mono" type="number" bind:value={editPrice} min={market.config.minPrice} />
                  </div>
                  <div class="field">
                    <span class="mini-label">Rent (hours)</span>
                    <div class="rent-row">
                      <label class="check">
                        <input type="checkbox" bind:checked={editRental} />
                      </label>
                      <input class="input mono" type="number" bind:value={editRentInterval} min="1" max="24" disabled={!editRental} />
                    </div>
                  </div>
                </div>
                <div class="chips wrap">
                  {#each market.sizeOrder as key (key)}
                    <button class="chip" class:active={editSize === key} onclick={() => (editSize = key)}>
                      {market.sizes[key]?.label ?? key}
                    </button>
                  {/each}
                </div>
                <textarea class="input summary" rows="3" maxlength="500" bind:value={editDescription}
                  placeholder="A short pitch shown on the market page"></textarea>
                <div class="chips wrap world">
                  {#each worldEdits as edit (edit.label)}
                    <button class="chip world-chip" onclick={edit.run}>{edit.label}</button>
                  {/each}
                </div>
                <button class="btn wide" onclick={saveEdits}>Save changes</button>
                {#if deleteArmed}
                  <button class="btn danger wide" onclick={deleteProperty}>Confirm — permanently delete</button>
                  <span class="hint">Removes the property, its furniture, stashes, photos and doors for good. Garaged vehicles go to the impound.</span>
                {:else}
                  <button class="delete-btn" disabled={selected.listed} onclick={() => (deleteArmed = true)}>Delete property</button>
                  {#if selected.listed}<span class="hint">Cancel the active listing before deleting.</span>{/if}
                {/if}
              {:else}
                <span class="pane-title">Unit</span>
                <span class="hint">Apartment units are managed from the Buildings tab. World edits and photos are handled by the building.</span>
              {/if}
            </div>

            <div class="pane">
              <span class="pane-title">Photos</span>
              {#if !selected.building}
                <div class="photos">
                  {#each details.images as image, i (image)}
                    <span class="photo">
                      <img src={image} alt="Property" onclick={() => (lightboxIndex = i)} />
                      <button class="photo-remove" onclick={() => fetchNui('realtor:removeImage', { propertyId: selected.id, index: i + 1 })}>×</button>
                    </span>
                  {/each}
                  <button class="photo-add" onclick={() => fetchNui('realtor:addImage', { propertyId: selected.id })}>+ Add</button>
                </div>
                <span class="hint">Adding a photo closes this window and captures your current view.</span>
              {/if}
              <div class="status">
                {#each statusRows as [k, v] (k)}
                  <div class="status-row">
                    <span class="status-k">{k}</span>
                    <span class="status-v">{v}</span>
                  </div>
                {/each}
                {#if details.keyholders?.length}
                  {#each details.keyholders as holder (holder.citizenid)}
                    <div class="status-row"><span class="status-k">{holder.name}</span><span class="status-v">Keyholder</span></div>
                  {/each}
                {/if}
                {#if details.access?.length}
                  {#each details.access as entry (entry.citizenid)}
                    <div class="status-row">
                      <span class="status-k">{entry.name}</span>
                      <span class="status-v">{['door', 'stash', 'furniture', 'garage'].filter((k) => entry[k]).join(', ') || 'none'}</span>
                    </div>
                  {/each}
                {/if}
              </div>
            </div>
          </div>

          {#if selected.owner}
            <div class="owner-bar">
              <span class="owner-info">
                <span class="owner-name">{ownerName(selected)}</span>
                <span class="owner-cid">{selected.owner}</span>
              </span>
              <span class="hint grow">An owned property cannot be listed. End the tenancy to return it to the pool.</span>
              {#if selected.building}
                <button class="delete-btn slim" onclick={() => { fetchNui('realtor:releaseUnit', { propertyId: selected.id, building: selected.building }); selected = null }}>
                  End tenancy
                </button>
              {:else}
                <button class="delete-btn slim" onclick={() => { fetchNui('realtor:repossess', { propertyId: selected.id }); selected = null }}>
                  Repossess
                </button>
              {/if}
            </div>
          {:else if selected.listed}
            <span class="hint">This property already has an active listing. Cancel it from the Market tab first.</span>
          {:else}
            <div class="listing">
              <span class="pane-title">Create listing</span>
              <div class="listing-row">
                <div class="chips">
                  {#each [['sale', 'Direct sale'], ['auction', 'Auction'], ['offer', 'Open to offers']] as [value, label] (value)}
                    <button class="chip" class:active={listingType === value} onclick={() => (listingType = value)}>{label}</button>
                  {/each}
                </div>
                <div class="field grow">
                  <span class="mini-label">{listingType === 'auction' ? 'Starting price' : 'Price'}</span>
                  <input class="input mono" type="number" bind:value={price} min={market.config.minPrice} />
                </div>
                {#if listingType === 'auction'}
                  <div class="field">
                    <span class="mini-label">Duration</span>
                    <div class="chips">
                      {#each [24, 48, 72].filter((h) => h <= market.config.maxAuctionHours) as hours (hours)}
                        <button class="chip" class:active={auctionHours === hours} onclick={() => (auctionHours = hours)}>{hours}h</button>
                      {/each}
                    </div>
                  </div>
                  <div class="field">
                    <span class="mini-label">Reserve (0 = none)</span>
                    <input class="input mono" type="number" bind:value={reservePrice} min="0" />
                  </div>
                  <div class="field">
                    <span class="mini-label">Min increment</span>
                    <input class="input mono" type="number" bind:value={minIncrement} min="1" />
                  </div>
                {/if}
                <button class="btn" disabled={!valid} onclick={createListing}>Create listing</button>
              </div>
            </div>
          {/if}
        {/if}
      </div>
    {/if}
  </div>
</div>

<Lightbox images={details?.images ?? []} bind:index={lightboxIndex} />

<style>
  .manage {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
  }

  .toolbar {
    display: flex;
    align-items: center;
    gap: 10px;
    padding-bottom: 14px;
    border-bottom: 1px solid var(--dark-6);
    flex: none;
  }

  .grow {
    flex: 1;
    min-width: 0;
  }

  .chips {
    display: flex;
    gap: 5px;
  }

  .chips.wrap {
    flex-wrap: wrap;
  }

  .chip {
    padding: 8px 12px;
    font-family: inherit;
    font-size: 12px;
    color: var(--dark-1);
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

  .world-chip {
    flex: 1;
    min-width: 112px;
    color: var(--dark-1);
  }

  .world-chip:hover {
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

  .grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 12px;
    flex: none;
  }

  .span-all {
    grid-column: 1 / -1;
  }

  .card {
    position: relative;
    display: flex;
    gap: 11px;
    padding: 11px;
    font-family: inherit;
    text-align: left;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: 8px;
    cursor: pointer;
  }

  .card:hover {
    border-color: var(--dark-3);
  }

  .card.selected {
    border-color: var(--blue);
    background: var(--accent-8);
  }

  .thumb {
    flex: none;
    width: 56px;
    height: 56px;
    border-radius: var(--radius-sm);
    overflow: hidden;
    background: repeating-linear-gradient(135deg, var(--dark-4) 0 7px, var(--dark-5) 7px 14px);
  }

  .thumb img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .card-info {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }

  .card-name {
    font-size: 13px;
    font-weight: 500;
    color: #fff;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .card-meta {
    font-size: 11px;
    color: var(--dark-2);
  }

  .card-owner {
    font-size: 11px;
    color: var(--dark-3);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .detail {
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding: 16px;
    background: #1f2023;
    border: 1px solid var(--dark-4);
    border-radius: 8px;
    flex: none;
  }

  .detail-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .detail-name {
    font-size: 15px;
    font-weight: 700;
    color: #fff;
  }

  .detail-badges {
    display: flex;
    gap: 6px;
  }

  .detail-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 18px;
  }

  .pane {
    display: flex;
    flex-direction: column;
    gap: 11px;
    min-width: 0;
  }

  .pane-title {
    font-size: 12px;
    font-weight: 700;
    color: var(--dark-0);
  }

  .edit-inputs {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
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
  }

  .rent-row {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .summary {
    resize: vertical;
    min-height: 56px;
    line-height: 1.5;
    font-family: inherit;
  }

  .wide {
    width: 100%;
  }

  .delete-btn {
    width: 100%;
    padding: 9px;
    font-family: inherit;
    font-size: 12px;
    color: var(--red);
    background: transparent;
    border: 1px solid rgba(250, 82, 82, 0.35);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .delete-btn:hover:not(:disabled) {
    background: var(--red);
    color: #fff;
  }

  .delete-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .delete-btn.slim {
    width: auto;
    flex: none;
    padding: 9px 14px;
  }

  .photos {
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    gap: 6px;
  }

  .photo {
    position: relative;
    height: 52px;
    border-radius: var(--radius-sm);
    overflow: hidden;
    border: 1px solid var(--dark-4);
  }

  .photo img {
    display: block;
    width: 100%;
    height: 100%;
    object-fit: cover;
    cursor: zoom-in;
  }

  .photo-remove {
    position: absolute;
    top: 2px;
    right: 2px;
    width: 18px;
    height: 18px;
    padding: 0;
    font-size: 12px;
    line-height: 1;
    color: #fff;
    background: rgba(0, 0, 0, 0.6);
    border: none;
    border-radius: 50%;
    cursor: pointer;
  }

  .photo-remove:hover {
    background: var(--red);
  }

  .photo-add {
    height: 52px;
    font-family: inherit;
    font-size: 11px;
    color: var(--dark-3);
    background: transparent;
    border: 1px dashed var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .photo-add:hover {
    color: #fff;
    border-color: var(--dark-3);
  }

  .status {
    display: flex;
    flex-direction: column;
  }

  .status-row {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 12px;
    padding: 6px 0;
    border-bottom: 1px solid var(--dark-6);
    font-size: 12px;
  }

  .status-k {
    color: var(--dark-2);
  }

  .status-v {
    font-weight: 500;
    color: #fff;
    text-align: right;
  }

  .owner-bar {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 12px 14px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .owner-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
    flex: none;
  }

  .owner-name {
    font-size: 13px;
    font-weight: 500;
    color: #fff;
  }

  .owner-cid {
    font-family: 'Roboto Mono', monospace;
    font-size: 11px;
    color: var(--dark-3);
  }

  .listing {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding-top: 12px;
    border-top: 1px solid var(--dark-4);
  }

  .listing-row {
    display: flex;
    align-items: flex-end;
    gap: 10px;
    flex-wrap: wrap;
  }
</style>
