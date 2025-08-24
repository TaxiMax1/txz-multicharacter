ESX = exports["es_extended"]:getSharedObject()
local nuiReady = false

CreateThread(function()
    while not ESX.PlayerLoaded do
        Wait(100)

        if NetworkIsPlayerActive(ESX.playerId) then
            ESX.DisableSpawnManager()
            Multicharacter:SetupCharacters()
            break
        end
    end
end)

ESX.SecureNetEvent("txz-multicharcater:SetupUI", function(characters, allowed, max)
    if not nuiReady then
        print(_U('nui_wait'))
        ESX.Await(function() return nuiReady == true end, _U('nui_failed', 10000), 10000)
    end
    Multicharacter:SetupUI(characters, allowed, max)
end)

RegisterNetEvent('esx:playerLoaded', function(playerData, isNew, skin)
    Multicharacter:PlayerLoaded(playerData, isNew, skin)
end)

ESX.SecureNetEvent('esx:onPlayerLogout', function()
    Wait(5000)

    Multicharacter.spawned = false

    Multicharacter:SetupCharacters()
    TriggerEvent("esx_skin:resetFirstSpawn")
end)

local relog = Config.Relog or {}
if relog.enabled and relog.command and relog.command ~= '' then
    RegisterCommand(relog.command, function()
        if not Multicharacter.canRelog then return end
        Multicharacter.canRelog = false
        TriggerServerEvent("txz-multicharcater:relog") 

        ESX.SetTimeout(500, function()
            Multicharacter.canRelog = true
        end)
    end, false)
end

RegisterNuiCallback('nuiReady', function(_, cb)
    nuiReady = true
    cb(1)
end)

---@diagnostic disable: duplicate-set-field
Multicharacter = {}
Multicharacter._index = Multicharacter
Multicharacter.canRelog = true
Multicharacter.Characters = {}
Multicharacter.hidePlayers = false

local function SetPedPosHeading(ped, x, y, z, h)
    h = (h or 0.0) % 360.0
    FreezeEntityPosition(ped, true)
    ClearPedTasksImmediately(ped)

    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, h)
    SetPedDesiredHeading(ped, h)
    Wait(250)
    SetEntityHeading(ped, h)

    FreezeEntityPosition(ped, false)
end

local function ReapplyHeading(ped, h)
    h = (h or 0.0) % 360.0
    SetEntityHeading(ped, h)
    SetPedDesiredHeading(ped, h)
    Wait(250)
    SetEntityHeading(ped, h)
    ESX.SetTimeout(50, function()
        if DoesEntityExist(ped) then
            SetEntityHeading(ped, h)
            SetPedDesiredHeading(ped, h)
        end
    end)
end

local function HidePedCompletely(ped)
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityAlpha(ped, 0, false)
    SetEntityVisible(ped, false, false)
    SetPedAoBlobRendering(ped, false)
end

local function ShowPedNormally(ped)
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    ResetEntityAlpha(ped)
    SetEntityVisible(ped, true, false)
    SetPedAoBlobRendering(ped, true)
end

local function MakeOverShoulderCam(ped, fov)
    local cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    local px,py,pz = table.unpack(GetEntityCoords(ped))
    local fx,fy,fz = table.unpack(GetEntityForwardVector(ped))

    local cx = px - fx * 3.2
    local cy = py - fy * 3.2
    local cz = pz + 1.2

    SetCamCoord(cam, cx, cy, cz)
    PointCamAtEntity(cam, ped, 0.0, 0.9, 0.0, true)
    SetCamFov(cam, fov or 50.0)
    return cam
end

local function StopScriptedCams()
    RenderScriptCams(false, true, 600, true, true)
end

function Multicharacter:LoadSkinBase(skin)
    TriggerEvent("skinchanger:loadSkin", skin or { sex = 0 })
end

local function isRunning(res)
    return GetResourceState(res or "") == "started"
end

