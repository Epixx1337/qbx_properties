const fs = require('fs');
const path = require('path');

const RESOURCE_NAME = GetCurrentResourceName();
const SCREENSHOTS_DIR = path.join(GetResourcePath(RESOURCE_NAME), 'screenshots');

if (!fs.existsSync(SCREENSHOTS_DIR)) fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });

function reply(id, result) {
  emit('qbx_properties:internal:shotResult', id, result);
}

on('qbx_properties:internal:shotWrite', (id, filename, base64) => {
  try {
    if (typeof filename !== 'string' || !/^[\w-]+$/.test(filename)) {
      return reply(id, { ok: false, error: 'unsafe filename' });
    }
    if (typeof base64 !== 'string' || base64.length > 2_000_000) {
      return reply(id, { ok: false, error: 'bad payload' });
    }
    const raw = base64.replace(/^data:image\/\w+;base64,/, '');
    const buffer = Buffer.from(raw, 'base64');
    if (buffer.length < 16 || buffer.toString('ascii', 0, 4) !== 'RIFF'
      || buffer.toString('ascii', 8, 12) !== 'WEBP') {
      return reply(id, { ok: false, error: 'not a webp' });
    }
    fs.writeFileSync(path.join(SCREENSHOTS_DIR, `${filename}.webp`), buffer);
    reply(id, { ok: true, file: `${filename}.webp` });
  } catch (err) {
    reply(id, { ok: false, error: String(err) });
  }
});

on('qbx_properties:internal:shotList', (id) => {
  try {
    const files = fs.readdirSync(SCREENSHOTS_DIR).filter((file) => file.endsWith('.webp'));
    reply(id, { ok: true, files });
  } catch (err) {
    reply(id, { ok: false, error: String(err) });
  }
});

const TUNING_PATH = path.join(SCREENSHOTS_DIR, '_tuning.json');

on('qbx_properties:internal:getTuning', (id) => {
  try {
    const tuning = fs.existsSync(TUNING_PATH) ? JSON.parse(fs.readFileSync(TUNING_PATH, 'utf8')) : {};
    reply(id, { ok: true, tuning });
  } catch (err) {
    reply(id, { ok: true, tuning: {} });
  }
});

on('qbx_properties:internal:saveTuning', (id, tuning) => {
  try {
    fs.writeFileSync(TUNING_PATH, JSON.stringify(tuning ?? {}, null, 2));
    reply(id, { ok: true });
  } catch (err) {
    reply(id, { ok: false, error: String(err) });
  }
});

const CDN_PATH = path.join(SCREENSHOTS_DIR, '_cdn.json');

let cdnMap = {};
try {
  if (fs.existsSync(CDN_PATH)) cdnMap = JSON.parse(fs.readFileSync(CDN_PATH, 'utf8'));
} catch { cdnMap = {}; }
for (const [key, value] of Object.entries(cdnMap)) {
  if (typeof value === 'string') cdnMap[key] = { url: value };
}

function saveCdnMap() {
  fs.writeFileSync(CDN_PATH, JSON.stringify(cdnMap, null, 2));
}

function responseField(value, fieldPath) {
  for (const key of fieldPath.split('.')) {
    if (typeof value !== 'object' || value === null) return;
    value = value[key];
  }
  return typeof value === 'string' ? value : undefined;
}

async function deleteRemote(entry, provider) {
  if (!entry?.path || !provider.deleteUrl) return;
  try {
    const res = await fetch(provider.deleteUrl.replace('%s', encodeURIComponent(entry.path)), {
      method: 'DELETE',
      headers: { Authorization: provider.apiKey },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) console.log(`^3[qbx_properties] cdn delete returned ${res.status} for ${entry.path}^0`);
  } catch (err) {
    console.log(`^3[qbx_properties] cdn delete failed for ${entry.path}: ${err}^0`);
  }
}

async function uploadFile(relPath, provider) {
  const filePath = path.join(SCREENSHOTS_DIR, relPath);
  if (!filePath.startsWith(SCREENSHOTS_DIR) || !fs.existsSync(filePath)) {
    return { ok: false, error: 'file not found' };
  }
  const form = new FormData();
  form.append(provider.field || 'file',
    new Blob([fs.readFileSync(filePath)], { type: 'image/webp' }),
    relPath.replace(/[\\/]/g, '_'));
  const res = await fetch(provider.url, {
    method: 'POST',
    headers: { Authorization: provider.apiKey },
    body: form,
    signal: AbortSignal.timeout(30_000),
  });
  if (!res.ok) return { ok: false, error: `http ${res.status}` };
  const json = await res.json().catch(() => null);
  const url = json && responseField(json, provider.responsePath || 'url');
  if (!url) return { ok: false, error: 'no url in response' };

  const previous = cdnMap[relPath];
  if (previous && previous.url !== url) await deleteRemote(previous, provider);

  const storagePath = provider.storagePath ? responseField(json, provider.storagePath) : undefined;
  cdnMap[relPath] = storagePath ? { url, path: storagePath } : { url };
  saveCdnMap();
  return { ok: true, url };
}

on('qbx_properties:internal:cdnUpload', (id, relPath, provider) => {
  uploadFile(String(relPath), provider)
    .then((result) => reply(id, result))
    .catch((err) => reply(id, { ok: false, error: String(err) }));
});

on('qbx_properties:internal:cdnMap', (id) => {
  const map = {};
  for (const [key, entry] of Object.entries(cdnMap)) map[key] = entry.url;
  reply(id, { ok: true, map });
});

const uploadQueue = [];
let uploading = false;

async function drainQueue() {
  if (uploading) return;
  uploading = true;
  while (uploadQueue.length > 0) {
    const { relPath, provider } = uploadQueue.shift();
    try {
      const result = await uploadFile(relPath, provider);
      if (!result.ok) console.log(`^3[qbx_properties] cdn upload failed for ${relPath}: ${result.error}^0`);
    } catch (err) {
      console.log(`^3[qbx_properties] cdn upload failed for ${relPath}: ${err}^0`);
    }
  }
  uploading = false;
}

on('qbx_properties:internal:cdnQueue', (relPath, provider) => {
  uploadQueue.push({ relPath: String(relPath), provider });
  drainQueue();
});
