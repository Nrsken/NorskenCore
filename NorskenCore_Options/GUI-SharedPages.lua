---@class NRSKNUI
local Core = _G.NorskenCore
---@class NRSKNUI.GUISharedPages
local Shared = {}
Core.GUISharedPages = Shared
local L = Core.L
local KajiGUI = Core.KajiGUI
local Theme = KajiGUI.DEFAULT_THEME
local rowH = Theme.rowHeight
local rowHL = Theme.rowHeightLast

local min = math.min
local format = string.format
local ceil, floor = math.ceil, math.floor
local unpack = unpack
local ipairs, pairs = ipairs, pairs
local CopyTable = CopyTable
local _G = _G

---A Hide Minimap Icon row for the addon's launcher, see RegisterLauncher.
---@param card table
---@param addon table
---@param height number? the row height, the last row in a card takes rowHeightLast
function Shared:LauncherRow(card, addon, height)
    card:Row(height or rowH):Checkbox(L['Hide Minimap Icon'], {
        width = 1,
        value = addon.launcherDB.hide,
        msgPopup = true,
        msgText = L['Hide Minimap Icon'],
        callback = function(checked)
            addon:SetLauncherHidden(checked)
        end,
    })
end

-- Load-time settings prompt one reload when the user leaves the page, never per edit; latest reason wins.
-- Written on Core so every addon's pages reach it, one settings window shows at a time.
local pendingReload

---@param reason string shown in the reload prompt
function Core:RequestReload(reason)
    pendingReload = reason
end

function Core:PromptPendingReload()
    if not pendingReload then return end

    local reason = pendingReload
    pendingReload = nil
    self:CreateReloadPrompt(reason)
end

-- { key, label } specs drive the color-picker grids below. key indexes the shared Colors.<category>.
-- Game terms pull Blizzard's own localized global strings so they translate for free.
local PowerColorSpecs = {
    { key = 0,  label = _G.MANA },
    { key = 1,  label = _G.RAGE },
    { key = 2,  label = _G.FOCUS },
    { key = 3,  label = _G.ENERGY },
    { key = 6,  label = _G.RUNIC_POWER },
    { key = 8,  label = _G.LUNAR_POWER },
    { key = 11, label = _G.MAELSTROM },
    { key = 13, label = _G.INSANITY },
    { key = 17, label = _G.FURY },
    { key = 18, label = _G.PAIN },
    { key = 4,  label = L['Combo Points'] },
    { key = 9,  label = L['Holy Power'] },
    { key = 7,  label = L['Soul Shards'] },
    { key = 12, label = L['Chi'] },
    { key = 16, label = L['Arcane Charges'] },
    { key = 19, label = L['Essence'] },
    { key = 5,  label = L['Runes'] },
}

local RuneColorSpecs = {
    { key = 1, label = L['Blood'] },
    { key = 2, label = L['Frost'] },
    { key = 3, label = L['Unholy'] },
}

local StaggerColorSpecs = {
    { key = 1, label = L['Light Stagger'] },
    { key = 2, label = L['Moderate Stagger'] },
    { key = 3, label = L['Heavy Stagger'] },
}

local ReactionColorSpecs = {}
for i = 1, 8 do
    ReactionColorSpecs[i] = { key = i, label = _G['FACTION_STANDING_LABEL' .. i] }
end

