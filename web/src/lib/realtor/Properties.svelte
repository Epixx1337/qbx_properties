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

  const details = $derived(realtor.details && selected && realtor.details.id === selected.id ? realtor.details : null)

  function select(property) {
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
  let listingType = $state('sale')
  let price = $state(50000)
  let auctionHours = $state(72)
  let reservePrice = $state(0)
  let minIncrement = $state(1000)
  let search = $state('')
  let filter = $state('all')

  const visible = $derived(
    realtor.properties.filter((property) => {
      if (filter === 'owned' && !property.owner) return false
      if (filter === 'free' && property.owner) return false
      if (search.trim() && !property.property_name.toLowerCase().includes(search.trim().toLowerCase())) return false
      return true
    })
  )

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

  const valid = $derived(
    selected !== null &&
      !selected.owner &&
      price >= market.config.minPrice &&
      price <= market.config.maxPrice &&
      (listingType === 'sale' ||
        (auctionHours >= 1 &&
          auctionHours <= market.config.maxAuctionHours &&
          minIncrement >= 1 &&
          (reservePrice === 0 || reservePrice >= price)))
  )

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
</script>

<div class="layout">
  <div class="col">
    <div class="toolbar">
      <input class="input" placeholder="Search properties..." bind:value={search} />
      <div class="chips">
        {#each [['all', 'All'], ['free', 'Available'], ['owned', 'Owned']] as [value, label]}
          <button class="chip" class:active={filter === value} onclick={() => (filter = value)}>{label}</button>
        {/each}
      </div>
    </div>

    <div class="list scroll">
      {#each visible as property (property.id)}
        <button class="row" class:active={selected?.id === property.id} onclick={() => select(property)}>
          <div class="row-main">
            <span class="row-name">{property.property_name}</span>
            <span class="row-sub">
              {#if property.owner}{ownerName(property)}{:else}Available{/if}
              {#if property.building} · Apartment{:else if property.shell} · Shell{:else} · MLO{/if}
            </span>
          </div>
          {#if property.listed}
            <span class="badge yellow">Listed</span>
          {:else if property.owner}
            <span class="badge red">Owned</span>
          {:else}
            <span class="badge green">Free</span>
          {/if}
        </button>
      {:else}
        <div class="empty">No properties match</div>
      {/each}
    </div>
  </div>

  <div class="col detail scroll">
    {#if !selected}
      <div class="empty">Select a property</div>
    {:else}
      <div class="detail-head">
        <span class="section-title">{selected.property_name}</span>
        {#if selected.listed}<span class="badge yellow">Listed</span>{/if}
      </div>

      <div class="facts">
        <div class="fact"><span>Property ID</span><b>{selected.id}</b></div>
        <div class="fact">
          <span>Type</span>
          <b>{selected.building ? 'Apartment' : selected.shell ? 'Shell' : 'MLO'}</b>
        </div>
        {#if selected.rent_interval}
          <div class="fact"><span>Rent</span><b>{formatMoney(selected.price)} / {selected.rent_interval}h</b></div>
        {/if}
        {#if details}
          <div class="fact"><span>Created by</span><b>{details.createdBy ?? 'Unknown'}</b></div>
          <div class="fact"><span>Interior</span><b>{details.interior}</b></div>
          <div class="fact"><span>Garden</span><b>{details.hasGarden ? 'Yes' : 'No'}</b></div>
          <div class="fact"><span>Garage</span><b>{details.hasGarage ? 'Yes' : 'No'}</b></div>
        {/if}
      </div>

      {#if details && !selected.building}
        <div class="section-title">Utilities</div>
        <div class="facts">
          <div class="fact"><span>Status</span><b class:danger={details.utilities.overdue}>{paidLabel(details.utilities)}</b></div>
          <div class="fact"><span>Power</span><b>{details.utilities.power} / {details.utilities.limit} W {details.utilities.powered ? '' : '· CUT OFF'}</b></div>
          <div class="fact"><span>Monthly cost</span><b>{formatMoney(details.utilities.cost)}</b></div>
        </div>

        {#if details.keyholders.length || details.access.length}
          <div class="section-title">Access</div>
          <div class="facts">
            {#each details.keyholders as holder (holder.citizenid)}
              <div class="fact"><span>{holder.name}</span><b>Keyholder</b></div>
            {/each}
            {#each details.access as entry (entry.citizenid)}
              <div class="fact">
                <span>{entry.name}</span>
                <b>{['door', 'stash', 'furniture', 'garage'].filter((k) => entry[k]).join(', ') || 'none'}</b>
              </div>
            {/each}
          </div>
        {/if}

        <div class="section-title">Edit property</div>
        <div class="field">
          <span class="label">Price</span>
          <input class="input" type="number" bind:value={editPrice} min={market.config.minPrice} />
        </div>
        <div class="field">
          <span class="label">Size</span>
          <div class="chips">
            {#each market.sizeOrder as key}
              <button class="chip" class:active={editSize === key} onclick={() => (editSize = key)}>
                {market.sizes[key]?.label ?? key}
              </button>
            {/each}
          </div>
        </div>
        <label class="check">
          <input type="checkbox" bind:checked={editRental} />
          <span>Rental property</span>
        </label>
        <div class="field">
          <span class="label">Listing summary</span>
          <textarea class="input summary-input" bind:value={editDescription} maxlength="500" rows="3"
            placeholder="A short pitch shown on the market page"></textarea>
        </div>
        {#if editRental}
          <div class="field">
            <span class="label">Rent interval (hours)</span>
            <input class="input" type="number" bind:value={editRentInterval} min="1" max="24" />
          </div>
        {/if}
        <button class="btn wide" onclick={saveEdits}>Save changes</button>

        <div class="chips">
          <button class="chip" onclick={() => fetchNui('realtor:editGarage', { propertyId: selected.id })}>
            {details.hasGarage ? 'Re-place garage' : 'Add garage'}
          </button>
          <button class="chip" onclick={() => fetchNui('realtor:editGarden', { propertyId: selected.id })}>
            {details.hasGarden ? 'Redraw garden' : 'Add garden'}
          </button>
        </div>

        {#if details.interior === 'mlo'}
          <div class="chips">
            <button class="chip" onclick={() => fetchNui('realtor:recaptureInterior', { propertyId: selected.id })}>
              Re-set interior point
            </button>
            <button class="chip" onclick={() => fetchNui('realtor:addDoor', { propertyId: selected.id, double: false })}>
              Add door
            </button>
            <button class="chip" onclick={() => fetchNui('realtor:addDoor', { propertyId: selected.id, double: true })}>
              Add double door
            </button>
          </div>
        {/if}
        <div class="section-title">Photos</div>
        {#if details.images.length}
          <div class="photos">
            {#each details.images as image, i (image)}
              <div class="photo">
                <img src={image} alt="Property" onclick={() => (lightboxIndex = i)} />
                <button class="photo-remove" onclick={() => fetchNui('realtor:removeImage', { propertyId: selected.id, index: i + 1 })}>×</button>
              </div>
            {/each}
          </div>
        {/if}
        <button class="btn subtle wide" onclick={() => fetchNui('realtor:addImage', { propertyId: selected.id })}>
          Take photo
        </button>
        <div class="hint">Closes this window and captures your current view.</div>

        <button class="btn subtle wide" onclick={() => fetchNui('realtor:enterProperty', { propertyId: selected.id })}>
          Enter property
        </button>
        <div class="hint">Once inside, open the radial menu to edit the interaction points.</div>
      {/if}

      {#if selected.owner}
        <div class="owned-block">
          <div class="section-title">Current owner</div>
          <div class="fact"><span>Name</span><b>{ownerName(selected)}</b></div>
          <div class="fact"><span>Citizen ID</span><b>{selected.owner}</b></div>
          <div class="hint">An owned property cannot be listed. End the tenancy first to return it to the pool.</div>

          {#if selected.building}
            <button
              class="btn danger wide"
              onclick={() => {
                fetchNui('realtor:releaseUnit', { propertyId: selected.id, building: selected.building })
                selected = null
              }}
            >
              End tenancy
            </button>
          {:else}
            <button
              class="btn danger wide"
              onclick={() => {
                fetchNui('realtor:repossess', { propertyId: selected.id })
                selected = null
              }}
            >
              Repossess property
            </button>
          {/if}
        </div>
      {:else if selected.listed}
        <div class="hint">This property already has an active listing. Cancel it from the Market tab first.</div>
      {:else}
        <div class="section-title">Create listing</div>

        <div class="field">
          <span class="label">Listing type</span>
          <div class="chips">
            {#each [['sale', 'Direct sale'], ['auction', 'Auction']] as [value, label]}
              <button class="chip" class:active={listingType === value} onclick={() => (listingType = value)}>
                {label}
              </button>
            {/each}
          </div>
        </div>

        <div class="field">
          <span class="label">{listingType === 'auction' ? 'Starting price' : 'Price'}</span>
          <input class="input" type="number" bind:value={price} min={market.config.minPrice} />
          <span class="hint">{formatMoney(price)}</span>
        </div>

        {#if listingType === 'auction'}
          <div class="field">
            <span class="label">Duration</span>
            <div class="chips">
              {#each [24, 48, 72].filter((h) => h <= market.config.maxAuctionHours) as hours}
                <button class="chip" class:active={auctionHours === hours} onclick={() => (auctionHours = hours)}>
                  {hours}h
                </button>
              {/each}
            </div>
          </div>

          <div class="field">
            <span class="label">Reserve price</span>
            <input class="input" type="number" bind:value={reservePrice} min="0" />
            <span class="hint">0 for no reserve. Must be at least the starting price.</span>
          </div>

          <div class="field">
            <span class="label">Minimum increment</span>
            <input class="input" type="number" bind:value={minIncrement} min="1" />
          </div>
        {/if}

        <button class="btn wide push" disabled={!valid} onclick={createListing}>Create listing</button>
      {/if}

      {#if !selected.building}
        <div class="section-title">Danger zone</div>
        {#if deleteArmed}
          <button class="btn danger wide" onclick={deleteProperty}>Confirm — permanently delete</button>
          <div class="hint">Removes the property, its furniture, stashes, photos and doors for good. Garaged vehicles go to the impound.</div>
        {:else}
          <button class="btn danger wide" disabled={selected.listed} onclick={() => (deleteArmed = true)}>Delete property</button>
          {#if selected.listed}
            <div class="hint">Cancel the active listing before deleting.</div>
          {/if}
        {/if}
      {/if}
    {/if}
  </div>
</div>

<Lightbox images={details?.images ?? []} bind:index={lightboxIndex} />

<style>
  .fact b.danger {
    color: var(--red);
  }

  .summary-input {
    resize: vertical;
    min-height: 60px;
    font-family: inherit;
  }

  .photos {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 6px;
  }

  .photo {
    position: relative;
    border-radius: var(--radius-sm);
    overflow: hidden;
    border: 1px solid var(--dark-4);
  }

  .photo img {
    display: block;
    width: 100%;
    height: 56px;
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

  .layout {
    display: grid;
    grid-template-columns: minmax(0, 0.85fr) minmax(0, 1fr);
    gap: 20px;
    height: 100%;
    min-height: 0;
  }

  .col {
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-height: 0;
  }

  .detail {
    padding-left: 20px;
    padding-right: 12px;
    border-left: 1px solid var(--dark-4);
  }

  .toolbar {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .chips {
    display: flex;
    gap: 6px;
  }

  .chip {
    flex: 1;
    padding: 6px 10px;
    font-family: inherit;
    font-size: 12px;
    color: var(--dark-1);
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .chip:hover {
    background: var(--dark-5);
  }

  .chip.active {
    color: #fff;
    border-color: var(--blue);
    background: var(--accent-15);
  }

  .list {
    display: flex;
    flex-direction: column;
    gap: 5px;
    min-height: 0;
  }

  .row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    padding: 9px 12px;
    font-family: inherit;
    text-align: left;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .row:hover {
    border-color: var(--dark-3);
  }

  .row.active {
    border-color: var(--blue);
    background: var(--accent-8);
  }

  .row-main {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .row-name {
    font-size: 13px;
    font-weight: 500;
    color: var(--dark-0);
  }

  .row-sub {
    font-size: 11px;
    color: var(--dark-2);
  }

  .detail-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .section-title {
    font-size: 13px;
    font-weight: 700;
  }

  .facts,
  .owned-block {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .owned-block {
    gap: 8px;
    padding-top: 12px;
    border-top: 1px solid var(--dark-4);
  }

  .fact {
    display: flex;
    justify-content: space-between;
    gap: 10px;
    font-size: 12px;
    color: var(--dark-2);
  }

  .fact b {
    color: #fff;
  }

  .wide {
    width: 100%;
  }

  .push {
    margin-top: auto;
  }
</style>
