---@class NRSKNUI
local Core = _G.NorskenCore
local Shared = Core.GUISharedPages
local L = Core.L
local rowHL = Core.KajiGUI.DEFAULT_THEME.rowHeightLast

local format = string.format

---@param page table
---@param addon table the addon whose window this is, it asks for the reload
function Shared:BuildLanguage(page, addon)
    local db = Core:GetSharedSettings()

    -- languages keep their own names so a reader can always find theirs
    local byKey, options = {}, {}
    for _, language in ipairs(Core.LANGUAGES) do
        byKey[language.key] = language
    end
    local client = byKey[Core:GetClientLanguage()]
    options[1] = { key = 'auto', text = format(L['Auto (%s)'], client and client.text or Core:GetClientLanguage()), font = client and client.font }
    for _, language in ipairs(Core.LANGUAGES) do
        options[#options + 1] = { key = language.key, text = language.text, font = language.font }
    end

    local card = page:Card(L['Language'])
    card:Row(rowHL, 0):Dropdown(L['Language'], {
        width = 0.5,
        options = options,
        value = db.Language,
        tooltip = L['Auto follows the game client. Used on every character.'],
        callback = function(key)
            db.Language = key
            addon:CreateReloadPrompt(L['The new language shows after a reload.'])
        end,
    })

    card:Separator()

    local infoHeight = 50
    card:Row(infoHeight, 0):Text(page.gui:ColorText(L['Language Info']), {
        width = 1,
        height = infoHeight,
        autoHeight = true,
        bgMode = 'hide',
        text = {
            L['Text without a translation in the picked language shows in English.'],
            L['Fonts must include the characters of the picked language, or those letters show as boxes.'],
        },
    })
end
