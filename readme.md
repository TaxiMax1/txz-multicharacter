TXZ SCRIPTS - :OOOO

-- Get slots
local slots = exports["txz-multicharacter"]:GetPlayerSlots(ESX.GetIdentifier(source))

-- Get all characters
local chars = exports["txz-multicharacter"]:GetCharacters(source)

-- Enable slot
exports["txz-multicharacter"]:EnableSlot(ESX.GetIdentifier(source), 2)

-- Disable slot
exports["txz-multicharacter"]:DisableSlot(ESX.GetIdentifier(source), 2)

-- Add 2 extra slots
exports["txz-multicharacter"]:AddSlots(ESX.GetIdentifier(source), 6) -- sets slots to 6