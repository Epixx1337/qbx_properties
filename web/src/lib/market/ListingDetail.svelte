<script>
  import Lightbox from '../Lightbox.svelte'

  let imageIndex = $state(0)
  let lightboxIndex = $state(null)

  $effect(() => {
    listing.id
    imageIndex = 0
  })

  import { fetchNui, formatMoney, formatRemaining } from '../nui.js'
  import { app, market } from '../store.svelte.js'

  let { listing, now } = $props()

  let bidAmount = $state(0)
  let agentTarget = $state('')
  let agentAmount = $state(0)

  const minimum = $derived((listing.top_bid ?? listing.price) + listing.min_increment)
  const ended = $derived(listing.listing_type === 'auction' && listing.auction_end - now <= 0)

  $effect(() => {
    bidAmount = minimum
    agentAmount = minimum
  })

  function bid() {
    if (bidAmount < minimum) return
    fetchNui('market:bid', { listingId: listing.id, amount: bidAmount })
  }

  function buy() {
    fetchNui('market:buy', { listingId: listing.id })
  }

  function requestClients() {
    fetchNui('market:getNearbyClients')
  }

  function agentBid() {
    if (!agentTarget || agentAmount < minimum) return
    fetchNui('market:agentBid', {
      listingId: listing.id,
      amount: agentAmount,
      targetServerId: Number(agentTarget),
    })
  }
</script>

