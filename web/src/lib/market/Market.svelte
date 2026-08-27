<script>
  import { fetchNui, formatMoney, formatRemaining } from '../nui.js'
  import { app, market } from '../store.svelte.js'
  import ListingDetail from './ListingDetail.svelte'

  let filter = $state('all')
  let search = $state('')
  let sort = $state('ending')
  let now = $state(Math.floor(Date.now() / 1000))

  const readStore = (key) => {
    try { return JSON.parse(localStorage.getItem(key) ?? '[]') } catch { return [] }
  }
  let saved = $state(readStore('qbx_properties_saved'))
  let recent = $state(readStore('qbx_properties_recent'))

  function toggleSave(id) {
    saved = saved.includes(id) ? saved.filter((s) => s !== id) : [...saved, id]
    localStorage.setItem('qbx_properties_saved', JSON.stringify(saved))
  }

  $effect(() => {
    const timer = setInterval(() => (now = Math.floor(Date.now() / 1000)), 1000)
    return () => clearInterval(timer)
  })

  const typeLabel = (listing) =>
    listing.listing_type === 'auction' ? 'Auction' : listing.listing_type === 'offer' ? 'Offers' : 'For sale'

  const metaLine = (listing) => {
    const bits = []
    if (listing.type) bits.push(listing.type.charAt(0).toUpperCase() + listing.type.slice(1))
    if (listing.size) bits.push(listing.size.charAt(0).toUpperCase() + listing.size.slice(1))
    bits.push(listing.rent_interval ? `Rental · ${listing.rent_interval}h` : 'Purchase')
    return bits.join(' · ')
  }

  const visible = $derived(
    market.listings
      .filter((listing) => {
        if (filter === 'saved') { if (!saved.includes(listing.id)) return false }
        else if (filter !== 'all' && listing.listing_type !== filter) return false
        if (search.trim() && !listing.property_name.toLowerCase().includes(search.trim().toLowerCase())) return false
        return true
      })
      .sort((a, b) => {
        if (sort === 'priceAsc') return (a.top_bid ?? a.price) - (b.top_bid ?? b.price)
        if (sort === 'priceDesc') return (b.top_bid ?? b.price) - (a.top_bid ?? a.price)
        if (sort === 'newest') return b.id - a.id
        return (a.auction_end ?? Infinity) - (b.auction_end ?? Infinity)
      })
  )

  const recentListings = $derived(
    recent.map((id) => market.listings.find((l) => l.id === id)).filter(Boolean).slice(0, 4)
  )

  function select(listing) {
    market.selected = listing
    market.bids = []
    recent = [listing.id, ...recent.filter((id) => id !== listing.id)].slice(0, 8)
    localStorage.setItem('qbx_properties_recent', JSON.stringify(recent))
    if (app.isRealtor) fetchNui('market:getBids', { listingId: listing.id })
  }
</script>

