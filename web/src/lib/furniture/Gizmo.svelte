<script>
  import { fetchNui } from '../nui.js'
  import { furniture } from '../store.svelte.js'

  const AXIS_PX = 96
  const RING_RADIUS = 0.65
  const RING_SEGMENTS = 32

  let drag = $state(null)

  const sync = $derived(furniture.gizmo)
  const mode = $derived(furniture.gizmoMode)
  const space = $derived(furniture.gizmoSpace)

  function rad(deg) {
    return (deg * Math.PI) / 180
  }

  function dot(a, b) {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
  }

  function cross(a, b) {
    return [
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0],
    ]
  }

  function basis(cam) {
    const pitch = rad(cam.rx)
    const yaw = rad(cam.rz)
    const cp = Math.cos(pitch)

    const forward = [-Math.sin(yaw) * cp, Math.cos(yaw) * cp, Math.sin(pitch)]
    const right = [Math.cos(yaw), Math.sin(yaw), 0]
    const up = cross(right, forward)
    return { forward, right, up }
  }

  // object rotation matrix columns = local axes (yaw-dominant furniture, ZXY-ish order)
  function localAxes(obj) {
    const x = rad(obj.rx ?? 0)
    const y = rad(obj.ry ?? 0)
    const z = rad(obj.rz ?? 0)

    const cx = Math.cos(x), sx = Math.sin(x)
    const cy = Math.cos(y), sy = Math.sin(y)
    const cz = Math.cos(z), sz = Math.sin(z)

    return [
      [cz * cy - sz * sx * sy, sz * cy + cz * sx * sy, -cx * sy],
      [-sz * cx, cz * cx, sx],
      [cz * sy + sz * sx * cy, sz * sy - cz * sx * cy, cx * cy],
    ]
  }

  function project(point, cam, view) {
    const v = [point[0] - cam.x, point[1] - cam.y, point[2] - cam.z]
    const cz = dot(v, view.forward)
    if (cz < 0.05) return null

    const tanV = Math.tan(rad(cam.fov) / 2)
    const aspect = window.innerWidth / window.innerHeight

    return {
      x: (0.5 + (dot(v, view.right) / (cz * tanV * aspect)) * 0.5) * window.innerWidth,
      y: (0.5 - (dot(v, view.up) / (cz * tanV)) * 0.5) * window.innerHeight,
    }
  }

  function mouseRay(mx, my, cam, view) {
    const tanV = Math.tan(rad(cam.fov) / 2)
    const aspect = window.innerWidth / window.innerHeight
    const ndcX = (mx / window.innerWidth) * 2 - 1
    const ndcY = 1 - (my / window.innerHeight) * 2

    const d = [
      view.forward[0] + view.right[0] * ndcX * tanV * aspect + view.up[0] * ndcY * tanV,
      view.forward[1] + view.right[1] * ndcX * tanV * aspect + view.up[1] * ndcY * tanV,
      view.forward[2] + view.right[2] * ndcX * tanV * aspect + view.up[2] * ndcY * tanV,
    ]
    const len = Math.hypot(d[0], d[1], d[2])
    return [d[0] / len, d[1] / len, d[2] / len]
  }

  function axisParam(origin, axis, cam, view, mx, my) {
    const d = mouseRay(mx, my, cam, view)
    const w0 = [origin[0] - cam.x, origin[1] - cam.y, origin[2] - cam.z]

    const b = dot(axis, d)
    const denom = 1 - b * b
    if (Math.abs(denom) < 1e-6) return null

    return (b * dot(d, w0) - dot(axis, w0)) / denom
  }

  function rayPlane(origin, normal, cam, view, mx, my) {
    const d = mouseRay(mx, my, cam, view)
    const denom = dot(normal, d)
    if (Math.abs(denom) < 1e-6) return null

    const s = (dot(normal, origin) - dot(normal, [cam.x, cam.y, cam.z])) / denom
    if (s < 0) return null

    return [cam.x + d[0] * s, cam.y + d[1] * s, cam.z + d[2] * s]
  }

  const AXES = [
    { key: 'x', index: 0, color: '#e5484d', euler: 'rx' },
    { key: 'y', index: 1, color: '#46a758', euler: 'ry' },
    { key: 'z', index: 2, color: '#3e8ef7', euler: 'rz' },
  ]

  const WORLD_DIRS = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]

  const view = $derived(sync ? basis(sync.cam) : null)
  const objPos = $derived(sync ? [sync.obj.x, sync.obj.y, sync.obj.z] : null)
  const objPoint = $derived(sync && view && objPos ? project(objPos, sync.cam, view) : null)
  // camera space keeps the arrows facing you: right/forward follow the view, recomputed every frame
  const dirs = $derived.by(() => {
    if (!sync) return WORLD_DIRS
    if (space === 'local') return localAxes(sync.obj)
    if (space === 'world') return WORLD_DIRS
    const yaw = rad(sync.cam.rz)
    return [
      [Math.cos(yaw), Math.sin(yaw), 0],
      [-Math.sin(yaw), Math.cos(yaw), 0],
      [0, 0, 1],
    ]
  })

  // rings edit euler components directly, so they stay on world or local axes
  const ringDirs = $derived.by(() => {
    if (!sync) return WORLD_DIRS
    return space === 'local' ? localAxes(sync.obj) : WORLD_DIRS
  })

  const arrows = $derived.by(() => {
    if (!sync || !view || !objPoint || mode !== 'translate') return []
    return AXES.map((axis) => {
      const dir = dirs[axis.index]
      const tip = project(
        [objPos[0] + dir[0], objPos[1] + dir[1], objPos[2] + dir[2]],
        sync.cam, view
      )
      if (!tip) return null

      let dx = tip.x - objPoint.x
      let dy = tip.y - objPoint.y
      const len = Math.hypot(dx, dy)
      if (len < 4) return null
      dx = (dx / len) * AXIS_PX
      dy = (dy / len) * AXIS_PX

      const x2 = objPoint.x + dx
      const y2 = objPoint.y + dy
      const nx = -dy / AXIS_PX
      const ny = dx / AXIS_PX

      return {
        ...axis, dir,
        x2, y2,
        head: `${x2 + (dx / AXIS_PX) * 14},${y2 + (dy / AXIS_PX) * 14} ${x2 + nx * 5.5},${y2 + ny * 5.5} ${x2 - nx * 5.5},${y2 - ny * 5.5}`,
      }
    }).filter(Boolean)
  })

  const rings = $derived.by(() => {
    if (!sync || !view || !objPos || mode !== 'rotate') return []
    return AXES.map((axis) => {
      const normal = ringDirs[axis.index]
      const u = ringDirs[(axis.index + 1) % 3]
      const v = ringDirs[(axis.index + 2) % 3]

      const points = []
      for (let i = 0; i <= RING_SEGMENTS; i++) {
        const theta = (i / RING_SEGMENTS) * Math.PI * 2
        const cos = Math.cos(theta) * RING_RADIUS
        const sin = Math.sin(theta) * RING_RADIUS
        const p = project([
          objPos[0] + u[0] * cos + v[0] * sin,
          objPos[1] + u[1] * cos + v[1] * sin,
          objPos[2] + u[2] * cos + v[2] * sin,
        ], sync.cam, view)
        if (!p) return null
        points.push(`${p.x},${p.y}`)
      }

      return { ...axis, normal, u, v, path: points.join(' ') }
    }).filter(Boolean)
  })

  function startArrowDrag(arrow, event) {
    if (!sync || !view) return
    const t0 = axisParam(objPos, arrow.dir, sync.cam, view, event.clientX, event.clientY)
    if (t0 === null) return
    drag = { kind: 'axis', dir: arrow.dir, origin: [...objPos], t0 }
    event.stopPropagation()
  }

  function startPlaneDrag(event) {
    if (!sync || !view) return
    const hit = rayPlane(objPos, [0, 0, 1], sync.cam, view, event.clientX, event.clientY)
    if (!hit) return
    drag = { kind: 'plane', origin: [...objPos], hit0: hit }
    event.stopPropagation()
  }

  function ringAngle(ring, hit) {
    const rel = [hit[0] - objPos[0], hit[1] - objPos[1], hit[2] - objPos[2]]
    return Math.atan2(dot(rel, ring.v), dot(rel, ring.u))
  }

  function startRingDrag(ring, event) {
    if (!sync || !view) return
    const hit = rayPlane(objPos, ring.normal, sync.cam, view, event.clientX, event.clientY)
    if (!hit) return
    drag = {
      kind: 'ring', ring,
      origin: [...objPos],
      angle0: ringAngle(ring, hit),
      value0: sync.obj[ring.euler] ?? 0,
    }
    event.stopPropagation()
  }

  function onMove(event) {
    if (!drag || !sync || !view) return

    if (drag.kind === 'axis') {
      const t = axisParam(drag.origin, drag.dir, sync.cam, view, event.clientX, event.clientY)
      if (t === null) return
      const delta = t - drag.t0
      fetchNui('gizmo:apply', {
        x: drag.origin[0] + drag.dir[0] * delta,
        y: drag.origin[1] + drag.dir[1] * delta,
        z: drag.origin[2] + drag.dir[2] * delta,
      })
    } else if (drag.kind === 'plane') {
      const hit = rayPlane(drag.origin, [0, 0, 1], sync.cam, view, event.clientX, event.clientY)
      if (!hit) return
      fetchNui('gizmo:apply', {
        x: drag.origin[0] + (hit[0] - drag.hit0[0]),
        y: drag.origin[1] + (hit[1] - drag.hit0[1]),
        z: drag.origin[2],
      })
    } else if (drag.kind === 'ring') {
      const hit = rayPlane(drag.origin, drag.ring.normal, sync.cam, view, event.clientX, event.clientY)
      if (!hit) return
      const delta = ((ringAngle(drag.ring, hit) - drag.angle0) * 180) / Math.PI
      fetchNui('gizmo:apply', { [drag.ring.euler]: (drag.value0 + delta) % 360 })
    }
  }

  function endDrag() {
    drag = null
  }
