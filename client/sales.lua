local targets = {}

local function clearTargets()
    for i = 1, #targets do
        exports.ox_target:removeZone(targets[i])
    end
    targets = {}
end

local function refreshTargets()
    clearTargets()
    if not IsRealtor(QBX.PlayerData.job) then return end

    local properties = lib.callback.await('qbx_properties:callback:getUnownedProperties', false)

    for i = 1, #properties do
        local property = properties[i]

        targets[#targets + 1] = exports.ox_target:addSphereZone({
            coords = property.coords,
            radius = 1.5,
            debug = false,
            options = {
                {
                    name = string.format('qbx_properties_view_%d', property.id),
                    label = string.format('View %s', property.name),
                    icon = 'fa-solid fa-door-open',
                    onSelect = function()
                        TriggerServerEvent('qbx_properties:server:enterProperty', { id = property.id })
                    end
                },
                {
                    name = string.format('qbx_properties_sell_%d', property.id),
                    label = string.format('Sell %s', property.name),
                    icon = 'fa-solid fa-handshake',
                    onSelect = function() OpenSellDialog(property) end
                }
            }
        })
    end
end

---@param property table
function OpenSellDialog(property)
    local nearby = lib.callback.await('qbx_properties:callback:getNearbyCitizens', false)

    local options = { { value = 'manual', label = 'Enter a citizen ID' } }
    for i = 1, #nearby do
        options[#options + 1] = { value = tostring(nearby[i].serverId), label = nearby[i].name }
    end

    local input = lib.inputDialog(string.format('Sell %s', property.name), {
        { type = 'select', label = 'Buyer', options = options, required = true },
        { type = 'input', label = 'Citizen ID', description = 'Only used when entering one manually' },
        { type = 'number', label = 'Price', default = property.price, min = 0, required = true },
    })
    if not input then return end

    local payload = { propertyId = property.id, price = input[3] }
    if input[1] == 'manual' then
        if not input[2] or input[2] == '' then
            lib.notify({ type = 'error', description = 'Enter a citizen ID.' })
            return
        end
        payload.citizenid = input[2]
    else
        payload.serverId = tonumber(input[1])
    end

    local ok, err = lib.callback.await('qbx_properties:callback:offerProperty', false, payload)
    lib.notify({
        type = ok and 'info' or 'error',
        description = ok and 'Offer sent. Waiting for their answer.' or (err or 'Could not send the offer.'),
    })
end

RegisterNetEvent('qbx_properties:client:propertyOffer', function(data)
    local accepted = lib.alertDialog({
        header = 'Property offer',
        content = string.format('**%s** is offering you **%s** for **$%s**.\n\nAccept?', data.seller, data.property, data.price),
        centered = true,
        cancel = true,
    })

    TriggerServerEvent('qbx_properties:server:respondToOffer', accepted == 'confirm')
end)

RegisterNetEvent('qbx_properties:client:refreshTargets', refreshTargets)
RegisterNetEvent('QBCore:Client:OnJobUpdate', refreshTargets)

CreateThread(function()
    Wait(3000)
    refreshTargets()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    clearTargets()
end)
