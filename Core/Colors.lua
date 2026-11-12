---@class NRSKNUI
local Core = select(2, ...)
local L = Core.L

-- Module with a bunch of color utilities

local math_floor = math.floor
local format = string.format
local issecretvalue = issecretvalue
local type = type
local tonumber = tonumber
local CreateColor = CreateColor
local select = select
local unpack = unpack
local modf = math.modf
local next = next

local GetBlizzardClassColor = C_ClassColor.GetClassColor

---An { r, g, b, a? } color array with 0-1 components.
---@alias RGBA number[]

---The one class colour source, the custom palette. Nil without a known class and until the palette loads.
---@param classToken? string
---@return ColorMixin?
function Core:GetClassColor(classToken)
    -- a secret token can't index the palette, so Blizzard's own colour is the only answer there
    if issecretvalue(classToken) then
        return GetBlizzardClassColor(classToken)
    end
    if not classToken then return nil end

    return Core.Colors.class[classToken]
end

---Wrap text in a class colour, unchanged without a known class.
---@param text string
---@param classToken? string
---@return string
function Core:ColorTextByClass(text, classToken)
    local color = Core:GetClassColor(classToken)
    if not color then
        return text
    end
    return color:WrapTextInColorCode(text)
end

---The player's name written the way an aura button writes a caster's (CustomAuraButtonPrivateMixin:ApplyCasterName,
---live 12.1.5), for previews of %casterName.
---@param useClassColors boolean?
---@param showRealmName boolean?
---@return string
function Core:FormatCasterName(useClassColors, showRealmName)
    local name = Core.MyName
    if showRealmName and Core.MyRealm and Core.MyRealm ~= '' then
        name = name .. '-' .. Core.MyRealm
    end
    -- the one place Blizzard's class colours are used: the game colours the real text itself, which stays secret
    local color = useClassColors and RAID_CLASS_COLORS[Core.MyClass]
    return color and color:WrapTextInColorCode(name) or name
end

---Convert 0-1 RGB components to an "RRGGBB" hex string.
---@param r? number
---@param g? number
---@param b? number
---@return string hex
function Core:RGBAToHex(r, g, b)
    r = math_floor((r or 1) * 255 + 0.5)
    g = math_floor((g or 1) * 255 + 0.5)
    b = math_floor((b or 1) * 255 + 0.5)
    return format("%02X%02X%02X", r, g, b)
end

---Get accent color components based on mode.
---@param colorMode? "class"|"theme"|"custom"
---@param customColor? RGBA Used when colorMode is "custom"
---@return number r, number g, number b, number a
function Core:GetAccentColor(colorMode, customColor)
    colorMode = colorMode or "custom"

    if colorMode == "class" then
        local classColor = Core:GetClassColor(Core.MyClass)
        if not classColor then
            return 1, 1, 1, 1
        end
        return classColor.r, classColor.g, classColor.b, 1
    elseif colorMode == "theme" then
        return self.GUI:Color("accent")
    else
        -- Validate custom color
        if customColor and type(customColor) == "table" and #customColor >= 3 then
            return customColor[1] or 1, customColor[2] or 1, customColor[3] or 1, customColor[4] or 1
        end
        return 1, 1, 1, 1
    end
end

---Create a color from basically anything: 0-1 RGB, 0-255 RGB, a hex string ("RRGGBB" or "AARRGGBB", optionally "#"-prefixed), or an { r, g, b, a } table.
---@param r number|string|{ r: number, g: number, b: number, a: number? }
---@param g? number
---@param b? number
---@param a? number
---@return ColorMixin
function Core:CreateColor(r, g, b, a)
    if type(r) == 'table' then
        return Core:CreateColor(r.r, r.g, r.b, r.a)
    elseif type(r) == 'string' then
        -- load from hex
        local hex = r:gsub('#', '')
        if #hex == 8 then
            -- prefixed with alpha
            a = tonumber(hex:sub(1, 2), 16) / 255
            r = tonumber(hex:sub(3, 4), 16) / 255
            g = tonumber(hex:sub(5, 6), 16) / 255
            b = tonumber(hex:sub(7, 8), 16) / 255
        elseif #hex == 6 then
            r = tonumber(hex:sub(1, 2), 16) / 255
            g = tonumber(hex:sub(3, 4), 16) / 255
            b = tonumber(hex:sub(5, 6), 16) / 255
        end
    elseif r > 1 or g > 1 or b > 1 then
        r = r / 255
        g = g / 255
        b = b / 255
    end
    local color = CreateColor(r --[[@as number]], g, b, a)
    return color
