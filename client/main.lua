ESX = exports["es_extended"]:getSharedObject()

local nuiReady = false

-- Multicharacter "class"
---@diagnostic disable: duplicate-set-field
Multicharacter = {}
Multicharacter._index = Multicharacter
Multicharacter.canRelog = true
Multicharacter.Characters = {}
Multicharacter.hidePlayers = false
Multicharacter.spawned = false
Multicharacter.finishedCreation = false

-- ============== UTILITIES ==============

local function pid() return PlayerId() end
local function ped() return PlayerPedId() end

local function SetPedPosHeading(p, x, y, z, h)
    h = (h or 0.0) % 360.0
    FreezeEntityPosition(p, true)
    ClearPedTasksImmediately(p)

    SetEntityCoordsNoOffset(p, x, y, z, false, false, false)
    SetEntityHeading(p, h)
    SetPedDesiredHeading(p, h)
    Wait(250)
    SetEntityHeading(p, h)

    FreezeEntityPosition(p, false)
end

local function ReapplyHeading(p, h)
    h = (h or 0.0) % 360.0
    SetEntityHeading(p, h)
    SetPedDesiredHeading(p, h)
    Wait(250)
    SetEntityHeading(p, h)
    ESX.SetTimeout(50, function()
        if DoesEntityExist(p) then
            SetEntityHeading(p, h)
            SetPedDesiredHeading(p, h)
        end
    end)
end

local function HidePedCompletely(p)
    FreezeEntityPosition(p, true)
    SetEntityCollision(p, false, false)
    SetEntityAlpha(p, 0, false)
    SetEntityVisible(p, false, false)
    SetPedAoBlobRendering(p, false)
end

local function ShowPedNormally(p)
    FreezeEntityPosition(p, false)
    SetEntityCollision(p, true, true)
    ResetEntityAlpha(p)
    SetEntityVisible(p, true, false)
    SetPedAoBlobRendering(p, true)
end

local function MakeOverShoulderCam(p, fov)
    local cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    local px,py,pz = table.unpack(GetEntityCoords(p))
    local fx,fy,fz = table.unpack(GetEntityForwardVector(p))

    local cx = px - fx * 3.2
    local cy = py - fy * 3.2
    local cz = pz + 1.2

    SetCamCoord(cam, cx, cy, cz)
    PointCamAtEntity(cam, p, 0.0, 0.9, 0.0, true)
    SetCamFov(cam, fov or 50.0)
    return cam
end

local function StopScriptedCams()
    RenderScriptCams(false, true, 600, true, true)
end

-- ============== HUD HIDE LOOP (SAFE) ==============

local _hudHideThread = nil
local function StartHudHideLoop()
    if _hudHideThread then return end
    _hudHideThread = true
    CreateThread(function()
        while Multicharacter.hidePlayers do
            HideHudAndRadarThisFrame()
            DisplayRadar(false)
            Wait(0)
        end
        _hudHideThread = nil
        DisplayRadar(true)
    end)
end

-- ============== CAMERA ==============

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

function Multicharacter:DestroyCamera()
    if self.cam then
        SetCamActive(self.cam, false)
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(self.cam, false)
        self.cam = nil
    end
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

-- ============== HUD / MUMBLE ==============

function Multicharacter:HideHud(hide)
    self.hidePlayers = hide and true or false
    MumbleSetVolumeOverride(pid(), hide and 0.0 or -1.0)
    if hide then StartHudHideLoop() end
end

-- ============== FLOW ==============