function Multicharacter:OpenCreationMenu(done)
    local choice = string.lower((Config.ClothingMenu or ""):gsub("%s+", ""))

    local function finish(saved)
        if type(done) == "function" then
            done(saved and true or false)
        end
    end

    if choice == "illenium-appearance" and isRunning("illenium-appearance") then
        exports['illenium-appearance']:startPlayerCustomization(function(appearance)
            if appearance then
                TriggerServerEvent('illenium-appearance:server:saveAppearance', appearance)
            end
        end, {
            ped = false,
            headBlend = true,
            faceFeatures = true,
            headOverlays = true,
            components = true,
            props = true,
            tattoos = true 
        })
        return
    end

    if choice == "fivem-appearance" and isRunning("fivem-appearance") then
        exports["fivem-appearance"]:startPlayerCustomization(function(appearance)
            finish(appearance ~= false)
        end, {
            ped = true,
            headBlend = true,
            faceFeatures = true,
            headOverlays = true,
            components = true,
            props = true,
        })
        return
    end

    if choice == "pure-clothing" and isRunning("pure-clothing") then
        exports['pure-clothing']:openMenu('createCharacter')
        return
    end

    if choice == "rcore-clothing" and (isRunning("rcore_clothes") or isRunning("rcore-clothes") or isRunning("rcore_clothing")) then
        local ok, err = pcall(function()
            if exports["rcore_clothes"] and exports["rcore_clothes"].OpenClothing then
                exports["rcore_clothes"]:OpenClothing(function(saved, _data)
                    finish(saved == true)
                end)
            elseif exports["rcore-clothes"] and exports["rcore-clothes"].OpenClothing then
                exports["rcore-clothes"]:OpenClothing(function(saved, _data)
                    finish(saved == true)
                end)
            else
                TriggerEvent("rcore_clothes:openClothing", {}, function(saved, _data)
                    finish(saved == true)
                end)
            end
        end)
        if ok then return end
    end
    TriggerEvent("esx_skin:openSaveableMenu",
        function() finish(true) end,
        function() finish(false) end
    )
end

function Multicharacter:SetupCamera()
    if self.cam then
        SetCamActive(self.cam, false)
        DestroyCam(self.cam, false)
        self.cam = nil
    end

    self.cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(self.cam, Config.Cam.x, Config.Cam.y, Config.Cam.z)
    SetCamRot(self.cam, -50.0, 0.0, Config.Cam.w, 2)
    SetCamFov(self.cam, 75.0)

    SetCamActive(self.cam, true)
    RenderScriptCams(true, false, 1, true, true)
end

function Multicharacter:DestoryCamera()
    if self.cam then
        SetCamActive(self.cam, false)
        RenderScriptCams(false, false, 0, true, true)
        self.cam = nil
    end
end

local HiddenCompents = {}

local function HideComponents(hide)
    local components = {11, 12, 21}
    for i = 1, #components do
        if hide then
            local size = GetHudComponentSize(components[i])
            if size.x > 0 or size.y > 0 then
                HiddenCompents[components[i]] = size
                SetHudComponentSize(components[i], 0.0, 0.0)
            end
        else
            if HiddenCompents[components[i]] then
                local size = HiddenCompents[components[i]]
                SetHudComponentSize(components[i], size.x, size.z)
                HiddenCompents[components[i]] = nil
            end
        end
    end
    DisplayRadar(not hide)
end

function Multicharacter:HideHud(hide)
    self.hidePlayers = true

    MumbleSetVolumeOverride(ESX.PlayerId, 0.0)
    HideComponents(hide)
end

function Multicharacter:SetupCharacters()
    ESX.PlayerLoaded = false
    ESX.PlayerData = {}

    self.spawned = false
    self.playerPed = PlayerPedId()
    self.spawnCoords = Config.PlayerSpawn

    SetEntityCoords(self.playerPed, self.spawnCoords.x, self.spawnCoords.y, self.spawnCoords.z, true, false, false, false)
    SetPedPosHeading(self.playerPed, self.spawnCoords.x, self.spawnCoords.y, self.spawnCoords.z, self.spawnCoords.w)
    HidePedCompletely(self.playerPed)

    SetPlayerControl(ESX.PlayerId, false, 0)
    self:SetupCamera()
    self:HideHud(true)

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    TriggerEvent("esx:loadingScreenOff")

    SetTimeout(200, function()
        TriggerServerEvent("txz-multicharcater:SetupCharacters")
    end)
end

function Multicharacter:GetSkin()
    local character = self.Characters[self.tempIndex]
    if character and character.skin then
        return character.skin
    end

    local sex = 0

    if character then
        if character.model == `mp_f_freemode_01` then
            sex = 1
        elseif character.model == `mp_m_freemode_01` then
            sex = 0
        elseif character.sex == "female" or character.sex == "f" or character.sex == 1 then
            sex = 1
        else
            sex = 0
        end
    end

    return { sex = sex }
end

local function ReassertScriptedCam(self, ticks)
    if not self or not self.cam then return end
    CreateThread(function()
        local count = ticks or 60
        while count > 0 and self.cam do
            SetCamActive(self.cam, true)
            RenderScriptCams(true, false, 0, true, true)
            count = count - 1
            Wait(250)
        end
    end)
end

function Multicharacter:SpawnTempPed()
    self.canRelog = false

    local skin = self:GetSkin()

    if not self.cam then
        self:SetupCamera()
    else
        SetCamActive(self.cam, true)
        RenderScriptCams(true, false, 0, true, true)
    end

    ESX.SpawnPlayer(skin, self.spawnCoords, function()
        self.playerPed = PlayerPedId()
        ReapplyHeading(self.playerPed, self.spawnCoords.w)
        HidePedCompletely(self.playerPed)
        ReassertScriptedCam(self, 90)
    end)
