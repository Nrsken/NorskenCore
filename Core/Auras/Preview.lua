---@class NorskenCore
---@field AuraPreview AuraPreview
local Core = select(2, ...)
---@class AuraPreview
local AuraPreview = {}
Core.AuraPreview = AuraPreview

local max, floor, ceil = math.max, math.floor, math.ceil
local ipairs, pairs = ipairs, pairs
local CreateFrame = CreateFrame
local tsort = table.sort
local GetTime = GetTime
local Mixin = Mixin
local next = next

local CreateDurationTextBinding = C_DurationUtil.CreateDurationTextBinding
local CreateDuration = C_DurationUtil.CreateDuration
local GetSpellTexture = C_Spell.GetSpellTexture
local GetSpellName = C_Spell.GetSpellName

local IconStyle = Enum.CustomAuraButtonDispelTypeTextureStyle.Icon
local Filters = AuraUtil.AuraFilters

local FALLBACK_ICON = 136243
local TICK = 0.1

-- Preview Data --

local DEBUFF_SPELLS = {
    Magic   = 589,    -- Shadow Word: Pain
    Curse   = 980,    -- Agony
    Disease = 55078,  -- Blood Plague
    Poison  = 2818,   -- Deadly Poison
    Bleed   = 1943,   -- Rupture
    Enrage  = 184362, -- Enrage
    None    = 115804, -- Mortal Wounds
}

-- Buffs the player will recognise, so a buff display previews with its own class's spells.
local CLASS_BUFF_SPELLS = {
    DEATHKNIGHT = { 48707, 48792, 55233, 49028, 51271 },
    DEMONHUNTER = { 187827, 198589, 258920, 196718 },
    DRUID       = { 22812, 61336, 1126, 774, 22842 },
    EVOKER      = { 363916, 374348, 358267, 370960 },
    HUNTER      = { 186257, 186265, 288613, 34477 },
    MAGE        = { 1459, 11426, 45438, 190319 },
    MONK        = { 115203, 122470, 115176, 116841 },
    PALADIN     = { 642, 1022, 31884, 465 },
    PRIEST      = { 21562, 17, 139, 586 },
    ROGUE       = { 5277, 31224, 2983, 315496 },
    SHAMAN      = { 192106, 108271, 2825, 974 },
    WARLOCK     = { 104773, 20707, 108416, 6229 },
    WARRIOR     = { 6673, 871, 12975, 97462 },
}

-- cycled per slot so the count text, the swipe and the full color ramp all show at once
local TIMINGS = {
    { duration = 30,   stacks = 0 },
    { duration = 12,   stacks = 3 },
    { duration = 6,    stacks = 0 },
    { duration = 45,   stacks = 20 },
    { duration = 20,   stacks = 0 },
    { duration = 8,    stacks = 2 },
    { duration = 120,  stacks = 0 },
    { duration = 1800, stacks = 0 },
}

-- The dispel types a preview can show, in the order they are cycled through.
local HARMFUL_DISPELS = { 'Magic', 'Curse', 'Disease', 'Poison', 'Bleed', 'None' }
local HELPFUL_DISPELS = { 'Magic', 'None', 'Enrage' }

-- Dispel icon atlases used by the skin, so the preview can match.
local DISPEL_ICON_ATLASES = {
    Magic   = 'RaidFrame-Icon-DebuffMagic',
    Curse   = 'RaidFrame-Icon-DebuffCurse',
    Disease = 'RaidFrame-Icon-DebuffDisease',
    Poison  = 'RaidFrame-Icon-DebuffPoison',
    Bleed   = 'RaidFrame-Icon-DebuffBleed',
}

local iconCache = {}

---@param spellID number
---@return number|string
local function SpellIcon(spellID)
    local icon = iconCache[spellID]
    if not icon then
        icon = GetSpellTexture(spellID)
        if icon then
            iconCache[spellID] = icon -- not cached while the client still has nothing for it
        end
    end
    return icon or FALLBACK_ICON
end

