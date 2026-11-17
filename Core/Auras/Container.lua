---@class NorskenCore
local Core = select(2, ...)

local UnitIsPlayerControlledOrGroupMember = UnitIsPlayerControlledOrGroupMember
local UnitIsVisible = UnitIsVisible
local ipairs, pairs = ipairs, pairs
local CreateFrame = CreateFrame
local CopyTable = CopyTable
local GetTime = GetTime
local Mixin = Mixin
local type = type

---@type fun(unit: UnitToken, target: UnitToken, canAssistImmunePC: boolean?, canAssistUninteractable: boolean?): boolean
local UnitCanAssist = UnitCanAssist

local huge = math.huge

local AuraFilterTokens = AuraUtil.AuraFilters

-- an empty include map matches nothing; unlike a filter string it holds on untrusted units
local NEVER_MATCH_CANDIDATES = { includeDispelTypes = {} }

-- element-wide defaults copied onto the container, a group's own options override them
local ELEMENT_OPTIONS = {
    'maxFrameCount', 'sortMethod', 'sortDirection', 'hidePermanent',
    'elementSpacing', 'lineSpacing', 'groupSpacing', 'groupLineSpacing',
    'forceNewLine', 'elementWidth', 'elementHeight',
}

-- Subset of ELEMENT_OPTIONS that belongs in a flow layout table.
local LAYOUT_OPTIONS = {
    'elementSpacing', 'lineSpacing', 'groupSpacing', 'groupLineSpacing',
    'forceNewLine', 'elementWidth', 'elementHeight',
}

---Resolve a growth direction to the AnchorUtil.FlowDirection value the flow layout expects.
---Accepts a FlowDirection value directly or one of 'LEFT'/'RIGHT'/'UP'/'DOWN'.
---@param direction string|number|nil
---@param default number
---@return number
local function ResolveGrowthDirection(direction, default)
    if type(direction) == 'number' then
        return direction
    end

    local flow = AnchorUtil.FlowDirection
    if direction == 'LEFT' then
        return flow.Left
    elseif direction == 'RIGHT' then
        return flow.Right
    elseif direction == 'UP' then
        return flow.Up
    elseif direction == 'DOWN' then
        return flow.Down
    end

    return default
end

---Push the container-level flow layout settings.
---Shared by creation and :ApplyLayout, as every one of these can change on a live container.
---@param container table
---@param config table
local function ApplyFlowLayout(container, config)
    local defaults = CustomAuraContainerLayoutDefaults
    local pad = config.padding or 0
    local horizontalGrowth = ResolveGrowthDirection(config.horizontalGrowthDirection, defaults.horizontalGrowthDirection)
    local verticalGrowth = ResolveGrowthDirection(config.verticalGrowthDirection, defaults.verticalGrowthDirection)

    container:SetFlowLayoutAxis(config.layoutAxis or defaults.axis)
    container:SetFlowLayoutAnchorPoint(config.anchorPoint or defaults.anchorPoint)
    container:SetFlowLayoutGrowthDirection(horizontalGrowth, verticalGrowth)
    container:SetFlowLayoutPadding(config.paddingLeft or pad, config.paddingRight or pad, config.paddingTop or pad, config.paddingBottom or pad)
    container:SetFlowLayoutMaximumLineSize(config.maximumLineSize) -- nil means unbounded
end

---A group/enchant layout padded with the container's element-wide layout defaults. A copy:
---a caller's table can be passed again after those defaults change.
---@param container table
---@param layout table?
---@return table
local function ResolveLayout(container, layout)
    local resolved = {}
    for key, value in pairs(layout or {}) do
        resolved[key] = value
    end
    for _, key in ipairs(LAYOUT_OPTIONS) do
        if resolved[key] == nil then
            resolved[key] = container[key]
        end
    end

    return resolved
end

-- Convenience mixin applied to every container created through frame:CreateAuraContainer.
-- This mirrors oUF's element API so unit-frame and standalone code read the same.
local ContainerMixin = {}

---Pad group/slot options with the container's sort.
---@param container table
---@param options table
local function ResolveDisplayOptions(container, options)
    options.sortMethod = options.sortMethod or container.sortMethod or AuraContainerSortMethod.ExpirationOnly
    options.sortDirection = options.sortDirection or container.sortDirection or AuraContainerSortDirection.Normal
end

