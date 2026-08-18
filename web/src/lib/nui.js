const RESOURCE = 'qbx_properties'

export const isBrowser = !window.invokeNative

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

export function onMessage(action, handler) {
  handlers.set(action, handler)
}

window.addEventListener('message', (event) => {
  const { action, data } = event.data ?? {}
  const handler = handlers.get(action)
  if (handler) handler(data)
})

export function formatMoney(value) {
  return `$${Number(value ?? 0).toLocaleString('en-US')}`
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
