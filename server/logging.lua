local config = require 'config.server'

local webhook = config.logging and config.logging.discordWebhook
if webhook == '' then webhook = nil end

---@param source number
---@param event string
---@param message string
function LogAction(source, event, message)
    if not webhook then
        lib.logger(source, event, message)
        return
    end

    local player = source and source > 0 and exports.qbx_core:GetPlayer(source)
    local footer = player
        and string.format('%s (%s) · id %d', GetPlayerName(source), player.PlayerData.citizenid, source)
        or 'server'

    PerformHttpRequest(webhook, function() end, 'POST', json.encode({
        username = 'qbx_properties',
        embeds = {
            {
                title = event,
                description = message,
                color = 2201331,
                footer = { text = footer },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
            },
        },
    }), { ['Content-Type'] = 'application/json' })
end