---Which identity verdict a spellID list hangs on, nil when the client never voids it.
---@param filterString string
---@param candidateFilters table?
---@return boolean?
local function ResolveIdentityDependence(filterString, candidateFilters)
    if not Core.AuraFilters:HasSpellIDCandidates(candidateFilters) then return nil end

    local anySecret = false
    for spellId in pairs(candidateFilters.includeSpellIDs) do
        if Core:IsSpellAuraSecret(spellId) then
            anySecret = true
            break
        end
    end
    if not anySecret then return nil end

    for component in filterString:gmatch('[^| ]+') do
        if component == AuraFilterTokens.Helpful then return true end
        if component == AuraFilterTokens.Harmful then return false end
    end

    return nil
end

---Can the client drop part of this filter string? A bare base token has nothing to lose.
---@param filterString string
---@return boolean
local function IsFilterStringNarrowing(filterString)
    local seen = false
    for _ in filterString:gmatch('[^| ]+') do
        if seen then return true end
        seen = true
    end

    return false
end

---Mirrors AuraContainerUtil.CanApplyIdentityCandidateFilters: a spellID list is voided
---for harmful auras on units you can help and helpful ones on the rest, bar group members.
---@param container table
---@param identity boolean? this display's ResolveIdentityDependence verdict
---@param assistOnly boolean? the display belongs on units the player can help, whatever it matches
---@param narrowing boolean? this display's IsFilterStringNarrowing verdict
---@return boolean
local function IsGated(container, identity, assistOnly, narrowing)
    if narrowing and container.unitInvisible then return true end
    if assistOnly and container.unitCanAssist == false then return true end
    if identity == nil then return false end
    if identity == true and container.unitAlwaysHelpful then return false end
    if container.unitCanAssist == nil then return false end

    return identity ~= container.unitCanAssist
end

---What a group's frame cap should be right now.
---@param container table
---@param slot number
---@return number
local function ResolveMaxFrameCount(container, slot)
    if container.parkedSlots and container.parkedSlots[slot] then
        return 0
    end

    local identity = container.groupIdentity and container.groupIdentity[slot]
    local narrowing = container.groupNarrowing and container.groupNarrowing[slot]
    if IsGated(container, identity, nil, narrowing) then
        return 0
    end

    return container.maxFrameCount or huge
end

---Sole writer of a group's frame cap, so the value it caches can never go stale.
---@param container table
---@param slot number
---@param key string
local function PushGroupCap(container, slot, key)
    local cap = ResolveMaxFrameCount(container, slot)
    local pushed = container.groupCaps

    if pushed[slot] == cap then return end
    pushed[slot] = cap

    container:SetAuraGroupMaxFrameCount(key, cap)
end

---Sole writer of a slot's candidate filters, see PushGroupCap. The gate can't use the
---filter string: a unit that isn't visible is where the client stops honouring one.
---@param container table
---@param index number
---@param key string
local function PushSlotCandidates(container, index, key)
    local filters = NEVER_MATCH_CANDIDATES
    if container.slotShown[index] and
        not IsGated(container, container.slotIdentity[index], container.slotAssistOnly[index], container.slotNarrowing[index]) then
        filters = container.slotCandidates[index] -- may be nil, meaning this slot filters on tokens alone
    end

    local pushed = container.slotPushed
    if pushed[index] == filters then return end
    pushed[index] = filters

    container:SetAuraSlotCandidateFilters(key, filters)
end

local SampleWatcher -- lives with the watchers below

---Mark that this container gates on the canAssist axis. Sticky, it can only ever over-read.
---@param container table
local function MarkNeedsAssist(container)
    if container.needsAssist then return end
    container.needsAssist = true

    local watcher = container.gateWatcher
    if not watcher then return end

    watcher.assistCount = watcher.assistCount + 1
    if watcher.canAssist == nil then -- never sampled before now
        SampleWatcher(watcher)
    end
end

---Mark that a display here has a filter string the client can drop. Sticky, as above.
---@param container table
local function MarkNeedsVisible(container)
    if container.needsVisible then return end
    container.needsVisible = true

    local watcher = container.gateWatcher
    if not watcher then return end

    watcher.visibleCount = watcher.visibleCount + 1
    SampleWatcher(watcher)
end

