return {
    police = {
        enabled = true,
        jobs = { -- job name mapped to the minimum grade level allowed to raid
            police = 0,
        },
        requiresDuty = true,
        warrantItem = 'search_warrant', -- needed at a receptionist to open a raid, nil to skip the check
        breachItem = 'WEAPON_BATTERINGRAM', -- needed to breach a door
        breachRequiresEquipped = true, -- the ram must be in hand, not just carried
        breachDuration = 10000,
        breachHeadingOffset = 270.0, -- degrees relative to facing the door so the ram thrusts into it
        breachAnim = { dict = 'anim@batteringram', clip = 'breach_loop' },
        breachSound = {
            name = 'CRASH',
            set = 'PAPARAZZO_03A',
            phases = { 0.45 }, -- how far through the loop the ram lands, 0-1
        },
        breachProp = {
            model = `w_me_batteringram`,
            bone = 28422,
            pos = vec3(0.1, 0.05, 0.02),
            rot = vec3(10.0, 90.0, 170.0),
        },
    },

    robbery = {
        enabled = false,
        allowApartments = false, -- false limits robbery to standalone properties, true includes pooled apartment units
        item = 'advancedlockpick',
        removeOnSuccess = true,
        skillCheck = { 'hard', 'hard', 'hard' },
        cooldown = 300, -- seconds before the same door can be attempted again

        -- plays at the entrance when a lockpick attempt fails, `bank` streams a custom native audio file
        alarm = {
            enabled = true,
            bank = 'audiodirectory/qbx_properties_sounds',
            name = 'house_alarm_sp',
            set = 'qbx_properties_sounds',
            duration = 8000,
            interval = 1000,
            range = 30.0,
        },
    },
}
