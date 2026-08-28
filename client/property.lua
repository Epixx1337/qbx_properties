local clientConfig = require 'config.client'
local sharedConfig = require 'config.shared'
local interiorShell
CurrentPropertyId = nil
PropertyAccess = { door = false, stash = false, furniture = false, garage = false }

---@param flags table?
function SetPropertyAccess(flags)
    PropertyAccess = flags or { door = false, stash = false, furniture = false, garage = false }
end

RegisterNetEvent('qbx_properties:client:accessFlags', function(flags)
    SetPropertyAccess(flags)
end)

DecorationObjects = {}
local properties = {}
local insideProperty = false
local isPropertyRental = false
local interactions
local isConcealing = false
local concealWhitelist = {}
local blips = {}

local function createBlip(apartmentCoords, label)
	local blip = AddBlipForCoord(apartmentCoords.x, apartmentCoords.y, apartmentCoords.z)
	SetBlipSprite(blip, 40)
	SetBlipAsShortRange(blip, true)
	SetBlipScale(blip, 0.8)
	SetBlipColour(blip, 2)
	BeginTextCommandSetBlipName('STRING')
	AddTextComponentString(label)
	EndTextCommandSetBlipName(blip)
	return blip
end

local function prepareKeyMenu()
    local keyholders = lib.callback.await('qbx_properties:callback:requestKeyHolders')
    local options = {
        {
            title = locale('menu.add_keyholder'),
            icon = 'plus',
            arrow = true,
            onSelect = function()
                local insidePlayers = lib.callback.await('qbx_properties:callback:requestPotentialKeyholders')
                local options = {}
                for i = 1, #insidePlayers do
                    options[#options + 1] = {
                        title = insidePlayers[i].name,
                        icon = 'user',
                        arrow = true,
                        onSelect = function()
                            local alert = lib.alertDialog({
                                header = insidePlayers[i].name,
                                content = locale('alert.give_keys'),
                                centered = true,
                                cancel = true
                            })
                            if alert == 'confirm' then
                                TriggerServerEvent('qbx_properties:server:addKeyholder', insidePlayers[i].citizenid)
                            end
                        end
                    }
                end
                lib.registerContext({
                    id = 'qbx_properties_insideMenu',
                    title = locale('menu.people_inside'),
                    menu = 'qbx_properties_keyMenu',
                    options = options
                })
                lib.showContext('qbx_properties_insideMenu')
            end
        }
    }
    for i = 1, #keyholders do
        options[#options + 1] = {
            title = keyholders[i].name,
            icon = 'user',
            arrow = true,
            onSelect = function()
                local alert = lib.alertDialog({
                    header = keyholders[i].name,
                    content = locale('alert.want_remove_keys'),
                    centered = true,
                    cancel = true
                })
                if alert == 'confirm' then
                    TriggerServerEvent('qbx_properties:server:removeKeyholder', keyholders[i].citizenid)
                end
            end
        }
    end
    lib.registerContext({
        id = 'qbx_properties_keyMenu',
        title = locale('menu.keyholders'),
        menu = 'qbx_properties_manageMenu',
        options = options
    })
    lib.showContext('qbx_properties_keyMenu')
end

local function prepareDoorbellMenu()
    local ringers = lib.callback.await('qbx_properties:callback:requestRingers')
    local options = {}
    for i = 1, #ringers do
        options[#options + 1] = {
            title = ringers[i].name,
            icon = 'user',
            arrow = true,
            onSelect = function()
                local alert = lib.alertDialog({
                    header = ringers[i].name,
                    content = locale('alert.want_let_person_in'),
                    centered = true,
                    cancel = true
                })
                if alert == 'confirm' then
                    TriggerServerEvent('qbx_properties:server:letRingerIn', ringers[i].citizenid)
                end
            end
        }
    end
    lib.registerContext({
        id = 'qbx_properties_doorbellMenu',
        title = locale('menu.doorbell_ringers'),
        menu = 'qbx_properties_manageMenu',
        options = options
    })
    lib.showContext('qbx_properties_doorbellMenu')
end