---Register a group of auras, can be called multiple times.
---@param filter string aura filter string ('HELPFUL', 'HARMFUL', ...)
---@param options table? optional per-group options
---@return string key
---@return number slot
function ContainerMixin:AddGroup(filter, options)
    options = options or {}

    options.maxFrameCount = options.maxFrameCount or self.maxFrameCount
    options.layout = ResolveLayout(self, options.layout)
    ResolveDisplayOptions(self, options)

    self.groupIndex = (self.groupIndex or 0) + 1
    local key = (self:GetDebugName() or 'NRSKNUIAuraContainer') .. 'Group' .. self.groupIndex
    self:AddAuraGroup(key, filter, options)

    -- kept so :ApplyLayout can re-push each group's settings without the caller's keys
    self.groupKeys = self.groupKeys or {}
    self.groupIdentity = self.groupIdentity or {}
    self.groupNarrowing = self.groupNarrowing or {}
    local slot = #self.groupKeys + 1
    self.groupKeys[slot] = key
    self.groupIdentity[slot] = ResolveIdentityDependence(filter, options.candidateFilters)
    if self.groupIdentity[slot] ~= nil then
        MarkNeedsAssist(self)
    end

    self.groupNarrowing[slot] = IsFilterStringNarrowing(filter) or nil
    if self.groupNarrowing[slot] then
        MarkNeedsVisible(self)
    end

    -- A group added while its gate is shut would otherwise come up live.
    PushGroupCap(self, slot, key)

    return key, slot
end

---A trigger's compiled branches, at least one so a binding never has no groups.
---@param trigger table?
---@return table[] branches
local function ResolveBranches(trigger)
    local branches = Core:GetTriggerBranches(trigger)
    if branches and branches[1] then
        return branches
    end
    return { { filterString = AuraFilterTokens.Harmful } }
end

---Point a binding's groups at its trigger's current branches.
---@param container table
---@param binding table
local function SyncBinding(container, binding)
    local branches = ResolveBranches(binding.trigger)
    container.parkedSlots = container.parkedSlots or {}
    container.groupIdentity = container.groupIdentity or {}
    container.groupNarrowing = container.groupNarrowing or {}

    for index, branch in ipairs(branches) do
        container:EnsureProcessAuraPolicy(branch.candidateFilters)

        local key = binding.keys[index]
        if key then
            container:SetAuraGroupFilterString(key, branch.filterString)
            container:SetAuraGroupCandidateFilters(key, branch.candidateFilters)
        else
            -- AddGroup mutates the options it is given, so each group gets its own copy.
            local groupOptions = binding.options and CopyTable(binding.options) or {}
            groupOptions.candidateFilters = branch.candidateFilters
            -- the game hands initializeFrame only the button, so a per-trigger caller is told which
            local initializeBranch = groupOptions.initializeBranchFrame
            groupOptions.initializeBranchFrame = nil
            if initializeBranch then
                groupOptions.initializeFrame = function(button) initializeBranch(button, index) end
            end
            binding.keys[index], binding.slots[index] = container:AddGroup(branch.filterString, groupOptions)
        end

        local slot = binding.slots[index]
        container.groupIdentity[slot] = ResolveIdentityDependence(branch.filterString, branch.candidateFilters)
        if container.groupIdentity[slot] ~= nil then
            MarkNeedsAssist(container)
        end

        container.groupNarrowing[slot] = IsFilterStringNarrowing(branch.filterString) or nil
        if container.groupNarrowing[slot] then
            MarkNeedsVisible(container)
        end
        container.parkedSlots[slot] = nil
        PushGroupCap(container, slot, binding.keys[index])
    end

    for index = #branches + 1, #binding.keys do
        container.parkedSlots[binding.slots[index]] = true
        PushGroupCap(container, binding.slots[index], binding.keys[index])
    end
end

---Register an inline trigger, can be called multiple times.
---@param trigger table? an inline trigger (see Core/Auras/Triggers.lua)
---@param options table? per-group options; candidateFilters comes from each branch and
---`initializeBranchFrame(button, index)` replaces initializeFrame and is told the branch
---@return string[]
function ContainerMixin:AddFilteredGroup(trigger, options)
    local binding = { trigger = trigger, keys = {}, slots = {}, options = options }

    self.filterBindings = self.filterBindings or {}
    self.filterBindings[#self.filterBindings + 1] = binding

    SyncBinding(self, binding)

    return binding.keys
end

---Turn on the ProcessAura policy when a filter asks to match on processedAuraType.
---@param candidateFilters table? the resolved candidate filter table (may be nil)
function ContainerMixin:EnsureProcessAuraPolicy(candidateFilters)
    if not (candidateFilters and candidateFilters.processedAuraType) then return end
    if self.processAuraPolicy then return end

    self:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.ProcessAura, self.__processAuraPolicyOptions)
    self.processAuraPolicy = true
