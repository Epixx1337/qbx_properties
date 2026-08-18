<script>
  import { fetchNui } from '../nui.js'
  import { creator, realtor } from '../store.svelte.js'

  let newKey = $state('')
  let newLabel = $state('')

  const draft = $derived(creator.draft)
  const interior = $derived(creator.interior)

  const expected = $derived(draft?.expectedRooms ?? interior?.roomCount ?? null)
  const roomsDone = $derived(draft ? draft.rooms.length : 0)

  const mappingOk = $derived.by(() => {
    if (!interior?.currentRoom || !creator.anchor) return false
    const n = Number(String(interior.currentRoom).match(/(\d+)$/)?.[1])
    return Number.isFinite(n) && n === creator.anchor.index
  })

  const ready = $derived(
    draft !== null &&
      draft.key.length > 0 &&
      draft.label.length >= 2 &&
      draft.rooms.length > 0 &&
      draft.floors.count >= 1 &&
      draft.floors.step > 0
  )

  function capture(what) {
    fetchNui('creator:capture', { what })
  }

  function update(patch) {
    fetchNui('creator:update', patch)
  }

  function fmt(v, digits = 2) {
    return Number(v ?? 0).toFixed(digits)
  }
</script>

<div class="layout">
  <div class="col">
    <div class="section-title">Interior scan</div>

    {#if interior?.id}
      <div class="scan">
        <div class="scan-row"><span>Interior id</span><b>{interior.id}</b></div>
        <div class="scan-row"><span>Detected pattern</span><b>{interior.pattern ?? 'none'}</b></div>
        <div class="scan-row"><span>Numbered rooms</span><b>{interior.roomCount ?? 0}</b></div>
        <div class="scan-row"><span>You are in</span><b>{interior.currentRoom ?? 'unknown'}</b></div>
        {#if creator.anchor}
          <div class="scan-row">
            <span>Nearest anchor</span>
            <b>#{creator.anchor.index} · floor {creator.anchor.floor} · {creator.anchor.distance}m</b>
          </div>
        {/if}
      </div>

      {#if interior.currentRoom && creator.anchor}
        <div class="hint {mappingOk ? '' : 'warn'}">
          {#if mappingOk}
            Mapping OK: anchor #{creator.anchor.index} is {interior.currentRoom}.
          {:else}
            Mismatch: you are standing in <b>{interior.currentRoom}</b> but the nearest anchor is
            <b>#{creator.anchor.index}</b>. The anchor order in config/buildings.lua does not match the MLO room numbering.
          {/if}
        </div>
      {/if}
      <div class="names scroll">
        {#each interior.names as name}
          <span class="badge">{name}</span>
        {/each}
      </div>
    {:else}
      <div class="hint">Stand inside the MLO to scan its interior rooms.</div>
    {/if}

    <div class="section-title">Building</div>
    {#if !draft}
      <div class="field">
        <span class="label">Key</span>
        <input class="input" bind:value={newKey} placeholder="wiwang" />
        <span class="hint">Lowercase letters, digits and underscores.</span>
      </div>
      <div class="field">
        <span class="label">Label</span>
        <input class="input" bind:value={newLabel} placeholder="Wiwang Hotel" />
      </div>
      <button
        class="btn wide"
        disabled={!newKey.trim() || newLabel.trim().length < 2}
        onclick={() => fetchNui('creator:newBuilding', { key: newKey, label: newLabel })}
      >
        Start capture here
      </button>

      {#if realtor.buildings.length}
        <span class="hint">Or edit an existing building:</span>
        {#each realtor.buildings as entry}
          <button class="btn subtle wide" onclick={() => fetchNui('creator:loadBuilding', { key: entry.key })}>
            {entry.label}
          </button>
        {/each}
      {/if}
    {:else}
      <div class="field">
        <span class="label">Label</span>
        <input class="input" value={draft.label} oninput={(e) => update({ label: e.target.value })} />
      </div>
      <div class="field">
        <span class="label">Room name pattern</span>
        <input class="input" value={draft.roomName} oninput={(e) => update({ roomName: e.target.value })} />
        <span class="hint">Must contain %d, e.g. <b>Room.%d</b></span>
      </div>
      <div class="field">
        <span class="label">IPL pattern (optional)</span>
        <input class="input" value={draft.ipl ?? ''} oninput={(e) => update({ ipl: e.target.value })} placeholder="floky_wiwang_hotel_%02d_milo_" />
      </div>
    {/if}
  </div>

  {#if draft}
    <div class="col">
      <div class="section-title">Capture</div>
      <div class="hint">Walk to each spot, then press the matching button.</div>

      <div class="grid">
        <button class="btn subtle" onclick={() => capture('entrance')}>Entrance</button>
        <button class="btn subtle" onclick={() => capture('receptionist')}>Receptionist</button>
        <button class="btn subtle" onclick={() => capture('lobbyElevator')}>Lobby elevator</button>
        <button class="btn subtle" onclick={() => capture('elevator')}>Floor elevator</button>
        <button class="btn subtle" onclick={() => capture('baseZ')}>Set base floor Z</button>
        <button class="btn subtle" onclick={() => capture('step')}>Set floor height</button>
      </div>

      <div class="section-title">Floors</div>
      <div class="grid">
        <div class="field">
          <span class="label">Count</span>
          <input class="input" type="number" min="1" max="100" value={draft.floors.count} oninput={(e) => update({ floorCount: e.target.value })} />
        </div>
        <div class="field">
          <span class="label">Step (m)</span>
          <input class="input" type="number" step="0.01" value={fmt(draft.floors.step)} oninput={(e) => update({ step: e.target.value })} />
        </div>
      </div>
      <div class="hint">Base Z {fmt(draft.floors.baseZ)} · top floor Z {fmt(draft.floors.baseZ + draft.floors.step * (draft.floors.count - 1))}</div>

      <div class="section-title">
        Room anchors
        {#if expected}
          <span class="badge {roomsDone === expected ? 'green' : 'yellow'}">{roomsDone} / {expected}</span>
        {:else}
          <span class="badge">{roomsDone}</span>
        {/if}
      </div>
      <div class="hint">Stand at each door on the <b>base floor only</b>, facing into the room.</div>

      <div class="actions">
        <button class="btn" onclick={() => capture('room')}>Capture room {roomsDone + 1}</button>
        <button class="btn subtle" onclick={() => capture('spawn')} disabled={roomsDone === 0}>Set spawn</button>
      </div>

      <div class="rooms scroll">
        {#each draft.rooms as room, index}
          <div class="room">
            <span class="room-no">{index + 1}</span>
            <span class="room-pos">{fmt(room.x)}, {fmt(room.y)}, {fmt(room.z)} @ {fmt(room.w, 1)}°</span>
            <button class="mini" onclick={() => fetchNui('creator:teleport', { index: index + 1 })}>go</button>
            <button class="mini danger" onclick={() => fetchNui('creator:removeRoom', { index: index + 1 })}>×</button>
          </div>
        {:else}
          <div class="empty">No rooms captured yet</div>
        {/each}
      </div>

      {#if expected && roomsDone !== expected}
        <div class="hint warn">The MLO defines {expected} numbered rooms but you have captured {roomsDone}. Anchor order must match {draft.roomName.replace('%d', '1')}…{draft.roomName.replace('%d', String(expected))}.</div>
      {/if}

      <button class="btn success wide" disabled={!ready} onclick={() => fetchNui('creator:save')}>
        Save to config/buildings.lua
      </button>
      <span class="hint">Writes the file and hot-updates the server. Restart the resource so clients pick it up.</span>
    </div>
  {/if}
</div>

<style>
  .layout {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 24px;
    height: 100%;
    min-height: 0;
  }

  .col {
    display: flex;
    flex-direction: column;
    gap: 10px;
    min-height: 0;
  }

  .section-title {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
    font-weight: 700;
    margin-top: 4px;
  }

  .scan {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 10px 12px;
    background: var(--dark-6);
    border: 1px solid var(--dark-4);
    border-radius: var(--radius-sm);
  }

  .scan-row {
    display: flex;
    justify-content: space-between;
    font-size: 12px;
    color: var(--dark-2);
  }

  .scan-row b {
    color: #fff;
  }

  .names {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    max-height: 90px;
  }

  .grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }

  .actions {
    display: grid;
    grid-template-columns: 2fr 1fr;
    gap: 8px;
  }

  .rooms {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-height: 60px;
    flex: 1;
  }

  .room {
    display: grid;
    grid-template-columns: 28px 1fr auto auto;
    align-items: center;
    gap: 8px;
    padding: 6px 8px;
    font-size: 11px;
    background: var(--dark-6);
    border-radius: var(--radius-sm);
  }

  .room-no {
    font-weight: 700;
    color: #fff;
  }

  .room-pos {
    color: var(--dark-2);
    font-variant-numeric: tabular-nums;
  }

  .mini {
    padding: 2px 7px;
    font-family: inherit;
    font-size: 11px;
    color: var(--dark-1);
    background: var(--dark-5);
    border: none;
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .mini:hover {
    background: var(--dark-4);
    color: #fff;
  }

  .mini.danger:hover {
    background: var(--red);
  }

  .warn {
    color: var(--yellow);
  }

  .wide {
    width: 100%;
  }
</style>