end

function Multicharacter:ChangeExistingPed()
    local newCharacter = self.Characters[self.tempIndex]
    local spawnedCharacter = self.Characters[self.spawned]

    if not newCharacter.model then
        newCharacter.model = newCharacter.sex == "male" and `mp_m_freemode_01` or `mp_f_freemode_01`
    end

    local function reassert()
        if not self.cam then
            self:SetupCamera()
        else
            SetCamActive(self.cam, true)
            RenderScriptCams(true, false, 0, true, true)
        end
        ReapplyHeading(PlayerPedId(), self.spawnCoords.w)
        ReassertScriptedCam(self, 90)
    end

    if spawnedCharacter and spawnedCharacter.model then
        local model = ESX.Streaming.RequestModel(newCharacter.model)
        if model then
            SetPlayerModel(ESX.playerId, newCharacter.model)
            SetModelAsNoLongerNeeded(newCharacter.model)
            reassert()
        end
    end

    TriggerEvent("skinchanger:loadSkin", newCharacter.skin, function()
        reassert()
    end)
end

function Multicharacter:PrepForUI()
    HidePedCompletely(self.playerPed)
end

function Multicharacter:CloseUI()
    SendNUIMessage({
        action = "ToggleMulticharacter",
        data = {
            show = false
        }
    })
    SetNuiFocus(false, false)
end

function Multicharacter:SetupCharacter(index)
    local character = self.Characters[index]
    self.tempIndex = index

    if not self.spawned then
        self:SpawnTempPed()
    elseif character and character.skin then
        self:ChangeExistingPed()
    end

    self.spawned = index
    self.playerPed = PlayerPedId()
    ReapplyHeading(self.playerPed, self.spawnCoords.w)
    self:PrepForUI()
end

function Multicharacter:SetupUI(characters, allowed, max)
    self.Characters = characters or {}
    self.slots = tonumber(allowed) or (Config.Slots and Config.Slots.default) or 1
    self.slotsMax = tonumber(max) or (Config.Slots and Config.Slots.max) or self.slots

    if self.spawned and not self.Characters[self.spawned] then
        self.spawned = false
    end

    SendNUIMessage({
        action = "Locales",
        data = GetUILocales()
    })

    local firstKey = next(self.Characters)
    if not firstKey then
        self.canRelog = false
        local skin = { sex = 0 }
        ESX.SpawnPlayer(skin, self.spawnCoords, function()
            self.playerPed = PlayerPedId()
            SetPedAoBlobRendering(self.playerPed, false)
            SetEntityAlpha(self.playerPed, 0, false)
            TriggerServerEvent("txz-multicharcater:CharacterChosen", 1, true)
            TriggerEvent("esx_identity:showRegisterIdentity")
        end)
        return
    end

    Menu:InitCharacter()
end

function Multicharacter:LoadSkinCreator(skin)
    TriggerEvent("skinchanger:loadSkin", skin, function()
        SetPedAoBlobRendering(self.playerPed, true)
        ResetEntityAlpha(self.playerPed)

        TriggerEvent("esx_skin:openSaveableMenu", function()
            Multicharacter.finishedCreation = true
        end, function()
            Multicharacter.finishedCreation = true
        end)
    end)
end

function Multicharacter:SetDefaultSkin(playerData)
    local sex  = playerData.sex == "m" and 0 or 1
    local model = sex == 0 and `mp_m_freemode_01` or `mp_f_freemode_01`

    model = ESX.Streaming.RequestModel(model)
    if not model then return end

    SetPlayerModel(ESX.playerId, model)
    SetModelAsNoLongerNeeded(model)
    self.playerPed = PlayerPedId()

    self:LoadSkinBase({ sex = sex })
end

function Multicharacter:Reset()
    self.Characters = {}
    self.tempIndex = nil
    self.playerPed = PlayerPedId()
    self.hidePlayers = false
    self.slots = nil

    SetTimeout(10000, function()
        self.canRelog = true
    end)
end

