local registered = {}

---@param id string
---@param option table
function AddPropertyRadial(id, option)
    if registered[id] then return end
    registered[id] = true
    option.id = id
    lib.addRadialItem(option)
end

---@param id string
function RemovePropertyRadial(id)
    if not registered[id] then return end
    registered[id] = nil
    lib.removeRadialItem(id)
end

function ClearPropertyRadials()
    for id in pairs(registered) do
        lib.removeRadialItem(id)
    end
    table.wipe(registered)
end

function AddDecorateRadial()
    AddPropertyRadial('qbx_properties_decorate', {
        label = 'Decorate',
        icon = 'couch',
        onSelect = function() StartDecorating() end
    })
end

function RemoveDecorateRadial()
    RemovePropertyRadial('qbx_properties_decorate')
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    ClearPropertyRadials()
end)
