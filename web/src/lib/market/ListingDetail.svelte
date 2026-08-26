<script>
  import Lightbox from '../Lightbox.svelte'
  import { fetchNui, formatMoney, formatRemaining } from '../nui.js'
  import { app, market } from '../store.svelte.js'

  let { listing, now, toggleSave, savedIds } = $props()

  let imageIndex = $state(0)
  let lightboxIndex = $state(null)
  let bidAmount = $state(0)
  let offerAmount = $state(0)
  let agentTarget = $state('')
  let agentAmount = $state(0)

  $effect(() => {
    listing.id
    imageIndex = 0
  })

  const minimum = $derived((listing.top_bid ?? listing.price) + listing.min_increment)
  const ended = $derived(listing.listing_type === 'auction' && listing.auction_end - now <= 0)
  const isSaved = $derived(savedIds.includes(listing.id))

  $effect(() => {
    bidAmount = minimum
    agentAmount = minimum
    offerAmount = listing.price
  })

  const typeBadge = $derived(
    listing.listing_type === 'auction' ? ['yellow', 'Auction'] : listing.listing_type === 'offer' ? ['blue', 'Open to offers'] : ['green', 'Direct sale']
  )

  const facts = $derived([
    ...(listing.size ? [['Size', market.sizes[listing.size]?.label ?? listing.size]] : []),
    ...(listing.type ? [['Type', listing.type.charAt(0).toUpperCase() + listing.type.slice(1)]] : [['Type', 'Residential']]),
    ['Sale', listing.rent_interval ? `Rental · every ${listing.rent_interval}h` : 'Full purchase'],
    ['Listing', `#${listing.id}`],
    ...(listing.size && market.sizes[listing.size] ? [['Power allowance', `${market.sizes[listing.size].power} W`]] : []),
    ...(listing.size && market.sizes[listing.size] ? [['Utilities', `${formatMoney(market.sizes[listing.size].cost)} / month`]] : []),
  ])

  function bid() {
    if (bidAmount < minimum) return
    fetchNui('market:bid', { listingId: listing.id, amount: bidAmount })
  }

  function buy() {
    fetchNui('market:buy', { listingId: listing.id })
  }

  function placeOffer() {
    if (offerAmount < listing.price) return
    fetchNui('market:placeOffer', { listingId: listing.id, amount: offerAmount })
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

<div class="detail">
  <div class="head">
    <div class="head-left">
      <button class="btn subtle" onclick={() => (market.selected = null)}>← All listings</button>
      <span class="title">{listing.property_name}</span>
      <span class="badge {typeBadge[0]}">{typeBadge[1]}</span>
      {#if listing.rent_interval}
        <span class="badge">Rental · {listing.rent_interval}h</span>
      {/if}
    </div>
    <div class="head-right">
      <button class="btn subtle" class:save-active={isSaved} onclick={() => toggleSave(listing.id)}>
        {isSaved ? 'Saved' : 'Save'}
      </button>
      {#if app.isRealtor}
        <button class="btn subtle danger-hover" onclick={() => fetchNui('market:cancelListing', { listingId: listing.id })}>
          Cancel listing
        </button>
      {/if}
    </div>
  </div>

  <div class="cols">
    <div class="main scroll">
      <div class="gallery">
        {#if listing.images?.length}
          <img
            src={listing.images[Math.min(imageIndex, listing.images.length - 1)]}
            alt={listing.property_name}
            onclick={() => (lightboxIndex = imageIndex)}
          />
        {:else}
          <span class="photo-label">NO PHOTOS YET</span>
        {/if}
      </div>
      {#if listing.images?.length > 1}
        <div class="thumbs">
          {#each listing.images as image, i (image)}
            <button class="thumb" class:active={imageIndex === i} onclick={() => (imageIndex = i)}>
              <img src={image} alt="" loading="lazy" />
            </button>
          {/each}
        </div>
      {/if}

      {#if listing.description}
        <p class="desc">{listing.description}</p>
      {/if}

      <div class="facts">
        {#each facts as [k, v] (k)}
          <div class="fact-card">
            <span class="fact-k">{k}</span>
            <span class="fact-v">{v}</span>
          </div>
        {/each}
      </div>
    </div>

    <div class="rail scroll">
      {#if listing.listing_type === 'auction'}
        <div class="panel-card">
          <div class="stat">
            <span class="stat-label">CURRENT BID</span>
            <span class="stat-big">{formatMoney(listing.top_bid ?? listing.price)}</span>
            <span class="stat-sub">{listing.top_bid ? 'top standing bid' : `starting at ${formatMoney(listing.price)}`}</span>
          </div>
          <div class="time-row">
            <span>Time left</span>
            <span class="time-value" class:urgent={listing.auction_end - now < 300}>{formatRemaining(listing.auction_end)}</span>
          </div>
          <div class="bid-box">
            <div class="row">
              <input class="input mono grow" type="number" min={minimum} step={listing.min_increment} bind:value={bidAmount} />
              <button class="btn accent" disabled={ended || bidAmount < minimum} onclick={bid}>Bid</button>
            </div>
            <span class="fine">Minimum {formatMoney(minimum)} · taken from your bank now, returned in full if you are outbid</span>
          </div>
        </div>

        {#if app.isRealtor}
          <div class="panel-card">
            <span class="panel-title">Bid on behalf of a client</span>
            <div class="row">
              <select class="select grow" bind:value={agentTarget} onfocus={requestClients}>
                <option value="">Select client...</option>
                {#each market.nearbyClients as client}
                  <option value={client.serverId}>{client.name}</option>
                {/each}
              </select>
              <button class="btn subtle" onclick={requestClients}>↻</button>
            </div>
            <div class="row">
              <input class="input mono grow" type="number" min={minimum} bind:value={agentAmount} />
              <button class="btn accent" disabled={!agentTarget || ended} onclick={agentBid}>Request</button>
            </div>
            <span class="fine">The client confirms in game and pays from their own bank.</span>
          </div>

          <div class="feed">
            <div class="feed-head">
              <span>Live bids</span>
              <span class="fine">{market.bids.length} total</span>
            </div>
            {#each market.bids as entry, i}
              <div class="feed-row" class:top={i === 0 && entry.status === 'active'}>
                <span class="feed-info">
                  <span class="feed-name">{entry.bidder}</span>
                  <span class="fine">{entry.status}</span>
                </span>
                <span class="feed-amt">{formatMoney(entry.amount)}</span>
              </div>
            {:else}
              <div class="fine">No bids yet</div>
            {/each}
          </div>
        {/if}
      {:else if listing.listing_type === 'offer'}
        <div class="panel-card">
          <div class="stat">
            <span class="stat-label">ASKING</span>
            <span class="stat-big">{formatMoney(listing.price)}</span>
            <span class="stat-sub">{listing.top_bid ? `best offer ${formatMoney(listing.top_bid)}` : 'no offers yet'}</span>
          </div>
          <div class="bid-box">
            <div class="row">
              <input class="input mono grow" type="number" min={listing.price} bind:value={offerAmount} />
              <button class="btn accent" disabled={offerAmount < listing.price} onclick={placeOffer}>Offer</button>
            </div>
            <span class="fine">The full amount is held from your bank until the offer is accepted or declined.</span>
          </div>
        </div>

        {#if app.isRealtor}
          <div class="feed">
            <div class="feed-head">
              <span>Offers</span>
              <span class="fine">{market.bids.length} total</span>
            </div>
            {#each market.bids as entry (entry.id)}
              <div class="feed-row">
                <span class="feed-info">
                  <span class="feed-name">{entry.bidder}</span>
                  <span class="feed-amt small">{formatMoney(entry.amount)}</span>
                </span>
                {#if entry.status === 'active'}
                  <span class="feed-actions">
                    <button class="mini accent" onclick={() => fetchNui('market:acceptOffer', { listingId: listing.id, bidId: entry.id })}>Accept</button>
                    <button class="mini danger" onclick={() => fetchNui('market:declineOffer', { listingId: listing.id, bidId: entry.id })}>Decline</button>
                  </span>
                {:else}
                  <span class="badge">{entry.status}</span>
                {/if}
              </div>
            {:else}
              <div class="fine">No offers yet</div>
            {/each}
          </div>
        {/if}
      {:else}
        <div class="panel-card">
          <div class="stat">
            <span class="stat-label">PRICE</span>
            <span class="stat-big">{formatMoney(listing.price)}</span>
            <span class="stat-sub">{listing.rent_interval ? `charged every ${listing.rent_interval} hours` : 'one-time purchase'}</span>
          </div>
          <button class="btn success wide" onclick={buy}>
            {listing.rent_interval ? `Rent for ${formatMoney(listing.price)}` : `Buy ${formatMoney(listing.price)}`}
          </button>
          <span class="fine">Paid from your bank. Keys, garage and stash transfer immediately.</span>
        </div>
      {/if}

      {#if listing.size && market.sizes[listing.size]}
        <div class="costs">
          <span class="panel-title">Running costs</span>
          <div class="cost-row">
            <span>Utilities</span>
            <span class="mono-v">{formatMoney(market.sizes[listing.size].cost)} / mo</span>
          </div>
          {#if listing.rent_interval}
            <div class="cost-row">
              <span>Rent</span>
              <span class="mono-v">{formatMoney(listing.price)} / {listing.rent_interval}h</span>
            </div>
          {/if}
        </div>
      {/if}
    </div>
  </div>
</div>

<Lightbox images={listing.images ?? []} bind:index={lightboxIndex} />

<style>
  .detail {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
  }

  .head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 14px;
    padding: 13px 18px;
    border-bottom: 1px solid var(--dark-6);
    flex: none;
  }

  .head-left {
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 0;
  }

  .head-right {
    display: flex;
    gap: 7px;
    flex: none;
  }

  .title {
    font-size: 17px;
    font-weight: 700;
    color: #fff;
    white-space: nowrap;
  }

  .save-active {
    color: var(--blue-light, #339af0);
    border: 1px solid var(--accent-35);
    background: var(--accent-8);
  }

  .danger-hover:hover {
    color: var(--red);
  }

  .cols {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 330px;
    flex: 1;
    min-height: 0;
  }

  .main {
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding: 18px;
    min-height: 0;
  }

  .gallery {
    position: relative;
    height: 262px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: repeating-linear-gradient(135deg, var(--dark-5) 0 11px, var(--dark-6) 11px 22px);
    border: 1px solid var(--dark-4);
    border-radius: 8px;
    overflow: hidden;
    flex: none;
  }

  .gallery img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    cursor: zoom-in;
  }

  .photo-label {
    font-family: 'Roboto Mono', monospace;
    font-size: 11px;
    letter-spacing: 0.12em;
    color: var(--dark-3);
  }

  .thumbs {
    display: flex;
    gap: 6px;
    flex: none;
    flex-wrap: wrap;
  }

  .thumb {
    width: 70px;
    height: 48px;
    padding: 0;
    border-radius: var(--radius-sm);
    border: 2px solid var(--dark-4);
    overflow: hidden;
    cursor: pointer;
    background: var(--dark-5);
  }

  .thumb img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }

  .thumb.active {
    border-color: var(--blue);
  }

  .desc {
    font-size: 13px;
    line-height: 1.6;
    color: var(--dark-1);
    flex: none;
  }

  .facts {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 8px;
    flex: none;
  }

  .fact-card {
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: 10px 11px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .fact-k {
    font-size: 11px;
    color: var(--dark-2);
  }

  .fact-v {
    font-size: 13px;
    font-weight: 500;
    color: #fff;
  }

  .rail {
    display: flex;
    flex-direction: column;
    gap: 12px;
    padding: 18px;
    border-left: 1px solid var(--dark-4);
    min-height: 0;
  }

  .panel-card {
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding: 15px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: 8px;
    flex: none;
  }

  .panel-title {
    font-size: 12px;
    font-weight: 700;
    color: var(--dark-0);
  }

  .stat {
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .stat-label {
    font-size: 11px;
    letter-spacing: 0.08em;
    color: var(--dark-2);
  }

  .stat-big {
    font-size: 29px;
    font-weight: 700;
    line-height: 1;
    color: #fff;
  }

  .stat-sub {
    font-size: 12px;
    color: var(--dark-2);
  }

  .time-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    padding: 10px 12px;
    background: var(--dark-8);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .time-row span:first-child {
    font-size: 12px;
    color: var(--dark-2);
  }

  .time-value {
    font-family: 'Roboto Mono', monospace;
    font-size: 15px;
    font-weight: 700;
    color: var(--yellow, #fab005);
  }

  .time-value.urgent {
    color: var(--red);
  }

  .bid-box {
    display: flex;
    flex-direction: column;
    gap: 7px;
  }

  .row {
    display: flex;
    gap: 7px;
  }

  .grow {
    flex: 1;
    min-width: 0;
  }

  .mono {
    font-family: 'Roboto Mono', monospace;
  }

  .fine {
    font-size: 11px;
    line-height: 1.45;
    color: var(--dark-3);
  }

  .select {
    padding: 9px 10px;
    font-family: inherit;
    font-size: 12px;
    color: var(--dark-0);
    background: var(--dark-8);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
    outline: none;
  }

  .feed {
    display: flex;
    flex-direction: column;
    gap: 6px;
    flex: none;
  }

  .feed-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 12px;
    font-weight: 700;
    color: var(--dark-0);
  }

  .feed-row {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    padding: 8px 10px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .feed-row.top {
    border-color: var(--green, #40c057);
  }

  .feed-info {
    display: flex;
    flex-direction: column;
    gap: 1px;
    min-width: 0;
  }

  .feed-name {
    font-size: 12px;
    color: var(--dark-0);
  }

  .feed-amt {
    font-family: 'Roboto Mono', monospace;
    font-size: 12px;
    font-weight: 700;
    color: #fff;
  }

  .feed-amt.small {
    font-weight: 500;
  }

  .feed-actions {
    display: flex;
    gap: 5px;
    flex: none;
  }

  .costs {
    display: flex;
    flex-direction: column;
    gap: 7px;
    flex: none;
  }

  .cost-row {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 10px;
    padding: 7px 0;
    border-bottom: 1px solid var(--dark-6);
    font-size: 12px;
    color: var(--dark-2);
  }

  .mono-v {
    font-family: 'Roboto Mono', monospace;
    font-size: 12px;
    font-weight: 500;
    color: #fff;
  }
</style>
