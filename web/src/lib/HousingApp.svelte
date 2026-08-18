<script>
  import { fetchNui } from './nui.js'
  import { app, market, creator } from './store.svelte.js'
  import Market from './market/Market.svelte'
  import CreateProperty from './realtor/CreateProperty.svelte'
  import Buildings from './realtor/Buildings.svelte'
  import Properties from './realtor/Properties.svelte'
  import Creator from './realtor/Creator.svelte'

  let tab = $derived(app.tab)

  function setTab(value) {
    app.tab = value
    if (value === 'market') fetchNui('market:refresh')
  }

  const tabs = $derived([
    ['market', 'Market'],
    ...(app.isRealtor
      ? [
          ['create', 'New property'],
          ['manage', 'Manage'],
        ]
      : []),
    ...(app.isRealtor || creator.enabled ? [['buildings', 'Buildings']] : []),
    ...(creator.enabled ? [['creator', 'MLO Apartments Creator']] : []),
  ])

  $effect(() => {
    if (tab === 'creator') fetchNui('creator:open')
  })
</script>

<div class="wrap">
  <div class="panel shell">
    <div class="panel-header">
      <div>
        <div class="panel-title">Housing</div>
        <div class="panel-subtitle">{market.listings.length} active listings</div>
      </div>
      <div class="head-actions">
        {#if app.isRealtor}
          <span class="badge blue">Realtor</span>
        {/if}
        <button class="btn subtle" onclick={() => fetchNui('close')}>Close</button>
      </div>
    </div>

    {#if tabs.length > 1}
      <div class="tabs">
        {#each tabs as [value, label]}
          <button class="tab" class:active={tab === value} onclick={() => setTab(value)}>{label}</button>
        {/each}
      </div>
    {/if}

    <div class="body">
      {#if tab === 'market'}
        <Market />
      {:else if tab === 'create'}
        <div class="pad scroll"><CreateProperty /></div>
      {:else if tab === 'buildings'}
        <div class="pad scroll"><Buildings /></div>
      {:else if tab === 'creator'}
        <div class="pad scroll"><Creator /></div>
      {:else}
        <div class="pad scroll"><Properties /></div>
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
    width: 1020px;
    height: 100%;
    max-height: 720px;
  }

  .head-actions {
    display: flex;
    align-items: center;
    gap: 10px;
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

  .tab:hover {
    background: var(--dark-6);
  }

  .tab.active {
    color: #fff;
    background: var(--accent-15);
  }

  .body {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
  }

  .pad {
    flex: 1;
    padding: 20px;
    min-height: 0;
  }
</style>
