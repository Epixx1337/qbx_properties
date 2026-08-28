const RESOURCE = 'qbx_properties'

// embedded frames (third-party apps loading this UI in an iframe) have no invokeNative but still live inside NUI
export const isEmbedded = new URLSearchParams(window.location.search).has('app')
export const isBrowser = !window.invokeNative && !isEmbedded

export async function fetchNui(name, data = {}) {
  if (isBrowser) return null

  try {
    const response = await fetch(`https://${RESOURCE}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
    })
    return await response.json()
  } catch (err) {
    console.error(`fetchNui ${name} failed`, err)
    return null
  }
}

const handlers = new Map()
const channel = typeof BroadcastChannel !== 'undefined' ? new BroadcastChannel('qbx_properties_ui') : null

export function onMessage(action, handler) {
  handlers.set(action, handler)
}

function dispatch(action, data) {
  const handler = handlers.get(action)
  if (handler) handler(data)
}

window.addEventListener('message', (event) => {
  const { action, data, embedded } = event.data ?? {}
  if (!action) return

  if (embedded) {
    channel?.postMessage({ action, data })
    return
  }

  if (!isEmbedded) dispatch(action, data)
})

if (channel && isEmbedded) {
  channel.onmessage = (event) => {
    const { action, data } = event.data ?? {}
    if (action) dispatch(action, data)
  }
}

export function formatMoney(value) {
  return `$${Number(value ?? 0).toLocaleString('en-US')}`
}

// svelte action: sets a cover background-image only once the node scrolls into view,
// so long card grids (the market) fetch images the way lazy <img> tags do
export function lazyBackground(node, url) {
  let current = url ?? null
  let visible = false

  const apply = () => {
    if (!visible) return
    if (current) {
      node.style.backgroundImage = `url("${current}")`
      node.style.backgroundSize = 'cover'
      node.style.backgroundPosition = 'center'
    } else {
      node.style.backgroundImage = ''
    }
  }

  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          visible = true
          apply()
          observer.disconnect()
        }
      }
    },
    { rootMargin: '250px' }
  )

  observer.observe(node)

  return {
    update(next) {
      current = next ?? null
      apply()
    },
    destroy() {
      observer.disconnect()
    },
  }
}

export function formatRemaining(endTimestamp) {
  const remaining = endTimestamp - Math.floor(Date.now() / 1000)
  if (remaining <= 0) return 'Ending'

  const days = Math.floor(remaining / 86400)
  const hours = Math.floor((remaining % 86400) / 3600)
  const minutes = Math.floor((remaining % 3600) / 60)

  if (days > 0) return `${days}d ${hours}h`
  if (hours > 0) return `${hours}h ${minutes}m`
  return `${minutes}m`
}