end

---Re-push everything the native container lets us change after creation.
---@param config table? the same table accepted by frame:CreateAuraContainer
function ContainerMixin:ApplyLayout(config)
    config = config or {}

    ApplyFlowLayout(self, config)

    for _, key in ipairs(ELEMENT_OPTIONS) do
        self[key] = config[key]
    end

    for slot, key in ipairs(self.groupKeys or {}) do
        self:SetAuraGroupLayout(key, ResolveLayout(self, nil))
        PushGroupCap(self, slot, key)
        self:SetAuraGroupSortMethod(key, self.sortMethod or AuraContainerSortMethod.ExpirationOnly, self.sortDirection or AuraContainerSortDirection.Normal)
    end
end

---Reapply every binding registered through :AddFilteredGroup
function ContainerMixin:ReapplyFilters()
    if not self.filterBindings then return end

    Core:RunWhenSafe(function()
        for _, binding in ipairs(self.filterBindings) do
            SyncBinding(self, binding)
        end
        -- a spellID list new to this container has no verdict yet, so it would show unfiltered
        if self:UpdateUnitGate() then
            self:UpdateAllAuras()
        end
    end)
end

---Point every :AddFilteredGroup binding at another trigger and reapply.
---Used when the GUI edits or replaces the trigger a display runs.
---@param trigger table? an inline trigger (see Core/Auras/Triggers.lua)
function ContainerMixin:RebindFilteredGroups(trigger)
    if not self.filterBindings then return end

    for _, binding in ipairs(self.filterBindings) do
        binding.trigger = trigger
    end

    self:ReapplyFilters()
end

---Register a single-aura slot (this can be called multiple times).
---@param filter string aura filter string
---@param options table? optional per-slot options (.assistOnly keeps the slot to units the player can help)
---@return table? slot
---@return string key
---@return number index
function ContainerMixin:AddSlot(filter, options)
    options = options or {}

    -- Ours rather than the client's, so it comes back out before the table crosses over.
    local assistOnly = options.assistOnly
    options.assistOnly = nil

    self:EnsureProcessAuraPolicy(options.candidateFilters)
    ResolveDisplayOptions(self, options)

    self.slotIndex = (self.slotIndex or 0) + 1
    local key = (self:GetDebugName() or 'NRSKNUIAuraContainer') .. 'Slot' .. self.slotIndex

    local index = self.slotIndex
    self.slotKeys[index] = key
    self.slotFilters[index] = filter
    self.slotCandidates[index] = options.candidateFilters
    self.slotShown[index] = true
    self.slotIdentity[index] = ResolveIdentityDependence(filter, options.candidateFilters)
    self.slotAssistOnly[index] = assistOnly or nil
    if self.slotIdentity[index] ~= nil or assistOnly then
        MarkNeedsAssist(self)
    end

    self.slotNarrowing[index] = IsFilterStringNarrowing(filter) or nil
    if self.slotNarrowing[index] then
        MarkNeedsVisible(self)
    end

    local slot = self:AddAuraSlot(key, filter, options)

    self.slotPushed[index] = options.candidateFilters -- AddAuraSlot has just installed these

    -- A slot added while its gate is shut would otherwise come up live.
    PushSlotCandidates(self, index, key)

    return slot, key, index
end

---The gate and SetSlotShown can still override these.
---@param index number the third return of :AddSlot
---@param candidateFilters table?
function ContainerMixin:SetSlotCandidates(index, candidateFilters)
    local key = self.slotKeys[index]
    if not key then return end

    self:EnsureProcessAuraPolicy(candidateFilters)
    self.slotCandidates[index] = candidateFilters
    -- new candidates can bring a spellID list the gate wasn't watching
    self.slotIdentity[index] = ResolveIdentityDependence(self.slotFilters[index], candidateFilters)
    if self.slotIdentity[index] ~= nil then
        MarkNeedsAssist(self)
    end
    PushSlotCandidates(self, index, key)
