<script>
  import { fetchNui, formatMoney, formatRemaining } from '../nui.js'
  import { app, market } from '../store.svelte.js'
  import ListingDetail from './ListingDetail.svelte'

  let filter = $state('all')
  let search = $state('')
  let now = $state(Math.floor(Date.now() / 1000))

  $effect(() => {
    const timer = setInterval(() => (now = Math.floor(Date.now() / 1000)), 1000)
    return () => clearInterval(timer)
  })

  const visible = $derived(
    market.listings.filter((listing) => {
      if (filter !== 'all' && listing.listing_type !== filter) return false
      if (search.trim() && !listing.property_name.toLowerCase().includes(search.trim().toLowerCase())) return false
      return true
    })
  )

  function select(listing) {
    market.selected = listing
    market.bids = []
    if (app.isRealtor) fetchNui('market:getBids', { listingId: listing.id })
  }
</script>

<div class="content">
      <div class="list-col">
        <div class="filters">
          <input class="input" placeholder="Search..." bind:value={search} />
          <div class="chips">
            {#each [['all', 'All'], ['sale', 'For sale'], ['auction', 'Auctions']] as [value, label]}
              <button class="chip" class:active={filter === value} onclick={() => (filter = value)}>{label}</button>
            {/each}
          </div>
        </div>

        <div class="listings scroll">
          {#each visible as listing (listing.id)}
            <button
              class="listing"
              class:active={market.selected?.id === listing.id}
              onclick={() => select(listing)}
            >
              {#if listing.images?.length}
                <img class="thumb" src={listing.images[0]} alt="" />
              {/if}
              <div class="listing-top">
                <span class="name">{listing.property_name}</span>
                <span class="badge {listing.listing_type === 'auction' ? 'yellow' : 'green'}">
                  {listing.listing_type === 'auction' ? 'Auction' : 'Sale'}
                </span>
              </div>
              <div class="listing-bottom">
                <span class="price">{formatMoney(listing.top_bid ?? listing.price)}</span>
                {#if listing.listing_type === 'auction'}
                  <span class="time" class:urgent={listing.auction_end - now < 300}>
                    {formatRemaining(listing.auction_end)}
                  </span>
                {/if}
              </div>
            </button>
          {:else}
            <div class="empty">No listings match your filters</div>
          {/each}
        </div>
      </div>

      <div class="detail-col">
        {#if market.selected}
          <ListingDetail listing={market.selected} {now} />
        {:else}
          <div class="empty">Select a listing to see details</div>
        {/if}
      </div>
    </div>

<style>
  .thumb {
    display: block;
    width: 100%;
    height: 84px;
    object-fit: cover;
    border-radius: var(--radius-sm);
    margin-bottom: 8px;
  }

  .content {
    display: grid;
    grid-template-columns: 340px 1fr;
    flex: 1;
    min-height: 0;
  }

  .list-col {
    display: flex;
    flex-direction: column;
    border-right: 1px solid var(--dark-4);
    min-height: 0;
  }

  .filters {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 14px 16px;
    border-bottom: 1px solid var(--dark-4);
  }

  .chips {
    display: flex;
    gap: 6px;
  }

  .chip {
    padding: 5px 10px;
    font-family: inherit;
    font-size: 12px;
    color: var(--dark-1);
    background: var(--dark-6);
    border: 1px solid transparent;
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .chip:hover {
    background: var(--dark-5);
  }

  .chip.active {
    color: #fff;
    background: var(--accent-15);
    border-color: var(--blue);
  }

  .listings {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 12px;
    min-height: 0;
  }

  .listing {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 12px;
    font-family: inherit;
    text-align: left;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: border-color 0.12s ease;
  }

  .listing:hover {
    border-color: var(--dark-3);
  }

  .listing.active {
    border-color: var(--blue);
    background: var(--accent-8);
  }

  .listing-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .name {
    font-size: 13px;
    font-weight: 500;
    color: var(--dark-0);
  }

  .listing-bottom {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .price {
    font-size: 14px;
    font-weight: 700;
    color: #fff;
  }

  .time {
    font-size: 11px;
    color: var(--dark-2);
  }

  .time.urgent {
    color: var(--red);
    font-weight: 500;
  }

  .detail-col {
    display: flex;
    flex-direction: column;
    min-height: 0;
  }
</style>
