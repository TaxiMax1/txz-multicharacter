-- server.lua
local ESX = exports["es_extended"]:getSharedObject()

local Server = {
  oneSync = GetConvar("onesync", "off"),
  slots = Config.Slots or 4,
  prefix = Config.Prefix or "char",
  identifierType = ESX.GetConfig("Identifier") or (GetConvar("sv_lan", "") == "true" and "ip" or "license"),
}
Server.__index = Server

ESX.Players = ESX.Players or {}

local function split(str, sep)
  local out, patt = {}, ("([^%s]+)"):format(sep:gsub("%W","%%%0"))
  for token in str:gmatch(patt) do out[#out+1] = token end
  return out
end

local function normalizeSlots(slots)
  if type(slots) == "number" then return { default = slots, max = slots } end
  if type(slots) == "table" then
    local allowed = tonumber(slots.default) or tonumber(slots.allowed) or tonumber(slots.min) or 1
    local max = tonumber(slots.max) or tonumber(slots.maximum) or allowed
    if max < allowed then max = allowed end
    return { default = allowed, max = max }
  end
  return { default = 1, max = 1 }
end

local function routeToOwnBucket(src) SetPlayerRoutingBucket(src, src) end
local function routeToPublic(src)    SetPlayerRoutingBucket(src, 0)   end

local Database = {
  connected = false,
  found = false,
  name = nil,
  tables = { users = "identifier" },
}
Database.__index = Database

function Database:GetConnectionInfo()
  local conn = GetConvar("mysql_connection_string", "")
  if conn == "" then error("^1Unable to start Multicharacter - mysql_connection_string is empty^0", 0) end

  if conn:find("^mysql://") then
    local uri = conn:sub(9)
    local slash = uri:find("/")
    if slash then
      local tail = uri:sub(slash + 1)
      self.name  = tail:gsub("[%?]+[%w%p]*$", "")
      self.found = self.name ~= nil
    end
  else
    for _, pair in ipairs(split(conn, ";")) do
      local k, v = pair:match("^%s*(.-)%s*=%s*(.-)%s*$")
      if k and v and k:lower() == "database" then
        self.name  = v
        self.found = true
        break
      end
    end
  end
end

Database:GetConnectionInfo()

local function ensureSchema()
  local ok1 = MySQL.transaction.await({
    { query = [[
      CREATE TABLE IF NOT EXISTS `multicharacter_slots` (
        `identifier` VARCHAR(60) NOT NULL,
        `slots` INT(11) NOT NULL,
        PRIMARY KEY (`identifier`) USING BTREE,
        INDEX `slots` (`slots`) USING BTREE
      ) ENGINE=InnoDB
    ]] }
  })
  if not ok1 then error("^1Failed creating/ensuring table `multicharacter_slots`^0") end

  local hasDisabled = MySQL.scalar.await([[
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'users' AND COLUMN_NAME = 'disabled'
  ]], { Database.name })
  if tonumber(hasDisabled or 0) == 0 then
    local ok2 = MySQL.update.await([[ALTER TABLE `users` ADD COLUMN `disabled` TINYINT(1) NOT NULL DEFAULT 0]])
    if not ok2 then error("^1Failed adding `users.disabled` column^0") end
  end
end

local function ensureIdentifierWidths()
  local desiredLen = 42 + #Server.prefix
  local rows = MySQL.query.await(
    'SELECT TABLE_NAME, COLUMN_NAME, CHARACTER_MAXIMUM_LENGTH ' ..
    'FROM INFORMATION_SCHEMA.COLUMNS ' ..
    'WHERE TABLE_SCHEMA = ? AND DATA_TYPE = "varchar" AND COLUMN_NAME IN (?)',
    { Database.name, { "identifier", "owner" } }
  ) or {}

  local toAlter = {}
  for _, col in ipairs(rows) do
    Database.tables[col.TABLE_NAME] = col.COLUMN_NAME
    local maxLen = tonumber(col.CHARACTER_MAXIMUM_LENGTH or 0) or 0
    if maxLen > 0 and maxLen < desiredLen then
      toAlter[#toAlter+1] = { tableName = col.TABLE_NAME, column = col.COLUMN_NAME }
    end
  end

  if #toAlter > 0 then
    local queries = {}
    for _, it in ipairs(toAlter) do
      queries[#queries+1] = { query = ("ALTER TABLE `%s` MODIFY COLUMN `%s` VARCHAR(%d)"):format(it.tableName, it.column, desiredLen) }
    end
    local ok = MySQL.transaction.await(queries)
    if not ok then
      print(("[^2INFO^7] Unable to update ^5%s^7 columns to ^5VARCHAR(%s)^7"):format(#toAlter, desiredLen))
    end
  end
end

MySQL.ready(function()
  if not Database.name then error("^1Database name is unknown — check mysql_connection_string^0") end
  ensureSchema()
  ensureIdentifierWidths()
  Database.connected = true

  ESX.Jobs = ESX.GetJobs()
  while not next(ESX.Jobs) do
    Wait(500)
    ESX.Jobs = ESX.GetJobs()
  end
end)

function Database:DeleteCharacter(src, charid)
  local identifier = ("%s%s:%s"):format(Server.prefix, charid, ESX.GetIdentifier(src))
  local queries, i = {}, 0
  for tbl, col in pairs(self.tables) do
    i = i + 1
    queries[i] = { query = ("DELETE FROM `%s` WHERE %s = ?"):format(tbl, col), values = { identifier } }
  end
  local ok = MySQL.transaction.await(queries)
  if not ok then error("\n^1Transaction failed while trying to delete " .. identifier .. "^0") end
end

function Database:GetPlayerSlots(id)
  return MySQL.scalar.await("SELECT slots FROM multicharacter_slots WHERE identifier = ?", { id }) or Server.slots
end

function Database:GetPlayerInfo(idLike, limit)
  return MySQL.query.await(
    "SELECT identifier, accounts, job, job_grade, firstname, lastname, dateofbirth, sex, skin, disabled " ..
    "FROM users WHERE identifier LIKE ? LIMIT ?",
    { idLike, limit }
  )
end

function Database:SetSlots(identifier, slots)
  MySQL.insert(
    "INSERT INTO `multicharacter_slots` (`identifier`, `slots`) VALUES (?, ?) " ..
    "ON DUPLICATE KEY UPDATE `slots` = VALUES(`slots`)",
    { identifier, slots }
  )
end

function Database:RemoveSlots(identifier)
  local had = MySQL.scalar.await("SELECT `slots` FROM `multicharacter_slots` WHERE identifier = ?", { identifier })
  if had then
    MySQL.update("DELETE FROM `multicharacter_slots` WHERE `identifier` = ?", { identifier })
    return true
  end
  return false
end

function Database:EnableSlot(identifier, slot)
  local selected = ("char%s:%s"):format(slot, identifier)
  return (MySQL.update.await("UPDATE `users` SET `disabled` = 0 WHERE identifier = ?", { selected }) or 0) > 0
end

function Database:DisableSlot(identifier, slot)
  local selected = ("char%s:%s"):format(slot, identifier)
  return (MySQL.update.await("UPDATE `users` SET `disabled` = 1 WHERE identifier = ?", { selected }) or 0) > 0
end

local Multicharacter = { awaitingRegistration = {} }
Multicharacter.__index = Multicharacter

function Multicharacter:SetupCharacters(src)
  routeToOwnBucket(src)
  while not Database.connected do Wait(100) end

  local baseId = ESX.GetIdentifier(src)
  ESX.Players[baseId] = src

  local slotInfo = normalizeSlots(Database:GetPlayerSlots(baseId))
  local likeId = (Server.prefix or "char") .. "%:" .. baseId
  local limit = tonumber(slotInfo.max) or 1
  local rows = Database:GetPlayerInfo(likeId, limit) or {}
  local characters = {}

  for _, v in ipairs(rows) do
    local jobName = v.job or "unemployed"
    local gradeKey = tostring(v.job_grade)
    local gradeLbl, jobLabel = "", jobName

    if ESX.Jobs[jobName] and ESX.Jobs[jobName].grades[gradeKey] then
      if jobName ~= "unemployed" then gradeLbl = ESX.Jobs[jobName].grades[gradeKey].label end
      jobLabel = ESX.Jobs[jobName].label
    end

    local accounts = json.decode(v.accounts or "{}") or {}
    local colonAt = string.find(v.identifier, ":") or 0
    local startIdx = #Server.prefix + 1
    local idStr = string.sub(v.identifier, startIdx, (colonAt > 0 and colonAt or startIdx) - 1)
    local id = tonumber(idStr)

    if id then
      characters[id] = {
        id = id,
        bank = accounts.bank or 0,
        money = accounts.money or 0,
        job = jobLabel,
        job_grade = gradeLbl,
        firstname = v.firstname,
        lastname = v.lastname,
        dateofbirth = v.dateofbirth,
        skin = v.skin and json.decode(v.skin) or {},
        disabled = v.disabled,
        sex = (v.sex == "m") and "male" or "female",
      }
    end
  end

  TriggerClientEvent("txz-multicharcater:SetupUI", src, characters, slotInfo.default, slotInfo.max)
end

function Multicharacter:CharacterChosen(src, charid, isNew)
  if type(charid) ~= "number" or #tostring(charid) > 2 or type(isNew) ~= "boolean" then return end

  if isNew then
    self.awaitingRegistration[src] = charid
    return
  end

  routeToPublic(src)

  if not ESX.GetConfig().EnableDebug then
    local identifier = ("%s%s:%s"):format(Server.prefix, charid, ESX.GetIdentifier(src))
    if ESX.GetPlayerFromIdentifier(identifier) then
      DropPlayer(src, "[ESX Multicharacter] Your identifier " .. identifier .. " is already on the server!")
      return
    end
  end

  local charPrefix = ("%s%s"):format(Server.prefix, charid)
  TriggerEvent("esx:onPlayerJoined", src, charPrefix)
  ESX.Players[ESX.GetIdentifier(src)] = charPrefix
end

function Multicharacter:RegistrationComplete(src, data)
  local charId = self.awaitingRegistration[src]
  local charPrefix = ("%s%s"):format(Server.prefix, charId)
  self.awaitingRegistration[src] = nil
  ESX.Players[ESX.GetIdentifier(src)] = charPrefix
  routeToPublic(src)
  TriggerEvent("esx:onPlayerJoined", src, charPrefix, data)
end

function Multicharacter:PlayerDropped(src)
  self.awaitingRegistration[src] = nil
  ESX.Players[ESX.GetIdentifier(src)] = nil
end

function Server:ResetPlayers()
  if next(ESX.Players) then
    local snapshot = table.clone(ESX.Players)
    table.wipe(ESX.Players)
    for baseId, ref in pairs(snapshot) do
      ESX.Players[ESX.GetIdentifier(ref.source or baseId)] = ref.identifier or ref
    end
  else
    ESX.Players = {}
  end
end

function Server:OnConnecting(src, deferrals)
  deferrals.defer()
  Wait(250)

  if not SetEntityOrphanMode then
    return deferrals.done("[ESX Multicharacter] ESX requires minimum Artifact 10188. Please update your server.")
  end

  if self.oneSync == "off" or self.oneSync == "legacy" then
    return deferrals.done(("[ESX Multicharacter] Requires OneSync Infinity. Current: %s"):format(self.oneSync))
  end

  if not Database.found then
    return deferrals.done("[ESX Multicharacter] mysql_connection_string not found in server.cfg")
  end

  if not Database.connected then
    return deferrals.done("[ESX Multicharacter] OxMySQL could not connect. Check your configuration.")
  end

  local ok, identifier = pcall(function() return ESX.GetIdentifier(src) end)
  if not ok or not identifier then
      return deferrals.done(_U('err_identifier', self.identifierType))
  end

  if ESX.GetConfig().EnableDebug or not ESX.Players[identifier] then
    ESX.Players[identifier] = src
    return deferrals.done()
  end

  local function cleanupStalePlayer(staleSrc)
    deferrals.update("[ESX Multicharacter] Cleaning stale player entry...")
    TriggerEvent("esx:onPlayerDropped", staleSrc, "esx_stale_player_obj", function()
      ESX.Players[identifier] = src
      deferrals.done()
    end)
  end

  local function reject()
    deferrals.done(("[ESX Multicharacter] Error loading your character!\n" ..
      "Error code: identifier-active\n\n" ..
      "Someone with the same identifier is already on the server.\n" ..
      "Make sure you are not playing on the same account.\n\nYour identifier: %s"):format(identifier))
  end

  local ref = ESX.Players[identifier]
  if type(ref) == "number" then
    if GetPlayerPing(ref) > 0 then return reject() end
    return cleanupStalePlayer(ref)
  end

  local xPlayer = ESX.GetPlayerFromIdentifier(("%s:%s"):format(ref, identifier))
  if not xPlayer then
    ESX.Players[identifier] = src
    return deferrals.done()
  end

  if GetPlayerPing(xPlayer.source) > 0 then
    return reject()
  end

  return cleanupStalePlayer(xPlayer.source)
end

AddEventHandler("playerConnecting", function(_, _, deferrals)
  Server:OnConnecting(source, deferrals)
end)

RegisterNetEvent("txz-multicharcater:SetupCharacters", function()
  Multicharacter:SetupCharacters(source)
end)

RegisterNetEvent("txz-multicharcater:CharacterChosen", function(charid, isNew)
  Multicharacter:CharacterChosen(source, charid, isNew)
end)

AddEventHandler("esx_identity:completedRegistration", function(src, data)
  Multicharacter:RegistrationComplete(src, data)
end)

AddEventHandler("playerDropped", function()
  Multicharacter:PlayerDropped(source)
end)

RegisterNetEvent("txz-multicharcater:DeleteCharacter", function(charid)
  if not Config.CanDelete then return end
  if type(charid) ~= "number" or #tostring(charid) > 2 then return end
  Database:DeleteCharacter(source, charid)
end)

RegisterNetEvent("txz-multicharcater:relog", function()
  local src = source
  local xPlayer = ESX.GetPlayerFromId(src)
  if not xPlayer then return end
  TriggerEvent("esx:playerLogout", src)
end)

Server:ResetPlayers()