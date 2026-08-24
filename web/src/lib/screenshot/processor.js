const FRAME_HEIGHT_FRAC = 0.92
const WORK_SIZE = 768
const MIN_LINE_PIXELS = 4
const ALPHA_THRESHOLD = 16

function loadImage(dataUri) {
    return new Promise((resolve, reject) => {
        const img = new Image()
        img.onload = () => resolve(img)
        img.onerror = () => reject(new Error('image load failed'))
        img.src = dataUri
    })
}

function frameCropped(img) {
    const side = Math.min(Math.round(img.naturalHeight * FRAME_HEIGHT_FRAC), img.naturalWidth, img.naturalHeight)
    const sx = Math.max(0, Math.round(img.naturalWidth / 2 - side / 2))
    const sy = Math.max(0, Math.round((img.naturalHeight - side) / 2))
    const w = Math.min(WORK_SIZE, side)

    const canvas = document.createElement('canvas')
    canvas.width = w
    canvas.height = w
    const ctx = canvas.getContext('2d', { willReadFrequently: true })
    ctx.drawImage(img, sx, sy, side, side, 0, 0, w, w)
    return { canvas, ctx, w }
}

function sampleBackdrop(px, w, h) {
    const spots = [
        [0.03, 0.03], [0.5, 0.02], [0.97, 0.03],
        [0.02, 0.5], [0.98, 0.5],
    ]
    const rs = [], gs = [], bs = []
    for (const [fx, fy] of spots) {
        const x = Math.min(w - 1, Math.round(w * fx))
        const y = Math.min(h - 1, Math.round(h * fy))
        const idx = (w * y + x) << 2
        rs.push(px[idx])
        gs.push(px[idx + 1])
        bs.push(px[idx + 2])
    }
    const median = (arr) => arr.sort((a, b) => a - b)[Math.floor(arr.length / 2)]
    return [median(rs), median(gs), median(bs)]
}

function dropStrayBlobs(p, w, h) {
    const labels = new Int32Array(w * h)
    const sizes = [0]
    const boxes = [null]
    const stack = []
    let count = 0

    for (let start = 0; start < w * h; start++) {
        if (labels[start] !== 0 || p[(start << 2) + 3] <= ALPHA_THRESHOLD) continue
        count++
        let size = 0
        let minX = w, maxX = 0, minY = h, maxY = 0
        labels[start] = count
        stack.push(start)
        while (stack.length > 0) {
            const idx = stack.pop()
            size++
            const x = idx % w
            const y = (idx / w) | 0
            if (x < minX) minX = x
            if (x > maxX) maxX = x
            if (y < minY) minY = y
            if (y > maxY) maxY = y
            if (x > 0 && labels[idx - 1] === 0 && p[((idx - 1) << 2) + 3] > ALPHA_THRESHOLD) { labels[idx - 1] = count; stack.push(idx - 1) }
            if (x < w - 1 && labels[idx + 1] === 0 && p[((idx + 1) << 2) + 3] > ALPHA_THRESHOLD) { labels[idx + 1] = count; stack.push(idx + 1) }
            if (y > 0 && labels[idx - w] === 0 && p[((idx - w) << 2) + 3] > ALPHA_THRESHOLD) { labels[idx - w] = count; stack.push(idx - w) }
            if (y < h - 1 && labels[idx + w] === 0 && p[((idx + w) << 2) + 3] > ALPHA_THRESHOLD) { labels[idx + w] = count; stack.push(idx + w) }
        }
        sizes.push(size)
        boxes.push({ minX, maxX, minY, maxY })
    }
    if (count < 2) return

    let main = 1
    for (let i = 2; i <= count; i++) {
        if (sizes[i] > sizes[main]) main = i
    }
    const keep = new Uint8Array(count + 1)
    keep[main] = 1
    const near = w * 0.1
    for (let i = 1; i <= count; i++) {
        if (keep[i]) continue
        if (sizes[i] >= sizes[main] * 0.05) { keep[i] = 1; continue }
        const a = boxes[i]
        const b = boxes[main]
        const dx = Math.max(0, a.minX - b.maxX, b.minX - a.maxX)
        const dy = Math.max(0, a.minY - b.maxY, b.minY - a.maxY)
        if (Math.max(dx, dy) <= near) keep[i] = 1
    }
    for (let i = 0; i < w * h; i++) {
        const label = labels[i]
        if (label !== 0 && keep[label] === 0) p[(i << 2) + 3] = 0
    }
}