<div class="detail scroll">
  <div class="head">
    <div>
      <h2>{listing.property_name}</h2>
      <div class="meta">
        <span class="badge {listing.listing_type === 'auction' ? 'yellow' : 'green'}">
          {listing.listing_type === 'auction' ? 'Auction' : 'Direct sale'}
        </span>
        {#if listing.rent_interval}
          <span class="badge">Rental · {listing.rent_interval}h</span>
        {/if}
      </div>
    </div>
  </div>

  {#if listing.images?.length}
    <div class="gallery">
      <img
        src={listing.images[Math.min(imageIndex, listing.images.length - 1)]}
        alt={listing.property_name}
        onclick={() => (lightboxIndex = Math.min(imageIndex, listing.images.length - 1))}
      />
    </div>
    {#if listing.images.length > 1}
      <div class="thumbs">
        {#each listing.images as image, i (image)}
          <button class="thumb-btn" class:active={i === imageIndex} onclick={() => (imageIndex = i)}>
            <img src={image} alt={'Photo ' + (i + 1)} />
          </button>
        {/each}
      </div>
    {/if}
  {/if}

  {#if listing.description}
    <p class="summary">{listing.description}</p>
  {/if}

  <div class="stats" class:single={listing.listing_type !== 'auction'}>
    <div class="stat">
      <span class="stat-label">{listing.listing_type === 'auction' ? 'Current bid' : 'Price'}</span>
      <span class="stat-value">{formatMoney(listing.top_bid ?? listing.price)}</span>
    </div>
    {#if listing.listing_type === 'auction'}
      <div class="stat">
        <span class="stat-label">Starting price</span>
        <span class="stat-value">{formatMoney(listing.price)}</span>
      </div>
      <div class="stat">
        <span class="stat-label">Time left</span>
        <span class="stat-value" class:urgent={listing.auction_end - now < 300}>
          {formatRemaining(listing.auction_end)}
        </span>
      </div>
      <div class="stat">
        <span class="stat-label">Min increment</span>
        <span class="stat-value">{formatMoney(listing.min_increment)}</span>
      </div>
    {/if}
  </div>

  {#if listing.listing_type === 'auction'}
    <div class="section">
      <div class="section-title">Place a bid</div>
      <div class="hint">Your bid is taken from your bank immediately and returned in full if someone outbids you.</div>
      <div class="row">
        <input class="input" type="number" min={minimum} step={listing.min_increment} bind:value={bidAmount} />
        <button class="btn" disabled={ended || bidAmount < minimum} onclick={bid}>Bid</button>
      </div>
      <div class="hint">Minimum {formatMoney(minimum)}</div>
    </div>
  {:else}
    <div class="section actions">
      <button class="btn success" onclick={buy}>Buy for {formatMoney(listing.price)}</button>
      {#if app.isRealtor}
        <button class="btn danger" onclick={() => fetchNui('market:cancelListing', { listingId: listing.id })}>
          Cancel listing
        </button>
      {/if}
    </div>
  {/if}

  {#if app.isRealtor && listing.listing_type === 'auction'}
    <div class="section realtor">
      <div class="section-title">Realtor tools</div>

      {#if listing.listing_type === 'auction'}
        <div class="field">
          <span class="label">Bid on behalf of a nearby client</span>
          <div class="row">
            <select class="select" bind:value={agentTarget} onfocus={requestClients}>
              <option value="">Select client...</option>
              {#each market.nearbyClients as client}
                <option value={client.serverId}>{client.name}</option>
              {/each}
            </select>
            <button class="btn subtle" onclick={requestClients}>Refresh</button>
          </div>
        </div>
        <div class="row">
          <input class="input" type="number" min={minimum} step={listing.min_increment} bind:value={agentAmount} />
          <button class="btn" disabled={!agentTarget || ended} onclick={agentBid}>Request</button>
        </div>
        <div class="hint">The client confirms in game and pays from their own bank.</div>

        <div class="bids">
          <div class="section-title">Bid history</div>
          {#each market.bids as entry}
            <div class="bid">
              <span>{entry.bidder}</span>
              <span class="bid-amount">{formatMoney(entry.amount)}</span>
              <span class="badge {entry.status === 'active' ? 'green' : ''}">{entry.status}</span>
            </div>
          {:else}
            <div class="hint">No bids yet</div>
          {/each}
        </div>
      {/if}

      <button class="btn danger wide" onclick={() => fetchNui('market:cancelListing', { listingId: listing.id })}>
        Cancel listing
      </button>
    </div>
  {/if}
</div>

<Lightbox images={listing.images ?? []} bind:index={lightboxIndex} />

<style>
  .gallery {
    position: relative;
    border-radius: var(--radius-md);
    overflow: hidden;
    border: 1px solid var(--dark-4);
  }

  .gallery img {
    display: block;
    width: 100%;
    height: 250px;
    object-fit: cover;
    cursor: zoom-in;
  }

  .thumbs {
    display: flex;
    gap: 6px;
    overflow-x: auto;
  }

  .thumb-btn {
    flex: none;
    width: 64px;
    height: 44px;
    padding: 0;
    background: none;
    border: 2px solid var(--dark-4);
    border-radius: var(--radius-sm);
    overflow: hidden;
    cursor: pointer;
  }

  .thumb-btn img {
    display: block;
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .thumb-btn.active {
    border-color: var(--blue);
  }

  .summary {
    font-size: 12px;
    line-height: 1.5;
    color: var(--dark-1);
    white-space: pre-wrap;
  }

  .detail {
    display: flex;
    flex-direction: column;
    gap: 18px;
    padding: 20px;
    min-height: 0;
  }

  h2 {
    font-size: 18px;
    font-weight: 700;
  }

  .meta {
    display: flex;
    gap: 6px;
    margin-top: 8px;
  }

  .stats {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 10px;
  }

  .stats.single {
    grid-template-columns: 1fr;
  }

  .stats.single .stat {
    align-items: center;
    padding: 8px;
  }

  .stats.single .stat-value {
    font-size: 14px;
  }

  .actions {
    flex-direction: row;
  }

  .actions .btn {
    flex: 1;
  }

  .stat {
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: 12px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .stat-label {
    font-size: 11px;
    color: var(--dark-2);
  }

  .stat-value {
    font-size: 16px;
    font-weight: 700;
    color: #fff;
  }

  .stat-value.urgent {
    color: var(--red);
  }

  .section {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding-top: 16px;
    border-top: 1px solid var(--dark-4);
  }

  .section-title {
    font-size: 13px;
    font-weight: 700;
  }

  .row {
    display: flex;
    gap: 8px;
  }

  .row .btn {
    flex-shrink: 0;
  }

  .wide {
    width: 100%;
  }

  .bids {
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-top: 6px;
  }

  .bid {
    display: grid;
    grid-template-columns: 1fr auto auto;
    align-items: center;
    gap: 10px;
    padding: 8px 10px;
    font-size: 12px;
    background: var(--dark-6);
    border-radius: var(--radius-sm);
  }

  .bid-amount {
    font-weight: 700;
    color: #fff;
  }
</style>
