ESX = exports["es_extended"]:getSharedObject()
local loadingScreenFinished = false
local ready = false
local guiEnabled = false

ESX.SecureNetEvent("esx_identity:alreadyRegistered", function()
    while not loadingScreenFinished do
        Wait(100)
    end
    TriggerEvent("esx_skin:playerRegistered")
end)

ESX.SecureNetEvent("esx_identity:setPlayerData", function(data)
    SetTimeout(1, function()
        ESX.SetPlayerData("name", ("%s %s"):format(data.firstName, data.lastName))
        ESX.SetPlayerData("firstName", data.firstName)
        ESX.SetPlayerData("lastName", data.lastName)
        ESX.SetPlayerData("dateofbirth", data.dateOfBirth)
        ESX.SetPlayerData("sex", data.sex)
        ESX.SetPlayerData("height", data.height)
    end)
end)

AddEventHandler("esx:loadingScreenOff", function()
    loadingScreenFinished = true
end)

RegisterNUICallback("ready", function(_, cb)
    ready = true
    cb(1)
end)

function setGuiState(state)
    guiEnabled = state

    SetNuiFocus(state, state)
    SetNuiFocusKeepInput(false)

    if state then
        CreateThread(function()
            local untilTime = GetGameTimer() + 1500
            while guiEnabled and GetGameTimer() < untilTime do
                SetNuiFocus(true, true)
                Wait(0)
            end
        end)
    end

    SendNUIMessage({ type = "enableui", enable = state })
end

RegisterNetEvent("esx_identity:showRegisterIdentity", function()
    TriggerEvent("esx_skin:resetFirstSpawn")
    while not (ready and loadingScreenFinished) do
        Wait(100)
    end

    if not ESX.PlayerData.firstName or not ESX.PlayerData.lastName then
        if not ESX.PlayerData.dead then
            SetTimeout(100, function()
                setGuiState(true)
            end)
        end
    end
end)

RegisterNUICallback("register", function(data, cb)
    if not guiEnabled then
        return
    end

    ESX.TriggerServerCallback("esx_identity:registerIdentity", function(callback)
        if not callback then
            return
        end

        ESX.ShowNotification(_U("thank_you_for_registering"))
        setGuiState(false)
    end, data)
    cb(1)
end)