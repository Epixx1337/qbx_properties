<script>
  import { fetchNui } from './nui.js'
  import { preview } from './store.svelte.js'

  const LABELS = {
    exit: 'Entrance / exit',
    stash: 'Stash',
    clothing: 'Wardrobe',
    logout: 'Logout',
  }

  function fmt(point) {
    if (!point) return 'not set'
    return `${point.x.toFixed(2)}, ${point.y.toFixed(2)}, ${point.z.toFixed(2)}`
  }
</script>

<div class="wrap">
  <aside class="panel tools">
    <div class="panel-header">
      <div>
        <div class="panel-title">Interaction points</div>
        <div class="panel-subtitle">{preview.interior}</div>
      </div>
    </div>

    <div class="body">
      <div class="hint">
        {preview.property
          ? 'Stand where the point should be, then capture it. These apply to this property only.'
          : 'Stand where the point should be, then capture it. These become the defaults for every property using this shell.'}
      </div>

      {#each preview.types as type}
        <div class="point">
          <div class="point-main">
            <span class="point-label">{LABELS[type] ?? type}</span>
            <span class="point-value" class:set={preview.points[type]}>{fmt(preview.points[type])}</span>
          </div>
          <button class="mini" onclick={() => fetchNui(preview.property ? 'preview:captureProperty' : 'preview:capture', { type })}>Capture</button>
        </div>
      {/each}

      <button class="btn success wide" onclick={() => fetchNui(preview.property ? 'preview:saveProperty' : 'preview:save')}>
        {preview.property ? 'Save points' : 'Save defaults'}
      </button>
      {#if preview.setup}
        <button class="btn wide" onclick={() => fetchNui('preview:nextShell')}>Next shell</button>
      {/if}
      <button class="btn subtle wide" onclick={() => fetchNui(preview.property ? 'preview:exitProperty' : 'preview:exit')}>
        {preview.property ? 'Close' : 'Exit preview'}
      </button>
    </div>
  </aside>

  <footer class="banner">
    <span class="dot"></span>
    {preview.property ? 'Editing' : 'Previewing'} <b>{preview.interior}</b>
    <span class="sep">·</span>
    <kbd>E</kbd> tools
    <span class="sep">·</span>
    <kbd>Esc</kbd> walk
    <span class="sep">·</span>
    <kbd>Backspace</kbd> exit
  </footer>
</div>

<style>
  .wrap {
    position: relative;
    display: flex;
    justify-content: flex-end;
    height: 100%;
    padding: 24px;
    pointer-events: none;
  }

  .tools {
    width: 320px;
    pointer-events: auto;
  }

  .body {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 16px;
  }

  .point {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    padding: 9px 11px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .point-main {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .point-label {
    font-size: 13px;
    color: var(--dark-0);
  }

  .point-value {
    font-size: 11px;
    color: var(--dark-3);
    font-variant-numeric: tabular-nums;
  }

  .point-value.set {
    color: var(--green);
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

  .mini:hover {
    background: var(--blue);
    color: #fff;
  }

  .banner {
    position: absolute;
    left: 50%;
    bottom: 28px;
    transform: translateX(-50%);
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 10px 18px;
    font-size: 13px;
    color: var(--dark-1);
    background: var(--dark-7);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-md);
    box-shadow: var(--shadow);
  }

  .banner b {
    color: #fff;
  }

  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--blue);
  }

  .sep {
    color: var(--dark-4);
  }

  .wide {
    width: 100%;
  }
</style>
