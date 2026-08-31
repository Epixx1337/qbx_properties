<script>
  import { fetchNui } from '../nui.js'

  let now = $state(new Date())

  $effect(() => {
    const timer = setInterval(() => (now = new Date()), 1000)
    return () => clearInterval(timer)
  })

  const pad = (n) => String(n).padStart(2, '0')
  const stamp = $derived(
    `${pad(now.getDate())}/${pad(now.getMonth() + 1)}/${now.getFullYear()}  ${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`
  )

  function onKeydown(event) {
    const key = event.key.toLowerCase()
    if (key === 'g' || key === 'escape') {
      event.preventDefault()
      fetchNui('doorcam:close')
    }
  }
</script>

<svelte:window on:keydown={onKeydown} />

<div class="doorcam">
  <div class="chip"><kbd>G</kbd> Close Camera Feed</div>

  <div class="rec">
    <span class="rec-dot"></span>
    <span class="rec-label">REC</span>
  </div>

  <div class="cam-label">DOORBELL CAM — LIVE</div>
  <div class="stamp">{stamp}</div>

  <div class="scanlines"></div>
  <div class="vignette"></div>
</div>

<style>
  .doorcam {
    position: fixed;
    inset: 0;
    pointer-events: none;
    font-family: 'Roboto Mono', monospace;
    color: #f1f1f1;
    text-shadow: 0 1px 3px rgba(0, 0, 0, 0.9);
  }

  .chip {
    position: absolute;
    top: 18px;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 9px 14px;
    font-family: 'Roboto', sans-serif;
    font-size: 14px;
    font-weight: 500;
    color: #fff;
    background: rgba(12, 13, 15, 0.82);
    border-radius: 6px;
    text-shadow: none;
    z-index: 3;
  }

  .chip kbd {
    display: inline-block;
    min-width: 18px;
    padding: 2px 6px;
    font-family: 'Roboto Mono', monospace;
    font-size: 12px;
    font-weight: 700;
    text-align: center;
    color: #0c0d0f;
    background: #f1f1f1;
    border-radius: 4px;
  }

  .rec {
    position: absolute;
    top: 26px;
    left: 34px;
    display: flex;
    align-items: center;
    gap: 10px;
    z-index: 3;
  }

  .rec-dot {
    width: 14px;
    height: 14px;
    background: #e03131;
    border-radius: 2px;
    animation: blink 1.2s steps(1) infinite;
  }

  .rec-label {
    font-size: 13px;
    letter-spacing: 0.18em;
  }

  @keyframes blink {
    50% {
      opacity: 0.15;
    }
  }

  .cam-label {
    position: absolute;
    left: 36px;
    bottom: 34px;
    font-size: 12px;
    letter-spacing: 0.22em;
    z-index: 3;
  }

  .stamp {
    position: absolute;
    right: 36px;
    bottom: 34px;
    font-size: 13px;
    letter-spacing: 0.08em;
    z-index: 3;
  }

  .scanlines {
    position: absolute;
    inset: 0;
    background: repeating-linear-gradient(0deg, rgba(0, 0, 0, 0.07) 0 1px, transparent 1px 3px);
    z-index: 1;
  }

  .vignette {
    position: absolute;
    inset: 0;
    background: radial-gradient(ellipse at center, transparent 58%, rgba(0, 0, 0, 0.42) 100%);
    z-index: 2;
  }
</style>
