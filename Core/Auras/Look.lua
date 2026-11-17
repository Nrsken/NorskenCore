---@class NorskenCore
local Core = select(2, ...)

local ipairs, pairs = ipairs, pairs
local setmetatable = setmetatable
local CreateFrame = CreateFrame
local CopyTable = CopyTable
local strmatch, strfind = string.match, string.find
local gsub = string.gsub
local strtrim = strtrim
local tonumber = tonumber
local unpack = unpack
local type = type
local select = select
local max = math.max
local sort, concat = table.sort, table.concat
local tostring = tostring

local BindingProperty = Enum.DurationTextBindingProperty
local PreserveAsset = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset

--[[
How an aura button looks: the style and sub elements both addons save and the pass that puts a
resolved look on a native AuraButton; their text tokens are Text.lua's. NorskenAuras works out
what conditions, overlays and bars change before handing it over; the unit frames hand over their
saved look as it is.
]]

-- the border and pandemic art our aura buttons draw
Core.AURA_OVERLAY_TEXTURE = Core.Media.GUITextures .. 'AuraOverlay.png'

-- Templates --

-- Every new icon starts from this; an icon owns its full style from then on.
Core.ICON_STYLE_TEMPLATE = {
    Width = 40,
    Height = 40,
    KeepAspectRatio = false,
    Color = { 1, 1, 1, 1 },
    Desaturate = false,
    IconSource = 'auto',
    IconShow = true,
    Tooltip = false,
    Alpha = 1,
    DrawSwipe = true,
    Reverse = false,
    DrawEdge = false,
    SwipeColor = { 0, 0, 0, 0.7 },
    ShowGCD = false,
    HideCountdown = true,
    DispelIcon = false,
    DispelIconSize = 10,
    -- nil is the top right corner; { AnchorFrom, AnchorTo, XOffset, YOffset } puts it elsewhere
    DispelIconPosition = nil,
    -- the cooldown's own number: unlike %p it follows recovery-rate buffs like the action bar
    TimerText = {
        UseGlobalFont = true,
        FontFace = 'Expressway',
        FontSize = 15,
        FontOutline = 'OUTLINE',
        Color = { 1, 1, 1, 1 },
        AnchorTo = 'CENTER',
        XOffset = 0,
        YOffset = 0,
    },
}

Core.SUBREGION_TEMPLATES = {
    text = {
        type = 'text',
        Enabled = true,
        Text = '%p',
        UseGlobalFont = true,
        FontFace = 'Expressway',
        FontOutline = 'OUTLINE',
        FontShadow = { Enabled = false, Color = { 0, 0, 0, 1 }, OffsetX = 1, OffsetY = -1 },
        FontSize = 15,
        Color = { 1, 1, 1, 1 },
        GlobalTimeColor = false, -- %p/%t: the shared Duration Text colours instead of Color
        TimeFormat = 'global',
        PrecisionBelow = 3,
        Precision = 1,
        NumberFormat = 'auto', -- values (power, stats): auto, decimals, abbreviate, large, breakup, percent (power only)
        Decimals = 1,
        HideZero = true,       -- %s
        NameFormat = 'full',   -- %n: full, initial, upper
        NameColor = 'custom',  -- %n: custom (the text's Color), class, theme
        Rotation = 'NONE',
        Justify = 'AUTO',
        WidthMode = 'auto',
        FixedWidth = 64,
        WordWrap = true,
        Position = { AnchorFrom = 'AUTO', AnchorTo = 'CENTER', XOffset = 0, YOffset = 0 },
    },
    border = {
        type = 'border',
        Enabled = true,
        Color = { 0, 0, 0, 1 },
        Size = 1,
        Offset = 0,
    },
    -- the aura border art in the aura's dispel type colour; a weapon enchant's in its Color
    auratype = {
        type = 'auratype',
        Enabled = true,
        ShowHelpful = true,
        ShowHarmful = true,
        DispelUntyped = false,
        Alpha = 1,
    },
    tick = {
        type = 'tick',
        Enabled = true,
        Color = { 0, 0, 0, 1 },
        Placement = 'auto',
        Placements = '50',
        Thickness = 1,
        AutoLength = true,
        Length = 10,
    },
    tint = {
        type = 'tint',
        Enabled = true,
        Texture = '',            -- a statusbar texture; empty is a flat colour
        Solid = false,           -- covers what's under it instead of adding to it
        ColorMode = 'custom',    -- custom, indicator (the caller's colour), dispel (the aura's type)
        Color = { 1, 1, 1, 0.4 },
        DispelUntyped = false,
    },
    glow = {
        type = 'glow',
        Enabled = false,
        Type = 'modern',
        ColorMode = 'default',
        Color = { 0.95, 0.95, 0.32, 1 },
        Lines = 8,
        Frequency = 0.25,
        Length = 10,
        Thickness = 2,
        Border = true,
        StartAnim = true,
    },
}

---A new sub element of a type, changed by each overrides table in turn.
---@param kind string
---@param ... table? overrides, later ones win
---@return table
function Core:NewSubRegion(kind, ...)
    local element = CopyTable(Core.SUBREGION_TEMPLATES[kind])
    for i = 1, select('#', ...) do
        for key, value in pairs(select(i, ...) or {}) do
            element[key] = type(value) == 'table' and CopyTable(value) or value
        end
    end

    return element
end

---A new aura group's elements: a 1px border, the time in the middle, stacks in the corner.
---@param look table? `{ timer, stacks, font, auraType, caster }`: overrides for time,
---the stacks, both texts and an aura type texture if any; the trigger naming the caster
---@return table[]
function Core:DefaultAuraGroupSubRegions(look)
    look = look or {}
    local list = { Core:NewSubRegion('border') }
    if look.auraType then
        list[2] = Core:NewSubRegion('auratype', look.auraType)
    end
    list[#list + 1] = Core:NewSubRegion('text', { FontSize = 18 }, look.font, look.timer)
    list[#list + 1] = Core:NewSubRegion('text', {
        Text = '%s',
        FontSize = 14,
        Position = { AnchorFrom = 'AUTO', AnchorTo = 'BOTTOMRIGHT', XOffset = 0, YOffset = 2 },
    }, look.font, look.stacks)
    if look.caster then
        list[#list + 1] = Core:NewSubRegion('text', {
            Text = '%' .. look.caster .. '.casterName',
            FontSize = 10,
            CasterClassColor = true,
            WidthMode = 'fixed', -- a long name is cut at the icon's edge
            FixedWidth = 48,
            WordWrap = false,
            Position = { AnchorFrom = 'AUTO', AnchorTo = 'TOP', XOffset = 0, YOffset = -2 },
        })
    end
    return list