---Dispel types a branch narrows to, keeping only the ones that have a color to draw with.
---@param includeDispelTypes table?
---@return string[]?
local function BranchDispels(includeDispelTypes)
    if not includeDispelTypes then return nil end

    local colors = Core.Colors.dispel
    local types
    for dispel in pairs(includeDispelTypes) do
        if colors[dispel] then
            types = types or {}
            types[#types + 1] = dispel
        end
    end

    if types then
        tsort(types)
    end
    return types
end

---Spell IDs a filter narrows to, when that's exactly one branch of whitelisted spells:
---the closest a preview gets to the real display, so it wins over the fallback tables.
---@param branch table?
---@return number[]?
local function BranchSpells(branch)
    local candidates = branch and branch.candidateFilters
    local include = candidates and candidates.includeSpellIDs
    if not include then return nil end

    -- the global blocklist is merged into every branch, so an excluded spell never shows live
    local exclude = candidates.excludeSpellIDs
    local spells
    for spellID in pairs(include) do
        if not (exclude and exclude[spellID]) then
            spells = spells or {}
            spells[#spells + 1] = spellID
        end
    end

    -- includeSpellIDs is a set, so the preview sorts it to stay stable across rebuilds
    if spells then
        tsort(spells)
    end
    return spells
end

---What one display previews: its icons, their dispel types and which way round they read.
---@param branches table[]? compiled filter branches
---@return number[]? spells nil to pick icons from the dispel type instead
---@return string[] dispels
---@return boolean harmful
local function ResolveDisplay(branches)
    -- helpful only when every branch is, so a multi-branch buff filter previews as buffs;
    -- only a spec branch carries its base type, a bare HELPFUL/HARMFUL is the filter string
    local harmful = true
    if branches and branches[1] then
        harmful = false
        for _, entry in ipairs(branches) do
            if (entry.type or entry.filterString) ~= Filters.Helpful then
                harmful = true
                break
            end
        end
    end

    -- a filter's own spells and dispel types only read clearly when it narrows to one branch
    local branch = branches and #branches == 1 and branches[1] or nil
    local spells = BranchSpells(branch)
    local dispels = BranchDispels(branch and branch.candidateFilters and branch.candidateFilters.includeDispelTypes)

    return spells, dispels or (harmful and HARMFUL_DISPELS or HELPFUL_DISPELS), harmful
end

---@param spells number[]?
---@param harmful boolean
---@return number[]? classSpells
local function ClassSpells(spells, harmful)
    if spells or harmful then return nil end
    return CLASS_BUFF_SPELLS[Core.MyClass] or CLASS_BUFF_SPELLS.PRIEST
end

---@param spells number[]?
---@param classSpells number[]?
---@param dispel string
---@param slot number
---@return number spellID
local function EntrySpell(spells, classSpells, dispel, slot)
    if spells then
        return spells[(slot - 1) % #spells + 1]
    end
    if classSpells then
        return classSpells[(slot - 1) % #classSpells + 1]
    end

    -- harmful with no whitelist: the icon follows the dispel type, matching the border
    return DEBUFF_SPELLS[dispel] or DEBUFF_SPELLS.None
end

---Fill in one display's fake auras, reusing the entry tables so a rebuild allocates nothing.
---@param state table
local function BuildEntries(state)
    local branches = Core:GetTriggerBranches(state.filter)
    local spells, dispels, harmful = ResolveDisplay(branches)
    local classSpells = ClassSpells(spells, harmful)

    -- a display styling each trigger apart shares its dummies out, each with its own spells
    local split = state.config.skin ~= nil and #branches > 1
    local own
    if split then
        own = {}
        for b, branch in ipairs(branches) do
            local branchSpells, branchDispels, branchHarmful = ResolveDisplay({ branch })
            own[b] = { spells = branchSpells, dispels = branchDispels, harmful = branchHarmful, classSpells = ClassSpells(branchSpells, branchHarmful) }
        end
    end

    local lead = state.lead
    local leadCount = lead and lead.count or 0

    local entries = state.entries
    for index = 1, state.count do
        local entry = entries[index]
        if not entry then
            entry = {}
            entries[index] = entry
        end

        local slot = index - leadCount -- the lead runs its own spells, the rest carry on from one
        local timing = TIMINGS[(index - 1) % #TIMINGS + 1]
        local branchIndex = 1
        local entrySpells, entryDispels, entryHarmful, entryClassSpells = spells, dispels, harmful, classSpells
        if split then
            -- spread so every trigger gets a share while there are enough, the remainder one each
            branchIndex = floor((index - 1) * #branches / state.count) + 1
            local resolved = own[branchIndex]
            entrySpells, entryDispels, entryHarmful, entryClassSpells = resolved.spells, resolved.dispels, resolved.harmful, resolved.classSpells
            slot = index - ceil((branchIndex - 1) * state.count / #branches)
        end
        local dispel = entryDispels[(index - 1) % #entryDispels + 1]

        entry.branch = branchIndex
        entry.harmful = entryHarmful
        entry.dispel = dispel ~= 'None' and dispel or nil
        entry.duration = timing.duration
        entry.stacks = timing.stacks

        local spellID
        if slot < 1 then
            spellID = lead.spells[(index - 1) % #lead.spells + 1]
        else
            spellID = EntrySpell(entrySpells, entryClassSpells, dispel, slot)
        end
        entry.icon = SpellIcon(spellID)
        entry.name = GetSpellName(spellID) or ''
    end

    for index = state.count + 1, #entries do
        entries[index] = nil
    end
end

-- Region Pools --

---@param texture Texture
local function BlankTexture(texture)
    texture:SetTexture(nil)
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetTexCoord(0, 1, 0, 1)
end

---@param fontString FontString
local function BlankFontString(fontString)
    fontString:SetText('')
    fontString:SetTextColor(1, 1, 1, 1)
end

---@param frame Frame
---@param create function the frame's own constructor, captured before it is replaced
---@param blank fun(region: any)
---@return table pool
local function CreatePool(frame, create, blank)
    local pool = { regions = {}, index = 0 }

    function pool:Reset()
        for _, region in ipairs(self.regions) do
            region:Hide()
        end
        self.index = 0
    end

    function pool:Take(layer, subLayer)
        self.index = self.index + 1

        local region = self.regions[self.index]
        if not region then
            region = create(frame, nil, layer, nil, subLayer)
            self.regions[self.index] = region
            return region
        end

        region:ClearAllPoints()
        region:SetDrawLayer(layer or 'ARTWORK', subLayer)
        region:SetAlpha(1)
        blank(region)
        region:Show()
        return region
    end

    return pool
end

---@param frame Frame
local function PoolRegions(frame)
    local textures = CreatePool(frame, frame.CreateTexture, BlankTexture)
    local fontStrings = CreatePool(frame, frame.CreateFontString, BlankFontString)

    frame.nuiPools = { textures, fontStrings }
    frame.CreateTexture = function(_, _, layer, _, subLayer) return textures:Take(layer, subLayer) end
    frame.CreateFontString = function(_, _, layer, _, subLayer) return fontStrings:Take(layer, subLayer) end
end

---@param frame Frame
local function ResetPools(frame)
    for _, pool in ipairs(frame.nuiPools) do
        pool:Reset()
    end
end

-- Dummy buttons --

local DummyMixin = {}

function DummyMixin:SetIcon(texture)
    self.nuiIcon = texture
end

function DummyMixin:SetDurationCooldown(cooldown)
    self.nuiCooldown = cooldown
end

function DummyMixin:SetApplicationCount(fontString, options)
    self.nuiCount = fontString
    self.nuiCountFormatter = options and options.formatter
end

function DummyMixin:SetDurationText(fontString, options)
    self.nuiTime = fontString
    self.nuiTimeOptions = options
end

function DummyMixin:AddDispelTypeTexture(texture, options)
    local index = self.nuiDispelCount + 1
    self.nuiDispelCount = index

    local slot = self.nuiDispel[index]
    if not slot then
        slot = {}
        self.nuiDispel[index] = slot
    end

    -- copied, as the game copies them: the caller reuses one table for every part
    slot.texture, slot.options = texture, CopyTable(options)
end

function DummyMixin:ClearIcon()
    self.nuiIcon = nil
end

function DummyMixin:ClearApplicationCount()
    self.nuiCount, self.nuiCountFormatter = nil, nil
end

function DummyMixin:ClearDurationText()
    self.nuiTime, self.nuiTimeOptions = nil, nil
end

function DummyMixin:SetSpellName(fontString)
    self.nuiName = fontString
end

function DummyMixin:ClearSpellName()
    self.nuiName = nil
end

function DummyMixin:SetCasterName(fontString, options)
    self.nuiCaster, self.nuiCasterOptions = fontString, options
end

function DummyMixin:ClearCasterName()
    self.nuiCaster, self.nuiCasterOptions = nil, nil
end

function DummyMixin:ClearDispelTypeTextures()
    self.nuiDispelCount = 0
end

-- A fake aura never reaches its pandemic window.
function DummyMixin:AddPandemicRegion(region)
    region:SetAlpha(0)
end

-- a stand-in never shows a tooltip, hides in combat or cancels the aura
function DummyMixin:SetTooltipAnchorPoint() end

function DummyMixin:SetHideTooltipInCombat() end

function DummyMixin:SetCancelAuraButtons() end

---@param display Frame
---@param index number
---@return table button
local function AcquireButton(display, index)
    local button = display.buttons[index]
    if button then
        return button
    end

    button = CreateFrame('Button', nil, display)
    Mixin(button, DummyMixin)
    button.nuiDispel, button.nuiDispelCount = {}, 0
    PoolRegions(button)

    display.buttons[index] = button
    return button
end

---Clear whatever the previous pass left on a dummy, so a rebuild starts from bare regions.
---@param button table
local function ResetDummy(button)
    ResetPools(button)

    button.nuiIcon, button.nuiCooldown, button.nuiCount, button.nuiCountFormatter = nil, nil, nil, nil
    button.nuiTime, button.nuiTimeOptions, button.nuiName = nil, nil, nil
    button.nuiCaster, button.nuiCasterOptions = nil, nil
    button.nuiDispelCount = 0
    -- its dispel parts start over too, so ApplyAuraLook mustn't think they're still held
    local entry = button.nuiAuraEntry
    if entry then
        entry.refs.dispelBound = nil
    end
end

---Settle a drawn dummy: anything that asked for duration text gets a live binding.
---@param button table
local function FinishDummy(button)
    button:EnableMouse(false) -- a dummy sits under the mover, it must never take the click

    if button.nuiCooldown then
        button.nuiCooldown:Show()
    end

    if button.nuiTime and CreateDurationTextBinding then
        local binding = button.nuiBinding
        if not binding then
            binding = CreateDurationTextBinding()
            button.nuiBinding = binding
        end

        -- as a real button's SetDurationText does (CustomAuraButtonSharedMixin), so the text
        -- matches down to the colour codes
        local options = button.nuiTimeOptions
        binding:SetToDefaults()
        if options and options.textFormat then
            binding:SetTextFormat(options.textFormat.formatString, options.textFormat.components)
        elseif options and options.textFormatter then
            binding:SetFormatter(options.textFormatter)
        end
        binding:SetFontString(button.nuiTime)
        binding:SetEnabled(true)
    elseif button.nuiBinding then
        button.nuiBinding:SetEnabled(false)
    end
end

---Run the display's own `options.skin` over a dummy, as its live buttons are styled.
---@param button table
---@param options table
---@param branch number the trigger branch the dummy stands in for
local function SkinButton(button, options, branch)
    local cooldown = button.nuiCooldown
    ResetDummy(button)
    -- the skin builds its parts once and restyles after, so its swipe stays
    button.nuiCooldown = cooldown
    options.skin(button, branch)
    FinishDummy(button)
end

---The color curve a real button colors its duration text with; nil in every other mode,
---where the formatter has already baked the color in.
---@param button table
---@return table? curve
local function DurationCurve(button)
    local textColor = button.nuiTimeOptions and button.nuiTimeOptions.textColor
    return textColor and textColor.curve or nil
end

---Apply the skin's dispel policy to one fake aura: the client's helpful/harmful/untyped
---rules and the same color map.
---@param button table
---@param entry table
local function ApplyDispel(button, entry)
    for index = 1, button.nuiDispelCount do
        local slot = button.nuiDispel[index]
        local options = slot.options
        local show = entry.harmful and options.showWhenHarmful or (not entry.harmful) and options.showWhenHelpful
        if show and not entry.dispel then
            show = options.showWithoutDispelType
        end

        local texture = slot.texture
        if show then
            if options.style == IconStyle then
                local atlas = entry.dispel and DISPEL_ICON_ATLASES[entry.dispel]
                if atlas then
                    texture:SetAtlas(atlas) -- art only, so it keeps the size the skin gave it
                else
                    show = false            -- enrage and untyped auras have no icon of their own
                end
            else
                -- an untyped aura takes the map's None entry, which the palette carries for that case
                -- plain r, g, b, as the game is handed (Core:LoadCustomColors' dispelRGB)
                local color = options.customDispelColorMap[entry.dispel or 'None']
                if color then
                    texture:SetVertexColor(color.r, color.g, color.b, 1)
                else
                    texture:SetVertexColor(1, 1, 1, 1)
                end
            end
        end

        texture:SetShown(show and true or false)
    end
end

---Start one fake aura on a dummy and note when it ends, so the ticker can restart it.
---@param button table
---@param entry table
---@param now number
local function StartAura(button, entry, now)
    local start = button.nuiStart
    if not start or button.nuiLength ~= entry.duration or now >= start + entry.duration then
        start = now
    end

    button.nuiStart, button.nuiLength = start, entry.duration
    button.nuiExpiration = start + entry.duration

    if button.nuiIcon then
        button.nuiIcon:SetTexture(entry.icon)
    end
    if button.nuiName then
        button.nuiName:SetText(entry.name)
    end
    if button.nuiCaster then
        local options = button.nuiCasterOptions or {}
        button.nuiCaster:SetText(Core:FormatCasterName(options.useClassColors, options.showRealmName))
    end
    if button.nuiCooldown then
        button.nuiCooldown:SetCooldown(start, entry.duration)
    end
    if button.nuiCount then
        local formatter = button.nuiCountFormatter
        button.nuiCount:SetText(formatter and formatter:FormatNumber(entry.stacks) or entry.stacks > 1 and entry.stacks or '')
    end

    if button.nuiBinding and CreateDuration then
        local duration = button.nuiDuration
        if not duration then
            duration = CreateDuration()
            button.nuiDuration = duration
        end
        duration:SetTimeFromStart(start, entry.duration)
        button.nuiBinding:SetDuration(duration)
    end

    ApplyDispel(button, entry)
end

-- Displays --

local active = {}
local ticker

---@param state table
local function Layout(state)
    local config = state.config
    local width = config.width or config.size or 24
    local height = config.height or config.size or 24
    local frameWidth, frameHeight, perLine = Core:GetAuraGridSize(config, state.count)
    -- a vertical flow fills columns first: element spacing runs down, line spacing across
    local byColumn = config.layoutAxis == AnchorUtil.FlowLayoutAxis.Vertical
    local xGap, yGap = config.elementSpacing or 0, config.lineSpacing or 0
    if byColumn then
        xGap, yGap = yGap, xGap
    end
    local xStep, yStep = width + xGap, height + yGap

    -- growth starts at anchorPoint: LEFT walks back from the right edge, UP from the bottom.
    -- The config carries either the plain token or a FlowDirection value.
    local flow = AnchorUtil.FlowDirection
    local horizontal = config.horizontalGrowthDirection
    local vertical = config.verticalGrowthDirection
    local xDir = (horizontal == 'LEFT' or horizontal == flow.Left) and -1 or 1
    local yDir = (vertical == 'UP' or vertical == flow.Up) and 1 or -1
    local point = config.anchorPoint or 'TOPLEFT'

    local frame = state.frame

    -- a slot's button covers its host, so its dummy does too
    if config.fill then
        local button = AcquireButton(frame, 1)
        button:ClearAllPoints()
        button:SetAllPoints(frame)
        button:Show()
        for index = 2, #frame.buttons do
            frame.buttons[index]:Hide()
        end
        frame:ClearAllPoints()
        frame:SetAllPoints(state.anchorTo)
        return
    end

    for index = 1, state.count do
        local button = AcquireButton(frame, index)
        local along = (index - 1) % perLine
        local line = floor((index - 1) / perLine)
        local column, row = along, line
        if byColumn then
            column, row = line, along
        end

        button:SetSize(width, height)
        button:ClearAllPoints()
        button:SetPoint(point, frame, point, column * xStep * xDir, row * yStep * yDir)
        button:Show()
    end

    for index = state.count + 1, #frame.buttons do
        frame.buttons[index]:Hide()
    end

    -- Anchored the way the container is anchored, never to the container,
    -- it carries forbidden aspects and nothing unrestricted is allowed to hang off it.
    frame:ClearAllPoints()
    frame:SetPoint(config.containerPoint or point, state.anchorTo, state.anchorPoint, state.anchorX, state.anchorY)
    frame:SetSize(frameWidth, frameHeight)
end

---Redraw a display. Geometry and aura data redo on every change, the skin pass only when
---the caller asks for it or a button never had one.
---@param state table
---@param reskin boolean
local function Refresh(state, reskin)
    if reskin then
        state.dirtySkin = false
    end

    BuildEntries(state)

    local frame = state.frame
    local lead = state.lead
    local leadCount = lead and lead.count or 0

    for index = 1, state.count do
        local button = AcquireButton(frame, index)
        if reskin or not button.nuiSkinned then
            SkinButton(button, (index <= leadCount) and lead.config or state.config, state.entries[index].branch)
            button.nuiSkinned = true
        end
    end

    Layout(state)

    local now = GetTime()
    for index = 1, state.count do
        StartAura(frame.buttons[index], state.entries[index], now)
    end
end

---Restart the auras that ran out and follow the duration color curve on every display.
local function Tick()
    local now = GetTime()

    for state in pairs(active) do
        -- Re-skinning is coalesced onto the tick, so a slider drag costs one pass per tick at most.
        if state.dirtySkin then
            Refresh(state, true)
        end

        for index = 1, state.count do
            local button = state.frame.buttons[index]
            local entry = state.entries[index]

            if now >= button.nuiExpiration then
                StartAura(button, entry, now)
            elseif button.nuiTime then
                local curve = DurationCurve(button)
                if curve then
                    button.nuiTime:SetTextColor(curve:EvaluateUnpacked(button.nuiExpiration - now))
                end
            end
        end
    end
end

local function UpdateTicker()
    local wanted = next(active) ~= nil
    if wanted and not ticker then
        ticker = C_Timer.NewTicker(TICK, Tick)
    elseif not wanted and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

---A container's preview state, created on the first call. The container is only ever a key,
---the preview never calls a method on it, since it carries forbidden aspects.
---@param container table
---@return table state
local function GetState(container)
    local state = container.nuiPreview
    if not state then
        state = { entries = {} }
        container.nuiPreview = state
    end
    return state
end

--[[

API: NRSKNUI.AuraPreview:Attach(container, relativeTo, relativePoint[, x, y, level])

Where a container's preview lives, which is wherever the container itself was anchored: pass the same
frame and point the container's own :SetPoint was given. The preview can never hang off the container,
since an AuraContainer carries forbidden aspects that an unrestricted frame is not allowed to inherit.

* container     - a container from frame:CreateAuraContainer
* relativeTo    - the frame the container is anchored to, which also parents the preview
* relativePoint - the point on that frame
* x, y          - the container's own offsets
* level         - the container's frame level, so the preview layers where the real display does

--]]
---@param container table
---@param relativeTo Frame
---@param relativePoint string
---@param x number?
---@param y number?
---@param level number? frame level to match the container's, passed in rather than read off the container
function AuraPreview:Attach(container, relativeTo, relativePoint, x, y, level)
    if not container then return end

    local state = GetState(container)
    state.anchorTo, state.anchorPoint, state.anchorX, state.anchorY = relativeTo, relativePoint, x or 0, y or 0
    state.level = level

    if state.frame then
        state.frame:SetParent(relativeTo)
        if level then
            state.frame:SetFrameLevel(level)
        end
        if state.frame:IsShown() then
            Layout(state)
        end
    end
end

--[[

API: NRSKNUI.AuraPreview:Update(container, config, count, trigger[, lead])

Tell a container what its preview should look like. Cheap and safe to call from any settings pass:
nothing is built until the preview is actually shown and a display that is already up redraws.

* container  - a container from frame:CreateAuraContainer
* config     - the same table that container was created with
* count      - how many dummies to show, normally the display's worst-case aura count
* trigger    - the trigger or filter string the container runs, so the preview can borrow its spells
* lead       - { count, config, spells } for displays that flow a second group in front of their auras,
*               i.e. the weapon enchants. They lay out in the same flow rather than a group of their own,
*               so the seam carries elementSpacing instead of groupSpacing.

--]]
---@param container table
---@param config table
---@param count number
---@param trigger (string|table)?
---@param lead table?
function AuraPreview:Update(container, config, count, trigger, lead)
    if not container then return end

    local state = GetState(container)
    state.config, state.count, state.filter, state.lead = config, max(1, count or 1), trigger, lead

    -- Geometry follows the cursor, the skin catches up on the next tick.
    if state.frame and state.frame:IsShown() then
        state.dirtySkin = true
        Refresh(state, false)
    end
end

--[[

API: NRSKNUI.AuraPreview:SetShown(container, shown)

Show or hide a container's dummy auras. The real container's own visibility is the caller's to manage,
since only the caller knows whether it should come back.

* container - a container from frame:CreateAuraContainer
* shown     - whether the dummies are on screen

--]]
---@param container table
---@param shown boolean
function AuraPreview:SetShown(container, shown)
    local state = container and container.nuiPreview
    if not state or not state.config or not state.anchorTo then return end

    if not shown then
        if state.frame then
            state.frame:Hide()
        end
        active[state] = nil
        UpdateTicker()
        return
    end

    if not state.frame then
        local frame = CreateFrame('Frame', nil, state.anchorTo)
        frame.buttons = {}
        state.frame = frame
    end

    if state.level then
        state.frame:SetFrameLevel(state.level)
    end

    Refresh(state, true)

    state.frame:Show()
    active[state] = true
    UpdateTicker()
end