local function prepareManageMenu()
    local hasAccess = lib.callback.await('qbx_properties:callback:checkAccess')
    if not hasAccess then exports.qbx_core:Notify(locale('notify.no_access'), 'error') return end
    local options = {
        {
            title = locale('menu.manage_keys'),
            icon = 'key',
            arrow = true,
            onSelect = function()
                prepareKeyMenu()
            end
        },
        {
            title = locale('menu.doorbell'),
            icon = 'bell',
            arrow = true,
            onSelect = function()
                prepareDoorbellMenu()
            end
        },
        {
            title = locale('menu.start_decorating'),
            icon = 'shrimp',
            onSelect = function()
                ToggleDecorating()
            end
        }
    }
    if isPropertyRental then
        options[#options+1] = {
            title = 'Stop Renting',
            icon = 'file-invoice-dollar',
            arrow = true,
            onSelect = function()
                local alert = lib.alertDialog({
                    header = 'Stop Renting',
                    content = 'Are you sure that you want to stop renting this place?',
                    centered = true,
                    cancel = true
                })
                if alert == 'confirm' then
                    TriggerServerEvent('qbx_properties:server:stopRenting')
                end
            end
        }
    end
    lib.registerContext({
        id = 'qbx_properties_manageMenu',
        title = locale('menu.manage_property'),
        options = options
    })
    lib.showContext('qbx_properties_manageMenu')
end

local function canUseStash()
    return PropertyAccess.stash or (IsPropertyBreached and IsPropertyBreached(CurrentPropertyId)) or false
end

local function openPropertyStash()
    TriggerServerEvent('qbx_properties:server:openStash')
end

local function exitPropertyInteract()
    DoScreenFadeOut(1000)
    while not IsScreenFadedOut() do Wait(0) end
    TriggerServerEvent('qbx_properties:server:exitProperty')
end

local function openClothingInteract()
    exports['illenium-appearance']:startPlayerCustomization(function(appearance)
        if appearance then
            TriggerServerEvent("illenium-appearance:server:saveAppearance", appearance)
        end
    end, {
        components = true, componentConfig = { masks = true, upperBody = true, lowerBody = true, bags = true, shoes = true, scarfAndChains = true, bodyArmor = true, shirts = true, decals = true, jackets = true },
        props = true, propConfig = { hats = true, glasses = true, ear = true, watches = true, bracelets = true },
        enableExit = true,
    })
end

local function openOutfitsInteract()
    TriggerEvent('illenium-appearance:client:openOutfitMenu')
end

local function logoutInteract()
    DoScreenFadeOut(1000)
    while not IsScreenFadedOut() do Wait(0) end
    TriggerServerEvent('qbx_properties:server:logoutProperty')
end

local function checkInteractions()
    local interactOptions = {
        ['stash'] = function(coords)
            if not canUseStash() then return end
            qbx.drawText3d({ coords = coords, text = locale('drawtext.stash') })
            if IsControlJustPressed(0, 38) then
                openPropertyStash()
            end
        end,
        ['exit'] = function(coords)
            qbx.drawText3d({ coords = coords, text = locale('drawtext.exit') })
            if IsControlJustPressed(0, 38) then
                exitPropertyInteract()
            end
            if IsControlJustPressed(0, 47) then
                prepareManageMenu()
            end
        end,
        ['clothing'] = function(coords)
            qbx.drawText3d({ coords = coords, text = locale('drawtext.clothing') })
            if IsControlJustPressed(0, 38) then
                openClothingInteract()
            end
            if IsControlJustPressed(0, 47) then
                openOutfitsInteract()
            end
        end,
        ['logout'] = function(coords)
            if not sharedConfig.logoutEnabled then return end
            qbx.drawText3d({ coords = coords, text = locale('drawtext.logout') })
            if IsControlJustPressed(0, 38) then
                logoutInteract()
            end
        end,
    }
    CreateThread(function()
        while insideProperty do
            local sleep = 800
            local playerCoords = GetEntityCoords(cache.ped)
            for i = 1, #interactions do
                if #(playerCoords - interactions[i].coords) < 1.5 and not IsDecorating then
                    sleep = 0
                    interactOptions[interactions[i].type](interactions[i].coords)
                end
            end
            Wait(sleep)
        end
    end)