end

---A saved style read through its template, so keys added since it was saved have a value.
---@param saved table
---@param template table
---@return table
function Core:ReadStyle(saved, template)
    return setmetatable({}, {
        __index = function(_, key)
            local value = saved[key]
            if value == nil then
                return template[key]
            end
            return value
        end,
    })
end

local LITERAL_PERCENT = Core.LITERAL_PERCENT
local CASTER_TEXT = '^' .. Core.CASTER_PATTERN .. '$' -- the game writes the whole text

-- what the game writes into a text itself, one of each per button
local SLOT_ROLES = { time = true, count = true, caster = true, name = true }

---What a text is on an aura button: one of the game's slots (time, count, caster, name),
---another trigger's value (sourced) or plain (static); nil when it doesn't show there.
---@param element table
---@param index number? the trigger the button shows
---@param group boolean? an aura group's button
---@return string? role
---@return number? source the trigger a sourced text reads
local function TextRole(element, index, group)
    if not element.Enabled then return nil end

    local text = element.Text or ''
    -- a text naming a trigger reads that one, so a group button shows only its own
    local target = tonumber(strmatch(text, '%%(%d+)%.'))
    local elsewhere = target ~= nil and target ~= index
    if group and elsewhere then return nil end

    -- a typed %% is a sign, not a token, as ExpandText reads it
    local isDuration, isCount, source = Core:ClassifyText((gsub(text, '%%%%', LITERAL_PERCENT)))
    if source == index then
        source = nil
    end
    if source and (isDuration or isCount) then
        return 'sourced', source
    end
    if isDuration then return 'time' end
    if isCount then return 'count' end
    local trimmed = strtrim(text)
    if not elsewhere and strmatch(trimmed, CASTER_TEXT) then return 'caster' end
    if group and trimmed == '%n' then return 'name' end
    return 'static'
end

---Texts an aura button leaves empty: an earlier one took the game's one slot for their
---time, stacks, caster or name. Asked per trigger; an aura group asks DroppedGroupTexts.
---@param subRegions table[]?
---@param index number? the trigger the button shows
---@param group boolean? an aura group's button
---@return table<table, string> dropped each such text and the slot it lost
function Core:DroppedAuraTexts(subRegions, index, group)
    local dropped, taken = {}, {}
    for _, element in ipairs(subRegions or {}) do
        local role = element.type == 'text' and TextRole(element, index, group)
        if role and SLOT_ROLES[role] then
            if taken[role] then
                dropped[element] = role
            end
            taken[role] = true
        end
    end
    return dropped
end