CreateThread(function()
    -- Wait for ESX player to be fully recognized
    while not ESX.PlayerLoaded do
        Wait(100)
        if NetworkIsPlayerActive(pid()) then
            ESX.DisableSpawnManager()
            Multicharacter:SetupCharacters()
            break
        end
    end
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

-- NUI ready
RegisterNUICallback('nuiReady', function(_, cb)
    nuiReady = true
    cb(1)
end)

-- Server asks us to (re)build the UI
ESX.SecureNetEvent("txz-multicharacter:SetupUI", function(characters, allowed, max)
    if not nuiReady then
        print(_U('nui_wait'))
        ESX.Await(function() return nuiReady == true end, _U('nui_failed', 10000), 10000)
    end
    Multicharacter:SetupUI(characters, allowed, max)
end)

-- Helpers
local function ensureCam(self)
    if not self.cam then
        self:SetupCamera()
    else
        SetCamActive(self.cam, true)
        RenderScriptCams(true, false, 0, true, true)
    end
end

-- Character setup entry
function Multicharacter:SetupCharacters()
    ESX.PlayerLoaded = false
    ESX.PlayerData = {}

    self.spawned = false
    self.playerPed = ped()
    self.spawnCoords = Config.PlayerSpawn

    SetEntityCoords(self.playerPed, self.spawnCoords.x, self.spawnCoords.y, self.spawnCoords.z, true, false, false, false)
    SetPedPosHeading(self.playerPed, self.spawnCoords.x, self.spawnCoords.y, self.spawnCoords.z, self.spawnCoords.w)
    HidePedCompletely(self.playerPed)

    SetPlayerControl(pid(), false, 0)
    self:SetupCamera()
    self:HideHud(true)

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    TriggerEvent("esx:loadingScreenOff")

    SetTimeout(200, function()
        TriggerServerEvent("txz-multicharacter:SetupCharacters")
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

function Multicharacter:SpawnTempPed()
    self.canRelog = false
    local skin = self:GetSkin()
    ensureCam(self)
    ESX.SpawnPlayer(skin, self.spawnCoords, function()
        self.playerPed = ped()
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
        ensureCam(self)
        ReapplyHeading(ped(), self.spawnCoords.w)
        ReassertScriptedCam(self, 90)
    end

    if spawnedCharacter and spawnedCharacter.model then
        local model = ESX.Streaming.RequestModel(newCharacter.model)
        if model then
            SetPlayerModel(pid(), newCharacter.model)
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
        data = { show = false }
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
    self.playerPed = ped()
    ReapplyHeading(self.playerPed, self.spawnCoords.w)
    self:PrepForUI()
end

function Multicharacter:SetupUI(characters, allowed, max)
    self.Characters = characters or {}
    self.slots     = tonumber(allowed) or (Config.Slots and Config.Slots.default) or 1
    self.slotsMax  = tonumber(max)     or (Config.Slots and Config.Slots.max)     or self.slots

    if self.spawned and not self.Characters[self.spawned] then
        self.spawned = false
    end

    SendNUIMessage({ action = "Locales", data = GetUILocales() })

    local firstKey = next(self.Characters)
    if not firstKey then
        self.canRelog = false
        local skin = { sex = 0 }
        ESX.SpawnPlayer(skin, self.spawnCoords, function()
            self.playerPed = ped()
            SetPedAoBlobRendering(self.playerPed, false)
            SetEntityAlpha(self.playerPed, 0, false)
            TriggerServerEvent("txz-multicharacter:CharacterChosen", 1, true)
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
    local sex = playerData.sex == "m" and 0 or 1
    local model = sex == 0 and `mp_m_freemode_01` or `mp_f_freemode_01`

    model = ESX.Streaming.RequestModel(model)
    if not model then return end

    SetPlayerModel(pid(), model)
    SetModelAsNoLongerNeeded(model)
    self.playerPed = ped()

    local skin = { sex = sex }
    self:LoadSkinCreator(skin)
end

function Multicharacter:Reset()
    self.Characters = {}
    self.tempIndex = nil
    self.playerPed = ped()
    self.hidePlayers = false
    self.slots = nil
    self:DestroyCamera()

    SetTimeout(10000, function()
        self.canRelog = true
    end)
end

function Multicharacter:PlayerLoaded(playerData, isNew, skin)
    local esxSpawns = ESX.GetConfig().DefaultSpawns
    local spawn = esxSpawns[math.random(1, #esxSpawns)]
    if not isNew and playerData.coords then
        spawn = playerData.coords
    end

    if isNew or not skin or #skin == 1 then
        self.finishedCreation = false
        self:SetDefaultSkin(playerData)
        while not self.finishedCreation do Wait(200) end
        skin = exports["skinchanger"]:GetSkin()
    else
        TriggerEvent("skinchanger:loadSkin", skin or self.Characters[self.spawned].skin)
    end

    ESX.SpawnPlayer(skin, spawn, function()
        self:HideHud(false)
        SetPlayerControl(pid(), true, 0)

        self.playerPed = ped()
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
            local t = 0
            local startFov, endFov = 75.0, 45.0
            SetCamFov(self.cam, startFov)
            while t < duration do
                local alpha = t / duration
                SetCamFov(camTo, startFov + (endFov - startFov) * alpha)
                t = t + 0
                Wait(0)
            end
        end)

        ESX.SetTimeout(duration + 50, function()
            StopScriptedCams()
            if self.cam then
                DestroyCam(self.cam, false)
                self.cam = nil
            end
            if camTo then
                DestroyCam(camTo, false)
            end

            TriggerServerEvent("esx:onPlayerSpawn")
            TriggerEvent("esx:onPlayerSpawn")
            TriggerEvent("esx:restoreLoadout")

            self:Reset()
        end)
    end)
end

-- ============== MENU API ==============

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

local function GetSlot()
    for i = 1, Multicharacter.slots do
        if not Multicharacter.Characters[i] then
            return i
        end
    end
end

function Menu:NewCharacter()
    local slot = GetSlot()
    TriggerServerEvent("txz-multicharacter:CharacterChosen", slot, true)
    TriggerEvent("esx_identity:showRegisterIdentity")

    local p = ped()
    SetPedAoBlobRendering(p, false)
    SetEntityAlpha(p, 0, false)

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
            MaxSlot    = Multicharacter.slotsMax,
        }
    })

    SetNuiFocus(true, true)
end

function Menu:SelectCharacter(index)
    Multicharacter:SetupCharacter(index)
end

function Menu:PlayCharacter()
    Multicharacter:CloseUI()
    TriggerServerEvent("txz-multicharacter:CharacterChosen", Multicharacter.spawned, false)
end

function Menu:DeleteCharacter()
    if not Config.CanDelete then return end
    local slot = Multicharacter.spawned
    if not slot or type(slot) ~= "number" then return end
    if not Multicharacter.Characters or not Multicharacter.Characters[slot] then return end
    if self._deleting then return end
    self._deleting = true

    TriggerServerEvent("txz-multicharacter:DeleteCharacter", slot)

    Multicharacter.Characters[slot] = nil
    Multicharacter.spawned = false
    Menu:InitCharacter()

    ESX.SetTimeout(400, function()
        TriggerServerEvent("txz-multicharacter:SetupCharacters")
        self._deleting = false
    end)
end

-- ============== RELOG COMMAND ==============

local relog = Config.Relog or {}
if relog.enabled and relog.command and relog.command ~= '' then
    RegisterCommand(relog.command, function()
        if not Multicharacter.canRelog then return end
        Multicharacter.canRelog = false
        TriggerServerEvent("txz-multicharacter:relog")
        ESX.SetTimeout(500, function()
            Multicharacter.canRelog = true
        end)
    end, false)
end