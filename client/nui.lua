local currentView = nil
local focused = false

---@param action string
---@param data any
function SendUI(action, data)
    SendNUIMessage({ action = action, data = data })
end

---@return string?
function GetUIView()
    return currentView
end

---@return boolean
function IsUIFocused()
    return focused
end

CreateThread(function()
    while true do
        if focused then
            DisableAllControlActions(0)
            Wait(0)
        else
            Wait(200)
        end
    end
end)

---@param value boolean
---@param keepInput boolean? let the game keep receiving input while the cursor stays usable
function SetUIFocus(value, keepInput)
    if not currentView then value, keepInput = false, false end
    focused = value and not keepInput
    SetNuiFocus(value, value)
    SetNuiFocusKeepInput(value and keepInput or false)
end

---@param view string
function OpenUI(view)
    currentView = view
    SendUI('theme', { color = GetConvar('ox:primaryColor', 'blue'), shade = GetConvarInt('ox:primaryShade', 8) })
    SendUI('setView', { view = view, isRealtor = IsRealtor(QBX.PlayerData.job) })
    SetUIFocus(true)
end

function CloseUI()
    currentView = nil
    focused = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendUI('setView', { view = nil })
end

function DismissUI()
    if currentView == 'furniture' and IsDecorating then
        RequestStopDecorating()
        return
    end

    if currentView == 'preview' then
        SetUIFocus(false)
        return
    end

    CloseUI()
end

RegisterNUICallback('close', function(_, cb)
    cb(1)
    DismissUI()
end)

RegisterNUICallback('setFocus', function(data, cb)
    cb(1)
    SetUIFocus(data == true or data?.focus == true)
end)

RegisterNUICallback('key', function(data, cb)
    cb(1)
    if type(data) ~= 'table' or not currentView then return end

    if data.key == 'Escape' then
        DismissUI()
    elseif data.key == 'e' and currentView == 'furniture' then
        SetCursorMode(HasPreviewObject())
        SetUIFocus(true, true)
        PushDecoratingState()
    elseif data.key == 'f' and currentView == 'furniture' then
        ToggleFreecam()
    elseif data.key == 'n' and currentView == 'furniture' then
        SnapToNeighbor()
    elseif data.key == 'h' and currentView == 'furniture' then
        SnapToWall()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end)
