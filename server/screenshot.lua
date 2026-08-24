local config = require 'config.server'

local pending = {}
local counter = 0

AddEventHandler('qbx_properties:internal:shotResult', function(id, result)
    local p = pending[id]
    if not p then return end
    pending[id] = nil
    p:resolve(result)
end)

local function requestCapture(event, ...)
    counter += 1
    local id = counter
    local p = promise.new()
    pending[id] = p
    TriggerEvent(event, id, ...)
    SetTimeout(15000, function()
        if pending[id] then
            pending[id] = nil
            p:resolve({ ok = false, error = 'timeout' })
        end
    end)
    return Citizen.Await(p)
end

local imageProviders = {
    qbox = {
        url = 'https://api.qbox.re/v1/file', field = 'file', responsePath = 'data.url',
        storagePath = 'data.path', deleteUrl = 'https://api.qbox.re/v1/file/%s',
    },
    fivemanage = {
        url = 'https://api.fivemanage.com/api/v3/file', field = 'file', responsePath = 'data.url',
        storagePath = 'data.id', deleteUrl = 'https://api.fivemanage.com/api/v3/file/%s',
    },
    fivemerr = { url = 'https://api.fivemerr.com/v1/media/images', field = 'file', responsePath = 'url' },
}

local function imageProvider()
    local cfg = config.imageUpload
    if not cfg or not cfg.apiKey or cfg.apiKey == '' then return end
    local provider = cfg.provider == 'custom' and cfg.custom or imageProviders[cfg.provider]
    if not provider or not provider.url or provider.url == '' then return end
    return {
        url = provider.url,
        field = provider.field or 'file',
        responsePath = provider.responsePath or 'url',
        storagePath = provider.storagePath,
        deleteUrl = provider.deleteUrl,
        apiKey = cfg.apiKey,
    }
end

local function isAdmin(source)
    return exports.qbx_core:HasPermission(source, 'admin')
end

lib.callback.register('qbx_properties:callback:furnitureShotWrite', function(source, filename, base64)
    if not isAdmin(source) then return { ok = false, error = 'no permission' } end
    local result = requestCapture('qbx_properties:internal:shotWrite', tostring(filename), base64)
    if result and result.ok and result.file and config.imageUpload and config.imageUpload.autoUpload then
        local provider = imageProvider()
        if provider then
            TriggerEvent('qbx_properties:internal:cdnQueue', result.file, provider)
        end
    end
    return result
end)

lib.callback.register('qbx_properties:callback:furnitureShotList', function(source)
    if not isAdmin(source) then return { ok = false } end
    return requestCapture('qbx_properties:internal:shotList')
end)

lib.callback.register('qbx_properties:callback:furnitureShotTuning', function(source)
    if not isAdmin(source) then return { ok = false } end
    return requestCapture('qbx_properties:internal:getTuning')
end)

lib.callback.register('qbx_properties:callback:furnitureShotSaveTuning', function(source, tuning)
    if not isAdmin(source) or type(tuning) ~= 'table' then return { ok = false } end
    return requestCapture('qbx_properties:internal:saveTuning', tuning)
end)

lib.callback.register('qbx_properties:callback:furnitureCdnMap', function()
    local result = requestCapture('qbx_properties:internal:cdnMap')
    return result and result.ok and result.map or {}
end)

local cdnSyncing = false

local function cdnSync(source, mode)
    local provider = imageProvider()
    if not provider then
        exports.qbx_core:Notify(source, 'No image upload provider configured, set imageUpload in config/server.lua.', 'error')
        return
    end
    if cdnSyncing then
        exports.qbx_core:Notify(source, 'An upload is already running.', 'error')
        return
    end

    local listed = requestCapture('qbx_properties:internal:shotList')
    if not listed or not listed.ok then
        exports.qbx_core:Notify(source, 'Could not list the screenshots.', 'error')
        return
    end
    local mapped = requestCapture('qbx_properties:internal:cdnMap')
    local map = mapped and mapped.ok and mapped.map or {}

    local missing = {}
    for i = 1, #listed.files do
        local file = listed.files[i]
        if mode == 'all' or not map[file] then missing[#missing + 1] = file end
    end
    if #missing == 0 then
        exports.qbx_core:Notify(source, 'Every screenshot is already on the CDN.', 'success')
        return
    end

    cdnSyncing = true
    exports.qbx_core:Notify(source, ('Uploading %d image(s) in the background.'):format(#missing), 'info')
    CreateThread(function()
        local failed = 0
        for i = 1, #missing do
            local result = requestCapture('qbx_properties:internal:cdnUpload', missing[i], provider)
            if not result or not result.ok then
                failed += 1
                lib.print.warn(('cdn upload failed for %s: %s'):format(missing[i], result and result.error or 'timeout'))
            end
            if i % 100 == 0 then
                lib.print.info(('cdn sync: %d/%d uploaded'):format(i, #missing))
            end
        end
        cdnSyncing = false
        lib.print.info(('cdn sync finished: %d uploaded, %d failed'):format(#missing - failed, failed))
        if GetPlayerName(source) then
            exports.qbx_core:Notify(source, ('CDN upload finished: %d uploaded, %d failed.'):format(#missing - failed, failed), failed > 0 and 'error' or 'success', 8000)
        end
    end)
end

lib.addCommand('screenshotfurniture', {
    help = 'Regenerate the furniture catalog images',
    params = {
        { name = 'mode', help = "'overwrite' reshoots existing images, 'manual' starts paused with full control, 'upload' pushes missing images to the CDN, 'uploadall' re-uploads everything", type = 'string', optional = true },
    },
    restricted = 'group.admin',
}, function(source, args)
    local mode = args.mode
    if mode == 'upload' or mode == 'uploadall' then
        cdnSync(source, mode == 'uploadall' and 'all' or 'missing')
        return
    end
    TriggerClientEvent('qbx_properties:client:screenshotFurniture', source, mode)
end)
