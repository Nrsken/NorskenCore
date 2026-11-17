---@class NorskenCore
local Core = select(2, ...)
local AuraPreview = Core.AuraPreview

local ipairs, pairs = ipairs, pairs
local CreateFrame = CreateFrame
local Mixin = Mixin
local wipe = wipe
local tremove = table.remove
local type = type
local setmetatable = setmetatable
local RunNextFrame = RunNextFrame
local InCombatLockdown = InCombatLockdown
local debugprofilestop = debugprofilestop
local next = next

local ENCHANT_SLOTS = { AuraContainerItemEnchantmentSlot.MainHand, AuraContainerItemEnchantmentSlot.OffHand }

--[[
# NewAuraDisplay

Auras drawn through a native aura container. The display owns a host frame, the container
on it, every button the game hands over and their preview stand-ins. The subscriber places
the host and says what a button looks like.

* `group` - a group per trigger branch, laid out like a dynamic group from a container config
* `slots` - slots by id, each one aura at a time from its trigger's first branch, on a host of its own: one container for every indicator on a unit frame

Any setter can run at any time. The container is made once there's a layout (and a trigger,
for a group) and combat allows it, and takes on whatever was set before then. That can
happen inside a setter, so set what `style` reads before calling it.

`style(entry)` runs on hand-over and on every restyle, the only times a button may be
touched: a button denies access while auras are secret, so `Restyle` waits for that to end.

## Example

    local display = addon:NewAuraDisplay(frame, { shape = 'group', style = StyleButton })
    display:SetLayout(addon:GetAuraGroupConfig(db, style), addon:GetAuraPreviewCount(db))
    display:SetTrigger(db.Trigger)
    display:SetUnit('player')
    display.host:SetPoint('CENTER')

    local display = addon:NewAuraDisplay(frame, { shape = 'slots', style = StyleIndicator })
    display:SetLayout({ width = 24, height = 24, disableMouse = true })
    display:SetSlot('dispel', trigger, frame.Health)
]]

---@class AuraDisplayEntry
---@field refs table from InitAuraButton, with the button as refs.button
---@field branch number the trigger branch it shows
---@field preview boolean? a preview stand-in, never a live aura
---@field enchant boolean? a weapon enchant, flowing in front of a group's auras
---@field display AuraDisplay
---@field id any? a slot's id
---@field host Frame? the frame a slot's button covers

---@class AuraDisplaySlot : AuraDisplayEntry
---@field trigger table
---@field shown boolean
---@field previewing boolean?
---@field sortMethod number?
---@field sortDirection number?
---@field assistOnly boolean? kept to units the player can help, set when its native slot is added
---@field index number? its native slot, once added
---@field key string?
---@field candidates table? what was last pushed, to skip a repeat
---@field sorted (number?)[]? the sort method and direction last pushed
---@field previewConfig table what its preview dummy is skinned with

---@class AuraDisplayOptions
---@field shape 'group'|'slots'
---@field style fun(entry: AuraDisplayEntry)
---@field name string? the host's global name, for a frame others anchor to by name

---@class AuraDisplay
---@field host Frame placed by the subscriber; a group display sizes it to its grid
---@field container table? once made
---@field shape 'group'|'slots'
---@field style fun(entry: AuraDisplayEntry)
---@field config table?
---@field count number
---@field level number?
---@field trigger table?
---@field unit string?
---@field previewing boolean
---@field released true?
---@field entries AuraDisplayEntry[] a group's buttons
---@field slots table<any, AuraDisplaySlot> by id
---@field free AuraDisplaySlot[] removed slots, which a new id takes over
---@field pending table<AuraDisplaySlot, true> slots waiting to be pointed at their trigger
---@field initButton fun(button: table, branch: number)
---@field skin fun(button: table, branch: number)
---@field SlotSkin fun(slot: AuraDisplaySlot): fun(button: table, branch: number)
---@field restyleList table[]? what the restyle queue still has to style, see QueueRestyle
---@field restyleAt number the next of them
---@field lookStamp any? the look its buttons were last restyled with
---@field restylePending true? a restyle waits for auras to stop being secret
---@field restyleQueued true? runRestyle is in the restriction queue
---@field runRestyle fun()
---@field build fun()
---@field applySlots fun()
---@field enchantsShown boolean?
---@field enchantLayout table?
---@field enchantsReady true? the game has the enchant frames
---@field previewLead table? the preview's enchant dummies, see AuraPreview:Update
---@field enchantConfig table a preview enchant's config: the group's, with the enchant skin
---@field applyEnchants fun()
---@field addingEnchants true? waiting a frame to add them
---@field addEnchants fun()
---@field initEnchant fun(button: table)
---@field park fun()
local DisplayMixin = {}

