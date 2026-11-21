---@class NorskenCore
local Core = _G.NorskenCore
---@class NorskenCore.GUIAuraLook
local AuraLook = {}
Core.GUIAuraLook = AuraLook
local L = Core.L
local Theme = Core.Kaji.DEFAULT_THEME
local rowH = Theme.rowHeight
local Apply = Core.Enum.Apply
local SharedPages = Core.GUISharedPages
local ANCHOR_POINTS = Core.AnchorOptions
local UNIT_NAME_PATTERN = Core.UNIT_NAME_PATTERN
local CASTER_PATTERN = Core.CASTER_PATTERN

local tinsert, tremove = table.insert, table.remove
local strfind, strmatch = string.find, string.match
local pairs, ipairs = pairs, ipairs
local format = string.format
local CopyTable = CopyTable
local tonumber = tonumber
local floor = math.floor
local type = type

local HEADING_HEIGHT = 26

AuraLook.sectionOpen = {
    icon = true,
    text = true,
    ['size:icon'] = true,
    groupLayout = true,
    groupEnchants = true,
    groupPosition = true,
}
local sectionOpen = AuraLook.sectionOpen
local subOpen = {}

AuraLook.AuraGroupAdds = {
    { 'text',     L['Add Text'] },
    { 'border',   L['Add Border'] },
    { 'auratype', L['Add Aura Type Texture'] },
}

local TEXT_JUSTIFY = {
    { value = 'AUTO',   text = L['Automatic'] },
    { value = 'LEFT',   text = L['Left'] },
    { value = 'CENTER', text = L['Center'] },
    { value = 'RIGHT',  text = L['Right'] },
}

-- why a text stays empty, by the slot an earlier text took
local DROPPED_NOTES = {
    time = L['An aura shows one timer. An earlier text already shows it, so this one stays empty.'],
    count = L['An aura shows one stack count. An earlier text already shows it, so this one stays empty.'],
    caster = L['An aura shows one caster name. An earlier text already shows it, so this one stays empty.'],
    name = L['An aura shows one spell name. An earlier text already shows it, so this one stays empty.'],
}

local SUBREGION_NAMES = {
    text = L['Text'],
    border = L['Border'],
    glow = L['Glow'],
    tick = L['Tick'],
    tint = L['Tint'],
    auratype = L['Aura Type Texture'],
}