end

---Point a slot at another filter string; the game keeps its button.
---@param index number the third return of :AddSlot
---@param filter string
function ContainerMixin:SetSlotFilterString(index, filter)
    local key = self.slotKeys[index]
    if not key or self.slotFilters[index] == filter then return end

    self.slotFilters[index] = filter
    self:SetAuraSlotFilterString(key, filter)
    self.slotNarrowing[index] = IsFilterStringNarrowing(filter) or nil
    if self.slotNarrowing[index] then
        MarkNeedsVisible(self)
    end
    -- whether a spellID list is voided hangs on helpful or harmful
    self.slotIdentity[index] = ResolveIdentityDependence(filter, self.slotCandidates[index])
    if self.slotIdentity[index] ~= nil then
        MarkNeedsAssist(self)
    end
    PushSlotCandidates(self, index, key)
end

---Show or hide a slot, which the gate can still override.
---@param index number the third return of :AddSlot
---@param shown boolean
function ContainerMixin:SetSlotShown(index, shown)
    local key = self.slotKeys[index]
    if not key then return end

    self.slotShown[index] = shown
    PushSlotCandidates(self, index, key)
end

-- Unit gate --

local UNIT_GATE_EVENTS = {
    'UNIT_FLAGS', 'UNIT_TARGETABLE_CHANGED',
    'UNIT_FACTION', -- The canAssist axis, UNIT_FLAGS alone misses reaction changes
    'UNIT_IN_RANGE_UPDATE', 'UNIT_DISTANCE_CHECK_UPDATE',
    'UNIT_PHASE', 'UNIT_AREA_CHANGED',
    'UNIT_NAME_UPDATE' -- Fires when the client learns a unit, the nearest entering-visibility signal
}

local GATE_EVENTS = {
    'PLAYER_ENTERING_WORLD', 'ZONE_CHANGED_NEW_AREA', -- visibility
    'GROUP_ROSTER_UPDATE',                            -- UnitIsPlayerControlledOrGroupMember
    'ZONE_CHANGED', 'ZONE_CHANGED_INDOORS',
    'GROUP_ROSTER_UPDATE', 'PARTY_MEMBER_ENABLE',
    'PARTY_MEMBER_DISABLE', 'PLAYER_FLAGS_CHANGED',
    'CINEMATIC_START', 'CINEMATIC_STOP', 'PLAY_MOVIE', 'STOP_MOVIE', -- no UNIT_* event marks either edge
    'PLAYER_DEAD', 'PLAYER_ALIVE', 'PLAYER_UNGHOST'                  -- quieter than the UNIT_HEALTH other units need
}

-- Item enchants need a re-push after a loading screen, which outlasts a frame.
local SETTLE_EVENTS = {
    PLAYER_ENTERING_WORLD = true
}

local SETTLE_DELAY = 0.5

-- a container listens to UNIT_AURA for its token only, never to who the token points at
local UNIT_CHANGED_EVENTS = {
    target = 'PLAYER_TARGET_CHANGED',
    focus = 'PLAYER_FOCUS_CHANGED',
}

-- one watcher per unit token: a unit frame's four containers all want the same verdict
---@type table<string, Frame>
local watchers = {}
local globalWatcher

---@type table<table, true> containers holding item enchants
local enchantContainers = {}

---Push a watcher's verdict onto one container.
---@param container table
---@param watcher Frame
---@return boolean changed
local function ApplyGate(container, watcher)
    local canAssist, alwaysHelpful, invisible
    if container.needsAssist then
        canAssist = watcher.canAssist
        alwaysHelpful = watcher.alwaysHelpful
    end
    if container.needsVisible then
        invisible = watcher.invisible
    end

    if container.unitCanAssist == canAssist and container.unitAlwaysHelpful == alwaysHelpful
        and container.unitInvisible == invisible then
        return false
    end

    container.unitCanAssist = canAssist
    container.unitAlwaysHelpful = alwaysHelpful
    container.unitInvisible = invisible

    for slot, key in ipairs(container.groupKeys or {}) do
        PushGroupCap(container, slot, key)
    end
    for index, key in ipairs(container.slotKeys or {}) do
        PushSlotCandidates(container, index, key)
    end

    return true
end