function Multicharacter:PlayerLoaded(playerData, isNew, skin)
    -- Pick spawn location
    local spawn
    if isNew then
        -- NEW character -> force Config.PlayerSpawn
        spawn = self.spawnCoords  -- comes from Config.PlayerSpawn
    elseif playerData and playerData.coords then
        -- Existing character -> last saved coords
        spawn = playerData.coords
    else
        -- Fallback to random default ESX spawn
        local esxSpawns = ESX.GetConfig().DefaultSpawns
        spawn = esxSpawns[math.random(1, #esxSpawns)]
    end

    local needsCreation = false

    if isNew or not skin or #skin == 1 then
        -- Prepare a base model/skin only; no menu yet
        needsCreation = true
        self:SetDefaultSkin(playerData)
        -- If you need current skin object for later, you can do:
        -- skin = exports["skinchanger"]:GetSkin()
    else
        TriggerEvent("skinchanger:loadSkin", skin or self.Characters[self.spawned].skin)
    end

    ESX.SpawnPlayer(skin or { sex = 0 }, spawn, function()
        self:HideHud(false)
        SetPlayerControl(ESX.playerId, true, 0)

        self.playerPed = PlayerPedId()
        ShowPedNormally(self.playerPed)
        FreezeEntityPosition(self.playerPed, false)
        SetEntityCollision(self.playerPed, true, true)
        ReapplyHeading(self.playerPed, self.spawnCoords.w)

        local camTo = MakeOverShoulderCam(self.playerPed, 50.0)

        if not self.cam then
            self.cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
            SetCamCoord(self.cam, Config.Cam.x, Config.Cam.y, Config.Cam.z)
            SetCamRot(self.cam, -50.0, 0.0, Config.Cam.w, 2)
            SetCamFov(self.cam, 75.0)
        end

        local duration = 1800
        SetCamActive(self.cam, true)
        SetCamActiveWithInterp(camTo, self.cam, duration, true, true)
        RenderScriptCams(true, false, 0, true, true)

        CreateThread(function()
            local startTime = GetGameTimer()
            local startFov, endFov = 75.0, 45.0
            SetCamFov(self.cam, startFov)

            while GetGameTimer() - startTime < duration do
                local alpha = (GetGameTimer() - startTime) / duration
                SetCamFov(camTo, startFov + (endFov - startFov) * alpha)
                Wait(0)
            end
        end)

        ESX.SetTimeout(duration + 100, function()
            local function finishUp()
                StopScriptCams()
                if self.cam then
                    DestroyCam(self.cam, false); self.cam = nil
                end
                if camTo then DestroyCam(camTo, false) end

                TriggerServerEvent("esx:onPlayerSpawn")
                TriggerEvent("esx:onPlayerSpawn")
                TriggerEvent("esx:restoreLoadout")

                self:Reset()
            end

            if not needsCreation then
                return finishUp()
            end

            self.finishedCreation = false
            self:OpenCreationMenu(function(saved)
                self.finishedCreation = true
                finishUp()
            end)
        end)
    end)
end

Menu = {}

function Menu:CheckModel(character)
    if not character.model and character.skin then
        if character.skin.model then
            character.model = character.skin.model
        elseif character.skin.sex == 1 then
            character.model = `mp_f_freemode_01`
        else
            character.model = `mp_m_freemode_01`
        end
    end
end

local GetSlot = function()
    for i = 1, Multicharacter.slots do
        if not Multicharacter.Characters[i] then
            return i
        end
    end
end

function Menu:NewCharacter()
    local slot = GetSlot()

    TriggerServerEvent("txz-multicharcater:CharacterChosen", slot, true)
    TriggerEvent("esx_identity:showRegisterIdentity")

    local playerPed = PlayerPedId()

    SetPedAoBlobRendering(playerPed, false)
    SetEntityAlpha(playerPed, 0, false)

    Multicharacter:CloseUI()
end


function Menu:InitCharacter()
    local Characters = Multicharacter.Characters
    local Character = next(Characters)
    self:CheckModel(Characters[Character])

    if not Multicharacter.spawned then
        Multicharacter:SetupCharacter(Character)
    end
    Wait(500)
    
    SendNUIMessage({
        action = "ToggleMulticharacter",
        data = {
            show = true,
            Characters = Characters,
            CanDelete  = Config.CanDelete,
            AllowedSlot= Multicharacter.slots,
            MaxSlot = Multicharacter.slotsMax,
        }
    })

    SetNuiFocus(true, true)
end

function Menu:SelectCharacter(index)
    Multicharacter:SetupCharacter(index)
end

function Menu:PlayCharacter()
    Multicharacter:CloseUI()
    TriggerServerEvent("txz-multicharcater:CharacterChosen", Multicharacter.spawned, false)
end

function Menu:DeleteCharacter()
    if not Config.CanDelete then return end
    local slot = Multicharacter.spawned
    if not slot or type(slot) ~= "number" then return end
    if not Multicharacter.Characters or not Multicharacter.Characters[slot] then return end
    if self._deleting then return end
    self._deleting = true

    TriggerServerEvent("txz-multicharcater:DeleteCharacter", slot)

    Multicharacter.Characters[slot] = nil
    Multicharacter.spawned = false
    Menu:InitCharacter()

    ESX.SetTimeout(400, function()
        TriggerServerEvent("txz-multicharcater:SetupCharacters")
        self._deleting = false
    end)
end