end

-- for the GUI dropdowns; filled in place, GUI files keep this table from load
---@type { key: "class"|"custom"|"theme", text: string }[]
Core.ColorModeOptions = {}
Core:OnLanguageSet(function()
    local options = Core.ColorModeOptions
    options[1] = { key = "class", text = L['Class Color'] }
    options[2] = { key = "custom", text = L['Custom Color'] }
    options[3] = { key = "theme", text = L['Theme Color'] }
end)

---Blend between RGB triplets based on the Min/Max ratio.
---@param Min number
---@param Max number
---@param ... number RGB triplets (r1, g1, b1, r2, g2, b2, ...)
---@return number r, number g, number b
---@return ...number
function Core:ColorGradient(Min, Max, ...)
    local Percent = (Max == 0) and 0 or (Min / Max)

    if Percent >= 1 then
        return select(select("#", ...) - 2, ...)
    elseif Percent <= 0 then
        return ...
    end

    local Num = select("#", ...) / 3
    local Segment, RelPercent = modf(Percent * (Num - 1))

    local R1, G1, B1, R2, G2, B2 = select((Segment * 3) + 1, ...)
    return
        R1 + (R2 - R1) * RelPercent,
        G1 + (G2 - G1) * RelPercent,
        B1 + (B2 - B1) * RelPercent
end

---Wrap text in a color escape code built from an RGBA table.
---@param text string
---@param color RGBA
---@return string
function Core:ColorText(text, color)
    local r, g, b, a = unpack(color)
    return format("|c%02X%02X%02X%02X%s|r", (a or 1) * 255, r * 255, g * 255, b * 255, text)
end

Core.Colors = {
    class = {},
    reaction = {},
    power = {},
    runes = {},
    stagger = {},
    status = {},
    dispel = {},
    white = CreateColor(1, 1, 1, 1),
    warning = { 1, 0.55, 0.2, 1 },
    highlightColor = { 1, 1, 1, 0.25 },
    selectedColor = { 0.8, 0.8, 0.8, 0.25 },
    blackBgColor = { 0, 0, 0, 0.8 },
    enchantColor = { 0.6, 0, 1, 1 }
}

-- Elements look power colors up by token as well as by type (the runes element reads RUNES).
local POWER_TOKENS = {
    [0] = 'MANA',
    [1] = 'RAGE',
    [2] = 'FOCUS',
    [3] = 'ENERGY',
    [4] = 'COMBO_POINTS',
    [5] = 'RUNES',
    [6] = 'RUNIC_POWER',
    [7] = 'SOUL_SHARDS',
    [8] = 'LUNAR_POWER',
    [9] = 'HOLY_POWER',
    [11] = 'MAELSTROM',
    [12] = 'CHI',
    [13] = 'INSANITY',
    [16] = 'ARCANE_CHARGES',
    [17] = 'FURY',
    [18] = 'PAIN',
    [19] = 'ESSENCE',
}

---The shared color palette into Core.Colors. NRSKNUI_COLORS_UPDATED tells
---whoever mirrors it (the unit frames push it into oUF.colors) to read it again.
function Core:LoadCustomColors()
    local db = self:GetSharedSettings().Colors

    local palette = self.Colors

    for powerType, c in next, db.Power do
        local col = CreateColor(c[1], c[2], c[3])
        palette.power[powerType] = col
        local token = POWER_TOKENS[powerType]
        if token then
            palette.power[token] = col
        end
    end

    for spec, c in next, db.Runes do
        palette.runes[spec] = CreateColor(c[1], c[2], c[3])
    end

    for level, c in next, db.Stagger do
        palette.stagger[level] = CreateColor(c[1], c[2], c[3])
    end

    for index, c in next, db.Reaction do
        palette.reaction[index] = CreateColor(c[1], c[2], c[3])
    end

    for token, c in next, db.Class do
        palette.class[token] = CreateColor(c[1], c[2], c[3])
    end

    for index, c in next, db.Dispel do
        palette.dispel[index] = CreateColor(c[1], c[2], c[3])
    end

    -- Status colors are consumed directly (RGBA) by the health handler.
    palette.status = db.Status

    Core.Ace:SendMessage('NRSKNUI_COLORS_UPDATED')
end