---The texts an aura group's buttons leave empty, on any of its trigger's branches.
---@param subRegions table[]?
---@param trigger table? the group's; none is one branch
---@return table<table, string> dropped each such text and the slot it lost
function Core:DroppedGroupTexts(subRegions, trigger)
    local dropped = {}
    for index = 1, Core:CountTriggerBranches(trigger) do
        for element, slot in pairs(Core:DroppedAuraTexts(subRegions, index, true)) do
            dropped[element] = slot
        end
    end
    return dropped
end

-- Borders and levels --

-- edge textures, not a Backdrop: an aura button's size is secret and Backdrop does maths
local EDGES = {
    { 'TOPLEFT',    'TOPRIGHT',    'height' },
    { 'BOTTOMLEFT', 'BOTTOMRIGHT', 'height' },
    { 'TOPLEFT',    'BOTTOMLEFT',  'width' },
    { 'TOPRIGHT',   'BOTTOMRIGHT', 'width' },
}

---A border sub element drawn around `anchor`.
---@param border table? nil makes one on `host`
---@param host Frame
---@param anchor table what it outlines
---@param element table
---@param engineSnap boolean? keep Blizzard's pixel snap, for an outline on edges we don't place ourselves
---@return table border a frame with its four `edges`
function Core:StyleBorder(border, host, anchor, element, engineSnap)
    if not border then
        border = CreateFrame('Frame', nil, host)
        border.edges = {}
        for i, edge in ipairs(EDGES) do
            local texture = border:CreateTexture(nil, 'OVERLAY')
            texture:NCSetPoint(edge[1], border, edge[1], 0, 0)
            texture:NCSetPoint(edge[2], border, edge[2], 0, 0)
            if not engineSnap then
                texture:NCDisablePixelSnap()
            end
            border.edges[i] = texture
        end
    end

    local offset, size = element.Offset, element.Size
    border:ClearAllPoints()
    border:NCSetPoint('TOPLEFT', anchor, 'TOPLEFT', -offset, offset)
    border:NCSetPoint('BOTTOMRIGHT', anchor, 'BOTTOMRIGHT', offset, -offset)
    for i, texture in ipairs(border.edges) do
        if EDGES[i][3] == 'height' then
            texture:NCSetHeight(size)
        else
            texture:NCSetWidth(size)
        end
        texture:SetColorTexture(unpack(element.Color))
    end
    border:SetShown(element.Enabled)
    return border
end

---Every border sub element in the list, reusing the frames made last time.
---@param borders table[]
---@param host Frame
---@param anchor table what they outline
---@param subRegions table[]
function Core:StyleBorders(borders, host, anchor, subRegions)
    local count = 0
    for _, element in ipairs(subRegions) do
        if element.type == 'border' then
            count = count + 1
            borders[count] = Core:StyleBorder(borders[count], host, anchor, element)
        end
    end
    for i = count + 1, #borders do
        borders[i]:Hide()
    end
end

---Put sub element n's frame at `levelOf(n)`; later elements draw on top.
---@param subRegions table[]
---@param borders Frame[]?
---@param glows table[]? anything with a `host` frame, by glow ordinal
---@param texts table[]? anything with a `host` frame, by text ordinal
---@param levelOf fun(n: number): number
---@param tickSets table[]? a bar layer's ticks, by tick ordinal
---@param tints Frame[]? by tint ordinal
---@param auraTypes Frame[]? by aura type texture ordinal
function Core:LevelElements(subRegions, borders, glows, texts, levelOf, tickSets, tints, auraTypes)
    local b, g, t, k, c, a = 0, 0, 0, 0, 0, 0
    for n, element in ipairs(subRegions) do
        if element.type == 'tint' then
            c = c + 1
            if tints and tints[c] then
                tints[c]:SetFrameLevel(levelOf(n))
            end
        elseif element.type == 'auratype' then
            a = a + 1
            if auraTypes and auraTypes[a] then
                auraTypes[a]:SetFrameLevel(levelOf(n))
            end
        elseif element.type == 'tick' then
            k = k + 1
            local set = tickSets and tickSets[k]
            if set then
                set.level = levelOf(n)
                for _, host in ipairs(set.hosts) do
                    host:SetFrameLevel(set.level)
                end
            end
        elseif element.type == 'border' then
            b = b + 1
            if borders and borders[b] then
                borders[b]:SetFrameLevel(levelOf(n))
            end
        elseif element.type == 'glow' then
            g = g + 1
            if glows and glows[g] then
                glows[g].host:SetFrameLevel(levelOf(n))
            end
        elseif element.type == 'text' then
            t = t + 1
            if texts and texts[t] then
                texts[t].host:SetFrameLevel(levelOf(n))
            end
        end
    end
