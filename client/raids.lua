local police = require('config.crime').police

if not police.enabled then return end

local raidState = {}

---@param propertyId integer?
---@return boolean
function IsPropertyBreached(propertyId)
    local state = propertyId and raidState[propertyId]
    return state ~= nil and state.breached
end

---@param propertyId integer?
---@return boolean
function IsPropertyLockedDown(propertyId)
    local state = propertyId and raidState[propertyId]
    return state ~= nil and state.lockdown
end

---@return boolean
local function isOfficer()
    return IsPolice(QBX.PlayerData.job)
end

---@param item string?
---@return boolean
local function carrying(item)
    if not item then return true end
    if police.breachRequiresEquipped then return GetSelectedPedWeapon(cache.ped) == joaat(item) end

    return (exports.ox_inventory:GetItemCount(item) or 0) > 0
end

---@param propertyId integer?
---@param breached boolean?
function SetRaidState(propertyId, breached)
    if not propertyId then return end
    raidState[propertyId] = breached and { breached = true } or nil
end

RegisterNetEvent('qbx_properties:client:raidState', function(propertyId, state)
    raidState[propertyId] = state
end)

---Places the officer at a fixed spot in the door's local space so the swing lands the same way every time.
---The offset is mirrored when they stand on the far side, so this never drags anyone through the door.
---@param entity number?
local function alignToDoor(entity)
    if not entity or not DoesEntityExist(entity) then return end

    local offset = police.breachOffset
    local flip = 1.0

    if offset then
        local ped = GetEntityCoords(cache.ped)
        local current = GetOffsetFromEntityGivenWorldCoords(entity, ped.x, ped.y, ped.z)

        if (current.y < 0.0) ~= (offset.y < 0.0) then flip = -1.0 end

        local coords = GetOffsetFromEntityInWorldCoords(entity, offset.x * flip, offset.y * flip, offset.z)
        SetEntityCoordsNoOffset(cache.ped, coords.x, coords.y, coords.z, false, false, false)
    end

    local heading = GetEntityHeading(entity) + (police.breachHeadingOffset or 0.0) + (flip < 0.0 and 180.0 or 0.0)
    SetEntityHeading(cache.ped, heading % 360.0)
end

---@param propertyId integer
---@param entity number?
---@return boolean
function BreachDoor(propertyId, entity)
    if not carrying(police.breachItem) then
        lib.notify({ type = 'error', description = 'You need a battering ram.' })
        return false
    end

    if not DoesAnimDictExist(police.breachAnim.dict) then
        lib.print.warn(('anim dict %s is not streamed'):format(police.breachAnim.dict))
    end

    alignToDoor(entity)
    lib.requestAnimDict(police.breachAnim.dict, 60000)

    local breaching = true
    CreateThread(function()
        local sound = police.breachSound
        if not sound or not sound.phases then return end

        local target = (entity and DoesEntityExist(entity)) and entity or cache.ped
        local fired = {}
        local previous = 1.0

        while breaching do
            local phase = GetEntityAnimCurrentTime(cache.ped, police.breachAnim.dict, police.breachAnim.clip)

            if phase < previous then table.wipe(fired) end
            previous = phase

            for i = 1, #sound.phases do
                if not fired[i] and phase >= sound.phases[i] then
                    fired[i] = true
                    PlaySoundFromEntity(-1, sound.name, target, sound.set, false, 0)
                end
            end

            Wait(0)
        end
    end)

    local completed = lib.progressBar({
        duration = police.breachDuration,
        label = 'Breaching the door',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = {
            dict = police.breachAnim.dict,
            clip = police.breachAnim.clip,
            flag = 1,
        },
        prop = not police.breachRequiresEquipped and {
            model = police.breachProp.model,
            bone = police.breachProp.bone,
            pos = police.breachProp.pos,
            rot = police.breachProp.rot,
        } or nil,
    })

    breaching = false
    ClearPedTasks(cache.ped)
    RemoveAnimDict(police.breachAnim.dict)

    if not completed then return false end

    if not lib.callback.await('qbx_properties:callback:breachDoor', false, propertyId) then
        lib.notify({ type = 'error', description = 'The door held.' })
        return false
    end

    lib.notify({ type = 'success', description = 'Door breached.' })
    return true
end