function chromaKey(p, w, h) {
    const B = sampleBackdrop(p, w, h)
    const T0 = 45
    const T1 = 130
    const greenKey = B[1] > B[0] && B[1] > B[2]
    for (let i = 0; i < p.length; i += 4) {
        const dist = Math.abs(p[i] - B[0]) + Math.abs(p[i + 1] - B[1]) + Math.abs(p[i + 2] - B[2])
        let alpha = (dist - T0) / (T1 - T0)
        alpha = alpha < 0 ? 0 : alpha > 1 ? 1 : alpha
        if (alpha === 0) {
            p[i + 3] = 0
            continue
        }
        if (alpha < 1) {
            if (greenKey) {
                const cap = Math.max(p[i], p[i + 2])
                if (p[i + 1] > cap) p[i + 1] = cap
            } else if (B[0] > B[1] && B[2] > B[1]) {
                const cap = Math.max(p[i + 1], Math.min(p[i], p[i + 2]))
                if (p[i] > cap && p[i + 2] > cap) {
                    p[i] = cap
                    p[i + 2] = cap
                }
            }
        }
        p[i + 3] = Math.round(alpha * 255)
    }
}

export async function processPair(uri1, uri2, opaque) {
    if (opaque) {
        const img = await loadImage(uri1)
        const frame = frameCropped(img)
        const OUT_MAX = 512
        const MAX_BYTES = 55000
        const side = Math.min(frame.w, OUT_MAX)
        const out = document.createElement('canvas')
        out.width = side
        out.height = side
        out.getContext('2d').drawImage(frame.canvas, 0, 0, frame.w, frame.w, 0, 0, side, side)
        for (const quality of [0.9, 0.8, 0.7, 0.6, 0.5]) {
            const uri = out.toDataURL('image/webp', quality)
            if ((uri.length * 3) / 4 <= MAX_BYTES) {
                return { ok: true, clipped: false, visible: side * side, dataUri: uri }
            }
        }
        return { ok: false, error: 'image exceeds byte budget' }
    }
    if (!uri2) {
        const img = await loadImage(uri1)
        const a = frameCropped(img)
        const w = a.w
        const id1 = a.ctx.getImageData(0, 0, w, w)
        chromaKey(id1.data, w, w)
        return finalize(a, id1, w, w)
    }

    const [img1, img2] = await Promise.all([loadImage(uri1), loadImage(uri2)])
    const a = frameCropped(img1)
    const b = frameCropped(img2)
    const w = Math.min(a.w, b.w)
    const h = w

    const id1 = a.ctx.getImageData(0, 0, w, h)
    const id2 = b.ctx.getImageData(0, 0, w, h)
    const p1 = id1.data
    const p2 = id2.data

    const B1 = sampleBackdrop(p1, w, h)
    const B2 = sampleBackdrop(p2, w, h)

    const denom = [B1[0] - B2[0], B1[1] - B2[1], B1[2] - B2[2]]
    const usable = denom.map((d) => Math.abs(d) >= 60)
    if (!usable.some(Boolean)) {
        return { ok: false, error: 'backdrops identical — difference matte impossible' }
    }

    for (let i = 0; i < p1.length; i += 4) {
        let alphaSum = 0
        let n = 0
        for (let c = 0; c < 3; c++) {
            if (!usable[c]) continue
            alphaSum += 1 - (p1[i + c] - p2[i + c]) / denom[c]
            n++
        }
        let alpha = alphaSum / n
        alpha = alpha < 0 ? 0 : alpha > 1 ? 1 : alpha

        if (alpha < 0.04) {
            p1[i + 3] = 0
        } else {
            const safeA = Math.max(alpha, 0.05)
            for (let c = 0; c < 3; c++) {
                const value = (p1[i + c] - (1 - alpha) * B1[c]) / safeA
                p1[i + c] = value < 0 ? 0 : value > 255 ? 255 : Math.round(value)
            }
            p1[i + 3] = Math.round(alpha * 255)
        }
    }

    return finalize(a, id1, w, h)
}