end

-- Tint --

---A tint over `anchor`: a flat colour or a texture, added to what's under it or solid.
---@param tint Frame? the frame made last time
---@param host Frame
---@param anchor table
---@param element table
---@param color number[] what it is coloured with outside dispel mode
---@param held boolean? the game holds its colour and shown state, which stay its own
---@return Frame tint
local function StyleTint(tint, host, anchor, element, color, held)
    if not tint then
        tint = CreateFrame('Frame', nil, host)
        tint.texture = tint:CreateTexture(nil, 'ARTWORK')
        tint.texture:SetAllPoints()
    end
    tint:SetAllPoints(anchor)

    local texture = tint.texture
    local name = element.Texture
    -- a file path can't be told from a media name the game doesn't know, so it is used as given
    if strfind(name, '\\', 1, true) then
        texture:SetTexture(name)
    elseif name ~= '' then
        texture:SetTexture(Core:ResolveMediaPath('statusbar', name))
    else
        texture:SetColorTexture(1, 1, 1, 1)
    end
    -- the game's tint and hide outlast turning dispel mode off
    if not held then
        texture:SetVertexColor(color[1], color[2], color[3], 1)
        texture:Show()
    end
    texture:SetBlendMode(element.Solid and 'BLEND' or 'ADD')
    -- on the frame, so it holds in dispel mode too, whose palette has no alpha
    tint:SetAlpha(color[4] or 1)
    tint:SetShown(element.Enabled)
    return tint
end

-- Icon --

---Crop the icon to its frame's shape, so a wide icon isn't stretched.
---@param texture Texture
---@param style table
function Core:ApplyTexCoords(texture, style)
    local margin = 0.25 * (style.Zoom or Core.GlobalZoom)
    local left, right, top, bottom = margin, 1 - margin, margin, 1 - margin
    if style.KeepAspectRatio and style.Width ~= style.Height then
        local span = 1 - 2 * margin
        if style.Width > style.Height then
            local cut = span * (1 - style.Height / style.Width) / 2
            top, bottom = top + cut, bottom - cut
        else
            local cut = span * (1 - style.Width / style.Height) / 2
            left, right = left + cut, right - cut
        end
    end
    texture:SetTexCoord(left, right, top, bottom)
end

---The cooldown frame's own number, styled as a text.
---@param cooldown Cooldown
---@param style table
function Core:StyleTimerText(cooldown, style)
    local timer = style.TimerText
    local countdown = cooldown:GetCountdownFontString()
    countdown:SetFontStyle(timer, timer.FontSize, nil, nil, true)
    countdown:SetTextColor(unpack(timer.Color))
    countdown:SetFontJustify(timer.AnchorTo, cooldown, timer.XOffset, timer.YOffset, true)
end

-- Button --

local PANDEMIC_COLOR = { 1, 0.25, 0.25, 1 }

-- AddSlot hands back a secret-wrapped button; this is the real one, so it all goes in refs
---@param button table native AuraButton
---@param host Frame? the frame it sits on; nil for an aura group's button, which the game's flow layout places
---@param refs table
---@param width number in a chain group the host's own size reads back secret
---@param height number
function Core:InitAuraButton(button, host, refs, width, height)
    button:SetSize(width, height)
    -- top-left with its own size, so a chain group can measure it; hidden it collapses
    if host then
        button:SetPoint('TOPLEFT', host, 'TOPLEFT')
        button:SetCollapsesLayout(true)
        button:EnableMouse(false)
    end
    refs.button = button

    -- The icon's own area; the button may be wider by a chain group's spacing.
    local inner = CreateFrame('Frame', nil, button)
    inner:SetPoint('TOPLEFT', button, 'TOPLEFT')
    inner:SetSize(width, height)
    refs.inner = inner

    local icon = button:CreateTexture(nil, 'ARTWORK')
    icon:SetAllPoints(inner)
    icon:NCDisablePixelSnap() -- snaps like the borders around it, so they still line up when a chain lands on a half pixel
    refs.icon = icon
    button:SetIcon(icon)

    local cooldown = CreateFrame('Cooldown', nil, button, 'CooldownFrameTemplate')
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawBling(false)
    cooldown:SetHideCountdownNumbers(true)
    refs.cooldown = cooldown
    button:SetDurationCooldown(cooldown)

    -- the pandemic border right over the swipe; sub elements are levelled above it when styled
    local base = cooldown:GetFrameLevel()
    local borderHost = CreateFrame('Frame', nil, button)
    borderHost:SetAllPoints(inner)
    borderHost:SetFrameLevel(base + 1)
    refs.borderHost = borderHost
    refs.borders = {}

    local textHost = CreateFrame('Frame', nil, button)
    textHost:SetAllPoints(inner)
    textHost:SetFrameLevel(base + 1)
    refs.textHost = textHost
    refs.textHosts = {}

    local pandemicHost = CreateFrame('Frame', nil, button)
    pandemicHost:SetAllPoints(inner)
    pandemicHost:SetFrameLevel(base + 1)
    local pandemic = pandemicHost:CreateTexture(nil, 'OVERLAY')
    pandemic:SetTexture(Core.AURA_OVERLAY_TEXTURE)
    pandemic:NCSetInside(inner)
    pandemic:SetVertexColor(unpack(PANDEMIC_COLOR))
    refs.pandemic = pandemic
    button:AddPandemicRegion(pandemic)