---@param buildingKey string
---@return table[]
function GetRaidOptions(buildingKey)
    if not isOfficer() then return {} end

    local options = {}
    local raids = lib.callback.await('qbx_properties:callback:getActiveRaids', false, buildingKey)

    if #raids == 0 then
        options[#options + 1] = {
            title = 'Raid apartment',
            description = 'Enter the citizen ID of the resident to raid',
            icon = 'shield-halved',
            onSelect = function()
                local input = lib.inputDialog('Raid apartment', {
                    { type = 'input', label = 'Citizen ID', required = true, min = 1 },
                })
                if not input then return end

                local ok, name, floor, room = lib.callback.await('qbx_properties:callback:startRaid', false, buildingKey, input[1])
                if not ok then
                    lib.notify({ type = 'error', description = name or 'Could not open a raid.' })
                    return
                end

                lib.alertDialog({
                    header = 'Raid authorised',
                    content = string.format('Unit **%s**\n\nFloor %d, room %d.\n\nBreach the door with a battering ram. Return here to end the raid.', name, floor, room),
                    centered = true,
                })
            end
        }
        return options
    end

    for i = 1, #raids do
        local raid = raids[i]
        options[#options + 1] = {
            title = string.format('End raid: %s', raid.label),
            description = raid.breached and 'Breached — releases the unit' or 'Not yet breached',
            icon = 'lock',
            onSelect = function()
                if lib.callback.await('qbx_properties:callback:endRaid', false, raid.propertyId) then
                    lib.notify({ type = 'success', description = 'Raid ended.' })
                else
                    lib.notify({ type = 'error', description = 'Could not end the raid.' })
                end
            end
        }
    end

    return options
end

---@param propertyId integer
function ReturnProperty(propertyId)
    local nearby = lib.callback.await('qbx_properties:callback:getNearbyCitizens', false)
    local options = {}
    for i = 1, #nearby do
        options[i] = { value = nearby[i].citizenid, label = nearby[i].name }
    end

    local input = lib.inputDialog('Return property', {
        { type = 'select', label = 'Nearby', options = options, clearable = true },
        { type = 'input', label = 'Or citizen ID' },
    })
    if not input then return end

    local citizenId = input[1] or input[2]
    if not citizenId or citizenId == '' then return end

    local ok, message = lib.callback.await('qbx_properties:callback:returnProperty', false, propertyId, citizenId)
    lib.notify({ type = ok and 'success' or 'error', description = message })
    if ok then RefreshRaids() end
end

---@param propertyId integer
---@return table[]
function GetBreachedDoorOptions(propertyId)
    if not isOfficer() or not IsPropertyBreached(propertyId) then return {} end

    return {
        {
            name = 'qbx_properties_end_raid',
            label = 'End raid',
            icon = 'fa-solid fa-lock',
            distance = 2.0,
            onSelect = function()
                if lib.callback.await('qbx_properties:callback:endRaid', false, propertyId) then
                    lib.notify({ type = 'success', description = 'Raid ended.' })
                end
            end
        },
        {
            name = 'qbx_properties_lockdown',
            label = 'Lockdown property',
            icon = 'fa-solid fa-ban',
            distance = 2.0,
            onSelect = function()
                if lib.callback.await('qbx_properties:callback:lockdownProperty', false, propertyId) then
                    lib.notify({ type = 'success', description = 'Property placed under lockdown.' })
                else
                    lib.notify({ type = 'error', description = 'Could not lock down this property.' })
                end
            end
        },
        {
            name = 'qbx_properties_return',
            label = 'Return to owner',
            icon = 'fa-solid fa-key',
            distance = 2.0,
            onSelect = function() ReturnProperty(propertyId) end
        },
    }
end

local activeRaids = {}
local zones = {}

---@param coords vector3
---@return table? raid
local function raidAtCoords(coords)
    for i = 1, #activeRaids do
        if #(coords - activeRaids[i].coords) < 1.5 then return activeRaids[i] end
    end
end

local function clearZones()
    for i = 1, #zones do
        exports.ox_target:removeZone(zones[i])
    end
    zones = {}
end

function RefreshRaids()
    clearZones()
    activeRaids = {}
    if not isOfficer() then return end

    activeRaids = lib.callback.await('qbx_properties:callback:getRaidZones', false) or {}

    for i = 1, #activeRaids do
        local raid = activeRaids[i]
        raid.coords = vec3(raid.coords.x, raid.coords.y, raid.coords.z)
        raidState[raid.propertyId] = { breached = raid.breached, lockdown = raid.lockdown }

        if not raid.building then
            zones[#zones + 1] = exports.ox_target:addSphereZone({
                coords = raid.coords,
                radius = 1.5,
                options = raid.breached and GetBreachedDoorOptions(raid.propertyId) or {
                    {
                        name = 'qbx_properties_breach_' .. raid.propertyId,
                        label = 'Breach door',
                        icon = 'fa-solid fa-hammer',
                        distance = 2.0,
                        canInteract = function() return carrying(police.breachItem) end,
                        onSelect = function()
                            if BreachDoor(raid.propertyId) then RefreshRaids() end
                        end
                    }
                },
            })
        end
    end
end

RegisterNetEvent('qbx_properties:client:raidState', function()
    SetTimeout(250, RefreshRaids)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == cache.resource then clearZones() end
end)