end

local interactionZones = {}

local function clearInteractionTargets()
    for i = 1, #interactionZones do
        exports.ox_target:removeZone(interactionZones[i])
    end
    table.wipe(interactionZones)
end

local function notDecorating()
    return not IsDecorating
end

local function createInteractionTargets()
    clearInteractionTargets()

    local targetOptions = {
        ['stash'] = function()
            return {
                {
                    label = 'Open stash',
                    icon = 'fas fa-box-open',
                    canInteract = function() return not IsDecorating and canUseStash() end,
                    onSelect = openPropertyStash,
                },
            }
        end,
        ['exit'] = function()
            return {
                {
                    label = 'Exit property',
                    icon = 'fas fa-door-open',
                    canInteract = notDecorating,
                    onSelect = exitPropertyInteract,
                },
                {
                    label = 'Manage property',
                    icon = 'fas fa-list',
                    canInteract = notDecorating,
                    onSelect = prepareManageMenu,
                },
            }
        end,
        ['clothing'] = function()
            return {
                {
                    label = 'Change clothing',
                    icon = 'fas fa-shirt',
                    canInteract = notDecorating,
                    onSelect = openClothingInteract,
                },
                {
                    label = 'Outfits',
                    icon = 'fas fa-person-booth',
                    canInteract = notDecorating,
                    onSelect = openOutfitsInteract,
                },
            }
        end,
        ['logout'] = function()
            if not sharedConfig.logoutEnabled then return end
            return {
                {
                    label = 'Log out',
                    icon = 'fas fa-bed',
                    canInteract = notDecorating,
                    onSelect = logoutInteract,
                },
            }
        end,
    }

    for i = 1, #interactions do
        local builder = targetOptions[interactions[i].type]
        local options = builder and builder()
        if options then
            for j = 1, #options do
                options[j].distance = TargetDistance('interaction', 2.0)
            end
            interactionZones[#interactionZones + 1] = exports.ox_target:addSphereZone({
                coords = interactions[i].coords,
                radius = 1.0,
                options = options,
            })
        end
    end
end

local function hideExterior(name)
    local models = clientConfig.exteriorHashs[name]
    if not models then return end
    CreateThread(function()
        while insideProperty do
            for i = 1, #models, 1 do
                EnableExteriorCullModelThisFrame(models[i])
            end
            Wait(0)
        end
    end)
end

RegisterNetEvent('qbx_properties:client:refreshInteractions', function(interactionsData)
    if not insideProperty then return end
    interactions = interactionsData
    if sharedConfig.targetShellInteractions then createInteractionTargets() end
end)

RegisterNetEvent('qbx_properties:client:updateInteractions', function(interactionsData, interiorString, isRental, propertyId)
    if propertyId then CurrentPropertyId = propertyId end

    if IsRealtor(QBX.PlayerData.job) and CurrentPropertyId and interiorString ~= 'mlo' then
        AddPropertyRadial('qbx_properties_points', {
            label = 'Interaction points',
            icon = 'location-dot',
            onSelect = function() StartPropertyPointEditor() end
        })
    end

    DoScreenFadeIn(1000)
    interactions = interactionsData
    insideProperty = true
    isPropertyRental = isRental
    if sharedConfig.targetShellInteractions then
        createInteractionTargets()
    else
        checkInteractions()
    end
    hideExterior(interiorString)

    if lib.callback.await('qbx_properties:callback:checkAccess', false) then
        AddDecorateRadial()
    end
end)

RegisterNetEvent('qbx_properties:client:createInterior', function(interiorHash, interiorCoords)
    lib.requestModel(interiorHash, 60000)
    interiorShell = CreateObjectNoOffset(interiorHash, interiorCoords.x, interiorCoords.y, interiorCoords.z, false, false, false)
    FreezeEntityPosition(interiorShell, true)
    SetModelAsNoLongerNeeded(interiorHash)
end)