function finalize(frame, imageData, w, h) {
    const p1 = imageData.data
    dropStrayBlobs(p1, w, h)

    let visible = 0
    const colCounts = new Uint32Array(w)
    const rowCounts = new Uint32Array(h)
    let rawMinX = w, rawMaxX = -1, rawMinY = h, rawMaxY = -1

    for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
            const idx = (w * y + x) << 2
            if (p1[idx + 3] > ALPHA_THRESHOLD) {
                visible++
                colCounts[x]++
                rowCounts[y]++
                if (x < rawMinX) rawMinX = x
                if (x > rawMaxX) rawMaxX = x
                if (y < rawMinY) rawMinY = y
                if (y > rawMaxY) rawMaxY = y
            }
        }
    }

    if (visible < 40) {
        return { ok: false, error: 'nothing visible after matting' }
    }

    let minX = 0, maxX = w - 1, minY = 0, maxY = h - 1
    while (minX < w && colCounts[minX] < MIN_LINE_PIXELS) minX++
    while (maxX >= 0 && colCounts[maxX] < MIN_LINE_PIXELS) maxX--
    while (minY < h && rowCounts[minY] < MIN_LINE_PIXELS) minY++
    while (maxY >= 0 && rowCounts[maxY] < MIN_LINE_PIXELS) maxY--
    if (minX > maxX || minY > maxY) {
        return { ok: false, error: 'nothing visible after matting' }
    }

    const clipped = rawMinX <= 3 || rawMinY <= 3 || rawMaxX >= w - 4 || rawMaxY >= h - 4

    const absorb = Math.round(w * 0.08)
    if (minX - rawMinX > 0 && minX - rawMinX <= absorb) minX = rawMinX
    if (rawMaxX - maxX > 0 && rawMaxX - maxX <= absorb) maxX = rawMaxX
    if (minY - rawMinY > 0 && minY - rawMinY <= absorb) minY = rawMinY
    if (rawMaxY - maxY > 0 && rawMaxY - maxY <= absorb) maxY = rawMaxY

    frame.ctx.putImageData(imageData, 0, 0)

    const pad = 10
    const cx = (minX + maxX) / 2
    const cy = (minY + maxY) / 2
    const cropSide = Math.min(Math.max(maxX - minX, maxY - minY) + pad * 2, w)
    const x0 = Math.max(0, Math.min(Math.round(cx - cropSide / 2), w - cropSide))
    const y0 = Math.max(0, Math.min(Math.round(cy - cropSide / 2), h - cropSide))

    const OUT_MAX = 512
    const MAX_BYTES = 55000
    const QUALITIES = [0.9, 0.8, 0.7, 0.6, 0.5]

    const encode = (side) => {
        const out = document.createElement('canvas')
        out.width = side
        out.height = side
        out.getContext('2d').drawImage(frame.canvas, x0, y0, cropSide, cropSide, 0, 0, side, side)
        for (const quality of QUALITIES) {
            const uri = out.toDataURL('image/webp', quality)
            if ((uri.length * 3) / 4 <= MAX_BYTES) return uri
        }
        return null
    }

    const outSide = Math.min(cropSide, OUT_MAX)
    const encoded = encode(outSide) ?? encode(Math.round(outSide * 0.7))
    if (!encoded) {
        return { ok: false, error: 'image exceeds byte budget' }
    }

    return { ok: true, clipped, visible, dataUri: encoded }
}
