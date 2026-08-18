<script>
  let { images = [], index = $bindable(null) } = $props()

  function close() {
    index = null
  }

  function step(direction) {
    if (!images.length) return
    index = (index + direction + images.length) % images.length
  }

  function onKey(event) {
    if (index === null) return
    event.stopPropagation()

    if (event.key === 'Escape') {
      event.preventDefault()
      close()
    } else if (event.key === 'ArrowRight') {
      step(1)
    } else if (event.key === 'ArrowLeft') {
      step(-1)
    }
  }

  $effect(() => {
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
  })
</script>

{#if index !== null && images.length}
  <div class="overlay" onclick={close} role="dialog">
    <img src={images[Math.min(index, images.length - 1)]} alt="" onclick={(e) => e.stopPropagation()} />

    {#if images.length > 1}
      <button class="nav prev" onclick={(e) => { e.stopPropagation(); step(-1) }}>&lsaquo;</button>
      <button class="nav next" onclick={(e) => { e.stopPropagation(); step(1) }}>&rsaquo;</button>
      <span class="counter">{index + 1} / {images.length}</span>
    {/if}

    <button class="close" onclick={close}>×</button>
  </div>
{/if}

<style>
  .overlay {
    position: fixed;
    inset: 0;
    z-index: 50;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(0, 0, 0, 0.85);
    cursor: zoom-out;
  }

  .overlay img {
    max-width: 88vw;
    max-height: 88vh;
    border-radius: var(--radius-md);
    box-shadow: var(--shadow);
    cursor: default;
  }

  .nav {
    position: absolute;
    top: 50%;
    transform: translateY(-50%);
    width: 44px;
    height: 64px;
    font-size: 30px;
    line-height: 1;
    color: #fff;
    background: rgba(0, 0, 0, 0.5);
    border: none;
    border-radius: var(--radius-sm);
    cursor: pointer;
  }

  .nav:hover {
    background: rgba(0, 0, 0, 0.75);
  }

  .prev { left: 24px; }
  .next { right: 24px; }

  .counter {
    position: absolute;
    bottom: 20px;
    left: 50%;
    transform: translateX(-50%);
    font-size: 12px;
    color: var(--dark-1);
  }

  .close {
    position: absolute;
    top: 18px;
    right: 22px;
    width: 34px;
    height: 34px;
    font-size: 20px;
    color: #fff;
    background: rgba(0, 0, 0, 0.5);
    border: none;
    border-radius: 50%;
    cursor: pointer;
  }

  .close:hover {
    background: var(--red);
  }
</style>