{#if market.selected}
  <ListingDetail listing={market.selected} {now} {toggleSave} savedIds={saved} />
{:else}
  <div class="content">
    <div class="toolbar">
      <input class="input grow" placeholder="Search listings, streets, agents..." bind:value={search} />
      <div class="chips">
        {#each [['all', 'All'], ['sale', 'For sale'], ['auction', 'Auctions'], ['offer', 'Offers'], ['saved', 'Saved']] as [value, label]}
          <button class="chip" class:active={filter === value} onclick={() => (filter = value)}>{label}</button>
        {/each}
      </div>
      <select class="select" bind:value={sort}>
        <option value="ending">Ending soonest</option>
        <option value="priceAsc">Price: low to high</option>
        <option value="priceDesc">Price: high to low</option>
        <option value="newest">Newest first</option>
      </select>
    </div>

    <div class="scroll body">
      {#if filter === 'saved' && visible.length === 0}
        <div class="empty tall">Nothing saved yet. Open a listing and hit Save to keep an eye on it.</div>
      {:else if visible.length === 0}
        <div class="empty tall">No listings match your filters</div>
      {:else}
        <div class="grid">
          {#each visible as listing (listing.id)}
            <button class="card" onclick={() => select(listing)}>
              <div class="photo" style={listing.images?.length ? `background-image: url("${listing.images[0]}"); background-size: cover; background-position: center` : ''}>
                {#if !listing.images?.length}
                  <span class="photo-label">NO PHOTOS YET</span>
                {/if}
                <span class="badge-floating type {listing.listing_type}">{typeLabel(listing)}</span>
                {#if saved.includes(listing.id)}
                  <span class="badge-floating saved">Saved</span>
                {/if}
                {#if listing.listing_type === 'auction' && listing.auction_end}
                  <span class="badge-floating ends" class:urgent={listing.auction_end - now < 300}>
                    {formatRemaining(listing.auction_end)} left
                  </span>
                {/if}
              </div>
              <div class="card-body">
                <div class="card-name">
                  <span class="name">{listing.property_name}</span>
                  <span class="meta">{metaLine(listing)}</span>
                </div>
                <div class="card-price">
                  <span class="price">{formatMoney(listing.top_bid ?? listing.price)}</span>
                  <span class="price-note">
                    {listing.listing_type === 'auction' ? (listing.top_bid ? 'current bid' : 'starting bid') : listing.listing_type === 'offer' ? 'asking' : listing.rent_interval ? `per ${listing.rent_interval}h` : 'buy now'}
                  </span>
                </div>
              </div>
            </button>
          {/each}
        </div>
      {/if}

      {#if recentListings.length && filter !== 'saved'}
        <div class="recent">
          <div class="recent-title">Recently viewed</div>
          <div class="recent-row">
            {#each recentListings as listing (listing.id)}
              <button class="recent-card" onclick={() => select(listing)}>
                <span class="recent-thumb">
                  {#if listing.images?.length}<img src={listing.images[0]} alt="" loading="lazy" />{/if}
                </span>
                <span class="recent-info">
                  <span class="recent-name">{listing.property_name}</span>
                  <span class="recent-price">{formatMoney(listing.top_bid ?? listing.price)}</span>
                </span>
              </button>
            {/each}
          </div>
        </div>
      {/if}
    </div>
  </div>
{/if}

<style>
  .content {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
  }

  .toolbar {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 14px 18px;
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
    flex: none;
  }

  .chip {
    padding: 8px 12px;
    font-family: inherit;
    font-size: 12px;
    white-space: nowrap;
    color: var(--dark-1);
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .chip:hover {
    background: var(--dark-5);
    color: #fff;
  }

  .chip.active {
    color: #fff;
    background: var(--accent-15);
    border-color: var(--blue);
  }

  .select {
    width: auto;
    flex: none;
    padding: 9px 10px;
    font-family: inherit;
    font-size: 12px;
    color: var(--dark-0);
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    outline: none;
  }

  .body {
    flex: 1;
    min-height: 0;
    padding: 18px;
  }

  .grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 14px;
  }

  .card {
    position: relative;
    display: flex;
    flex-direction: column;
    padding: 0;
    font-family: inherit;
    text-align: left;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: 8px;
    overflow: hidden;
    cursor: pointer;
    transition: border-color 0.12s ease;
  }

  .card:hover {
    border-color: var(--dark-3);
  }

  .photo {
    position: relative;
    width: 100%;
    height: 136px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: repeating-linear-gradient(135deg, var(--dark-5) 0 9px, var(--dark-6) 9px 18px);
  }

  .photo-label {
    font-family: 'Roboto Mono', monospace;
    font-size: 10px;
    letter-spacing: 0.12em;
    color: var(--dark-3);
  }

  .badge-floating {
    position: absolute;
    padding: 3px 8px;
    font-size: 11px;
    font-weight: 500;
    border-radius: var(--radius-sm);
    backdrop-filter: blur(4px);
  }

  .badge-floating.type {
    top: 9px;
    left: 9px;
  }

  .badge-floating.type.sale {
    background: rgba(64, 192, 87, 0.15);
    color: var(--green, #40c057);
  }

  .badge-floating.type.auction {
    background: rgba(250, 176, 5, 0.15);
    color: var(--yellow, #fab005);
  }

  .badge-floating.type.offer {
    background: var(--accent-15);
    color: var(--blue-light, #339af0);
  }

  .badge-floating.saved {
    top: 9px;
    right: 9px;
    background: rgba(10, 11, 12, 0.72);
    color: var(--blue-light, #339af0);
  }

  .badge-floating.ends {
    bottom: 9px;
    left: 9px;
    font-family: 'Roboto Mono', monospace;
    background: rgba(10, 11, 12, 0.72);
    color: var(--dark-0);
  }

  .badge-floating.ends.urgent {
    background: rgba(250, 82, 82, 0.9);
    color: #fff;
  }

  .card-body {
    display: flex;
    flex-direction: column;
    gap: 9px;
    width: 100%;
    padding: 12px 13px 14px;
  }

  .card-name {
    display: flex;
    flex-direction: column;
    gap: 3px;
    width: 100%;
    text-align: left;
  }

  .name {
    font-size: 13px;
    font-weight: 500;
    color: #fff;
  }

  .meta {
    font-size: 11px;
    color: var(--dark-2);
  }

  .card-price {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 8px;
    width: 100%;
    padding-top: 9px;
    border-top: 1px solid var(--dark-4);
  }

  .price {
    font-size: 17px;
    font-weight: 700;
    color: #fff;
  }

  .price-note {
    font-size: 11px;
    color: var(--dark-3);
  }

  .recent {
    display: flex;
    flex-direction: column;
    gap: 9px;
    margin-top: 22px;
    padding-top: 16px;
    border-top: 1px solid var(--dark-6);
  }

  .recent-title {
    font-size: 12px;
    font-weight: 500;
    color: var(--dark-2);
  }

  .recent-row {
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
  }

  .recent-card {
    display: flex;
    align-items: center;
    gap: 9px;
    padding: 7px 11px 7px 7px;
    font-family: inherit;
    text-align: left;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .recent-card:hover {
    border-color: var(--dark-3);
  }

  .recent-thumb {
    flex: none;
    width: 44px;
    height: 32px;
    border-radius: 3px;
    overflow: hidden;
    background: repeating-linear-gradient(135deg, var(--dark-4) 0 6px, var(--dark-5) 6px 12px);
  }

  .recent-thumb img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .recent-info {
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .recent-name {
    font-size: 12px;
    color: var(--dark-0);
  }

  .recent-price {
    font-size: 11px;
    color: var(--dark-3);
  }

  .empty.tall {
    padding: 56px 16px;
    text-align: center;
  }
</style>
