-- Hook these into whatever dispatch resource the server runs, they receive the
-- entrance coords and the property name.
return {
    enabled = false,

    ---Someone forced a door with a lockpick.
    ---@param coords vector3
    ---@param propertyName string
    Burglary = function(coords, propertyName)
        -- TriggerEvent('police:client:policeAlert', coords, ('Break-in in progress at %s'):format(propertyName))
    end,

    ---The lockpick attempt failed and the door held.
    ---@param coords vector3
    ---@param propertyName string
    FailedBurglary = function(coords, propertyName)
    end,
}
