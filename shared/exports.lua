-- exports.lua
local Multicharacter = Multicharacter or {}
local Database = Database or {}

exports("GetPlayerSlots", function(identifier)
    return Database:GetPlayerSlots(identifier)
end)

exports("GetCharacters", function(src)
    local baseId = ESX.GetIdentifier(src)
    local likeId = (Config.Prefix or "char") .. "%:" .. baseId
    local limit = Database:GetPlayerSlots(baseId)
    return Database:GetPlayerInfo(likeId, limit) or {}
end)

exports("DeleteCharacter", function(src, charid)
    return Database:DeleteCharacter(src, charid)
end)

exports("EnableSlot", function(identifier, slot)
    return Database:EnableSlot(identifier, slot)
end)

exports("DisableSlot", function(identifier, slot)
    return Database:DisableSlot(identifier, slot)
end)

exports("SetupCharacters", function(src)
    return Multicharacter:SetupCharacters(src)
end)

exports("CharacterChosen", function(src, charid, isNew)
    return Multicharacter:CharacterChosen(src, charid, isNew)
end)

exports("AddSlots", function(identifier, slots)
    return Database:SetSlots(identifier, slots)
end)

exports("RemoveSlots", function(identifier)
    return Database:RemoveSlots(identifier)
end)