---Re-read a watcher's unit into its cached verdict.
---@param watcher Frame
function SampleWatcher(watcher)
    watcher.sampled = GetTime()

    if watcher.assistCount > 0 then
        -- Both reads mirror CanApplyIdentityCandidateFilters, including its two canAssist overrides.
        watcher.canAssist = UnitCanAssist('player', watcher.unit, true, true)
        watcher.alwaysHelpful = UnitIsPlayerControlledOrGroupMember and UnitIsPlayerControlledOrGroupMember(watcher.unit) or nil
    else
        watcher.canAssist, watcher.alwaysHelpful = nil, nil
    end

    watcher.invisible = watcher.visibleCount > 0 and not UnitIsVisible(watcher.unit) or nil
end

---Re-read a watcher's unit and push the result to every container on it.
---@param watcher Frame
local function RefreshWatcher(watcher)
    if not watcher.unit then return end
    SampleWatcher(watcher)

    -- UNIT_FLAGS and friends fire constantly in group content but almost never move the verdict.
    for container in pairs(watcher.containers) do
        if ApplyGate(container, watcher) then
            container:UpdateAllAuras()
        end
    end
end

local function RefreshAll()
    for _, watcher in pairs(watchers) do
        if watcher.count > 0 then
            RefreshWatcher(watcher)
        end
    end
end

local function SettleAll()
    RefreshAll()

    -- item enchants sit outside the gate and would stay dead after a loading screen
    for container in pairs(enchantContainers) do
        container:UpdateAllAuras()
    end
end

---Re-read next frame and again after SETTLE_DELAY, since a load screen outlasts a frame.
---@param frame Frame
---@param callback fun()
local function ScheduleSettle(frame, callback)
    frame:NCScheduleUpdate()

    if frame.settling then return end
    frame.settling = true

    C_Timer.After(SETTLE_DELAY, function()
        frame.settling = nil
        callback()
    end)
end

---@param watcher Frame
---@param event string
local function OnGateEvent(watcher, event)
    if event ~= UNIT_CHANGED_EVENTS[watcher.unit] then
        RefreshWatcher(watcher)
        return
    end

    -- another unit now, so every container redraws whether or not the verdict moved
    SampleWatcher(watcher)
    for container in pairs(watcher.containers) do
        ApplyGate(container, watcher)
        container:UpdateAllAuras()
    end
end

---@param _ Frame
---@param event string
local function OnGlobalGateEvent(_, event)
    RefreshAll()

    if SETTLE_EVENTS[event] then
        ScheduleSettle(globalWatcher, SettleAll)
    end
end

---@param watcher Frame
local function RegisterWatcher(watcher)
    local unit = watcher.unit

    -- an unknown token makes every RegisterUnitEvent unitless, firing for the whole roster
    if not Core:IsValidUnitToken(unit) then return end

    for _, event in ipairs(UNIT_GATE_EVENTS) do
        watcher:RegisterUnitEvent(event, unit, unit ~= 'player' and 'player' or nil)
    end

    local changed = UNIT_CHANGED_EVENTS[unit]
    if changed then
        watcher:RegisterEvent(changed)
    end
end

---The shared watcher for a unit, built on first use.
---@param unit string
---@return Frame watcher
local function GetWatcher(unit)
    local watcher = watchers[unit]
    if watcher then
        return watcher
    end

    watcher = CreateFrame('Frame')
    watcher.unit = unit
    watcher.containers = {}
    watcher.count = 0
    watcher.assistCount = 0
    watcher.visibleCount = 0
    watcher:SetScript('OnEvent', OnGateEvent)
    watcher:NCSetScheduledUpdate(RefreshWatcher)
    watchers[unit] = watcher

    if not globalWatcher then
        globalWatcher = CreateFrame('Frame')
        globalWatcher:SetScript('OnEvent', OnGlobalGateEvent)
        globalWatcher:NCSetScheduledUpdate(RefreshAll)
        for _, event in ipairs(GATE_EVENTS) do
            globalWatcher:RegisterEvent(event)
        end
    end

    return watcher
end

---Take a container off the watcher it is on.
---@param container table
local function UnwatchUnit(container)
    local current = container.gateWatcher
    if not current then return end

    container.gateWatcher = nil
    current.containers[container] = nil
    current.count = current.count - 1
    if container.needsAssist then
        current.assistCount = current.assistCount - 1
    end
    if container.needsVisible then
        current.visibleCount = current.visibleCount - 1
    end

    -- Frames cannot be destroyed, so an idle watcher is kept for reuse but stops listening.
    if current.count == 0 then
        current:UnregisterAllEvents()
    end
