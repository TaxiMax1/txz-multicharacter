Locales = Locales or {}
CurrentLocale = Config.Locale or 'en'

local function exists(tbl, k) return tbl and tbl[k] ~= nil end

function _U(key, ...)
    local loc = Locales[CurrentLocale] or Locales['en'] or {}
    local str = loc[key] or (Locales['en'] and Locales['en'][key]) or key
    if select('#', ...) > 0 then
        pcall(function(...)
            str = str:format(...)
        end, ...)
    end
    return str
end

function GetUILocales()
    local L = Locales[CurrentLocale] or Locales['en'] or {}
    return {
        locked_slot     = L.locked_slot,
        empty_slot      = L.empty_slot,
        create_char     = L.create_char,
        play_char       = L.play_char,
        delete_char     = L.delete_char,
        job             = L.job,
        cash            = L.cash,
        bank            = L.bank,
        dob             = L.dob,
        sex             = L.sex,
        confirm_title   = L.confirm_title,
        confirm_sub     = L.confirm_sub,
        confirm_label   = L.confirm_label,
        confirm_cancel  = L.confirm_cancel,
        confirm_delete  = L.confirm_delete,
    }
end