RegisterNetEvent('qbx_properties:client:finishSpawn', function()
    DoScreenFadeIn(1000)
    FreezeEntityPosition(cache.ped, false)
end)

RegisterNetEvent('qbx_properties:client:loadDecorations', function(decorations)
    for i = 1, #decorations do
        SpawnDecoration(decorations[i])
    end
end)

RegisterNetEvent('qbx_properties:client:reloadDecorations', function(decorations)
    LoadRoomFurniture(decorations)
end)

RegisterNetEvent('qbx_properties:client:addDecoration', function(decoration)
    if type(decoration) ~= 'table' then return end
    SpawnDecoration(decoration)
end)

RegisterNetEvent('qbx_properties:client:removeDecoration', function(objectId)
    DespawnDecoration(objectId)
end)

RegisterNetEvent('qbx_properties:client:unloadProperty', function()
    RemovePropertyRadial('qbx_properties_points')
    clearInteractionTargets()

    DoScreenFadeIn(1000)
    if insideProperty then CurrentPropertyId = nil end
    insideProperty = false
    if DoesEntityExist(interiorShell) then DeleteEntity(interiorShell) end
    UnloadRoomFurniture()
    interiorShell = nil
    RemoveDecorateRadial()
end)

local function singlePropertyMenu(property, noBackMenu)
    local options = {}

    if IsRealtor(QBX.PlayerData.job) and not property.owner then
        options[#options + 1] = {
            title = 'Enter (realtor)',
            description = 'Inspect the property and adjust its interaction points',
            icon = 'briefcase',
            arrow = true,
            onSelect = function()
                DoScreenFadeOut(1000)
                while not IsScreenFadedOut() do Wait(0) end
            end,
            serverEvent = 'qbx_properties:server:enterProperty',
            args = { id = property.id }
        }
    end

    if QBX.PlayerData.citizenid == property.owner or QBX.PlayerData.citizenid == property.tenant or lib.table.contains(json.decode(property.keyholders), QBX.PlayerData.citizenid) then
        options[#options + 1] = {
            title = locale('menu.enter'),
            icon = 'cog',
            arrow = true,
            onSelect = function()
                DoScreenFadeOut(1000)
                while not IsScreenFadedOut() do Wait(0) end
            end,
            serverEvent = 'qbx_properties:server:enterProperty',
            args = { id = property.id }
        }
    elseif property.owner == nil then
        if property.rent_interval then
            options[#options + 1] = {
                title = 'Rent',
                icon = 'dollar-sign',
                arrow = true,
                onSelect = function()
                    local alert = lib.alertDialog({
                        header = string.format('Renting - %s', property.property_name),
                        content = string.format('Are you sure you want to rent %s for $%s which will be billed every %sh(s)?', property.property_name, property.price, property.rent_interval),
                        centered = true,
                        cancel = true
                    })
                    if alert == 'confirm' then
                        TriggerServerEvent('qbx_properties:server:rentProperty', property.id)
                    end
                end,
            }
        else
            options[#options + 1] = {
                title = 'Buy',
                icon = 'dollar-sign',
                arrow = true,
                onSelect = function()
                    local alert = lib.alertDialog({
                        header = string.format('Buying - %s', property.property_name),
                        content = string.format('Are you sure you want to buy %s for $%s?', property.property_name, property.price),
                        centered = true,
                        cancel = true
                    })
                    if alert == 'confirm' then
                        TriggerServerEvent('qbx_properties:server:buyProperty', property.id)
                    end
                end,
            }
        end
    else
        options[#options + 1] = {
            title = locale('menu.ring_doorbell'),
            icon = 'bell',
            arrow = true,
            serverEvent = 'qbx_properties:server:ringProperty',
            args = { id = property.id }
        }
    end
    local menu = 'qbx_properties_propertiesMenu'
    ---@diagnostic disable-next-line: cast-local-type
    if noBackMenu then menu = nil end
    lib.registerContext({
        id = 'qbx_properties_propertyMenu',
        title = property.property_name,
        menu = menu,
        options = options
    })
    lib.showContext('qbx_properties_propertyMenu')
