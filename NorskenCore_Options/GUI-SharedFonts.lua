---@class NRSKNUI
local Core = _G.NorskenCore
local Shared = Core.GUISharedPages
local L = Core.L
local rowHL = Core.KajiGUI.DEFAULT_THEME.rowHeightLast

---@param page table
function Shared:BuildFonts(page)
    local fontDB = Core:GetSharedSettings().globalMedia.profileFont

    page:SetCondition('globFontON', function() return fontDB.Enabled end)

    local globalCard = page:Card(L['Global Font'])
    local globalRow = globalCard:Row(rowHL, 0)
    globalRow:Checkbox(L['Use Global Font'], {
        width = 0.5,
        value = fontDB.Enabled,
        msgPopup = true,
        msgText = L['Global Font'],
        callback = function(checked)
            fontDB.Enabled = checked
            Core:SharedSettingsChanged()
            Core:RefreshFontStyles()
            page:Refresh()
        end,
    })
    globalRow:Dropdown(L['Font'], {
        width = 0.5,
        media = 'font',
        value = fontDB.FontFace,
        searchable = true,
        conditions = { 'globFontON' },
        callback = function(key)
            fontDB.FontFace = key
            Core:SharedSettingsChanged(true)
            Core:RefreshFontStyles()
        end,
    })

    globalCard:Separator()

    local infoHeight = 50
    globalCard:Row(infoHeight, 0):Text(page.gui:ColorText(L['Global Font Info']), {
        width = 1,
        height = infoHeight,
        autoHeight = true,
        bgMode = 'hide',
        text = {
            L['Font selected above is applied to all modules and blizzard texts that support it.'],
            L['Each module can override the global font with its own font face.'],
        },
    })
end
