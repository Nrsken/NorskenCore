---@class NorskenCore
local Core = select(2, ...)

local strmatch = string.match
local strupper = string.upper
local strfind = string.find
local gsub = string.gsub
local tonumber = tonumber

local BindingProperty = Enum.DurationTextBindingProperty

Core.LITERAL_PERCENT = '\001' -- a typed %%, until the text's kind decides how a percent sign is written
Core.CASTER_PATTERN = '%%%d*%.?casterName' -- %casterName or %2.casterName, see ApplyAuraLook

local LITERAL_PERCENT = Core.LITERAL_PERCENT
local CASTER_PATTERN = Core.CASTER_PATTERN

-- %p is the time left and %t the total, both rendered by the duration binding
local DURATION_TOKENS = { p = BindingProperty.RemainingDuration, t = BindingProperty.TotalDuration }

local TEXT_ROTATIONS = { LEFT = math.pi / 2, RIGHT = -math.pi / 2 }

---Whether a text has duration (%p/%t) or charge (%s) tokens and which trigger %N. reads.
---@param text string
---@return boolean duration, boolean charges, number? source
function Core:ClassifyText(text)
    return strfind(text, '%%%d*%.?[pt]') ~= nil, strfind(text, '%%%d*%.?s') ~= nil, tonumber(strmatch(text, '%%(%d+)%.[pts]'))
end

---@param mark string
---@return string?
local function RaidMarker(mark)
    local index = tonumber(mark)
    if index and index >= 1 and index <= 8 then
        return '|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_' .. index .. ':0|t'
    end
end

---@param addon table whose theme a theme-coloured name takes
---@param element table
---@param name string?
---@return string?
local function FormatName(addon, element, name)
    if not name then return nil end

    if element.NameFormat == 'initial' then
        name = strmatch(name, '^[%z\1-\127\194-\244][\128-\191]*') or '' -- one UTF-8 character, for non-Latin clients
    elseif element.NameFormat == 'upper' then
        name = strupper(name)
    end

    -- custom keeps the text's own Color
    if element.NameColor == 'class' then
        return Core:ColorTextByClass(name, Core.MyClass)
    elseif element.NameColor == 'theme' then
        return addon.GUI:ColorText(name)
    end

    return name
end

---The text with %n, %N.n, %i, %N.i, %casterName, \n and {rt1}..{rt8} filled in.
---%% stays LITERAL_PERCENT until the text's kind writes the sign.
---@param element table
---@param spellName string
---@param texture number|string?
---@param triggers table[]? the display's triggers, which %N.n and %N.i read
---@param reader table? answers `previewing`, `:GetTriggerName(trigger)` and `:GetTriggerTexture(trigger)`
---@return string
function Core:ExpandText(element, spellName, texture, triggers, reader)
    local raw = gsub(element.Text or '', '%%%%', LITERAL_PERCENT)
    -- only an aura button knows its caster, as a whole text; a preview shows the player
    raw = gsub(raw, CASTER_PATTERN, function()
        return reader and reader.previewing and Core:FormatCasterName(element.CasterClassColor, element.CasterRealm) or ''
    end)
    raw = gsub(raw, '\\n', '\n')
    raw = gsub(raw, '{rt(%d)}', RaidMarker)
    raw = gsub(raw, '%%(%d+)%.i', function(index)
        local trigger = triggers and triggers[tonumber(index)]
        local icon = trigger and reader and reader:GetTriggerTexture(trigger)
        return icon and ('|T' .. icon .. ':0|t') or ''
    end)
    raw = gsub(raw, '%%i', function()
        return texture and ('|T' .. texture .. ':0|t') or ''
    end)
    raw = gsub(raw, '%%(%d+)%.n', function(index)
        local trigger = triggers and triggers[tonumber(index)]
        return FormatName(self, element, trigger and reader and reader:GetTriggerName(trigger)) or ''
    end)

    return (gsub(raw, '%%n', function()
        return FormatName(self, element, spellName)
    end))
end

---A %p/%t text as a binding format: '{}' per token, each with a component that renders it.
---@param raw string
---@param element table
---@param global table? what a text on the Global time format uses, the plain breakpoints when nil
---@return string format, table[] components
function Core:DurationTextFormat(raw, element, global)
    local formatter = element.TimeFormat == 'custom'
        and Core:GetPrecisionDurationFormatter(element.PrecisionBelow, element.Precision)
        or global or Core:GetAuraDurationFormatter()

    local components = {}
    local format = gsub(raw, '%%%d*%.?([pt])', function(token)
        components[#components + 1] = { property = DURATION_TOKENS[token], formatter = formatter }
        return '{}'
    end)
    format = gsub(format, '%%%d*%.?s', '')

    return (gsub(format, LITERAL_PERCENT, '%%')), components
end

---The text's own point on the frame's point, then alignment, rotation and width.
---@param fs FontString
---@param element table
---@param parent Frame
---@param pin string? a text display's text sits on this point of its frame instead, picked by its alignment
function Core:PlaceText(fs, element, parent, pin)
    local position = element.Position
    local to = pin or position.AnchorTo or 'CENTER'
    local from = pin or position.AnchorFrom ~= 'AUTO' and position.AnchorFrom or to
    fs:SetFontJustify(from, parent, nil, nil, true, {
        { point = from, relTo = parent, relPoint = to, offsetX = pin and 0 or position.XOffset, offsetY = pin and 0 or position.YOffset },
    })
    if element.Justify ~= 'AUTO' then
        fs:SetJustifyH(element.Justify)
    end
    fs:SetRotation(TEXT_ROTATIONS[element.Rotation] or 0)

    local fixed = element.WidthMode == 'fixed'
    local wrap = not fixed or element.WordWrap
    fs:SetWidth(fixed and element.FixedWidth or 0)
    fs:SetWordWrap(wrap)
    fs:SetNonSpaceWrap(wrap)
end

---The formatter and colour curve the shared Duration Text settings give a time left.
---@return table formatter
---@return table? curve nil unless the colours follow the curve
function Core:GetSharedDurationText()
    local mode = Core:GetSharedDurationMode()
    local single = mode == 'single' and Core:GetSharedSettings().globalMedia.durationSingleColorValue or nil
    return Core:GetAuraDurationFormatter(mode == 'breakpoint', single), mode == 'curve' and Core.curves.AuraDurationColor or nil
end