end

local function propertyMenu(propertyList, owned)
    local options = {
        {
            title = locale('menu.retrieve_properties'),
            description = locale('menu.show_owned_properties'),
            icon = 'bars',
            onSelect = function()
                propertyMenu(propertyList, true)
            end
        }
    }
    for i = 1, #propertyList do
        if owned and propertyList[i].owner == QBX.PlayerData.citizenid or lib.table.contains(json.decode(propertyList[i].keyholders), QBX.PlayerData.citizenid) then
            options[#options + 1] = {
                title = propertyList[i].property_name,
                icon = 'home',
                arrow = true,
                onSelect = function()
                    singlePropertyMenu(propertyList[i])
                end
            }
        elseif not owned then
            options[#options + 1] = {
                title = propertyList[i].property_name,
                icon = 'home',
                arrow = true,
                onSelect = function()
                    singlePropertyMenu(propertyList[i])
                end
            }
        end
    end
    lib.registerContext({
        id = 'qbx_properties_propertiesMenu',
        title = locale('menu.properties'),
        options = options
    })
    lib.showContext('qbx_properties_propertiesMenu')
end

function PreparePropertyMenu(propertyCoords)
    local propertyList = lib.callback.await('qbx_properties:callback:requestProperties', false, propertyCoords)
    if #propertyList == 1 then
        singlePropertyMenu(propertyList[1], true)
    else
        propertyMenu(propertyList)
    end
end

local entranceZones = {}

local function refreshEntranceZones()
    for i = 1, #entranceZones do
        exports.ox_target:removeZone(entranceZones[i])
    end
    table.wipe(entranceZones)

    local label = locale('drawtext.view_property'):gsub('^%[E%]%s*%-?%s*', '')
    for i = 1, #properties do
        local coords = properties[i]
        entranceZones[#entranceZones + 1] = exports.ox_target:addSphereZone({
            coords = coords.xyz,
            radius = 1.6,
            options = {
                {
                    label = label,
                    icon = 'fas fa-house',
                    distance = TargetDistance('entrance', 2.0),
                    onSelect = function()
                        PreparePropertyMenu(coords)
                    end,
                },
            },
        })
    end
end

CreateThread(function()
    local apartmentOptions = GetApartmentOptions()
    for i = 1, #apartmentOptions do
        local data = apartmentOptions[i]

        if not blips[data.enter] then
            blips[data.enter] = createBlip(data.enter, data.label)
        end
    end

    properties = lib.callback.await('qbx_properties:callback:loadProperties')

    if sharedConfig.targetShellInteractions then
        refreshEntranceZones()
        return
    end

    while true do
        local sleep = 800
        local playerCoords = GetEntityCoords(cache.ped)
        for i = 1, #properties do
            if #(playerCoords - properties[i].xyz) < TargetDistance('entrance', 2.0) then
                sleep = 0
                qbx.drawText3d({ coords = properties[i].xyz, text = locale('drawtext.view_property') })
                if IsControlJustPressed(0, 38) then
                    PreparePropertyMenu(properties[i])
                end
            end
        end
        Wait(sleep)
    end
end)

local ownedBlips = {}

