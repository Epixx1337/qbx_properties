<script>
  import { fetchNui } from '../nui.js'
  import { shot } from '../store.svelte.js'

  const BACKGROUNDS = { green: '#00ff00', blue: '#003cff', magenta: '#ff00ff', orange: '#ff8000' }

  function control(action, data = {}) {
    if (action === 'pause') shot.paused = true
    if (action === 'resume') shot.paused = false
    fetchNui('shotstudio:control', { action, ...data })
  }

  const progress = $derived(shot.total > 0 ? (shot.index / shot.total) * 100 : 0)

  let dragging = $state(false)
  let lastX = 0
  let lastY = 0
  let pendingDx = 0
  let pendingDy = 0
  let rafQueued = false

  function flushAdjust() {
    rafQueued = false
    if (pendingDx !== 0 || pendingDy !== 0) {
      fetchNui('shotstudio:control', { action: 'adjust', dx: pendingDx, dy: pendingDy })
      pendingDx = 0
      pendingDy = 0
    }
  }

  function onPointerDown(event) {
    dragging = true
    lastX = event.clientX
    lastY = event.clientY
    event.currentTarget.setPointerCapture(event.pointerId)
  }

  function onPointerMove(event) {
    if (!dragging) return
    pendingDx += event.clientX - lastX
    pendingDy += event.clientY - lastY
    lastX = event.clientX
    lastY = event.clientY
    if (!rafQueued) {
      rafQueued = true
      requestAnimationFrame(flushAdjust)
    }
  }

  let wheelBusy = false
  function onWheel(event) {
    if (wheelBusy) return
    wheelBusy = true
    requestAnimationFrame(() => (wheelBusy = false))
    fetchNui('shotstudio:control', { action: 'zoom', dir: event.deltaY > 0 ? -1 : 1 })
  }

  function onKeydown(event) {
    if (event.key === 'Escape') control('stop')
  }
</script>

<svelte:window on:keydown={onKeydown} />

<div
  class="camera-surface"
  class:dragging
  role="application"
  onpointerdown={onPointerDown}
  onpointermove={onPointerMove}
  onpointerup={() => (dragging = false)}
  onwheel={onWheel}
></div>

<div class="panel">
  <div class="head">
    <span class="title">Catalog studio</span>
    <span class="count">{shot.index}/{shot.total}</span>
  </div>
  <div class="bar"><span style:width={`${progress}%`}></span></div>

  <div class="item">
    <span class="label">{shot.label || '—'}</span>
    <span class="object">
      {shot.object}
      {#if shot.hasImage}<i class="dot has" title="Has an image on disk"></i>{/if}
      {#if shot.tuned}<i class="dot tuned" title="Saved framing"></i>{/if}
    </span>
  </div>

  <div class="row">
    {#if shot.paused}
      <button class="btn accent" onclick={() => control('resume')}>Resume</button>
    {:else}
      <button class="btn accent" onclick={() => control('pause')}>Pause</button>
    {/if}
    <button class="btn" onclick={() => control('back')}>◀</button>
    <button class="btn" onclick={() => control('next')}>▶</button>
    <button class="btn" onclick={() => control('shoot')} disabled={!shot.paused}>Shoot</button>
    <button class="btn danger" onclick={() => control('stop')}>Stop</button>
  </div>

  <div class="row">
    <span class="hint-label">Backdrop</span>
    {#each Object.entries(BACKGROUNDS) as [name, color] (name)}
      <button
        class="swatch"
        class:active={shot.primary === name}
        style:background={color}
        title={name}
        onclick={() => control('background', { color: name })}
      ></button>
    {/each}
    <span class="spacer"></span>
    <button class="btn" title="Wider field of view" onclick={() => control('fov', { dir: 1 })}>FOV +</button>
    <button class="btn" title="Tighter field of view" onclick={() => control('fov', { dir: -1 })}>FOV −</button>
  </div>

  <div class="row">
    <button class="btn" onclick={() => control('save')} disabled={!shot.paused}>Save framing</button>
    <button class="btn" onclick={() => control('clearTune')} disabled={!shot.tuned}>Clear framing</button>
  </div>

  <div class="counts">
    <span>{shot.done} shot</span>
    <span>{shot.skipped} skipped</span>
    <span class:bad={shot.failed > 0}>{shot.failed} failed</span>
    <span>{shot.empty} empty</span>
  </div>

  <span class="hint">Drag ←→ rotate · ↑↓ height · scroll zoom · Esc stop</span>
</div>

<style>
  .camera-surface {
    position: fixed;
    inset: 0;
    cursor: grab;
  }

  .camera-surface.dragging {
    cursor: grabbing;
  }

  .panel {
    position: fixed;
    top: 16px;
    right: 16px;
    width: 300px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 12px;
    border-radius: 10px;
    background: rgba(20, 21, 23, 0.92);
    border: 1px solid var(--dark-5, #2c2e33);
    color: var(--dark-0, #c1c2c5);
    font-size: 13px;
  }

  .head {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
  }

  .title {
    font-weight: 600;
    font-size: 14px;
  }

  .count {
    color: var(--dark-2, #909296);
  }

  .bar {
    height: 4px;
    border-radius: 2px;
    background: var(--dark-6, #25262b);
    overflow: hidden;
  }

  .bar span {
    display: block;
    height: 100%;
    background: var(--blue, #4dabf7);
    transition: width 0.15s ease;
  }

  .item {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .item .label {
    font-weight: 500;
  }

  .item .object {
    color: var(--dark-2, #909296);
    font-size: 12px;
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    display: inline-block;
  }

  .dot.has { background: #51cf66; }
  .dot.tuned { background: #4dabf7; }

  .row {
    display: flex;
    gap: 6px;
    align-items: center;
    flex-wrap: wrap;
  }

  .spacer { flex: 1; }

  .btn {
    padding: 5px 9px;
    border-radius: 6px;
    border: 1px solid var(--dark-5, #2c2e33);
    background: var(--dark-6, #25262b);
    color: inherit;
    cursor: pointer;
    font-size: 12px;
  }

  .btn:hover:not(:disabled) {
    background: var(--dark-5, #2c2e33);
  }

  .btn:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .btn.accent {
    background: var(--blue, #4dabf7);
    border-color: transparent;
    color: #101113;
    font-weight: 600;
  }

  .btn.danger {
    border-color: rgba(255, 107, 107, 0.4);
    color: #ff8787;
  }

  .hint-label {
    color: var(--dark-2, #909296);
    font-size: 12px;
  }

  .swatch {
    width: 20px;
    height: 20px;
    border-radius: 5px;
    border: 2px solid transparent;
    cursor: pointer;
  }

  .swatch.active {
    border-color: #fff;
  }

  .counts {
    display: flex;
    gap: 10px;
    color: var(--dark-2, #909296);
    font-size: 12px;
  }

  .counts .bad {
    color: #ff8787;
  }

  .hint {
    color: var(--dark-3, #5c5f66);
    font-size: 11px;
  }
</style>
