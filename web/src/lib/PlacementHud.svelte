<script>
  import { placement } from './store.svelte.js'

  const AXES = { z: 'Yaw', x: 'Pitch', y: 'Roll' }
  const axisName = $derived(AXES[placement.mode?.axis] ?? 'Yaw')
</script>

{#if placement.photo}
  <div class="viewfinder">
    <span class="corner tl"></span>
    <span class="corner tr"></span>
    <span class="corner bl"></span>
    <span class="corner br"></span>
  </div>
{/if}

<div class="hud">
  <span class="prompt">{placement.prompt}</span>
  <div class="keys">
    {#if placement.gizmo}
      <span><kbd>T</kbd> Move</span>
      <span><kbd>R</kbd> Rotate</span>
      {#if placement.flying}
        <span><kbd>WASD</kbd> Fly</span>
        <span><kbd>Space</kbd>/<kbd>Ctrl</kbd> Up / down</span>
        <span><kbd>Scroll</kbd> Speed</span>
        <span><kbd>G</kbd> Drag gizmo</span>
        <span><kbd>F</kbd> Exit freecam</span>
      {:else}
        <span><kbd>G</kbd> Walk / adjust</span>
        <span><kbd>F</kbd> Freecam</span>
      {/if}
      <span><kbd>Enter</kbd> Confirm</span>
    {:else if placement.zone}
      <span><kbd>LMB</kbd> Add corner</span>
      <span><kbd>Scroll</kbd> Height</span>
      <span><kbd>Backspace</kbd> Undo</span>
      <span><kbd>Enter</kbd> Finish</span>
      <span class="count">{placement.points} corner{placement.points === 1 ? '' : 's'}{placement.height !== null ? ` · ${placement.height.toFixed(1)}m high` : ''}</span>
    {:else if placement.vehicle}
      <span><kbd>LMB</kbd> Place</span>
      <span><kbd>Scroll</kbd> Rotate</span>
    {:else if placement.tour}
      <span><kbd>WASD</kbd> Fly</span>
      <span><kbd>Space</kbd>/<kbd>Ctrl</kbd> Up / down</span>
      <span><kbd>Scroll</kbd> Speed</span>
      <span><kbd>G</kbd> Take photo</span>
      <span><kbd>X</kbd> Skip house</span>
    {:else if placement.photo}
      <span><kbd>E</kbd> Take photo</span>
    {:else if placement.capture}
      <span><kbd>E</kbd> Capture</span>
    {:else if placement.freePlace}
      <span><kbd>LMB</kbd> Place</span>
      <span><kbd>Scroll</kbd> Turn {axisName}</span>
      <span><kbd>R</kbd> Axis</span>
      <span><kbd>Ctrl</kbd>+<kbd>Scroll</kbd> Coarse</span>
      <span><kbd>Alt</kbd>+<kbd>Scroll</kbd> Fine</span>
      <span><kbd>Shift</kbd>+<kbd>Scroll</kbd> Raise / distance</span>
      <span><kbd>G</kbd> Follow surface</span>
      <span><kbd>X</kbd> Grid</span>
      <span><kbd>H</kbd> Flat to wall</span>
    {:else}
      <span><kbd>LMB</kbd> Select</span>
    {/if}
    <span><kbd>Esc</kbd> Cancel</span>
  </div>

  {#if placement.freePlace && placement.mode}
    <div class="modes">
      <span class="chip" class:on={placement.mode.grid}>Grid {placement.mode.grid ? 'on' : 'off'}</span>
      <span class="chip" class:on={placement.mode.wall}>Wall {placement.mode.wall ? 'on' : 'off'}</span>
      <span class="chip" class:on={placement.mode.ground}>Surface {placement.mode.ground ? 'on' : 'off'}</span>
      <span class="chip on">{axisName}</span>
      {#if placement.mode.door !== undefined && placement.mode.door !== null}
        <span class="chip" class:on={placement.mode.door}>
          {placement.mode.door ? 'Fixes to this door' : 'Not on a door'}
        </span>
      {/if}
    </div>
  {/if}
</div>

<style>
  .viewfinder {
    position: absolute;
    inset: 10%;
    pointer-events: none;
  }

  .corner {
    position: absolute;
    width: 42px;
    height: 42px;
    border: 3px solid rgba(255, 255, 255, 0.85);
  }

  .corner.tl { top: 0; left: 0; border-right: none; border-bottom: none; }
  .corner.tr { top: 0; right: 0; border-left: none; border-bottom: none; }
  .corner.bl { bottom: 0; left: 0; border-right: none; border-top: none; }
  .corner.br { bottom: 0; right: 0; border-left: none; border-top: none; }

  .hud {
    position: absolute;
    left: 50%;
    bottom: 28px;
    transform: translateX(-50%);
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    padding: 12px 20px;
    background: var(--dark-7);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-md);
    box-shadow: var(--shadow);
    pointer-events: none;
  }

  .prompt {
    font-size: 14px;
    font-weight: 500;
    color: #fff;
  }

  .keys {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 6px 14px;
    font-size: 12px;
    color: var(--dark-2);
  }

  .keys span {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    white-space: nowrap;
  }

  .count {
    color: var(--blue-light);
    font-weight: 500;
  }

  .modes {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 6px;
  }

  .chip {
    padding: 2px 8px;
    font-size: 11px;
    color: var(--dark-2);
    background: var(--dark-6);
    border-radius: var(--radius-sm);
  }

  .chip.on {
    color: #fff;
    background: var(--blue);
  }
</style>