-- Restyle --

-- a big restyle (a raid's aura buttons) spreads over frames, this long a frame
local RESTYLE_BUDGET = 4

-- displays with buttons left to style, worked through by the frame below
local queue = {}
local worker = CreateFrame('Frame')
worker:Hide()

---Wait for the restriction to lift: a button denies access while auras are secret.
---The restriction queue keeps every entry, so a display waits there once.
---@param display AuraDisplay
local function WaitForAccess(display)
    queue[display] = nil
    display.restyleList = nil
    display.restylePending = true
    if not display.restyleQueued then
        display.restyleQueued = true
        Core:DeferUntilUnrestricted(0, display.runRestyle)
    end
end

worker:SetScript('OnUpdate', function(self)
    if Core:AreAurasSecret() then
        -- secret without a restriction to wait on, the queue tries again next frame
        if Core:IsRestricted() then
            -- collected first: a wait that ends at once queues the display again
            local waiting = {}
            for display in pairs(queue) do
                waiting[#waiting + 1] = display
            end
            for _, display in ipairs(waiting) do
                WaitForAccess(display)
            end
        end
        if not next(queue) then
            self:Hide()
        end
        return
    end

    local stop = debugprofilestop() + RESTYLE_BUDGET
    local display = next(queue)
    while display do
        local list, style = display.restyleList, display.style
        local group = display.shape == 'group'
        for i = display.restyleAt, #list do
            local entry = list[i]
            -- moved on first, so a style that errors fails once, not every frame
            display.restyleAt = i + 1
            -- a slot removed since it was queued has nothing to show
            if group or entry.shown then
                style(entry)
            end
            if debugprofilestop() > stop then
                return
            end
        end
        queue[display] = nil
        display.restyleList = nil
        display = next(queue)
    end
    self:Hide()
end)

---Restyle every button over the next frames; the worker waits while auras are secret.
---@param display AuraDisplay
local function QueueRestyle(display)
    -- the buttons as they are now; one handed over later is styled when it's made
    local list = {}
    if display.shape == 'group' then
        for i, entry in ipairs(display.entries) do
            list[i] = entry
        end
    else
        for _, slot in pairs(display.slots) do
            if slot.shown and slot.refs.button then
                list[#list + 1] = slot
            end
        end
    end
    display.restyleList, display.restyleAt = list, 1
    queue[display] = true
    worker:Show()
end

-- Container --

---@param display AuraDisplay
local function ApplyUnit(display)
    local unit, container = display.unit, display.container
    if not unit then return end

    container:SetUnit(unit) -- early-outs when the token is unchanged
    if container:UpdateUnitGate() then
        container:UpdateAllAuras()
    end
end

---@param display AuraDisplay
local function AttachPreview(display)
    AuraPreview:Attach(display.container, display.host, display.config.containerPoint, 0, 0, display.level)
end

-- a slot's dummy covers its host, so it is keyed by the slot and needs no container
---@param display AuraDisplay
---@param slot AuraDisplaySlot
local function AttachSlotPreview(display, slot)
    AuraPreview:Attach(slot, slot.host, 'CENTER', 0, 0, display.level)
end

---@param display AuraDisplay
local function UpdatePreview(display)
    AttachPreview(display)
    AuraPreview:Update(display.container, display.config, display.count, display.trigger, display.previewLead)
end

---@param display AuraDisplay
---@param slot AuraDisplaySlot
local function UpdateSlotPreview(display, slot)
    AttachSlotPreview(display, slot)
    AuraPreview:Update(slot, slot.previewConfig, 1, slot.trigger)
end

---@param display AuraDisplay
local function ApplyPreview(display)
    local previewing = display.previewing
    AuraPreview:SetShown(display.container, previewing)
    display.container:SetShown(not previewing)
end

---The container, out of its parking spot if Release put it there; nil until it's made.
---@param display AuraDisplay
---@return table? container
local function Ready(display)
    local released = display.released
    display.released = nil

    local container = display.container
    if not container then
        Core:RunWhenSafe(display.build)
        return nil
    end

    if released then
        Core:RunWhenSafe(display.park)
    end
    return container
end

-- Slots --

-- compiled filters are fresh tables, so an unchanged trigger is found by value
---@param a any
---@param b any
---@return boolean
local function Same(a, b)
    if a == b then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end

    for k, v in pairs(a) do
        if not Same(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

---Point a slot's one native slot at its trigger's first branch, adding it the first time.
---@param display AuraDisplay
---@param slot AuraDisplaySlot
---@return boolean reshown a slot with a button that was off, which keeps its old look
local function ApplySlot(display, slot)
    local container = display.container
    local branch = Core:GetTriggerBranches(slot.trigger)[1]

    local reshown = false
    if slot.index then
        reshown = slot.shown and slot.refs.button ~= nil and not container.slotShown[slot.index]
        container:SetSlotFilterString(slot.index, branch.filterString)
        -- each push makes the game re-read every aura, and an edit to the look changes none of this
        if not Same(slot.candidates, branch.candidateFilters) then
            slot.candidates = branch.candidateFilters
            container:SetSlotCandidates(slot.index, branch.candidateFilters)
        end
        local sorted = slot.sorted
        if slot.sortMethod and not (sorted and sorted[1] == slot.sortMethod and sorted[2] == slot.sortDirection) then
            slot.sorted = { slot.sortMethod, slot.sortDirection }
            container:SetAuraSlotSortMethod(slot.key, slot.sortMethod, slot.sortDirection)
        end
    else
        slot.candidates = branch.candidateFilters
        slot.sorted = slot.sortMethod and { slot.sortMethod, slot.sortDirection }
        local _, key, index = container:AddSlot(branch.filterString, {
            candidateFilters = branch.candidateFilters,
            sortMethod = slot.sortMethod,
            sortDirection = slot.sortDirection,
            assistOnly = slot.assistOnly,
            initializeFrame = function(button)
                Core:InitAuraButton(button, slot.host, slot.refs, display.config.width, display.config.height)
                display.style(slot)
            end,
        })
        slot.key, slot.index = key, index
    end
    container:SetSlotShown(slot.index, slot.shown and not slot.previewing)
    return reshown
end

-- API --

---Where the buttons go: a group's flow layout, the size a new slot button starts at.
---@param config table GetAuraGroupConfig's for a group; width, height and disableMouse for slots
---@param count number? a group's most buttons, which its preview and host size allow for
---@param level number? the preview's frame level, so it layers where the live buttons do
function DisplayMixin:SetLayout(config, count, level)
    self.config, self.level = config, level
    if self.shape == 'group' then
        config.skin = self.skin
        self.count = count or 1
        local width, height = Core:GetAuraGridSize(config, self.count)
        self.host:NCSetSize(width, height)
    end

    local container = Ready(self)
    if not container or self.shape ~= 'group' then return end

    container:ClearAllPoints()
    container:SetPoint(config.containerPoint, self.host, config.containerPoint)
    container:ApplyLayout(config)
    UpdatePreview(self)
end

---What a group display shows. Call it again with the same trigger after editing it.
---@param trigger table? an inline trigger (see Core/Auras/Triggers.lua)
function DisplayMixin:SetTrigger(trigger)
    self.trigger = trigger

    local container = Ready(self)
    if not container then return end

    container:RebindFilteredGroups(trigger)
    UpdatePreview(self)
end

---Weapon enchants in front of a group display's auras, switched on and off live.
---@param shown boolean
---@param layout table? their flow group's layout, see ContainerMixin:SetItemEnchantLayout
---@param previewSpells number[] what the preview's enchant dummies show
function DisplayMixin:SetItemEnchants(shown, layout, previewSpells)
    self.enchantsShown, self.enchantLayout = shown, layout
    self.previewLead = shown and { count = #ENCHANT_SLOTS, config = self.enchantConfig, spells = previewSpells } or nil
    if not Ready(self) then return end

    Core:RunWhenSafe(self.applyEnchants)
    UpdatePreview(self)
end

---Add a slot or re-point it; call it again after editing its trigger.
---@param id any
---@param trigger table an inline trigger; its first branch is the slot's
---@param host Frame? what its button covers, the display's host when nil
---@param opts { sortMethod: number?, sortDirection: number?, assistOnly: boolean? }? sort: which aura
---wins (AuraContainerSortMethod); assistOnly: kept off units the player can't help
function DisplayMixin:SetSlot(id, trigger, host, opts)
    local slot = self.slots[id]
    if not slot then
        -- the game can't remove a slot, so a removed one serves the next id
        slot = tremove(self.free)
        if not slot then
            slot = { refs = {}, branch = 1, display = self }
            slot.previewConfig = { fill = true, skin = self.SlotSkin(slot) }
        end
        slot.id = id
        self.slots[id] = slot
    end
    opts = opts or {}
    slot.trigger, slot.host, slot.shown = trigger, host or self.host, true
    slot.sortMethod, slot.sortDirection, slot.assistOnly = opts.sortMethod, opts.sortDirection, opts.assistOnly
    UpdateSlotPreview(self, slot)

    self.pending[slot] = true
    if not Ready(self) then return end

    -- adding a slot waits for combat to end, as the groups' rebind does
    Core:RunWhenSafe(self.applySlots)
end

---Switch a slot off; the game can't remove one, so it waits for SetSlot to use it again.
---@param id any
function DisplayMixin:RemoveSlot(id)
    local slot = self.slots[id]
    if not slot or not slot.shown then return end

    slot.shown = false
    AuraPreview:SetShown(slot, false)
    slot.previewing = nil
    if slot.index then
        self.container:SetSlotShown(slot.index, false)
    end
    self.slots[id] = nil
    self.free[#self.free + 1] = slot
end

---@param unit string
function DisplayMixin:SetUnit(unit)
    self.unit = unit
    if not Ready(self) then return end

    ApplyUnit(self)
end

---Re-read the unit gate and every aura, for a token that now points at someone else.
function DisplayMixin:Refresh()
    local container = self.container
    if not container then return end

    container:UpdateUnitGate()
    container:UpdateAllAuras()
end

---Run `style` over every button again, the preview's too, spread over frames.
---@param look any? Core:LookStamp of what the look reads; the same one again does nothing
function DisplayMixin:Restyle(look)
    if self.released then return end
    if look ~= nil and look == self.lookStamp then return end

    self.lookStamp = look

    if self.shape == 'group' then
        if not self.container then return end
        UpdatePreview(self)
    else
        for _, slot in pairs(self.slots) do
            UpdateSlotPreview(self, slot)
        end
    end
    QueueRestyle(self)
end

---The preview dummies' level, as SetLayout's: all a layer move changes. The host's own level
---stays the subscriber's.
---@param level number
function DisplayMixin:SetLevel(level)
    self.level = level
    -- attached again only: an update would reskin every dummy
    if self.shape == 'group' then
        if self.container then
            AttachPreview(self)
        end
        return
    end
    for _, slot in pairs(self.slots) do
        AttachSlotPreview(self, slot)
    end
end

---Dummy auras in place of the live ones: one slot's, every slot's when id is nil.
---@param shown boolean
---@param id any?
function DisplayMixin:SetPreview(shown, id)
    shown = shown == true
    if self.shape == 'group' then
        if self.previewing == shown then return end

        self.previewing = shown
        if self.container then
            ApplyPreview(self)
        end
        return
    end

    for slotId, slot in pairs(self.slots) do
        local on = shown and slot.shown and (id == nil or id == slotId)
        if (slot.previewing == true) ~= on and (id == nil or id == slotId) then
            slot.previewing = on or nil
            AuraPreview:SetShown(slot, on)
            if slot.index then
                self.container:SetSlotShown(slot.index, slot.shown and not on)
            end
        end
    end
end

---Hide and stop the container; it can't be destroyed, so it parks until a setter wakes it.
---Waking leaves the host hidden, showing it is the subscriber's.
function DisplayMixin:Release()
    self.released = true
    -- a queued restyle would touch buttons nobody shows
    self.restylePending = nil
    queue[self] = nil
    self.restyleList = nil
    self.lookStamp = nil
    self.host:Hide()

    -- the live container comes back with the display, not the dummies
    local previewing = self.previewing
    self.previewing = false
    if self.shape == 'slots' then
        self:SetPreview(false)
    end

    local container = self.container
    if not container then return end

    if previewing then
        ApplyPreview(self)
    end
    Core:RunWhenSafe(self.park)
end

---Auras on a native container: its host, the buttons it hands over and their previews.
---@param parent Frame
---@param opts AuraDisplayOptions
---@return AuraDisplay
function Core:NewAuraDisplay(parent, opts)
    local display = Mixin({
        host = CreateFrame('Frame', opts.name, parent),
        shape = opts.shape,
        style = opts.style,
        entries = {},
        slots = {},
        free = {},
        pending = {},
        count = 1,
        previewing = false,
    }, DisplayMixin)
    local entries, slots, pending, style = display.entries, display.slots, display.pending, display.style

    -- the only time the game hands a group's button over, so it is kept to restyle later
    display.initButton = function(button, branch)
        local entry = { refs = {}, branch = branch, display = display }
        Core:InitAuraButton(button, nil, entry.refs, display.config.width, display.config.height)
        entries[#entries + 1] = entry
        style(entry)
    end

    -- a preview stand-in takes the same look, built once and restyled after
    display.skin = function(button, branch)
        local entry = button.nuiAuraEntry
        if entry then
            entry.branch = branch -- a dummy can stand in for another trigger on the next pass
        else
            entry = { refs = {}, branch = branch, preview = true, display = display }
            Core:InitAuraButton(button, nil, entry.refs, display.config.width, display.config.height)
            button.nuiAuraEntry = entry
        end
        entry.enchant = nil -- and an enchant dummy for an aura, when the enchants go
        style(entry)
    end

    -- an enchant has no trigger, so a text naming one never shows on it
    display.initEnchant = function(button)
        local entry = { refs = {}, branch = 0, enchant = true, display = display }
        Core:InitAuraButton(button, nil, entry.refs, display.config.width, display.config.height)
        entries[#entries + 1] = entry
        style(entry)
    end

    -- the group's own config, read live, with dummies skinned as enchants
    display.enchantConfig = setmetatable({
        skin = function(button)
            local entry = button.nuiAuraEntry
            if not entry then
                entry = { refs = {}, preview = true, display = display }
                Core:InitAuraButton(button, nil, entry.refs, display.config.width, display.config.height)
                button.nuiAuraEntry = entry
            end
            entry.branch, entry.enchant = 0, true
            style(entry)
        end,
    }, { __index = function(_, key) return display.config[key] end })

    display.applyEnchants = function()
        if display.enchantsReady then
            for _, slot in ipairs(ENCHANT_SLOTS) do
                display.container:SetItemEnchantmentEnabled(slot, display.enchantsShown == true)
            end
            display.container:SetItemEnchantLayout(display.enchantLayout)
        elseif display.enchantsShown and not display.addingEnchants then
            -- the game reads them only when they're added, and at login not before the next frame
            display.addingEnchants = true
            RunNextFrame(display.addEnchants)
        end
    end

    display.addEnchants = function()
        if InCombatLockdown() then
            Core:RunWhenSafe(display.addEnchants)
            return
        end
        local container = display.container
        for _, slot in ipairs(ENCHANT_SLOTS) do
            container:AddItemEnchant(slot, { initializeFrame = display.initEnchant })
            container:SetItemEnchantmentEnabled(slot, display.enchantsShown == true)
        end
        container:SetItemEnchantLayout(display.enchantLayout)
        display.enchantsReady = true
    end

    ---@param slot AuraDisplaySlot
    ---@return fun(button: table, branch: number)
    display.SlotSkin = function(slot)
        return function(button)
            local entry = button.nuiAuraEntry
            if not entry then
                entry = { refs = {}, branch = 1, preview = true, display = display }
                Core:InitAuraButton(button, nil, entry.refs, display.config.width, display.config.height)
                button.nuiAuraEntry = entry
            end
            -- a reused slot stands in for another id
            entry.id, entry.host = slot.id, slot.host
            style(entry)
        end
    end

    display.runRestyle = function()
        display.restyleQueued = nil
        if display.restylePending then
            display.restylePending = nil
            QueueRestyle(display)
        end
    end

    -- one function per display, so building again in combat doesn't queue another
    display.build = function()
        if display.container or display.released then return end
        local config, trigger, host = display.config, display.trigger, display.host
        local group = display.shape == 'group'
        if not config or group and not trigger then return end

        local container = host:CreateAuraContainer(config)
        if not container then return end
        display.container = container

        if not group then
            display.applySlots()
            return
        end
        container:SetPoint(config.containerPoint, host, config.containerPoint)
        container:AddFilteredGroup(trigger, { initializeBranchFrame = display.initButton })
        display.applyEnchants()
        ApplyUnit(display)
        UpdatePreview(display)
        if display.previewing then
            ApplyPreview(display)
        end
    end

    display.applySlots = function()
        local reshown = false
        for slot in pairs(pending) do
            reshown = ApplySlot(display, slot) or reshown
        end
        wipe(pending)
        if reshown then
            QueueRestyle(display)
        end
        -- a spellID list new to this container has no verdict yet, so it would show unfiltered
        ApplyUnit(display)
    end

    display.park = function()
        local container = display.container
        container:SetEnabled(not display.released)
        -- a parked container mustn't keep redrawing on every target or gate event
        if display.released then
            container:StopUnitGate()
        else
            ApplyUnit(display)
        end
    end

    return display
end