local function refreshOwnedBlips()
    for i = 1, #ownedBlips do
        RemoveBlip(ownedBlips[i])
    end
    table.wipe(ownedBlips)

    local owned = lib.callback.await('qbx_properties:callback:getMyBlips', false) or {}

    for i = 1, #owned do
        local entry = owned[i]
        ownedBlips[#ownedBlips + 1] = createBlip(entry.coords, entry.name)

        if entry.garage then
            local blip = AddBlipForCoord(entry.garage.x, entry.garage.y, entry.garage.z)
            SetBlipSprite(blip, 357)
            SetBlipAsShortRange(blip, true)
            SetBlipScale(blip, 0.7)
            SetBlipColour(blip, 3)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(entry.name .. ' Garage')
            EndTextCommandSetBlipName(blip)
            ownedBlips[#ownedBlips + 1] = blip
        end
    end
end

RegisterNetEvent('qbx_properties:client:refreshBlips', refreshOwnedBlips)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    SetTimeout(3000, refreshOwnedBlips)
end)

CreateThread(function()
    Wait(4000)
    if LocalPlayer.state.isLoggedIn then refreshOwnedBlips() end
end)

RegisterNetEvent('qbx_properties:client:concealPlayers', function(playerIds)
    local players = GetActivePlayers()
    for i = 1, #players do NetworkConcealPlayer(players[i], false, false) end
    concealWhitelist = playerIds
    if not isConcealing then
        isConcealing = true
        while isConcealing do
            players = GetActivePlayers()
            for i = 1, #players do
                if not lib.table.contains(concealWhitelist, GetPlayerServerId(players[i])) then
                    NetworkConcealPlayer(players[i], true, false)
                end
            end
            Wait(3000)
        end
    end
end)

RegisterNetEvent('qbx_properties:client:revealPlayers', function()
    local players = GetActivePlayers()
    for i = 1, #players do NetworkConcealPlayer(players[i], false, false) end
    isConcealing = false
end)

RegisterNetEvent('qbx_properties:client:addProperty', function(propertyCoords)
    if lib.table.contains(properties, propertyCoords) then return end
    properties[#properties + 1] = propertyCoords
    if sharedConfig.targetShellInteractions then refreshEntranceZones() end
end)

local ringZones = {}

local function refreshRingZones()
    for i = 1, #ringZones do
        exports.ox_target:removeZone(ringZones[i])
    end
    table.wipe(ringZones)

    local points = lib.callback.await('qbx_properties:callback:getRingPoints', false) or {}
    for i = 1, #points do
        local entry = points[i]
        ringZones[#ringZones + 1] = exports.ox_target:addSphereZone({
            coords = entry.coords,
            radius = 1.2,
            options = {
                {
                    name = string.format('qbx_properties_ring_%d_%d', entry.id, i),
                    label = 'Ring doorbell',
                    icon = 'fas fa-bell',
                    distance = TargetDistance('doorbell', 1.5),
                    onSelect = function()
                        TriggerServerEvent('qbx_properties:server:ringProperty', { id = entry.id })
                        lib.notify({ type = 'info', description = 'You rang the doorbell.' })
                    end,
                },
            },
        })
    end
end

RegisterNetEvent('qbx_properties:client:refreshBlips', refreshRingZones)
RegisterNetEvent('qbx_properties:client:invalidateUnitAccess', refreshRingZones)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', refreshRingZones)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= cache.resource then return end
    if LocalPlayer.state.isLoggedIn then refreshRingZones() end
end)

local mailboxZones = {}

local function refreshMailboxes()
    for i = 1, #mailboxZones do
        exports.ox_target:removeZone(mailboxZones[i])
    end
    table.wipe(mailboxZones)

    if not sharedConfig.mailbox or not sharedConfig.mailbox.enabled then return end

    local list = lib.callback.await('qbx_properties:callback:getMailboxes', false) or {}
    for i = 1, #list do
        local entry = list[i]
        mailboxZones[#mailboxZones + 1] = exports.ox_target:addSphereZone({
            coords = entry.coords,
            radius = 0.8,
            options = {
                {
                    label = 'Mailbox',
                    icon = 'fas fa-envelope',
                    distance = TargetDistance('mailbox', 2.0),
                    onSelect = function()
                        TriggerServerEvent('qbx_properties:server:openMailbox', entry.id)
                    end,
                },
            },
        })
    end
end

RegisterNetEvent('qbx_properties:client:refreshMailboxes', refreshMailboxes)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', refreshMailboxes)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= cache.resource then return end
    if LocalPlayer.state.isLoggedIn then refreshMailboxes() end
end)

RegisterNetEvent('qbx_properties:client:removeProperty', function(propertyCoords)
    for i = 1, #properties do
        if #(properties[i] - propertyCoords) < 0.05 then
            table.remove(properties, i)
            break
        end
    end
    if sharedConfig.targetShellInteractions then refreshEntranceZones() end
end)