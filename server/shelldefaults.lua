local POINTS <const> = { 'exit', 'stash', 'clothing', 'logout' }
local FILE <const> = 'config/shell_defaults.lua'

local shellDefaults = {}

local function loadDefaults()
    local raw = LoadResourceFile(cache.resource, FILE)
    if not raw then return end

    local chunk = load(raw, FILE, 't', _ENV)
    local ok, result = pcall(chunk)
    if ok and type(result) == 'table' then shellDefaults = result end
end

local function serialise()
    local lines = { 'return {' }

    for interior, points in pairs(shellDefaults) do
        lines[#lines + 1] = string.format("    ['%s'] = {", interior)
        for i = 1, #POINTS do
            local point = points[POINTS[i]]
            if point then
                lines[#lines + 1] = string.format('        %s = vec4(%.4f, %.4f, %.4f, %.4f),', POINTS[i], point.x, point.y, point.z, point.w or 0.0)
            end
        end
        lines[#lines + 1] = '    },'
    end

    lines[#lines + 1] = '}'
    return table.concat(lines, '\n') .. '\n'
end

CreateThread(loadDefaults)

---@param interior string
---@return table?
local function resolveDefaults(interior)
    local entry = shellDefaults[interior]
    if entry then return entry end

    local hash = tonumber(interior)
    if hash then
        for key, points in pairs(shellDefaults) do
            if joaat(key) == hash then return points end
        end
    end
end

lib.callback.register('qbx_properties:callback:getShellDefaults', function(_, interior)
    if type(interior) ~= 'string' then return end
    return resolveDefaults(interior)
end)

lib.callback.register('qbx_properties:callback:saveShellDefaults', function(source, interior, points)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or not IsRealtor(player.PlayerData.job) then return false end
    if type(interior) ~= 'string' or type(points) ~= 'table' then return false end

    local hash = tonumber(interior)
    if hash then
        for key in pairs(shellDefaults) do
            if joaat(key) == hash then
                interior = key
                break
            end
        end
    end

    local sanitised = {}
    for i = 1, #POINTS do
        local point = points[POINTS[i]]
        if type(point) == 'table' then
            local x, y, z, w = tonumber(point.x), tonumber(point.y), tonumber(point.z), tonumber(point.w)
            if x and y and z then
                sanitised[POINTS[i]] = { x = x, y = y, z = z, w = w or 0.0 }
            end
        end
    end

    shellDefaults[interior] = sanitised

    return SaveResourceFile(cache.resource, FILE, serialise(), -1) and true or false
end)

---@param interior string
---@return table?
function GetShellDefaults(interior)
    return resolveDefaults(interior)
end