local ClassColorSpecs = {}
local ClassTokens = {
    'DEATHKNIGHT', 'DEMONHUNTER', 'DRUID', 'EVOKER', 'HUNTER', 'MAGE', 'MONK',
    'PALADIN', 'PRIEST', 'ROGUE', 'SHAMAN', 'WARLOCK', 'WARRIOR',
}
for _, token in ipairs(ClassTokens) do
    ClassColorSpecs[#ClassColorSpecs + 1] = { key = token, label = LOCALIZED_CLASS_NAMES_MALE[token] }
end

local StatusColorSpecs = {
    { key = 'Tapped',       label = L['Tapped'] },
    { key = 'Disconnected', label = L['Disconnected'] },
    { key = 'Dead',         label = L['Dead'] },
}

local DispelColorTypes = {
    { key = 'None',    label = L['None'] },
    { key = 'Magic',   label = L['Magic'] },
    { key = 'Curse',   label = L['Curse'] },
    { key = 'Disease', label = L['Disease'] },
    { key = 'Poison',  label = L['Poison'] },
    { key = 'Bleed',   label = L['Bleed'] },
    { key = 'Enrage',  label = L['Enrage'] },
}

local formatOptions = {
    { key = '%0.1f',                        text = L['Tenths (2.4)'] },
    { key = '%0.1fs',                       text = L['Tenths with s (2.4s)'] },
    { key = '%d',                           text = L['Seconds (7)'] },
    { key = '%ds',                          text = L['Seconds with s (7s)'] },
    { key = Core.MINUTES_SECONDS_FORMAT, text = L['Minutes and Seconds (2:10)'] },
    { key = '%dm',                          text = L['Minutes (3m)'] },
    { key = '%dh',                          text = L['Hours (2h)'] },
    { key = '%dd',                          text = L['Days (3d)'] },
}

-- Aura buttons are built once by the game, so formatter edits only show after a reload.
local function RefreshFormatter()
    Core:RefreshAuraDurationFormatter()
    Core:SharedSettingsChanged()
    Core:RequestReload(L['Duration text changes show on auras after a reload.'])
end

-- key indexes the shared Colors.
local ColorCategories = {
    { type = 'label',   key = 'colors',       text = L['Colors'] },
    { key = 'Class',    text = L['Class'],    title = L['Class Colors'],    specs = ClassColorSpecs },
    { key = 'Power',    text = L['Power'],    title = L['Power Colors'],    specs = PowerColorSpecs },
    { key = 'Runes',    text = L['Runes'],    title = L['Rune Colors'],     specs = RuneColorSpecs },
    { key = 'Stagger',  text = L['Stagger'],  title = L['Stagger Colors'],  specs = StaggerColorSpecs },
    { key = 'Reaction', text = L['Reaction'], title = L['Reaction Colors'], specs = ReactionColorSpecs },
    { key = 'Status',   text = L['Status'],   title = L['Status Colors'],   specs = StatusColorSpecs,  storeAlpha = true },
    { key = 'Dispel',   text = L['Dispel'],   title = L['Dispel Colors'],   specs = DispelColorTypes,  storeAlpha = true },
}

local function RefreshColors()
    Core:LoadCustomColors()
    Core:SharedSettingsChanged()
end

local function BuildColorsPage(page, db, category)
    local dbTable = db[category.key]
    local specs = category.specs
    local card = page:Card(category.title, 'all')

    card:Rebuild(function(c)
        for i = 1, #specs, 3 do
            local row = c:Row(rowH)

            for j = i, min(i + 2, #specs) do
                local spec = specs[j]

                row:ColorPicker(spec.label, {
                    width = (1 / 3),
                    value = dbTable[spec.key],
                    callback = function(r, g, b, a)
                        dbTable[spec.key] = category.storeAlpha and { r, g, b, a } or { r, g, b }
                        RefreshColors()
                    end,
                })
            end
        end

        c:Row(rowHL - 9, 0):Button(L['Reset to Default'], {
            width = 1,
            height = 30,
            yOffset = -2,
            callback = function()
                page.gui:Prompt({
                    title = L['Reset to Default'],
                    text = format(L["Reset all %s to their defaults?"], category.title),
                    onAccept = function()
                        -- Written in place, dbTable is the live shared table the pickers hold.
                        for key, color in pairs(Core:GetSharedDefaults().Colors[category.key]) do
                            dbTable[key] = CopyTable(color)
                        end
                        RefreshColors()
                        card:Rebuild()
                    end,
                    acceptText = L['Reset'],
                    cancelText = L['Cancel'],
                })
            end,
        })
    end)
end

-- Texture preview --

-- Drawn through the modules' own resolvers; a fixed fill, never live data.
local PREVIEW_TYPE = 'NUITexturePreview'
local PREVIEW_BAR_HEIGHT = 22
local PREVIEW_FILL = 0.62
local PREVIEW_PAD = 12 -- checker showing around the bar, so the backdrop and border sit on it
local PREVIEW_CHECKER = Core.Media.GUITextures .. 'PreviewChecker.png'

-- GUI-only sentinel for the flat backdrop, the db stores nil.
local FLAT_BACKGROUND = '__FLAT'

local PreviewMixin = {}

function PreviewMixin:OnAcquire(parent)
    self:SetParent(parent)
    self:ClearAllPoints()
    -- Reparenting resets levels; keep the border frame above the bar, as the castbars draw it.
    self.bar:SetFrameLevel(self.holder:GetFrameLevel() + 1)
    self.borders:SetFrameLevel(self.holder:GetFrameLevel() + 5)
    self:Show()
    self:Refresh()
end

function PreviewMixin:Refresh()
    local c = Core:GetClassColor(Core.MyClass)
    local bg, border = Core:GetBackdropColor(), Core:GetBorderColor()
    self.holder:SetBackgroundTexture(Core:GetBarBackground())
    self.holder:SetBackgroundColor(bg[1], bg[2], bg[3], bg[4])
    self.borders:SetBorderColor(border[1], border[2], border[3], border[4])
    self.bar:SetStatusBarTexture(Core:GetStatusbar())
    self.bar:SetStatusBarColor(c.r, c.g, c.b, 1)
    Core:SetSpark(self.spark, nil, PREVIEW_BAR_HEIGHT)
    -- Anchored after the bar texture is set, as the castbars do: the fill texture only exists from then.
    self.spark:ClearAllPoints()
    self.spark:SetPoint('CENTER', self.bar:GetStatusBarTexture(), 'RIGHT', 0, 0)
end

KajiGUI:RegisterWidgetType(PREVIEW_TYPE, function()
    local frame = Mixin(CreateFrame('Frame'), PreviewMixin)

    -- Checkerboard so a translucent backdrop doesn't vanish into the card's dark fill.
    local checker = frame:CreateTexture(nil, 'BACKGROUND')
    checker:SetTexture(PREVIEW_CHECKER, 'REPEAT', 'REPEAT')
    checker:SetHorizTile(true)
    checker:SetVertTile(true)
    checker:SetAllPoints()

    local holder = CreateFrame('Frame', nil, frame)
    holder:NCSetHeight(PREVIEW_BAR_HEIGHT)
    holder:NCSetPoint('LEFT', frame, 'LEFT', PREVIEW_PAD, 0)
    holder:NCSetPoint('RIGHT', frame, 'RIGHT', -PREVIEW_PAD, 0)
    holder:NCCreateBackdrop(true)
    frame.holder = holder

    local bar = CreateFrame('StatusBar', nil, holder)
    bar:NCSetPoint('TOPLEFT', holder, 'TOPLEFT', 1, -1)
    bar:NCSetPoint('BOTTOMRIGHT', holder, 'BOTTOMRIGHT', -1, 1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(PREVIEW_FILL)
    frame.bar = bar

    local spark = bar:CreateTexture(nil, 'OVERLAY')
    spark:NCDisablePixelSnap()
    spark:SetBlendMode('ADD')
    frame.spark = spark

    local borders = CreateFrame('Frame', nil, holder)
    borders:SetAllPoints(holder)
    borders:NCAddBorders()
    frame.borders = borders

    return frame
end)

local function BuildTexturesPage(page, db)
    local bar, spark, borders = db.profileBar, db.profileSpark, db.profileBorder
    local preview

    -- The preview is one bar, so it follows every tick; the modules wait for the input to settle.
    local function Apply()
        Core:SharedSettingsChanged()
        preview:Refresh()
    end

    page:Card(L['Textures']):Rebuild(function(c)
        -- Only the solid spark takes a width, art sparks keep their own proportions.
        local isSolid = spark.sparkTexture == 'Solid'

        preview = c:Row(rowHL):Widget(PREVIEW_TYPE, nil, { width = 1 })

        c:Separator(L['Bar'], { useLabel = true })
        local barRow = c:Row(rowH)
        barRow:Dropdown(L['Texture'], {
            width = 0.5,
            media = 'statusbar',
            value = bar.statusBar,
            searchable = true,
            tooltip = L['Used by every module set to follow the global texture.'],
            callback = function(key)
                bar.statusBar = key
                Apply()
            end,
        })
        barRow:Dropdown(L['Background'], {
            width = 0.5,
            media = 'statusbar',
            options = { { key = FLAT_BACKGROUND, text = L['Flat'] } },
            value = bar.backgroundTexture or FLAT_BACKGROUND,
            searchable = true,
            tooltip = L['Texture for the empty part of the bar, tinted by the backdrop color. Flat keeps a plain fill.'],
            callback = function(key)
                bar.backgroundTexture = key ~= FLAT_BACKGROUND and key or nil
                Apply()
            end,
        })

        c:Separator(L['Castbar Spark'], { useLabel = true })
        local sparkRow = c:Row(rowH)
        sparkRow:Dropdown(L['Texture'], {
            width = 0.5,
            media = 'spark',
            value = spark.sparkTexture,
            searchable = true,
            tooltip = L['Used by every castbar set to follow the global spark.'],
            callback = function(key)
                spark.sparkTexture = key
                Apply()
                if (key == 'Solid') ~= isSolid then c:Rebuild() end
            end,
        })
        sparkRow:ColorPicker(L['Color'], {
            width = 0.5,
            value = spark.color,
            callback = function(r, g, b, a)
                spark.color = { r, g, b, a }
                Apply()
            end,
        })

        local sizeRow = c:Row(rowH)
        sizeRow:Slider(L['Scale'], {
            width = 0.5,
            min = 0.5,
            max = 4,
            step = 0.05,
            value = spark.Scale,
            tooltip = L['Scales the spark against the bar height. Art sparks keep their own proportions.'],
            callback = function(val)
                spark.Scale = val
                Apply()
            end,
            callbackOnRelease = true,
        })
        if isSolid then
            sizeRow:Slider(L['Width'], {
                width = 0.5,
                min = 1,
                max = 16,
                step = 1,
                value = spark.Width,
                callback = function(val)
                    spark.Width = val
                    Apply()
                end,
            })
        end

        c:Separator(L['Borders & Backdrops'], { useLabel = true })
        local colorRow = c:Row(rowHL, 0)
        colorRow:ColorPicker(L['Border Color'], {
            width = 0.5,
            value = borders.BorderColor,
            tooltip = L['Used by every module set to follow the global border.'],
            callback = function(r, g, b, a)
                borders.BorderColor = { r, g, b, a }
                Apply()
            end,
        })
        colorRow:ColorPicker(L['Backdrop Color'], {
            width = 0.5,
            value = borders.BackdropColor,
            tooltip = L['Used by every module set to follow the global backdrop.'],
            callback = function(r, g, b, a)
                borders.BackdropColor = { r, g, b, a }
                Apply()
            end,
        })
    end)
end

local POINTS = {
    { key = 'pointOne',   color = 'colorOne' },
    { key = 'pointTwo',   color = 'colorTwo' },
    { key = 'pointThree', color = 'colorThree' },
    { key = 'pointFour',  color = 'colorFour' },
    { key = 'pointFive',  color = 'colorFive' },
    { key = 'pointSix',   color = 'colorSix' },
}

local COLOR_MODES = {
    { id = 'breakpoint', text = L['Breakpoint Colors'], hint = L['Color changes instantly at each breakpoint.'] },
    { id = 'curve',      text = L['Curve Colors'],      hint = L['Color fades smoothly between breakpoints.'] },
    { id = 'single',     text = L['Single Color'],      hint = L['One color for everything.'] },
}

local RADIO_ROW_HEIGHT = 32
local TABLE_ROW_HEIGHT = 32
local FIELD_TOP = 14 -- label-less fields still leave their label strip empty, lift them into it
local SECONDS_PER_UNIT = { s = 1, m = 60, h = 3600, d = 86400 }

local function FormatSeconds(seconds)
    if seconds >= 86400 and seconds % 86400 == 0 then return (seconds / 86400) .. 'd' end
    if seconds >= 3600 and seconds % 3600 == 0 then return (seconds / 3600) .. 'h' end
    if seconds >= 60 and seconds % 60 == 0 then return (seconds / 60) .. 'm' end
    return seconds .. 's'
end

-- Accepts whole seconds with an optional s/m/h/d unit: 90, 90s, 5m, 1h, 1d.
local function ParseSeconds(text)
    local num, unit = text:lower():match('^%s*(%d+)%s*([smhd]?)%s*$')
    if not num then return end
    return tonumber(num) * SECONDS_PER_UNIT[unit ~= '' and unit or 's']
end

local function TooltipFiller(title, body)
    return function(tooltip, frame)
        local theme = frame._kajiGui.theme
        tooltip:SetText(title, theme.accent[1], theme.accent[2], theme.accent[3], 1, false)
        tooltip:AddLine(body, theme.textSecondary[1], theme.textSecondary[2], theme.textSecondary[3], true)
    end
end

local startTooltip = TooltipFiller(L['Start Time'],
    L['Kicks in when this much time is left. Type 90, 5m, 1h or 1d.'])

local function BuildDurationTextPage(page, db)
    local points = db.profileBreakPoints

    page:SetCondition('never', function() return false end)

    local function GetDurationColorMode()
        if db.durationSingleColor then return 'single' end
        if db.durationBreakpointColors then return 'breakpoint' end
        return 'curve'
    end

    -- The formatter forces point one to start at 0.
    local function StartOf(i)
        return i == 1 and 0 or points[POINTS[i].key].threshold
    end

    local modeCard = page:Card(L['Color Mode'])
    local rowsCard = page:Card(L['Breakpoints'])

    local examples = {}

    local function ExampleText(i)
        local start, nextPoint = StartOf(i), POINTS[i + 1]
        local sample = nextPoint and (start + points[nextPoint.key].threshold) / 2 or start * 2
        local fmt = points[POINTS[i].key].format
        local div, step, nearest = Core:GetDurationFormatUnit(fmt)
        local value = sample / div
        if step < 1 then
            value = ceil(value * 10) / 10
        else
            value = nearest and floor(value + 0.5) or ceil(value)
        end
        local color = db.durationSingleColor and db.durationSingleColorValue
            or (db.durationCurveColors and db.profileColorCurve or db.profileColorBreakPoint)[POINTS[i].color]
        local text = fmt == Core.MINUTES_SECONDS_FORMAT and format(fmt, floor(value / 60), value % 60) or format(fmt, value)
        return CreateColor(unpack(color)):WrapTextInColorCode(text)
    end

    local function RefreshExamples()
        for i, example in ipairs(examples) do example:SetText(ExampleText(i)) end
    end

    modeCard:Rebuild(function(c)
        local mode = GetDurationColorMode()
        local previous
        for i, info in ipairs(COLOR_MODES) do
            local selected = mode == info.id
            local isLast = i == #COLOR_MODES
            previous = c:Row(RADIO_ROW_HEIGHT, isLast and 0 or nil):Radio(info.text, {
                width = 1,
                description = info.hint,
                selected = selected,
                linkTo = previous,
                callback = function()
                    db.durationBreakpointColors = (info.id == 'breakpoint')
                    db.durationCurveColors = (info.id == 'curve')
                    db.durationSingleColor = (info.id == 'single')
                    RefreshFormatter()
                    c:Rebuild()
                    rowsCard:Rebuild()
                end,
            })
        end
    end)

    rowsCard:Rebuild(function(c)
        local showColors = not db.durationSingleColor
        local colorTable = db.durationCurveColors and db.profileColorCurve or db.profileColorBreakPoint
        local widths = showColors and { 0.2, 0.35, 0.25, 0.2 } or { 0.2, 0.5, nil, 0.3 }
        local startBoxes = {}
        wipe(examples)

        if not showColors then
            c:Row(rowH):ColorPicker(L['Color'], {
                width = 0.5,
                value = db.durationSingleColorValue,
                callback = function(r, g, b, a)
                    db.durationSingleColorValue = { r, g, b, a }
                    RefreshExamples()
                    RefreshFormatter()
                end,
            })
        end

        local header = c:Row(16)
        for col, title in ipairs({ L['Starts At'], L['Shown As'], showColors and L['Color'] or false, L['Looks Like'] }) do
            if title then
                header:Text(nil, { width = widths[col], text = title, height = 16, autoHeight = false, bgMode = 'hide' })
            end
        end

        for i, point in ipairs(POINTS) do
            local dbPoint = points[point.key]
            local isFirst = i == 1
            local isLast = i == #POINTS
            local row = c:Row(TABLE_ROW_HEIGHT, isLast and 0 or nil)

            startBoxes[i] = row:EditBox(nil, {
                width = widths[1],
                yOffset = FIELD_TOP,
                value = FormatSeconds(StartOf(i)),
                conditions = isFirst and { 'never' } or nil,
                tooltip = not isFirst and startTooltip or nil,
                callback = not isFirst and function(text)
                    local seconds = ParseSeconds(text)
                    local nextPoint = POINTS[i + 1]
                    -- Rows have to stay in order, anything else snaps back to the stored value.
                    if seconds and seconds > StartOf(i - 1) and (not nextPoint or seconds < points[nextPoint.key].threshold) then
                        dbPoint.threshold = seconds
                        RefreshExamples()
                        RefreshFormatter()
                    end
                    startBoxes[i]:SetValue(FormatSeconds(dbPoint.threshold))
                end or nil,
            })

            row:Dropdown(nil, {
                width = widths[2],
                yOffset = FIELD_TOP,
                options = formatOptions,
                value = dbPoint.format,
                callback = function(key)
                    dbPoint.format = key
                    RefreshExamples()
                    RefreshFormatter()
                end,
            })

            if showColors then
                row:ColorPicker(nil, {
                    width = widths[3],
                    yOffset = FIELD_TOP,
                    value = colorTable[point.color],
                    callback = function(r, g, b, a)
                        colorTable[point.color] = { r, g, b, a }
                        RefreshExamples()
                        RefreshFormatter()
                    end,
                })
            end

            examples[i] = row:Text(nil, {
                width = widths[4],
                text = ExampleText(i),
                height = 24,
                autoHeight = false,
                justify = 'CENTER',
                bgMode = 'show',
            })
        end
    end)
end

Shared.ColorCategories = ColorCategories

---@param page table
---@param item table one of ColorCategories
function Shared:BuildColors(page, item)
    -- The search harvester walks the caption row too, it has no card.
    if item.type == 'label' then return end

    BuildColorsPage(page, Core:GetSharedSettings().Colors, item)
end

---@param page table
function Shared:BuildTextures(page)
    BuildTexturesPage(page, Core:GetSharedSettings().globalMedia)
end

---@param page table
function Shared:BuildDurationText(page)
    BuildDurationTextPage(page, Core:GetSharedSettings().globalMedia)
end