</script>

<svelte:window on:mousemove={onMove} on:mouseup={endDrag} />

{#if sync && objPoint}
  <svg class="gizmo" class:dragging={drag}>
    {#if mode === 'rotate'}
      {#each rings as ring (ring.key)}
        <g class="ring-group" onmousedown={(e) => startRingDrag(ring, e)} role="presentation">
          <polyline class="hit" points={ring.path} />
          <polyline class="ring" points={ring.path} stroke={ring.color} />
        </g>
      {/each}
    {:else}
      {#each arrows as arrow (arrow.key)}
        <g class="axis" onmousedown={(e) => startArrowDrag(arrow, e)} role="presentation">
          <line class="hit" x1={objPoint.x} y1={objPoint.y} x2={arrow.x2} y2={arrow.y2} />
          <line class="line" x1={objPoint.x} y1={objPoint.y} x2={arrow.x2} y2={arrow.y2} stroke={arrow.color} />
          <polygon class="head" points={arrow.head} fill={arrow.color} />
        </g>
      {/each}

      <rect
        class="plane"
        x={objPoint.x - 10} y={objPoint.y - 10} width="20" height="20"
        onmousedown={startPlaneDrag}
        role="presentation"
      />
    {/if}

    <circle class="center" cx={objPoint.x} cy={objPoint.y} r="4" />
  </svg>
{/if}

<style>
  .gizmo {
    position: fixed;
    inset: 0;
    width: 100vw;
    height: 100vh;
    pointer-events: none;
    z-index: 10;
  }

  .gizmo.dragging {
    pointer-events: auto;
    cursor: grabbing;
  }

  .axis,
  .plane,
  .ring-group {
    pointer-events: auto;
    cursor: grab;
  }

  .axis .hit {
    stroke: transparent;
    stroke-width: 16;
  }

  .axis .line {
    stroke-width: 3;
  }

  .axis:hover .line,
  .axis:hover .head {
    filter: brightness(1.45);
  }

  .ring-group .hit {
    fill: none;
    stroke: transparent;
    stroke-width: 14;
  }

  .ring-group .ring {
    fill: none;
    stroke-width: 2.5;
  }

  .ring-group:hover .ring {
    stroke-width: 3.5;
    filter: brightness(1.45);
  }

  .plane {
    fill: rgba(255, 255, 255, 0.22);
    stroke: rgba(255, 255, 255, 0.75);
    stroke-width: 1.5;
  }

  .plane:hover {
    fill: rgba(255, 255, 255, 0.42);
  }

  .center {
    fill: #fff;
    stroke: rgba(0, 0, 0, 0.45);
    stroke-width: 1.5;
  }
</style>
