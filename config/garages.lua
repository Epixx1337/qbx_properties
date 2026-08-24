-- Adapters for third-party garage systems, used when garageSystem in config/shared.lua is not 'qbx'.
-- Every function receives { name, label, coords } where coords is the vec4 the player is standing at.
return {
    ['jg-advancedgarages'] = {
        open = function(garage)
            TriggerEvent('jg-advancedgarages:client:open-garage', garage.name, 'car', garage.coords)
        end,
        store = function(garage)
            TriggerEvent('jg-advancedgarages:client:store-vehicle', garage.name, 'car')
        end,
    },
    ['cd_garage'] = {
        open = function(garage)
            TriggerEvent('cd_garage:PropertyGarage:Open', garage.coords)
        end,
        store = function()
            TriggerEvent('cd_garage:PropertyGarage:StoreVehicle')
        end,
    },
    ['okokGarage'] = {
        open = function(garage)
            TriggerEvent('okokGarage:OpenPrivateGarageMenu', garage.coords.xyz, garage.coords.w)
        end,
        store = function()
            TriggerEvent('okokGarage:StoreVehiclePrivate')
        end,
    },
    custom = { -- wire any other garage system in here and set garageSystem = 'custom'
        open = function(garage) end, ---@diagnostic disable-line: unused-local
        store = function(garage) end, ---@diagnostic disable-line: unused-local
    },
}