end

---@param fs FontString
---@param element table
---@param parent Frame
local function StyleText(fs, element, parent)
    fs:SetFontStyle(element, element.FontSize, nil, nil, true)
    Core:PlaceText(fs, element, parent)
    fs:SetTextColor(unpack(element.Color))
end

-- the button denies reparenting its fontstrings, so each text frame makes its own
---@param entry table
---@param kind string
---@return FontString
local function TextOf(entry, kind)
    local fs = entry.strings[kind]
    if not fs then
        fs = entry.host:CreateFontString(nil, 'OVERLAY')
        entry.strings[kind] = fs
    end
    return fs
end

--[[
# ApplyAuraLook

Put a look on an aura button built by InitAuraButton: its icon, swipe, timer text, texts, borders, tints
and the dispel type parts its elements ask for; on an aura group's button the tooltip too. Only call it
while auras aren't secret or from initializeFrame.

The first %p/%t text becomes the native duration text and the first %s text its stack count, the rest stay plain.

## Example

    local levelOf = addon:ApplyAuraLook(refs, look)
]]

---@class AuraLook
---@field style table read through its template
---@field subRegions table[]
---@field color number[] the icon's colour as it shows now
---@field desaturate boolean?
---@field swipe boolean?
---@field reverse boolean?
---@field showIcon boolean
---@field iconTexture (number|string|false)? art that replaces the aura's own
---@field bar boolean? drawn on a bar, so no edge or timer text
---@field timerText boolean whether the cooldown's own number shows
---@field pandemicColor number[]? nil hides the pandemic border
---@field textParent Frame what texts are placed on
---@field spellName string what %n reads, see ExpandText
---@field texture (number|string)? what %i reads
---@field triggers table[]? what %N.n and %N.i read
---@field index number? the trigger this button shows
---@field reader table? see ExpandText
---@field group boolean? an aura group's button: %n, tooltip and the style's size
---@field tintColor number[]? what a tint in indicator mode is coloured with
---@field levelOf (fun(n: number): number)|false? for buttons whose elements interleave with others
---@field timeColor (fun(look: AuraLook, ordinal: number, element: table): table?)? a %p text's colour curve
---@field timeFormatter table? what a %p on the Global time format and colours writes with
---@field countFormatter (fun(look: AuraLook, ordinal: number): table?)? a %s text's formatter
---@field sourced (fun(look: AuraLook, entry: table, fs: FontString, element: table, source: number, ordinal: number): boolean)? a text reading another trigger; true shows it

