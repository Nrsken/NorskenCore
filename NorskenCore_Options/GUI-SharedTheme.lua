---@class NRSKNUI
local Core = _G.NorskenCore
local Shared = Core.GUISharedPages
local L = Core.L
local Theme = LibStub('LibKaji-1.0').DEFAULT_THEME
local rowH = Theme.rowHeight
local rowHL = Theme.rowHeightLast

local ipairs = ipairs
local min = math.min

local MODE_OPTIONS = {
    { key = 'preset', text = L['Preset Theme'] },
    { key = 'class',  text = L['Class Color'] },
    { key = 'custom', text = L['Custom'] },
}

local MODE_DESCRIPTIONS = {
    preset = L['Use one of the pre-made color themes.'],
    class  = L["Accent colors will match your character's class color."],
    custom = L['Fully customize every color in the theme.'],
}

local CATEGORY_ORDER = {
    { key = 'Backgrounds',      text = L['Backgrounds'] },
    { key = 'Borders',          text = L['Borders'] },
    { key = 'Accent Colors',    text = L['Accent Colors'] },
    { key = 'Text Colors',      text = L['Text Colors'] },
    { key = 'Selection Colors', text = L['Selection Colors'] },
    { key = 'Status Colors',    text = L['Status Colors'] },
}

local PREVIEW_KEYS = { 'bgDark', 'bgMedium', 'bgLight', 'accent', 'selectedBg' }

local function PresetOptions(gui)
    local options = {}
    for _, name in ipairs(gui:GetPresetNames()) do
        options[#options + 1] = { key = name, text = name }
    end
    return options
end

local function BuildModeCard(page, mode, reload)
    local gui = page.gui
    local card = page:Card(L['Theme Mode'])
    card:Row(rowH):Dropdown(L['Theme Mode'], {
        width = 1,
        options = MODE_OPTIONS,
        value = mode,
        callback = function(key)
            gui:SetMode(key)
            reload()
        end,
    })
    card:Row(20, 0):Text(nil, {
        width = 1,
        text = MODE_DESCRIPTIONS[mode],
        height = 20,
        bgMode = 'hide',
    })
end

local function BuildPresetCard(page, reload)
    local gui = page.gui
    local card = page:Card(L['Preset Theme'])
    card:Row(rowH):Dropdown(L['Theme'], {
        width = 1,
        options = PresetOptions(gui),
        value = gui:GetSelectedPreset(),
        callback = function(key)
            gui:SetPreset(key)
            reload()
        end,
    })

    card:Separator()

    local preset = gui:GetPreset(gui:GetSelectedPreset())
    local swatchRow = card:Row(28)
    for _, key in ipairs(PREVIEW_KEYS) do
        local color = preset[key]
        local swatch = swatchRow:Icon({ width = 1 / #PREVIEW_KEYS, align = 'FILL' })
        swatch.icon:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    end
end

local function BuildClassCard(page)
    local card = page:Card(L['Class Color Mode'])
    local color = Core:GetPlayerClassColor()
    local swatch = card:Row(18):Icon({ width = 1, align = 'FILL' })
    swatch.icon:SetColorTexture(color[1], color[2], color[3], 1)
    card:Row(40, 0):Text(nil, {
        width = 1,
        text = {
            L['The class color above is used for accents and selections.'],
            L['Background colors will use the Dark theme.'],
        },
        height = 40,
        bgMode = 'hide',
    })
end

local function BuildCustomCards(page, reload)
    local gui = page.gui
    local categories = {}
    for _, def in ipairs(gui:GetColorKeys()) do
        local list = categories[def.category]
        if not list then
            list = {}
            categories[def.category] = list
        end
        list[#list + 1] = def
    end

    for _, category in ipairs(CATEGORY_ORDER) do
        local defs = categories[category.key]
        if defs then
            local card = page:Card(category.text)
            for i = 1, #defs, 2 do
                local isLast = i + 2 > #defs
                local row = card:Row(isLast and rowHL or rowH, isLast and 0 or nil)
                for j = i, min(i + 1, #defs) do
                    local def = defs[j]
                    row:ColorPicker(def.name, {
                        width = 0.5,
                        value = gui:GetCustomColor(def.key),
                        callback = function(r, g, b, a)
                            gui:SetCustomColor(def.key, r, g, b, a)
                        end,
                    })
                end
            end
        end
    end

    local quickCard = page:Card(L['Quick Setup'])
    quickCard:Row(20):Text(nil, {
        width = 1,
        text = L['Copy colors from a preset theme as a starting point.'],
        height = 20,
        bgMode = 'hide',
    })
    local quickRow = quickCard:Row(rowHL, 0)
    quickRow:Dropdown(L['Copy From'], {
        width = 0.5,
        options = PresetOptions(gui),
        value = '',
        callback = function(key)
            gui:CopyPresetToCustom(key)
            reload()
        end,
    })
    quickRow:Button(L['Reset Custom'], {
        width = 0.5,
        height = 24,
        yOffset = -14,
        callback = function()
            gui:ResetCustomColors()
            reload()
        end,
    })
end

local function BuildResetCard(page, reload)
    local card = page:Card(L['Reset'])
    card:Row(rowHL - 9):Button(L['Reset All Theme Settings'], {
        width = 1,
        height = 30,
        yOffset = -2,
        callback = function()
            page.gui:ResetTheme()
            reload()
        end,
    })
    card:Row(20, 0):Text(nil, {
        width = 1,
        text = L["This will reset theme mode to 'Preset' with the NUI v2 theme."],
        height = 20,
        bgMode = 'hide',
    })
end

---A theme belongs to the addon drawing the page, its GUI saves it.
---@param page table
---@param reload fun() shows this page again, a theme change rebuilds it
function Shared:BuildTheme(page, reload)
    local mode = page.gui:GetMode()

    BuildModeCard(page, mode, reload)

    if mode == 'preset' then
        BuildPresetCard(page, reload)
    elseif mode == 'class' then
        BuildClassCard(page)
    elseif mode == 'custom' then
        BuildCustomCards(page, reload)
    end

    BuildResetCard(page, reload)
end