local TEXT_SELF_POINTS = {
    { value = 'AUTO', text = L['Automatic'] },
}
for _, point in ipairs(ANCHOR_POINTS) do
    TEXT_SELF_POINTS[#TEXT_SELF_POINTS + 1] = point
end

local TIME_FORMATS = {
    { value = 'global', text = L['Global'] },
    { value = 'custom', text = L['Custom'] },
}

local NUMBER_FORMATS = {
    { value = 'auto',       text = L['Automatic'] },
    { value = 'decimals',   text = L['Decimals'] },
    { value = 'abbreviate', text = L['Short'] },
    { value = 'large',      text = L['Short (Large)'] },
    { value = 'breakup',    text = L['Separated (12,345)'] },
}
-- a power's %p can also read as a percent of its max
local POWER_NUMBER_FORMATS = CopyTable(NUMBER_FORMATS)
POWER_NUMBER_FORMATS[#POWER_NUMBER_FORMATS + 1] = { value = 'percent', text = L['Percent'] }

local NAME_FORMATS = {
    { value = 'full',    text = L['Full'] },
    { value = 'initial', text = L['First Letter'] },
    { value = 'upper',   text = L['Uppercase'] },
}

local PRECISIONS = {
    { value = 1, text = '12.3' },
    { value = 2, text = '12.34' },
}

local TEXT_ROTATIONS = {
    { value = 'NONE',  text = L['None'] },
    { value = 'LEFT',  text = L['Left'] },
    { value = 'RIGHT', text = L['Right'] },
}

local TEXT_ALIGNMENTS = { TEXT_JUSTIFY[2], TEXT_JUSTIFY[3], TEXT_JUSTIFY[4] } -- a text display has no anchor to follow

local WIDTH_MODES = {
    { value = 'auto',  text = L['Automatic'] },
    { value = 'fixed', text = L['Fixed'] },
}

local TEXT_TOKENS = {
    { '%p',            L['Time left'] },
    { '%t',            L['Total time'] },
    { '%s',            L['Charges'] },
    { '%n',            L['Spell name'] },
    { '%2.n',          L["Trigger 2's name, e.g. the highest stat"] },
    { '%i',            L['Spell icon'] },
    { '%2.i',          L["Trigger 2's icon"] },
    { '%casterName',   L['Who cast the aura'] },
    { '%2.casterName', L["In an aura group, only on Trigger 2's auras"] },
    { '%%',            L['A percent sign'] },
    { '\\n',           L['New line'] },
    { '{rt1}',         L['Raid marker 1 to 8'] },
}

-- Structure --

---The centred heading between a Display card's sections.
---@param card table
---@param title string
function AuraLook.Heading(card, title)
    card:Separator(title, { useLabel = true, centered = true, height = HEADING_HEIGHT })
end

---Write a value at a path, copying nested tables first so two displays never share one.
---@param target table
---@param path string[]
---@param value any
function AuraLook.Assign(target, path, value)
    local node = target
    for i = 1, #path - 1 do
        local key = path[i]
        node[key] = CopyTable(node[key] or {})
        node = node[key]
    end
    node[path[#path]] = type(value) == 'table' and CopyTable(value) or value
end

---Two settings read the same: numbers to 2 decimals, tables key by key, unset as false.
---@param a any
---@param b any
---@return boolean
local function Same(a, b)
    if type(a) == 'table' or type(b) == 'table' then
        if type(a) ~= 'table' or type(b) ~= 'table' then return false end
        for key, value in pairs(a) do
            if not Same(value, b[key]) then return false end
        end
        for key, value in pairs(b) do
            if a[key] == nil and not Same(nil, value) then return false end
        end
        return true
    end
    if type(a) == 'number' and type(b) == 'number' then
        return floor(a * 100 + 0.5) == floor(b * 100 + 0.5)
    end
    return (a or false) == (b or false)
end

---`mixed(path)` for displays edited together: their values if they differ, nil if not.
---A setting read as `x or default` passes that default, so unset compares as what it draws.
---@param displays table[]
---@param read fun(display: table): table? where the path starts: its style, a sub element, the display itself
---@return fun(path: (string|number)[], default: any?): KajiGUIMixedEntry[]?
function AuraLook.Differ(displays, read)
    if not displays[2] then
        return function() return nil end
    end

    local function At(display, path, default)
        local node = read(display)
        for _, key in ipairs(path) do
            if node == nil then
                return default
            end
            node = node[key]
        end
        if node == nil then
            return default
        end
        return node
    end

    return function(path, default)
        local base = At(displays[1], path, default)
        local differs = false
        for i = 2, #displays do
            differs = differs or not Same(base, At(displays[i], path, default))
        end
        if not differs then return nil end

        local entries = {}
        for i, display in ipairs(displays) do
            entries[i] = { name = display.name, value = At(display, path, default) }
        end
        return entries
    end
end

---A collapsible section, closed until opened; its rows only exist while it's open.
---@param card table
---@param key string
---@param title string
---@param actions table?
---@return boolean expanded
function AuraLook.Section(card, key, title, actions)
    local config = {
        key = key,
        collapsed = not sectionOpen[key],
        onToggle = function()
            sectionOpen[key] = not sectionOpen[key] or nil
            card:Rebuild()
        end,
    }
    for name, handler in pairs(actions or {}) do
        config[name] = handler
    end
    return card:Section(title, config)
end

local Section = AuraLook.Section

---An animated header for the less used settings inside a section, closed until opened.
---@param card table
---@param key string
---@param title string
---@param summary string? what the closed header says about its settings
---@return boolean open
---@return KajiGUISectionHeader header
local function SubSection(card, key, title, summary)
    return card:SubSection(title, {
        key = key,
        summary = summary,
        collapsed = not subOpen[key],
        onToggle = function()
            subOpen[key] = not subOpen[key] or nil
            card:Rebuild()
        end,
    })
end

-- Icon --

---@alias AuraLookRows fun(card: table, page: table, style: table, set: fun(path: string[], value: any, part: NorskenCore.Apply), mixed: fun(path: (string|number)[], default: any?): KajiGUIMixedEntry[]?)

---An aura group's dispel type icon, where an icon picks its source.
---@type AuraLookRows
function AuraLook.DispelIconRows(card, page, style, set, mixed)
    page:SetCondition('cdm:dispelIcon', function() return style.DispelIcon == true or mixed({ 'DispelIcon' }) end)
    local dispelRow = card:Row(rowH)
    dispelRow:Checkbox(L['Show Dispel Icon'], {
        width = 0.5,
        value = style.DispelIcon,
        mixed = mixed({ 'DispelIcon' }),
        callback = function(checked)
            set({ 'DispelIcon' }, checked, Apply.Visibility)
            page:Refresh()
        end,
    })
    dispelRow:Slider(L['Dispel Icon Size'], {
        width = 0.5,
        conditions = { 'cdm:dispelIcon' },
        min = 6,
        max = 40,
        step = 1,
        value = style.DispelIconSize,
        mixed = mixed({ 'DispelIconSize' }),
        callback = function(value) set({ 'DispelIconSize' }, value, Apply.Layout) end,
    })
end

---@param card table
---@param page table
---@param style table read side
---@param set fun(path: string[], value: any, part: NorskenCore.Apply)
---@param mixed fun(path: (string|number)[], default: any?): KajiGUIMixedEntry[]?
---@param sourceRows AuraLookRows where the icon comes from: an icon's source, an aura group's DispelIconRows
function AuraLook.IconSettings(card, page, style, set, mixed, sourceRows)
    page:SetCondition('cdm:icon', function() return style.IconShow or mixed({ 'IconShow' }) end)

    local showRow = card:Row(rowH)
    showRow:Checkbox(L['Show Icon'], {
        width = 0.5,
        tooltip = L['Off leaves only the texts, borders and glows, such as an aura shown as just its stacks.'],
        value = style.IconShow,
        mixed = mixed({ 'IconShow' }),
        callback = function(checked)
            set({ 'IconShow' }, checked, Apply.Visibility)
            page:Refresh()
        end,
    })
    showRow:ColorPicker(L['Color'], {
        width = 0.5,
        conditions = { 'cdm:icon' },
        value = style.Color,
        mixed = mixed({ 'Color' }),
        callback = function(r, g, b, a) set({ 'Color' }, { r, g, b, a }, Apply.Color) end,
    })

    sourceRows(card, page, style, set, mixed)

    local lookRow = card:Row(rowH)
    lookRow:Checkbox(L['Desaturate'], {
        width = 0.5,
        conditions = { 'cdm:icon' },
        value = style.Desaturate,
        mixed = mixed({ 'Desaturate' }),
        callback = function(checked) set({ 'Desaturate' }, checked, Apply.Color) end,
    })
    lookRow:Slider(L['Zoom'], {
        width = 0.5,
        min = 0,
        max = 1,
        step = 0.01,
        conditions = { 'cdm:icon' },
        value = style.Zoom or Core.GlobalZoom,
        mixed = mixed({ 'Zoom' }, Core.GlobalZoom),
        callback = function(value) set({ 'Zoom' }, value, Apply.Look) end,
    })
    card:Row(rowH):Checkbox(L['Keep Aspect Ratio'], {
        width = 0.5,
        conditions = { 'cdm:icon' },
        tooltip = L['Crop the icon to the frame shape instead of stretching it.'],
        value = style.KeepAspectRatio,
        mixed = mixed({ 'KeepAspectRatio' }),
        callback = function(checked) set({ 'KeepAspectRatio' }, checked, Apply.Look) end,
    })
end

---@param card table
---@param page table
---@param style table
---@param set fun(path: string[], value: any, part: NorskenCore.Apply)
---@param mixed fun(path: (string|number)[], default: any?): KajiGUIMixedEntry[]?
---@param auraGroup boolean? an aura's swipe has no global cooldown to show
function AuraLook.SwipeSettings(card, page, style, set, mixed, auraGroup)
    page:SetCondition('cdm:swipe', function() return style.DrawSwipe == true or mixed({ 'DrawSwipe' }) end)
    local row1 = card:Row(rowH)
    row1:Checkbox(L['Enable Swipe'], {
        width = 0.5,
        value = style.DrawSwipe,
        mixed = mixed({ 'DrawSwipe' }),
        callback = function(checked)
            set({ 'DrawSwipe' }, checked, Apply.Visibility)
            page:Refresh()
        end,
    })
    row1:Checkbox(L['Inverse'], {
        width = 0.5,
        conditions = { 'cdm:swipe' },
        value = style.Reverse,
        mixed = mixed({ 'Reverse' }),
        callback = function(checked) set({ 'Reverse' }, checked, Apply.Look) end,
    })

    local row2 = card:Row(rowH)
    row2:Checkbox(L['Show Edge'], {
        width = 0.5,
        conditions = { 'cdm:swipe' },
        value = style.DrawEdge,
        mixed = mixed({ 'DrawEdge' }),
        callback = function(checked) set({ 'DrawEdge' }, checked, Apply.Look) end,
    })
    if not auraGroup then
        row2:Checkbox(L['Show Global Cooldown'], {
            width = 0.5,
            conditions = { 'cdm:swipe' },
            tooltip = L['Run the swipe for the global cooldown too.'],
            value = style.ShowGCD,
            mixed = mixed({ 'ShowGCD' }),
            callback = function(checked) set({ 'ShowGCD' }, checked, Apply.Visibility) end,
        })
    end

    card:Row(rowH):ColorPicker(L['Swipe Color'], {
        width = 0.5,
        conditions = { 'cdm:swipe' },
        value = style.SwipeColor,
        mixed = mixed({ 'SwipeColor' }),
        callback = function(r, g, b, a) set({ 'SwipeColor' }, { r, g, b, a }, Apply.Color) end,
    })
end

---The cooldown frame's own number, styled like a text.
---@param card table
---@param page table
---@param style table
---@param set fun(path: string[], value: any, part: NorskenCore.Apply)
---@param mixed fun(path: (string|number)[], default: any?): KajiGUIMixedEntry[]?
---@param triggers table[] the longest list among the displays, for the trigger picker
function AuraLook.TimerTextSettings(card, page, style, set, mixed, triggers)
    local function counts() return not style.HideCountdown or mixed({ 'HideCountdown' }) end
    page:SetCondition('cdm:timerText', counts)
    page:SetCondition('cdm:timerFont', function() return counts() and (not style.TimerText.UseGlobalFont or mixed({ 'TimerText', 'UseGlobalFont' })) end)
    -- the whole table is written, so an icon saved before Timer Text never holds half of one
    local function setTimer(key, value, part)
        local timer = CopyTable(style.TimerText)
        timer[key] = value
        set({ 'TimerText' }, timer, part)
    end
    local timer = style.TimerText

    local fontRow = card:Row(rowH)
    fontRow:Checkbox(L['Show Timer Text'], {
        width = 0.5,
        tooltip = L["The cooldown's own countdown, as the action bar shows it; unlike %p it speeds up with recovery-rate buffs."],
        value = not style.HideCountdown,
        mixed = mixed({ 'HideCountdown' }),
        callback = function(checked)
            set({ 'HideCountdown' }, not checked, Apply.Visibility)
            page:Refresh()
        end,
    })
    fontRow:Checkbox(L['Use Global Font'], {
        width = 0.5,
        conditions = { 'cdm:timerText' },
        value = timer.UseGlobalFont,
        mixed = mixed({ 'TimerText', 'UseGlobalFont' }),
        callback = function(checked)
            setTimer('UseGlobalFont', checked, Apply.Text)
            page:Refresh()
        end,
    })

    local sizeRow = card:Row(rowH)
    sizeRow:Dropdown(L['Font'], {
        width = 0.5,
        media = 'font',
        conditions = { 'cdm:timerFont' },
        value = timer.FontFace,
        mixed = mixed({ 'TimerText', 'FontFace' }),
        callback = function(value) setTimer('FontFace', value, Apply.Text) end,
    })
    sizeRow:Slider(L['Size'], {
        width = 0.5,
        conditions = { 'cdm:timerText' },
        min = 6,
        max = 40,
        step = 1,
        value = timer.FontSize,
        mixed = mixed({ 'TimerText', 'FontSize' }),
        callback = function(value) setTimer('FontSize', value, Apply.Text) end,
    })

    local outlineRow = card:Row(rowH)
    outlineRow:Dropdown(L['Outline'], {
        width = 0.5,
        conditions = { 'cdm:timerText' },
        options = Core:GetOutlineOptions(),
        value = timer.FontOutline,
        mixed = mixed({ 'TimerText', 'FontOutline' }),
        callback = function(value) setTimer('FontOutline', value, Apply.Text) end,
    })
    outlineRow:ColorPicker(L['Color'], {
        width = 0.5,
        conditions = { 'cdm:timerText' },
        value = timer.Color,
        mixed = mixed({ 'TimerText', 'Color' }),
        callback = function(r, g, b, a) setTimer('Color', { r, g, b, a }, Apply.Color) end,
    })

    local sources = { { value = 0, text = L['Automatic'] } }
    for i in ipairs(triggers) do
        sources[#sources + 1] = { value = i, text = format(L['Trigger %d'], i) }
    end
    local sourceRow = card:Row(rowH)
    sourceRow:Dropdown(L['Trigger'], {
        width = 0.5,
        conditions = { 'cdm:timerText' },
        tooltip = L["Whose countdown shows: Automatic is the icon's own, never an aura overlay's; a picked trigger's shows only while its layer does."],
        options = sources,
        value = timer.Trigger or 0,
        mixed = mixed({ 'TimerText', 'Trigger' }, 0),
        callback = function(value) setTimer('Trigger', value ~= 0 and value or nil, Apply.Visibility) end,
    })
    sourceRow:Dropdown(L['Anchor'], {
        width = 0.5,
        conditions = { 'cdm:timerText' },
        options = ANCHOR_POINTS,
        value = timer.AnchorTo,
        mixed = mixed({ 'TimerText', 'AnchorTo' }),
        callback = function(point) setTimer('AnchorTo', point, Apply.Position) end,
    })
    local offsetRow = card:Row(rowH)
    offsetRow:Slider(L['X Offset'], {
        width = 0.5,
        conditions = { 'cdm:timerText' },
        min = -40,
        max = 40,
        step = 1,
        value = timer.XOffset,
        mixed = mixed({ 'TimerText', 'XOffset' }),
        callback = function(value) setTimer('XOffset', value, Apply.Position) end,
    })
    offsetRow:Slider(L['Y Offset'], {
        width = 0.5,
        conditions = { 'cdm:timerText' },
        min = -40,
        max = 40,
        step = 1,
        value = timer.YOffset,
        mixed = mixed({ 'TimerText', 'YOffset' }),
        callback = function(value) setTimer('YOffset', value, Apply.Position) end,
    })
end

-- Layout --

---@param card table
---@param page table
---@param style table
---@param set fun(path: string[], value: any, part: NorskenCore.Apply)
---@param mixed fun(path: (string|number)[], default: any?): KajiGUIMixedEntry[]?
---@param isBar boolean? a bar's tooltip is its spell or item
---@param auraGroup boolean? an aura group's buttons can hide their tooltips in combat
function AuraLook.GeneralSettings(card, page, style, set, mixed, isBar, auraGroup)
    local row = card:Row(rowH)
    row:Slider(L['Alpha'], {
        width = 0.5,
        min = 0,
        max = 1,
        step = 0.05,
        value = style.Alpha,
        mixed = mixed({ 'Alpha' }),
        callback = function(value) set({ 'Alpha' }, value, Apply.Color) end,
    })
    row:Checkbox(L['Tooltip on Mouseover'], {
        width = 0.5,
        tooltip = isBar and L["The bar's spell or item; power bars have none."] or nil,
        value = style.Tooltip,
        mixed = mixed({ 'Tooltip' }),
        callback = function(checked)
            set({ 'Tooltip' }, checked, Apply.Visibility)
            page:Refresh()
        end,
    })
    if auraGroup then
        page:SetCondition('cdm:tooltip', function() return style.Tooltip == true or mixed({ 'Tooltip' }) end)
        card:Row(rowH):Checkbox(L['Hide Tooltip In Combat'], {
            width = 0.5,
            conditions = { 'cdm:tooltip' },
            value = style.TooltipHideInCombat,
            mixed = mixed({ 'TooltipHideInCombat' }),
            callback = function(checked) set({ 'TooltipHideInCombat' }, checked, Apply.Visibility) end,
        })
    end
end

---@param card table
---@param style table
---@param set fun(path: string[], value: any, part: NorskenCore.Apply)
---@param mixed fun(path: (string|number)[], default: any?): KajiGUIMixedEntry[]?
---@param maxSize number
---@param widthConditions string[]? a matched bar takes its group's width
function AuraLook.SizeRows(card, style, set, mixed, maxSize, widthConditions)
    local sizeRow = card:Row(rowH)
    sizeRow:Slider(L['Width'], {
        width = 0.5,
        conditions = widthConditions,
        min = 8,
        max = maxSize,
        step = 1,
        value = style.Width,
        mixed = mixed({ 'Width' }),
        callback = function(value) set({ 'Width' }, value, Apply.Layout) end,
    })
    sizeRow:Slider(L['Height'], {
        width = 0.5,
        min = 2,
        max = maxSize,
        step = 1,
        value = style.Height,
        mixed = mixed({ 'Height' }),
        callback = function(value) set({ 'Height' }, value, Apply.Layout) end,
    })
end

-- Text --

-- Whether a text writes a unit's name, which Class Color and Show Realm format
---@param text string?
---@return boolean
local function ReadsUnit(text)
    return strfind(text or '', CASTER_PATTERN) ~= nil or strfind(text or '', UNIT_NAME_PATTERN) ~= nil
end

---What a text's %p/%t stand for: a time on most triggers, a value on Power and Stat.
---@param text string?
---@param triggers table[]
---@param isValue (fun(trigger: table): boolean)?
---@return boolean readsTime
---@return boolean readsValue
---@return boolean readsPower
---@return boolean readsCount
---@return number? source the trigger its %N. token names
local function Reads(text, triggers, isValue)
    local hasDuration, hasCharges, source = Core:ClassifyText(text or '')
    -- an aura group's buttons read their own auras
    if not triggers[1] then
        return hasDuration, false, false, hasCharges, source
    end

    local readsTime, readsValue, readsPower, readsCount = false, false, false, false
    for index, trigger in ipairs(triggers) do
        if not source or index == source then
            if isValue and isValue(trigger) then
                readsValue = hasDuration or hasCharges
                readsPower = readsPower or (readsValue and trigger.Type == 'power')
            else
                readsTime = readsTime or hasDuration
                readsCount = readsCount or hasCharges
            end
        end
    end
    return readsTime, readsValue, readsPower, readsCount, source
end

---@class AuraLookTextContext
---@field displays table[] the displays this text is on; the first one's triggers are what %N.p tokens point into
---@field slot number where the text sits in each one's SubRegions
---@field pipName string? a split power bar's "Rune", whose texts can repeat on each one
---@field main boolean? a text display's own text: always shown, pinned at its alignment, no rotation
---@field dropped string? the aura button slot an earlier text already took: time, count, caster or name
---@field isValue (fun(trigger: table): boolean)? a trigger whose %p is a value, not a time
---@field noColor boolean? the caller colours it, so it has no Color row

---@param card table
---@param page table
---@param element table read side
---@param set fun(path: string[], value: any, part: NorskenCore.Apply)
---@param mixed fun(path: (string|number)[], default: any?): KajiGUIMixedEntry[]?
---@param key string unique per element, for its conditions and sub-sections
---@param ctx AuraLookTextContext
function AuraLook.TextRows(card, page, element, set, mixed, key, ctx)
    local displays, main, pipName = ctx.displays, ctx.main, ctx.pipName
    local shown, customFont, shadow = key .. ':shown', key .. ':font', key .. ':shadow'
    local customTime, decimals, fixedWidth = key .. ':time', key .. ':decimals', key .. ':fixed'
    page:SetCondition(shown, function() return element.Enabled == true or mixed({ 'Enabled' }) end)
    page:SetCondition(customFont, function() return element.UseGlobalFont ~= true or mixed({ 'UseGlobalFont' }) end)
    page:SetCondition(shadow, function() return element.FontShadow.Enabled == true or mixed({ 'FontShadow', 'Enabled' }) end)
    page:SetCondition(customTime, function() return element.TimeFormat == 'custom' or mixed({ 'TimeFormat' }) end)
    page:SetCondition(decimals, function()
        return (element.TimeFormat == 'custom' or mixed({ 'TimeFormat' })) and (element.PrecisionBelow > 0 or mixed({ 'PrecisionBelow' }))
    end)
    page:SetCondition(fixedWidth, function() return element.WidthMode == 'fixed' or mixed({ 'WidthMode' }) end)

    local triggers = displays[1].Triggers
    local readsTime, readsValue, readsPower, readsCount, source = Reads(element.Text, triggers, ctx.isValue)

    -- what the text can't show goes on its marker; a missing trigger or a dropped %s warns
    local sourceTrigger = source and triggers[source]
    local notes, level = {}, 'info'
    if readsTime and readsCount then -- a time's binding has no slot for a count; a Power or Stat value text mixes them fine
        notes[#notes + 1] = L["%s is dropped here: a time and a charge count can't share one text. Add a second text for it."]
        level = 'warning'
    end
    -- an aura group text naming a trigger shows only on that trigger's buttons
    local groupTrigger = not triggers[1] and displays[1].Trigger
    local named = groupTrigger and tonumber(strmatch(element.Text or '', '%%(%d+)%.'))
    if source and not sourceTrigger and triggers[1] or named and named > #Core:GetTriggerBranches(groupTrigger) then
        notes[#notes + 1] = format(L["There's no Trigger %d, so this text stays empty."], named or source)
        level = 'warning'
    elseif named then
        notes[#notes + 1] = format(L["Only shows on Trigger %d's auras."], named)
    elseif sourceTrigger and (sourceTrigger.Type == 'aura' or sourceTrigger.Type == 'auraoverlay') then
        notes[#notes + 1] = format(L['Only shows on the Trigger %d overlay.'], source)
    end
    if ctx.dropped then
        notes[#notes + 1] = DROPPED_NOTES[ctx.dropped]
        level = 'warning'
    end

    local textRow = card:Row(rowH)
    if not main then
        textRow:Checkbox(L['Show Text'], {
            width = 0.5,
            value = element.Enabled,
            mixed = mixed({ 'Enabled' }),
            callback = function(checked)
                set({ 'Enabled' }, checked, Apply.Visibility)
                page:Refresh()
            end,
        })
    end
    textRow:EditBox(L['Display Text'], {
        width = main and 1 or 0.5,
        conditions = { shown },
        tooltip = function(tooltip)
            local accent, secondary = page.gui.theme.accent, page.gui.theme.textSecondary
            tooltip:SetText(L['Display Text'], accent[1], accent[2], accent[3], 1, false)
            for _, token in ipairs(TEXT_TOKENS) do
                tooltip:AddDoubleLine(token[1], token[2], accent[1], accent[2], accent[3], secondary[1], secondary[2], secondary[3])
            end
            tooltip:AddLine(' ')
            tooltip:AddLine(L["%p and %t can't share a text with %s."], secondary[1], secondary[2], secondary[3], true)
            tooltip:AddLine(L['On Power, %p is the value and %t the max; on Player Stat, %p is the percent and %t the rating.'], secondary[1], secondary[2], secondary[3], true)
            tooltip:AddLine(L['%2.p, %2.t or %2.s read Trigger 2 instead of the shown trigger. A text reads one trigger.'], secondary[1], secondary[2], secondary[3], true)
            tooltip:AddLine(L['%casterName only works on an aura, as a text of its own.'], secondary[1], secondary[2], secondary[3], true)
        end,
        notice = notes[1] and { level = level, text = notes } or nil,
        value = element.Text,
        mixed = mixed({ 'Text' }),
        callback = function(text)
            set({ 'Text' }, text, Apply.Text)
            card:Rebuild()
        end,
    })
    if pipName then
        card:Row(rowH):Checkbox(format(L['Each %s'], pipName), {
            width = 0.5,
            conditions = { shown },
            tooltip = format(L['Repeat the text on every %s.'], pipName),
            value = element.EachPip,
            mixed = mixed({ 'EachPip' }),
            callback = function(checked) set({ 'EachPip' }, checked or nil, Apply.Visibility) end,
        })
    end

    local fontRow = card:Row(rowH)
    fontRow:Checkbox(L['Use Global Font'], {
        width = 0.5,
        conditions = { shown },
        value = element.UseGlobalFont,
        mixed = mixed({ 'UseGlobalFont' }),
        callback = function(checked)
            set({ 'UseGlobalFont' }, checked, Apply.Text)
            page:Refresh()
        end,
    })
    fontRow:Dropdown(L['Font'], {
        width = 0.5,
        media = 'font',
        conditions = { shown, customFont },
        value = element.FontFace,
        mixed = mixed({ 'FontFace' }),
        callback = function(value) set({ 'FontFace' }, value, Apply.Text) end,
    })

    local sizeRow = card:Row(rowH)
    sizeRow:Slider(L['Size'], {
        width = 0.5,
        conditions = { shown },
        min = 6,
        max = main and 72 or 40,
        step = 1,
        value = element.FontSize,
        mixed = mixed({ 'FontSize' }),
        callback = function(value) set({ 'FontSize' }, value, Apply.Text) end,
    })
    sizeRow:Dropdown(L['Outline'], {
        width = 0.5,
        conditions = { shown },
        options = Core:GetOutlineOptions(),
        value = element.FontOutline,
        mixed = mixed({ 'FontOutline' }),
        callback = function(value) set({ 'FontOutline' }, value, Apply.Text) end,
    })

    page:SetCondition(key .. ':numberDecimals', function() return element.NumberFormat == 'decimals' or mixed({ 'NumberFormat' }, 'auto') end)

    -- only a text with a time, value, count or name has anything to format
    local readsName = strfind(element.Text or '', '%%%d*%.?n') ~= nil
    local readsCaster = ReadsUnit(element.Text)
    for i = 2, #displays do
        local other = displays[i].SubRegions[ctx.slot].Text
        local time, value, power, count = Reads(other, displays[i].Triggers, ctx.isValue)
        readsTime = readsTime or time
        readsValue = readsValue or value
        readsPower = readsPower or power
        readsCount = readsCount or count
        readsName = readsName or strfind(other or '', '%%%d*%.?n') ~= nil
        readsCaster = readsCaster or ReadsUnit(other)
    end

    if not ctx.noColor then
        local ownColor = key .. ':ownColor'
        page:SetCondition(ownColor, function()
            return not (readsTime and element.GlobalTimeColor) or mixed({ 'GlobalTimeColor' }) ~= nil
        end)
        local colorRow = card:Row(rowH)
        colorRow:ColorPicker(L['Color'], {
            width = 0.5,
            conditions = { shown, ownColor },
            value = element.Color,
            mixed = mixed({ 'Color' }),
            callback = function(r, g, b, a) set({ 'Color' }, { r, g, b, a }, Apply.Color) end,
        })
        if readsTime then
            colorRow:Checkbox(L['Global Duration Color'], {
                width = 0.5,
                conditions = { shown },
                tooltip = L['Colors the time like Global Settings > Duration Text.'],
                link = SharedPages:GlobalLink(page.gui, SharedPages.DURATION_TEXT_ITEM, L['Open Duration Text']),
                value = element.GlobalTimeColor,
                mixed = mixed({ 'GlobalTimeColor' }),
                callback = function(checked)
                    set({ 'GlobalTimeColor' }, checked, Apply.Color)
                    page:Refresh()
                end,
            })
        end
    end
    local formatOpen = (readsTime or readsValue or readsCount or readsName or readsCaster) and SubSection(card, key .. ':format', L['Format Options'])
    if formatOpen and readsCaster then
        local casterRow = card:Row(rowH)
        casterRow:Checkbox(L['Class Color'], {
            width = 0.5,
            conditions = { shown },
            tooltip = L["Colors %casterName and %unitName by class, in the game's class colors."],
            value = element.CasterClassColor,
            mixed = mixed({ 'CasterClassColor' }),
            callback = function(checked) set({ 'CasterClassColor' }, checked or nil, Apply.Color) end,
        })
        casterRow:Checkbox(L['Show Realm'], {
            width = 0.5,
            conditions = { shown },
            value = element.CasterRealm,
            mixed = mixed({ 'CasterRealm' }),
            callback = function(checked) set({ 'CasterRealm' }, checked or nil, Apply.Text) end,
        })
    end
    if formatOpen and readsName then
        local nameRow = card:Row(rowH)
        nameRow:Dropdown(L['Name Format'], {
            width = 0.5,
            conditions = { shown },
            tooltip = L['How %n reads. First Letter turns Mastery into M, Uppercase into MASTERY.'],
            options = NAME_FORMATS,
            value = element.NameFormat or 'full',
            mixed = mixed({ 'NameFormat' }, 'full'),
            callback = function(value) set({ 'NameFormat' }, value, Apply.Text) end,
        })
        nameRow:Dropdown(L['Name Color'], {
            width = 0.5,
            conditions = { shown },
            tooltip = L["The colour of %n. Custom uses the text's Color."],
            options = Core.ColorModeOptions,
            value = element.NameColor or 'custom',
            mixed = mixed({ 'NameColor' }, 'custom'),
            callback = function(value) set({ 'NameColor' }, value, Apply.Color) end,
        })
    end
    if formatOpen and readsValue then
        local numberRow = card:Row(rowH)
        numberRow:Dropdown(L['Number Format'], {
            width = 0.5,
            conditions = { shown },
            tooltip = readsPower and L['How a Power value reads. Automatic: whole numbers. Percent: %p as a share of the max, like Stagger against your health.']
                or L['How a Power or Stat value reads. Automatic: whole numbers, as the character sheet shows them.'],
            options = readsPower and POWER_NUMBER_FORMATS or NUMBER_FORMATS,
            value = element.NumberFormat or 'auto',
            mixed = mixed({ 'NumberFormat' }, 'auto'),
            callback = function(value)
                set({ 'NumberFormat' }, value, Apply.Text)
                page:Refresh()
            end,
        })
        numberRow:Slider(L['Decimals'], {
            width = 0.5,
            conditions = { shown, key .. ':numberDecimals' },
            min = 0,
            max = 3,
            step = 1,
            value = element.Decimals or 1,
            mixed = mixed({ 'Decimals' }, 1),
            callback = function(value) set({ 'Decimals' }, value, Apply.Text) end,
        })
    end
    if formatOpen and readsCount then
        card:Row(rowH):Checkbox(L['Hide Zero'], {
            width = 0.5,
            conditions = { shown },
            tooltip = L['%s shows nothing instead of 0.'],
            value = element.HideZero,
            mixed = mixed({ 'HideZero' }),
            callback = function(checked) set({ 'HideZero' }, checked or nil, Apply.Visibility) end,
        })
    end
    if formatOpen and readsTime then
        card:Row(rowH):Dropdown(L['Time Format'], {
            width = 0.5,
            conditions = { shown },
            tooltip = L['Global uses the duration breakpoints from the global settings.'],
            options = TIME_FORMATS,
            value = element.TimeFormat,
            mixed = mixed({ 'TimeFormat' }),
            callback = function(value)
                set({ 'TimeFormat' }, value, Apply.Text)
                page:Refresh()
            end,
        })

        local precisionRow = card:Row(rowH)
        precisionRow:Slider(L['Increase Precision Below'], {
            width = 0.5,
            conditions = { shown, customTime },
            tooltip = L['Seconds left at which the time shows decimals. 0 never shows them.'],
            min = 0,
            max = 60,
            step = 1,
            value = element.PrecisionBelow,
            mixed = mixed({ 'PrecisionBelow' }),
            callback = function(value)
                set({ 'PrecisionBelow' }, value, Apply.Text)
                page:Refresh()
            end,
        })
        precisionRow:Dropdown(L['Precision'], {
            width = 0.5,
            conditions = { shown, decimals },
            options = PRECISIONS,
            value = element.Precision,
            mixed = mixed({ 'Precision' }),
            callback = function(value) set({ 'Precision' }, value, Apply.Text) end,
        })
    end

    local fontShadow = element.FontShadow
    local function FlagsSummary()
        if not fontShadow.Enabled then
            return L['None']
        end
        local c = fontShadow.Color
        local swatch = format('|cff%02x%02x%02x%s|r', c[1] * 255, c[2] * 255, c[3] * 255, L['Color'])
        return format(L['Shadow %s with offset %d/%d'], swatch, fontShadow.OffsetX, fontShadow.OffsetY)
    end
    local flagsOpen, flagsHeader = SubSection(card, key .. ':shadow', L['Font Flags'], FlagsSummary())
    local function setShadow(path, value)
        set(path, value, Apply.Text)
        flagsHeader:SetSummary(FlagsSummary())
    end
    if flagsOpen then
        local toggleRow = card:Row(rowH)
        toggleRow:Checkbox(L['Shadow'], {
            width = 0.5,
            conditions = { shown },
            value = fontShadow.Enabled,
            mixed = mixed({ 'FontShadow', 'Enabled' }),
            callback = function(checked)
                setShadow({ 'FontShadow', 'Enabled' }, checked)
                page:Refresh()
            end,
        })
        toggleRow:ColorPicker(L['Shadow Color'], {
            width = 0.5,
            conditions = { shown, shadow },
            value = fontShadow.Color,
            mixed = mixed({ 'FontShadow', 'Color' }),
            callback = function(r, g, b, a) setShadow({ 'FontShadow', 'Color' }, { r, g, b, a }) end,
        })

        local offsetRow = card:Row(rowH)
        offsetRow:Slider(L['Shadow X'], {
            width = 0.5,
            conditions = { shown, shadow },
            min = -5,
            max = 5,
            step = 1,
            value = fontShadow.OffsetX,
            mixed = mixed({ 'FontShadow', 'OffsetX' }),
            callback = function(value) setShadow({ 'FontShadow', 'OffsetX' }, value) end,
        })
        offsetRow:Slider(L['Shadow Y'], {
            width = 0.5,
            conditions = { shown, shadow },
            min = -5,
            max = 5,
            step = 1,
            value = fontShadow.OffsetY,
            mixed = mixed({ 'FontShadow', 'OffsetY' }),
            callback = function(value) setShadow({ 'FontShadow', 'OffsetY' }, value) end,
        })

        local alignRow = card:Row(rowH)
        if not main then
            alignRow:Dropdown(L['Rotate Text'], {
                width = 0.5,
                conditions = { shown },
                options = TEXT_ROTATIONS,
                value = element.Rotation,
                mixed = mixed({ 'Rotation' }),
                callback = function(value) set({ 'Rotation' }, value, Apply.Text) end,
            })
        end
        alignRow:Dropdown(L['Alignment'], {
            width = 0.5,
            conditions = { shown },
            tooltip = main and L['The side the text grows from, and how its lines line up.'] or L['Automatic aligns the text to the side it is anchored on.'],
            options = main and TEXT_ALIGNMENTS or TEXT_JUSTIFY,
            value = element.Justify,
            mixed = mixed({ 'Justify' }),
            callback = function(value) set({ 'Justify' }, value, Apply.Text) end,
        })

        local widthRow = card:Row(rowH)
        widthRow:Dropdown(L['Width'], {
            width = 0.5,
            conditions = { shown },
            options = WIDTH_MODES,
            value = element.WidthMode,
            mixed = mixed({ 'WidthMode' }),
            callback = function(value)
                set({ 'WidthMode' }, value, Apply.Layout)
                page:Refresh()
            end,
        })
        widthRow:Slider(L['Fixed Width'], {
            width = 0.5,
            conditions = { shown, fixedWidth },
            min = 8,
            max = 256,
            step = 1,
            value = element.FixedWidth,
            mixed = mixed({ 'FixedWidth' }),
            callback = function(value) set({ 'FixedWidth' }, value, Apply.Layout) end,
        })
        card:Row(rowH):Checkbox(L['Word Wrap'], {
            width = 0.5,
            conditions = { shown, fixedWidth },
            tooltip = L['Off cuts a text longer than the width short instead of wrapping it.'],
            value = element.WordWrap,
            mixed = mixed({ 'WordWrap' }),
            callback = function(checked) set({ 'WordWrap' }, checked, Apply.Text) end,
        })
    end
    if main then return end

    local position = element.Position
    local function AnchorSummary()
        local pointName = position.AnchorTo
        for _, point in ipairs(ANCHOR_POINTS) do
            if point.value == position.AnchorTo then
                pointName = point.text
            end
        end
        local summary = format(L["Anchored to frame's %s"], pointName)
        if position.XOffset == 0 and position.YOffset == 0 then
            return summary
        end
        return format(L['%s with offset %d/%d'], summary, position.XOffset, position.YOffset)
    end
    local anchorOpen, anchorHeader = SubSection(card, key .. ':anchor', L['Anchors'], AnchorSummary())
    local function setPosition(path, value)
        set(path, value, Apply.Position)
        anchorHeader:SetSummary(AnchorSummary())
    end
    if anchorOpen then
        local pointRow = card:Row(rowH)
        pointRow:Dropdown(L['Anchor'], {
            width = 0.5,
            conditions = { shown },
            tooltip = L["The text's own point. Automatic keeps the text inside the icon at the frame's point."],
            options = TEXT_SELF_POINTS,
            value = position.AnchorFrom,
            mixed = mixed({ 'Position', 'AnchorFrom' }),
            callback = function(point) setPosition({ 'Position', 'AnchorFrom' }, point) end,
        })
        pointRow:Dropdown(L["To Frame's"], {
            width = 0.5,
            conditions = { shown },
            options = ANCHOR_POINTS,
            value = position.AnchorTo,
            mixed = mixed({ 'Position', 'AnchorTo' }),
            callback = function(point) setPosition({ 'Position', 'AnchorTo' }, point) end,
        })

        local offsetRow = card:Row(rowH)
        offsetRow:Slider(L['X Offset'], {
            width = 0.5,
            conditions = { shown },
            min = -40,
            max = 40,
            step = 1,
            value = position.XOffset,
            mixed = mixed({ 'Position', 'XOffset' }),
            callback = function(value) setPosition({ 'Position', 'XOffset' }, value) end,
        })
        offsetRow:Slider(L['Y Offset'], {
            width = 0.5,
            conditions = { shown },
            min = -40,
            max = 40,
            step = 1,
            value = position.YOffset,
            mixed = mixed({ 'Position', 'YOffset' }),
            callback = function(value) setPosition({ 'Position', 'YOffset' }, value) end,
        })
    end
end

-- Border --

---@param card table
---@param page table
---@param element table
---@param set fun(path: string[], value: any, part: NorskenCore.Apply)
---@param mixed fun(path: (string|number)[], default: any?): KajiGUIMixedEntry[]?
---@param key string
---@param pipName string? a split power bar's "Rune", whose borders can repeat on each one
local function BorderRows(card, page, element, set, mixed, key, pipName)
    local shown = key .. ':shown'
    page:SetCondition(shown, function() return element.Enabled == true or mixed({ 'Enabled' }) end)

    local showRow = card:Row(rowH)
    showRow:Checkbox(L['Show Border'], {
        width = pipName and 0.5 or 1,
        value = element.Enabled,
        mixed = mixed({ 'Enabled' }),
        callback = function(checked)
            set({ 'Enabled' }, checked, Apply.Visibility)
            page:Refresh()
        end,
    })
    if pipName then
        showRow:Checkbox(format(L['Each %s'], pipName), {
            width = 0.5,
            conditions = { shown },
            tooltip = format(L['Outline every %s instead of the whole bar.'], pipName),
            value = element.EachPip,
            mixed = mixed({ 'EachPip' }),
            callback = function(checked) set({ 'EachPip' }, checked or nil, Apply.Visibility) end,
        })
    end

    card:Row(rowH):ColorPicker(L['Border Color'], {
        width = 1,
        conditions = { shown },
        value = element.Color,
        mixed = mixed({ 'Color' }),
        callback = function(r, g, b, a) set({ 'Color' }, { r, g, b, a }, Apply.Color) end,
    })

    local sizeRow = card:Row(rowH)
    sizeRow:Slider(L['Border Size'], {
        width = 0.5,
        conditions = { shown },
        min = 1,
        max = 16,
        step = 1,
        value = element.Size,
        mixed = mixed({ 'Size' }),
        callback = function(value) set({ 'Size' }, value, Apply.Look) end,
    })
    sizeRow:Slider(L['Border Offset'], {
        width = 0.5,
        conditions = { shown },
        min = -10,
        max = 10,
        step = 1,
        value = element.Offset,
        mixed = mixed({ 'Offset' }),
        callback = function(value) set({ 'Offset' }, value, Apply.Look) end,
    })
end

-- Aura type texture --

local SHOW_ON = {
    { value = 'both',    text = L['Buffs & Debuffs'] },
    { value = 'helpful', text = L['Buffs'] },
    { value = 'harmful', text = L['Debuffs'] },
}
-- only a group with weapon enchants can leave its auras uncoloured and still draw something
local SHOW_ON_ENCHANTS = CopyTable(SHOW_ON)
SHOW_ON_ENCHANTS[#SHOW_ON_ENCHANTS + 1] = { value = 'enchants', text = L['None (Enchants Only)'] }

---The aura border art in its dispel type colour; on a weapon enchant, the enchant colour.
---@param card table
---@param page table
---@param element table read side
---@param set fun(path: (string|number)[], value: any, part: NorskenCore.Apply)
---@param mixed fun(path: (string|number)[], default: any?): KajiGUIMixedEntry[]?
---@param key string unique per element, for its conditions
---@param enchants boolean? the group shows weapon enchants, which always take the enchant colour
local function AuraTypeRows(card, page, element, set, mixed, key, enchants)
    local shown, typed = key .. ':shown', key .. ':typed'
    page:SetCondition(shown, function() return element.Enabled == true or mixed({ 'Enabled' }) end)
    page:SetCondition(typed, function()
        return element.ShowHelpful or element.ShowHarmful or mixed({ 'ShowHelpful' }) or mixed({ 'ShowHarmful' })
    end)

    local first = card:Row(rowH)
    first:Checkbox(L['Show Aura Type Texture'], {
        width = 0.5,
        tooltip = L['The aura border art in the color of the aura\'s dispel type, or the enchant color on a weapon enchant.'],
        value = element.Enabled,
        mixed = mixed({ 'Enabled' }),
        callback = function(checked)
            set({ 'Enabled' }, checked, Apply.Visibility)
            page:Refresh()
        end,
    })
    -- the game's dispel palette has no alpha, so the texture's own goes on top
    first:Slider(L['Opacity'], {
        width = 0.5,
        conditions = { shown },
        min = 0,
        max = 1,
        step = 0.05,
        value = element.Alpha,
        mixed = mixed({ 'Alpha' }),
        callback = function(value) set({ 'Alpha' }, value, Apply.Color) end,
    })

    -- stored as the two flags the game takes; neither leaves only the enchants
    local options = enchants and SHOW_ON_ENCHANTS or SHOW_ON
    local helpful, harmful = element.ShowHelpful, element.ShowHarmful
    local showOn = helpful and harmful and 'both' or helpful and 'helpful' or harmful and 'harmful' or 'enchants'
    local kinds = card:Row(rowH)
    kinds:Dropdown(L['Show On'], {
        width = 0.5,
        conditions = { shown },
        options = options,
        value = showOn,
        mixed = mixed({ 'ShowHelpful' }) or mixed({ 'ShowHarmful' }),
        callback = function(value)
            set({ 'ShowHelpful' }, value == 'both' or value == 'helpful', Apply.Visibility)
            set({ 'ShowHarmful' }, value == 'both' or value == 'harmful', Apply.Visibility)
            page:Refresh()
        end,
    })
    kinds:Checkbox(L['Show Without Dispel Type'], {
        width = 0.5,
        conditions = { shown, typed },
        value = element.DispelUntyped,
        mixed = mixed({ 'DispelUntyped' }),
        callback = function(checked) set({ 'DispelUntyped' }, checked, Apply.Visibility) end,
    })
end

-- Tint --

---A tint: a flat colour or a texture over the icon, coloured the way its Color Mode says.
---@param card table
---@param page table
---@param element table read side
---@param set fun(path: (string|number)[], value: any, part: NorskenCore.Apply)
---@param mixed fun(path: (string|number)[], default: any?): KajiGUIMixedEntry[]?
---@param key string unique per element, for its conditions
---@param modes { value: string, text: string }[] the colour modes this caller offers
function AuraLook.TintRows(card, page, element, set, mixed, key, modes)
    local shown, custom, typed = key .. ':shown', key .. ':custom', key .. ':typed'
    page:SetCondition(shown, function() return element.Enabled == true or mixed({ 'Enabled' }) end)
    page:SetCondition(custom, function() return element.ColorMode == 'custom' or mixed({ 'ColorMode' }) end)
    page:SetCondition(typed, function() return element.ColorMode == 'dispel' or mixed({ 'ColorMode' }) end)

    local first = card:Row(rowH)
    first:Checkbox(L['Show Tint'], {
        width = 0.5,
        value = element.Enabled,
        mixed = mixed({ 'Enabled' }),
        callback = function(checked)
            set({ 'Enabled' }, checked, Apply.Visibility)
            page:Refresh()
        end,
    })
    first:Dropdown(L['Color Mode'], {
        width = 0.5,
        conditions = { shown },
        options = modes,
        value = element.ColorMode,
        mixed = mixed({ 'ColorMode' }),
        callback = function(value)
            set({ 'ColorMode' }, value, Apply.Color)
            page:Refresh()
        end,
    })

    local look = card:Row(rowH)
    look:Dropdown(L['Texture'], {
        width = 0.5,
        conditions = { shown },
        media = 'statusbar',
        searchable = true,
        value = element.Texture,
        mixed = mixed({ 'Texture' }),
        tooltip = L['Leave empty for a flat color.'],
        callback = function(value) set({ 'Texture' }, value, Apply.Look) end,
    })
    look:Checkbox(L['Solid'], {
        width = 0.5,
        conditions = { shown },
        value = element.Solid,
        mixed = mixed({ 'Solid' }),
        tooltip = L['Draw the tint over the bar instead of adding to it, so alpha reads as real opacity.'],
        callback = function(checked) set({ 'Solid' }, checked, Apply.Look) end,
    })

    card:Row(rowH):ColorPicker(L['Tint Color'], {
        width = 1,
        conditions = { shown, custom },
        value = element.Color,
        mixed = mixed({ 'Color' }),
        callback = function(r, g, b, a) set({ 'Color' }, { r, g, b, a }, Apply.Color) end,
    })
    -- the game's dispel palette has no alpha, so the tint's own goes on top
    local dispelRow = card:Row(rowH)
    dispelRow:Slider(L['Opacity'], {
        width = 0.5,
        conditions = { shown, typed },
        min = 0,
        max = 1,
        step = 0.05,
        value = element.Color[4] or 1,
        mixed = mixed({ 'Color', 4 }),
        callback = function(value) set({ 'Color', 4 }, value, Apply.Color) end,
    })
    dispelRow:Checkbox(L['Show Without Dispel Type'], {
        width = 0.5,
        conditions = { shown, typed },
        value = element.DispelUntyped,
        mixed = mixed({ 'DispelUntyped' }),
        callback = function(checked) set({ 'DispelUntyped' }, checked or nil, Apply.Visibility) end,
    })
end

-- Sub elements --

---Rows standing between the sub elements, which a move crosses instead of swapping.
---@class AuraLookOverlays
---@field rows fun(slot: number) draws the rows sitting under element `slot`, 0 for under every element
---@field adjacent fun(slot: number, closestFirst: boolean): number? the row right at `slot`
---@field move fun(row: number, by: number) moves that row one element along

---@class AuraLookSubElements
---@field adds { [1]: string, [2]: string }[] the sub element kinds the Add buttons offer, with their labels
---@field tintModes { value: string, text: string }[]? the colour modes a tint offers, when `adds` has one
---@field enchants boolean? the group shows weapon enchants, see AuraTypeRows
---@field pipName string? a split power bar's "Rune"
---@field isValue (fun(trigger: table): boolean)? see TextRows
---@field dropped table<table, string>? texts an aura button leaves empty, see Core:DroppedAuraTexts
---@field auraGroup boolean? an aura group's button, whose dropped texts are found here
---@field rows fun(card: table, page: table, element: table, set: function, mixed: function, key: string)? kinds this file doesn't draw
---@field remap fun(display: table, remap: fun(n: number): number?, index: number, by: number?)? `by` 1 copied, -1 removed
---@field overlays AuraLookOverlays?

---The sub element list: a section per element, then the Add buttons.
---@param card table
---@param page table
---@param displays table[] edited together; writes reach every one
---@param apply fun(part: NorskenCore.Apply)
---@param opts AuraLookSubElements
function AuraLook.SubElements(card, page, displays, apply, opts)
    local first = displays[1]
    first.SubRegions = first.SubRegions or {}

    -- every display must hold the same kinds of element in the same order
    for i = 2, #displays do
        local other = displays[i].SubRegions or {}
        local differs = #other ~= #first.SubRegions
        for index, element in ipairs(first.SubRegions) do
            differs = differs or not other[index] or other[index].type ~= element.type
        end
        if differs then
            card:Row(rowH):Text(nil, { width = 1, text = L['These icons have different sub elements; edit them per icon.'], bgMode = 'hide' })
            return
        end
    end

    local function Each(fn)
        for _, display in ipairs(displays) do
            display.SubRegions = display.SubRegions or {}
            fn(display.SubRegions, display)
        end
        apply(Apply.Look)
        card:Rebuild()
    end
    local function Remap(display, remap, index, by)
        if opts.remap then
            opts.remap(display, remap, index, by)
        end
    end

    local overlays = opts.overlays
    local function OverlayRows(slot)
        if overlays then
            overlays.rows(slot)
        end
    end
    local function Adjacent(slot, closestFirst)
        return overlays and overlays.adjacent(slot, closestFirst)
    end

    -- texts an aura button leaves empty, as an earlier one took the game's slot for them
    local dropped = opts.dropped or opts.auraGroup and Core:DroppedGroupTexts(first.SubRegions, first.Trigger)

    local counts = {}
    local elements = first.SubRegions
    OverlayRows(0)
    for index, element in ipairs(elements) do
        counts[element.type] = (counts[element.type] or 0) + 1
        local title = format('%s %d', SUBREGION_NAMES[element.type] or element.type, counts[element.type])
        local key = 'cdm:sub:' .. first.type .. ':' .. index .. ':' .. element.type -- a mixed selection has a list per type

        local function set(path, value, part)
            for _, display in ipairs(displays) do
                AuraLook.Assign(display.SubRegions[index], path, value)
            end
            apply(part)
        end
        -- the same layout on all of them, so this is each one's element at this index
        local mixed = AuraLook.Differ(displays, function(display) return display.SubRegions[index] end)

        local above, below = Adjacent(index - 1, false), Adjacent(index, true)
        local slot = dropped and dropped[element] or nil
        local expanded = Section(card, key, title, {
            -- seen without opening the section
            notice = slot and { text = DROPPED_NOTES[slot] } or nil,
            onMoveUp = above and function() overlays.move(above, 1) end or index > 1 and function()
                Each(function(list, display)
                    list[index], list[index - 1] = list[index - 1], list[index]
                    Remap(display, function(n) return n == index and index - 1 or n == index - 1 and index or n end, index)
                end)
            end or nil,
            onMoveDown = below and function() overlays.move(below, -1) end or index < #elements and function()
                Each(function(list, display)
                    list[index], list[index + 1] = list[index + 1], list[index]
                    Remap(display, function(n) return n == index and index + 1 or n == index + 1 and index or n end, index)
                end)
            end or nil,
            onDuplicate = function()
                Each(function(list, display)
                    tinsert(list, index + 1, CopyTable(list[index]))
                    Remap(display, function(n) return n > index and n + 1 or n end, index, 1)
                end)
            end,
            onDelete = function()
                Each(function(list, display)
                    tremove(list, index)
                    Remap(display, function(n)
                        if n == index then return nil end
                        return n > index and n - 1 or n
                    end, index, -1)
                end)
            end,
        })

        if expanded then
            if element.type == 'text' then
                AuraLook.TextRows(card, page, element, set, mixed, key, {
                    displays = displays,
                    slot = index,
                    pipName = opts.pipName,
                    dropped = slot,
                    isValue = opts.isValue,
                })
            elseif element.type == 'border' then
                BorderRows(card, page, element, set, mixed, key, opts.pipName)
            elseif element.type == 'auratype' then
                AuraTypeRows(card, page, element, set, mixed, key, opts.enchants)
            elseif element.type == 'tint' then
                AuraLook.TintRows(card, page, element, set, mixed, key, opts.tintModes)
            elseif opts.rows then
                opts.rows(card, page, element, set, mixed, key)
            end
        end
        OverlayRows(index)
    end
    card:EndSection()
    card:Separator()

    local btnH = 24
    local adds = opts.adds
    local addRow
    for i, add in ipairs(adds) do
        if i % 2 == 1 then
            addRow = card:Row(btnH)
        end
        addRow:Button(add[2], {
            width = (i % 2 == 1 and i == #adds) and 1 or 0.5, -- a button alone on its row fills it
            height = btnH,
            callback = function()
                Each(function(list) list[#list + 1] = Core:NewSubRegion(add[1]) end)
            end,
        })
    end
end

-- Aura group --

---An aura group's extra Dynamic Group rows: the game sorts its auras and caps each trigger.
---@param card table
---@param db table the aura group's settings
---@param apply fun(part: NorskenCore.Apply)
function AuraLook.AuraGroupCountRows(card, db, apply)
    local function Set(key)
        return function(value)
            db[key] = value
            apply(Apply.Layout)
        end
    end

    local sortRow = card:Row(rowH)
    sortRow:Dropdown(L['Sort Method'], { width = 0.5, options = Core.GUIAuraCards.SortMethods, value = db.sortMethod, callback = Set('sortMethod') })
    sortRow:Dropdown(L['Sort Direction'], { width = 0.5, options = Core.GUIAuraCards.SortDirections, value = db.sortDirection, callback = Set('sortDirection') })

    local countRow = card:Row(Theme.rowHeightLast, 0)
    countRow:Slider(L['Auras Per Trigger'], {
        width = 0.5,
        tooltip = L['Each trigger shows up to this many, so several triggers can show more in total.'],
        min = 1,
        max = 40,
        step = 1,
        value = db.maxFrameCount,
        callback = Set('maxFrameCount'),
    })
    countRow:Slider(L['Preview Limit'], {
        width = 0.5,
        tooltip = L['How many auras the preview and the mover box show. The real auras are left alone.'],
        min = 1,
        max = 40,
        step = 1,
        value = db.previewLimit,
        callback = Set('previewLimit'),
    })
end

---An aura group's Display card: icon, swipe, timer text, size and general settings,
---then the sub elements, which `subElements` draws with the caller's own hooks.
---@param card table
---@param page table
---@param style table
---@param set fun(path: string[], value: any, part: NorskenCore.Apply)
---@param mixed fun(path: (string|number)[], default: any?): KajiGUIMixedEntry[]?
---@param noGeneral boolean? General sits on a card of its own, for a selection of several types
---@param subElements fun()
function AuraLook.AuraGroupRows(card, page, style, set, mixed, noGeneral, subElements)
    if Section(card, 'icon', L['Icon Settings']) then
        AuraLook.IconSettings(card, page, style, set, mixed, AuraLook.DispelIconRows)
    end
    if Section(card, 'swipe', L['Swipe Settings']) then
        AuraLook.SwipeSettings(card, page, style, set, mixed, true)
    end
    -- an aura group has no triggers to pick a countdown from
    if Section(card, 'timerText', L['Timer Text Settings']) then
        AuraLook.TimerTextSettings(card, page, style, set, mixed, {})
    end
    -- the group is placed on its own tab, its buttons by the game
    AuraLook.Heading(card, L['Layout'])
    if Section(card, 'size:auragroup', L['Size Settings']) then
        AuraLook.SizeRows(card, style, set, mixed, 128)
    end
    if not noGeneral and Section(card, 'general', L['General']) then
        AuraLook.GeneralSettings(card, page, style, set, mixed, false, true)
    end

    AuraLook.Heading(card, L['Sub Elements'])
    subElements()
end