---@param refs table from InitAuraButton
---@param look AuraLook
---@return fun(n: number): number levelOf the level each sub element got, for anything the caller adds above them
function Core:ApplyAuraLook(refs, look)
    local button, style, subRegions = refs.button, look.style, look.subRegions
    local showIcon, group = look.showIcon, look.group

    local icon = refs.icon
    Core:ApplyTexCoords(icon, style)
    icon:SetVertexColor(unpack(look.color))
    icon:SetDesaturated(look.desaturate == true)
    -- the button overrides a held icon's alpha, so a hidden icon is taken off it
    icon:SetShown(showIcon)
    if not showIcon then
        button:ClearIcon()
    elseif look.iconTexture then
        button:ClearIcon()
        icon:SetTexture(look.iconTexture)
    else
        button:SetIcon(icon)
    end

    local cooldown = refs.cooldown
    cooldown:SetDrawSwipe(look.swipe and showIcon)
    cooldown:SetDrawEdge(style.DrawEdge and showIcon and not look.bar)
    cooldown:SetReverse(look.reverse == true)
    cooldown:SetSwipeColor(unpack(style.SwipeColor))
    cooldown:SetHideCountdownNumbers(not look.timerText or not showIcon or look.bar)
    Core:StyleTimerText(cooldown, style)

    local pandemicColor = look.pandemicColor
    refs.pandemic:SetAlpha(pandemicColor and 1 or 0)
    if pandemicColor then
        refs.pandemic:SetVertexColor(unpack(pandemicColor))
    end

    -- each text draws from its own frame, at its place in the list
    local textParent = look.textParent
    local taken, ordinal = {}, 0
    for _, element in ipairs(subRegions) do
        if element.type == 'text' then
            ordinal = ordinal + 1
            local entry = refs.textHosts[ordinal]
            if not entry then
                local host = CreateFrame('Frame', nil, refs.textHost)
                host:SetAllPoints(refs.inner)
                entry = { host = host, strings = {} }
                refs.textHosts[ordinal] = entry
            end
            for _, fs in pairs(entry.strings) do
                fs:Hide()
            end

            local role, source = TextRole(element, look.index, group)
            if SLOT_ROLES[role] and taken[role] then
                -- the game writes one of each per button, so a later text stays empty
                role = nil
            end
            if role then
                taken[role] = true
                local raw = self:ExpandText(element, look.spellName, look.texture, look.triggers, look.reader)
                if role == 'sourced' then
                    -- another trigger's time or charges, which only the caller can feed
                    if look.sourced then
                        local fs = TextOf(entry, 'sourced')
                        StyleText(fs, element, textParent)
                        if look.sourced(look, entry, fs, element, source, ordinal) then
                            fs:Show()
                        end
                    end
                elseif role == 'time' then
                    local fs = TextOf(entry, 'time')
                    StyleText(fs, element, textParent)
                    local format, components = Core:DurationTextFormat(raw, element, element.GlobalTimeColor and look.timeFormatter or nil)
                    local curve = look.timeColor and look.timeColor(look, ordinal, element)
                    button:SetDurationText(fs, {
                        textFormat = { formatString = format, components = components },
                        textColor = curve and { curve = curve, property = BindingProperty.RemainingDuration } or nil,
                    })
                    fs:Show()
                elseif role == 'count' then
                    local fs = TextOf(entry, 'count')
                    StyleText(fs, element, textParent)
                    button:SetApplicationCount(fs, { formatter = look.countFormatter and look.countFormatter(look, ordinal) })
                    fs:Show()
                elseif role == 'caster' then
                    -- the game writes who cast the aura and keeps it secret, so it takes the whole text
                    local fs = TextOf(entry, 'caster')
                    StyleText(fs, element, textParent)
                    button:SetCasterName(fs, { useClassColors = element.CasterClassColor == true, showRealmName = element.CasterRealm == true })
                    fs:Show()
                elseif role == 'name' then
                    -- every button shows a different aura, so the game writes its name; it takes the whole text
                    local fs = TextOf(entry, 'name')
                    StyleText(fs, element, textParent)
                    button:SetSpellName(fs)
                    fs:Show()
                else
                    local fs = TextOf(entry, 'static')
                    StyleText(fs, element, textParent)
                    fs:SetText((gsub(raw, LITERAL_PERCENT, '%%')))
                    fs:Show()
                end
            end
        end
    end
    -- text frames past the current list stay hidden
    for i = ordinal + 1, #refs.textHosts do
        for _, fs in pairs(refs.textHosts[i].strings) do
            fs:Hide()
        end
    end

    if not taken.time then
        button:ClearDurationText()
    end
    if not taken.count then
        button:ClearApplicationCount()
    end
    if group and not taken.name then
        button:ClearSpellName()
    end
    if not taken.caster then
        button:ClearCasterName()
    end

    Core:StyleBorders(refs.borders, refs.borderHost, refs.inner, subRegions)

    -- each add copies its options and redraws the button, so only a change hands them over
    local wanted = { Core.Colors.dispelRGB }
    local borders, tints, auraTypes = 0, 0, 0
    for _, element in ipairs(subRegions) do
        if element.type == 'auratype' then
            auraTypes = auraTypes + 1
            -- a weapon enchant's has a Color of its own and stays ours
            if element.Enabled and not element.Color then
                wanted[#wanted + 1] = 'aura' .. auraTypes .. (element.ShowHelpful and 'h' or '')
                    .. (element.ShowHarmful and 'H' or '') .. (element.DispelUntyped and '+' or '')
            end
        elseif element.type == 'border' then
            borders = borders + 1
            if element.Enabled and element.DispelColor then
                wanted[#wanted + 1] = 'border' .. borders .. (element.DispelUntyped and '+' or '')
            end
        elseif element.type == 'tint' then
            tints = tints + 1
            if element.Enabled and element.ColorMode == 'dispel' then
                wanted[#wanted + 1] = 'tint' .. tints .. (element.DispelUntyped and '+' or '')
            end
        end
    end
    if style.DispelIcon then
        wanted[#wanted + 1] = 'icon'
    end
    local bound = refs.dispelBound
    local rebind = not bound or #bound ~= #wanted
    for i = 1, rebind and 0 or #wanted do
        if bound[i] ~= wanted[i] then
            rebind = true
            break
        end
    end

    local dispel
    if rebind then
        refs.dispelBound = wanted
        -- the game asserts on a texture it already holds, so a change starts over
        button:ClearDispelTypeTextures()
        dispel = {
            style = PreserveAsset,
            showWhenHelpful = true,
            showWhenHarmful = true,
            customDispelColorMap = Core.Colors.dispelRGB,
        }
    end

    borders, tints, auraTypes = 0, 0, 0
    refs.tints = refs.tints or {}
    refs.auraTypes = refs.auraTypes or {}
    for _, element in ipairs(subRegions) do
        if element.type == 'auratype' then
            auraTypes = auraTypes + 1
            local host = refs.auraTypes[auraTypes]
            if not host then
                host = CreateFrame('Frame', nil, button)
                host:SetAllPoints(refs.inner)
                host.texture = host:CreateTexture(nil, 'OVERLAY')
                host.texture:SetTexture(Core.AURA_OVERLAY_TEXTURE)
                host.texture:NCSetInside(refs.inner)
                refs.auraTypes[auraTypes] = host
            end
            -- the palette has no alpha, so it fades on its frame
            host:SetAlpha(element.Alpha or 1)
            host:SetShown(element.Enabled)
            local texture = host.texture
            local typed = element.Enabled and not element.Color
            if not typed then
                if element.Color then
                    texture:SetVertexColor(unpack(element.Color))
                end
                texture:Show()
            elseif rebind then
                texture:SetVertexColor(1, 1, 1, 1)
                texture:Show()
                dispel.showWhenHelpful = element.ShowHelpful == true
                dispel.showWhenHarmful = element.ShowHarmful == true
                dispel.showWithoutDispelType = element.DispelUntyped == true
                button:AddDispelTypeTexture(texture, dispel)
            end
        elseif element.type == 'border' then
            borders = borders + 1
            -- the palette has no alpha, so a dispel coloured border fades on its frame
            local typed = element.Enabled and element.DispelColor
            refs.borders[borders]:SetAlpha(typed and element.DispelAlpha or 1)
            for _, edge in ipairs(refs.borders[borders].edges) do
                -- the game's colour and hide outlast dispel mode, and are its own while it holds the edge
                if rebind or not typed then
                    edge:SetVertexColor(1, 1, 1, 1)
                    edge:Show()
                end
                if typed then
                    edge:SetColorTexture(1, 1, 1, 1) -- the type's colour tints white
                end
                if typed and rebind then
                    dispel.showWhenHelpful, dispel.showWhenHarmful = true, true
                    dispel.showWithoutDispelType = element.DispelUntyped == true
                    button:AddDispelTypeTexture(edge, dispel)
                end
            end
        elseif element.type == 'tint' then
            tints = tints + 1
            local mode = element.ColorMode
            local typed = element.Enabled and mode == 'dispel'
            local color = mode == 'indicator' and look.tintColor or element.Color
            local tint = StyleTint(refs.tints[tints], button, refs.inner, element, color, typed and not rebind)
            refs.tints[tints] = tint
            if typed and rebind then
                dispel.showWhenHelpful, dispel.showWhenHarmful = true, true
                dispel.showWithoutDispelType = element.DispelUntyped == true
                button:AddDispelTypeTexture(tint.texture, dispel)
            end
        end
    end
    for i = tints + 1, #refs.tints do
        refs.tints[i]:Hide()
    end
    for i = auraTypes + 1, #refs.auraTypes do
        refs.auraTypes[i]:Hide()
    end

    -- made here, not on hand-over, so only a button that shows it carries one
    local dispelIcon = refs.dispelIcon
    if style.DispelIcon and not dispelIcon then
        dispelIcon = CreateFrame('Frame', nil, button):CreateTexture(nil, 'OVERLAY')
        refs.dispelIcon = dispelIcon
    end
    if dispelIcon and (rebind or not style.DispelIcon) then
        dispelIcon:SetShown(style.DispelIcon == true)
    end
    if style.DispelIcon then
        -- above every sub element, which are levelled after it
        dispelIcon:GetParent():SetFrameLevel(cooldown:GetFrameLevel() + #subRegions + 2)
        dispelIcon:ClearAllPoints()
        local pos = style.DispelIconPosition
        if pos then
            dispelIcon:SetPoint(pos.AnchorFrom, refs.inner, pos.AnchorTo, pos.XOffset, pos.YOffset)
        else
            dispelIcon:SetPoint('TOPRIGHT', refs.inner, 'TOPRIGHT', -2, -2)
        end
        dispelIcon:SetSize(style.DispelIconSize, style.DispelIconSize)
        if rebind then
            button:AddDispelTypeTexture(dispelIcon, {
                style = Enum.CustomAuraButtonDispelTypeTextureStyle.Icon,
                showWhenHelpful = true,
                showWhenHarmful = true,
            })
        end
    end

    if group then
        button:EnableMouse(style.Tooltip == true)
        button:SetHideTooltipInCombat(style.TooltipHideInCombat == true)
    end

    -- the flow layout places a group button, the caller places any other
    local inner = refs.inner
    inner:ClearAllPoints()
    inner:SetPoint('TOPLEFT', button, 'TOPLEFT')
    if group then
        button:SetSize(style.Width, style.Height)
        inner:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT')
    end

    local base = cooldown:GetFrameLevel() + 1
    local listLevel = look.levelOf
    local function LevelOf(n)
        if listLevel then
            return max(base + 1, listLevel(n)) -- never under its own swipe and pandemic border
        end
        return base + n
    end
    Core:LevelElements(subRegions, refs.borders, nil, refs.textHosts, LevelOf, nil, refs.tints, refs.auraTypes)

    return LevelOf
end

-- Restyle --

local function ByName(a, b)
    return tostring(a) < tostring(b)
end

---@param parts string[]
---@param value any
local function AppendStamp(parts, value)
    if type(value) ~= 'table' then
        parts[#parts + 1] = tostring(value)
        return
    end

    -- sorted, so the same settings make the same stamp whatever order pairs walks them in
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    sort(keys, ByName)
    parts[#parts + 1] = '{'
    for _, key in ipairs(keys) do
        parts[#parts + 1] = tostring(key)
        parts[#parts + 1] = '='
        AppendStamp(parts, value[key])
        parts[#parts + 1] = ';'
    end
    parts[#parts + 1] = '}'
end

---A look's settings as one string for an aura display's Restyle(look), shared ones included:
---equal settings give the same string, so a restyle that changes nothing is skipped.
---@param ... any the settings the look reads: style, sub elements and anything else
---@return string
function Core:LookStamp(...)
    local parts = { tostring(Core.SharedVersion) }
    for i = 1, select('#', ...) do
        parts[#parts + 1] = '|'
        AppendStamp(parts, (select(i, ...)))
    end
    return concat(parts)
end

-- Icon look --

local iconCurve

---@param element table
---@return table? curve
local function IconTimeColor(_, _, element)
    if not element.GlobalTimeColor then return end
    -- its own Time Format writes no colour codes, so every mode comes as a curve
    if element.TimeFormat == 'custom' then
        return Core:GetSharedDurationColorCurve()
    end
    return iconCurve
end

-- what ApplyAuraLook reads, refilled for every button
local iconLook = { group = true, spellName = '', timeColor = IconTimeColor }

---An aura group's settings ready to draw or edit: elements seeded, style read.
---Seeded rather than a default, since AceDB would put a deleted element back.
---@param db table
---@param seed fun(): table DefaultAuraGroupSubRegions' look, for a group with no elements yet
---@return table style
function Core:PrepareAuraGroup(db, seed)
    if not db.SubRegions then
        db.SubRegions = Core:DefaultAuraGroupSubRegions(seed())
    end
    return Core:ReadStyle(db.Style, Core.ICON_STYLE_TEMPLATE)
end

---An aura group's button in an icon style and its sub elements, timed by the shared
---Duration Text settings: UF aura kinds and Icon spots, Standard Buffs and Debuffs.
---@param refs table from InitAuraButton
---@param style table read through its template
---@param subRegions table[]
---@param branch number the trigger branch it shows
---@param tintColor number[]? what a tint in indicator mode is coloured with
---@return fun(n: number): number levelOf
function Core:ApplyIconLook(refs, style, subRegions, branch, tintColor)
    iconLook.style, iconLook.subRegions = style, subRegions
    iconLook.color, iconLook.desaturate = style.Color, style.Desaturate
    iconLook.swipe, iconLook.reverse = style.DrawSwipe, style.Reverse
    iconLook.showIcon = style.IconShow
    iconLook.timerText = not style.HideCountdown
    iconLook.textParent = refs.inner
    iconLook.index, iconLook.tintColor = branch, tintColor
    iconLook.timeFormatter, iconCurve = Core:GetSharedDurationText()
    return self:ApplyAuraLook(refs, iconLook)
end