end

---Move a container onto the shared watcher for a unit, dropping the one it was on.
---@param container table
---@param unit string
---@return Frame watcher
local function WatchUnit(container, unit)
    UnwatchUnit(container)

    local watcher = GetWatcher(unit)
    if watcher.count == 0 then
        RegisterWatcher(watcher)
    end

    watcher.containers[container] = true
    watcher.count = watcher.count + 1
    if container.needsAssist then
        watcher.assistCount = watcher.assistCount + 1
    end
    if container.needsVisible then
        watcher.visibleCount = watcher.visibleCount + 1
    end
    container.gateWatcher = watcher

    SampleWatcher(watcher)

    return watcher
end

---Reapply this container's gate for its current unit.
---@return boolean changed true when the verdict moved and the filters were reapplied
function ContainerMixin:UpdateUnitGate()
    local unit = self:GetUnit()
    if not unit then return false end

    local watcher = self.gateWatcher
    if not watcher or watcher.unit ~= unit then
        watcher = WatchUnit(self, unit)
    elseif watcher.sampled ~= GetTime() then
        SampleWatcher(watcher) -- once per frame, however many containers on the unit ask
    end

    return ApplyGate(self, watcher)
end

---Stop gating a parked container; the next UpdateUnitGate puts it back.
function ContainerMixin:StopUnitGate()
    UnwatchUnit(self)
end

---Register a temporary weapon-enchant frame (main/off-hand).
---@param slot number AuraContainerItemEnchantmentSlot value (MainHand / OffHand / Ranged)
---@param options table per-frame options: initializeFrame, and hidePermanent, .templateNames, ...
---@return table? enchant
function ContainerMixin:AddItemEnchant(slot, options)
    if options.hidePermanent == nil then
        options.hidePermanent = self.hidePermanent
    end

    enchantContainers[self] = true

    return self:AddItemEnchantment(slot, options)
end

---The item-enchant group's flow layout, padded with the container's layout defaults.
---@param options table? optional layout overrides (.placement, .elementSpacing, .groupSpacing, .layoutIndex, ...)
function ContainerMixin:SetItemEnchantLayout(options)
    self:SetItemEnchantmentLayout(ResolveLayout(self, options))
end

---A native aura container on this frame, with the NorskenUI API mixed in.
---@param config table?
---@return table? container
local function CreateAuraContainer(self, config)
    config = config or {}

    local container = CreateFrame('AuraContainer', nil, self, 'CustomAuraContainerTemplate')

    ApplyFlowLayout(container, config)

    -- Carry element-wide layout and sort defaults so AddGroup/AddSlot can read them.
    for _, key in ipairs(ELEMENT_OPTIONS) do
        container[key] = config[key]
    end

    -- kept addon-side, the container's own copy lives in the restricted environment
    container.__processAuraPolicyOptions = config.processAuraPolicyOptions

    -- the last values PushGroupCap / PushSlotCandidates pushed, so a repeat stays addon-side
    container.groupCaps = {}
    container.slotPushed = {}
    container.slotKeys = {}
    container.slotFilters = {}
    container.slotCandidates = {}
    container.slotShown = {}
    container.slotIdentity = {}
    container.slotNarrowing = {}
    container.slotAssistOnly = {}

    local policy = config.auraProcessingPolicy
    if policy then
        local isProcessAura = policy == CustomAuraContainerAuraProcessingPolicy.ProcessAura
        container:SetAuraProcessingPolicy(policy, isProcessAura and config.processAuraPolicyOptions or nil)
        container.processAuraPolicy = isProcessAura
    end

    if config.itemEnchantmentSortMethod then
        container:SetItemEnchantmentSortMethod(config.itemEnchantmentSortMethod, config.itemEnchantmentSortDirection or AuraContainerSortDirection.Normal)
    end

    return Mixin(container, ContainerMixin)
end

Core:InjectAPI(CreateFrame('Frame'), { CreateAuraContainer = CreateAuraContainer })
Core:InjectAPI(CreateFrame('Button'), { CreateAuraContainer = CreateAuraContainer })