CreateThread(function()
    local models = {}

    for _, building in pairs(Buildings) do
        local doors = building.roomLayout and building.roomLayout.doors
        if doors then
            for i = 1, #doors do
                models[doors[i].model] = true
            end
        end
    end

    for model in pairs(models) do
        exports.ox_target:addModel(model, {
            {
                name = 'qbx_properties_breach',
                label = 'Breach door',
                icon = 'fa-solid fa-hammer',
                distance = 2.0,
                canInteract = function(entity)
                    if not isOfficer() or not carrying(police.breachItem) then return false end
                    local raid = raidAtCoords(GetEntityCoords(entity))
                    return raid ~= nil and not raid.breached
                end,
                onSelect = function(data)
                    local raid = raidAtCoords(GetEntityCoords(data.entity))
                    if raid and BreachDoor(raid.propertyId, data.entity) then RefreshRaids() end
                end
            },
            {
                name = 'qbx_properties_raid_end',
                label = 'End raid',
                icon = 'fa-solid fa-lock',
                distance = 2.0,
                canInteract = function(entity)
                    if not isOfficer() then return false end
                    local raid = raidAtCoords(GetEntityCoords(entity))
                    return raid ~= nil and raid.breached
                end,
                onSelect = function(data)
                    local raid = raidAtCoords(GetEntityCoords(data.entity))
                    if raid and lib.callback.await('qbx_properties:callback:endRaid', false, raid.propertyId) then
                        lib.notify({ type = 'success', description = 'Raid ended.' })
                    end
                end
            },
            {
                name = 'qbx_properties_raid_lockdown',
                label = 'Lockdown property',
                icon = 'fa-solid fa-ban',
                distance = 2.0,
                canInteract = function(entity)
                    if not isOfficer() then return false end
                    local raid = raidAtCoords(GetEntityCoords(entity))
                    return raid ~= nil and raid.breached and not raid.lockdown
                end,
                onSelect = function(data)
                    local raid = raidAtCoords(GetEntityCoords(data.entity))
                    if not raid then return end
                    if lib.callback.await('qbx_properties:callback:lockdownProperty', false, raid.propertyId) then
                        lib.notify({ type = 'success', description = 'Property placed under lockdown.' })
                        RefreshRaids()
                    end
                end
            },
            {
                name = 'qbx_properties_raid_return',
                label = 'Return to owner',
                icon = 'fa-solid fa-key',
                distance = 2.0,
                canInteract = function(entity)
                    local player = QBX.PlayerData
                    if not isOfficer() and not IsRealtor(player.job) then return false end
                    local raid = raidAtCoords(GetEntityCoords(entity))
                    return raid ~= nil and raid.lockdown
                end,
                onSelect = function(data)
                    local raid = raidAtCoords(GetEntityCoords(data.entity))
                    if raid then ReturnProperty(raid.propertyId) end
                end
            },
        })
    end

    Wait(2500)
    RefreshRaids()
end)

---@param coords vector3
---@return integer? propertyId, string? label
function ResolveEntryProperty(coords)
    local list = lib.callback.await('qbx_properties:callback:requestProperties', false, coords)
    if not list or #list == 0 then return end
    if #list == 1 then return list[1].id, list[1].property_name end

    local options = {}
    for i = 1, #list do
        options[i] = { value = list[i].id, label = list[i].property_name }
    end

    local input = lib.inputDialog('Which property?', {
        { type = 'select', label = 'Property', options = options, required = true },
    })
    if not input then return end

    for i = 1, #list do
        if list[i].id == input[1] then return list[i].id, list[i].property_name end
    end
end

CreateThread(function()
    local entrances = lib.callback.await('qbx_properties:callback:loadProperties') or {}

    for i = 1, #entrances do
        local coords = entrances[i]

        exports.ox_target:addSphereZone({
            coords = coords,
            radius = 1.5,
            options = {
                {
                    name = 'qbx_properties_entry_breach',
                    label = 'Breach door',
                    icon = 'fa-solid fa-hammer',
                    distance = 2.0,
                    canInteract = function()
                        return isOfficer() and carrying(police.breachItem)
                    end,
                    onSelect = function()
                        local propertyId = ResolveEntryProperty(coords)
                        if not propertyId or IsPropertyBreached(propertyId) then return end
                        BreachDoor(propertyId)
                    end
                },
                {
                    name = 'qbx_properties_entry_endraid',
                    label = 'End raid',
                    icon = 'fa-solid fa-lock',
                    distance = 2.0,
                    canInteract = function() return isOfficer() end,
                    onSelect = function()
                        local propertyId = ResolveEntryProperty(coords)
                        if not propertyId or not IsPropertyBreached(propertyId) then return end
                        if lib.callback.await('qbx_properties:callback:endRaid', false, propertyId) then
                            lib.notify({ type = 'success', description = 'Raid ended.' })
                        end
                    end
                },
            },
        })
    end
end)
