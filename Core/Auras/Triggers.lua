---@class NorskenCore
local Core = select(2, ...)
---@class AuraTriggers
local AuraTriggers = {}
Core.AuraTriggers = AuraTriggers
local L = Core.L

local CopyTable = CopyTable
local pairs = pairs
local ipairs = ipairs
local type = type
local next = next

local AF = AuraUtil.AuraFilters

--[[

What an aura display matches, owned inline by whatever display owns it. There is no registry: a
trigger is edited on the display's own Trigger tab and read straight back by it.

    Trigger = {
        Type = 'Preset' | 'AuraFilter',
        Unit = 'player' | 'target',      -- standalone displays only, unit frames use their own unit
        Base = 'HELPFUL' | 'HARMFUL',    -- applies to every branch, meaningless for Preset

        Preset   = 'preset:defensives',                   -- Type == Preset
        Added    = { [spellID] = 'GROUP' },               -- Type == Preset, spells added to its list
        Removed  = { [spellID] = true },                  -- Type == Preset, shipped spells switched off
        branches = { { tokens =, candidates =, shipped = }, ... },   -- Type == AuraFilter
    }

A branch's `shipped` links a spell condition to a preset's list, so it keeps getting list updates.
Old 'SpellIDs'/'Preset' saves still compile; the trigger editor converts them to AuraFilter on open.

Every type compiles to the same branch list through AuraFilters:Compile, so a container never learns
which type produced it.

API: Core:GetTriggerBranches(trigger)

--]]

AuraTriggers.Types = {
    SpellIDs = 'SpellIDs',
    Preset = 'Preset',
    AuraFilter = 'AuraFilter',
}

local Types = AuraTriggers.Types

Core:OnLanguageSet(function()
    AuraTriggers.UnitOptions = {
        { value = 'player', text = L['Player'] },
        { value = 'target', text = L['Target'] },
    }
end)

local Defaults = {
    Type = Types.AuraFilter,
    Unit = 'player',
    Base = AF.Harmful,
    Preset = '',
    branches = { {} },
}

---A fresh trigger, for a new display or a display that has none yet.
---@param overrides table? merged over the defaults
---@return table trigger
function AuraTriggers:New(overrides)
    local trigger = CopyTable(Defaults)

    for key, value in pairs(overrides or {}) do
        trigger[key] = value
    end

    return trigger
end

---A branch matching all the base type allows, so an empty AuraFilter trigger resolves.
---@param trigger table
---@return table[]
local function BareBranch(trigger)
    return { { type = trigger.Base or AF.Harmful } }
end

--[[

API: Core:GetTriggerBranches(trigger)

Compile a trigger into the { filterString, candidateFilters } branches an aura container consumes,
one aura group per branch. Always at least one, so a binding never ends up with no groups.

* trigger - an inline trigger table (may be nil, which compiles to a bare HARMFUL)

--]]
---@param trigger table?
---@return table[] branches
function Core:GetTriggerBranches(trigger)
    local Filters = Core.AuraFilters

    -- a bare filter string is a one-branch trigger; PlayerAuras and its previews pass one
    if type(trigger) == 'string' then
        if not AuraUtil.IsValidFilterString(trigger) then
            return Filters:Compile(nil, AF.Harmful)
        end
        return Filters:Compile({ { type = trigger } }, nil)
    end

    if type(trigger) ~= 'table' then
        return Filters:Compile(nil, AF.Harmful)
    end

    if trigger.Type == Types.Preset then
        -- A preset ships its own per-branch types, so it needs no base of its own.
        local branches = AuraTriggers:GetPresetBranches(trigger)
        if not branches then
            return Filters:Compile(nil, AF.Harmful)
        end

        return Filters:Compile(branches, nil)
    end

    if trigger.Type == Types.SpellIDs then
        local map = trigger.SpellIDs
        -- a spell list says which aura, never whose: that's the PLAYER token, as a SpellIDs
        -- trigger has no branch of its own to put one on
        local tokens = trigger.OnlyMine and { [AF.Player] = true } or nil

        if type(map) ~= 'table' or next(map) == nil then
            -- An empty list is no filter at all to the client, so it would show everything the base
            -- matches. Nothing selected means nothing shown instead.
            return Filters:Compile({ { tokens = tokens, candidates = { includeSpellIDs = { [0] = true } } } }, trigger.Base)
        end

        return Filters:Compile({ { tokens = tokens, candidates = { includeSpellIDs = map } } }, trigger.Base)
    end

    local branches = trigger.branches
    if type(branches) ~= 'table' or not branches[1] then
        branches = BareBranch(trigger)
    end

    return Filters:Compile(branches, trigger.Base)
end

---How many branches GetTriggerBranches makes, without the new tables a compile makes.
---@param trigger (table|string)?
---@return number
function Core:CountTriggerBranches(trigger)
    local branches = type(trigger) == 'table' and trigger.branches
    if type(trigger) == 'table' and trigger.Type == Types.Preset then
        -- an edited preset only adds and removes spells, never branches
        local preset = Core.AuraFiltersPremade:Get(trigger.Preset)
        branches = preset and preset.branches
    end
    -- a spell list, a bare filter string or no branches at all compile to one
    if type(trigger) ~= 'table' or trigger.Type == Types.SpellIDs or type(branches) ~= 'table' or not branches[1] then
        return 1
    end

    -- up to the first gap, as Compile walks them
    local count = 0
    for _ in ipairs(branches) do
        count = count + 1
    end
    return count
end

---A preset's branches with the trigger's added and switched-off spells applied.
---@param trigger table
---@return table[]? branches nil for an unknown preset
function AuraTriggers:GetPresetBranches(trigger)
    local preset = Core.AuraFiltersPremade:Get(trigger.Preset)
    if not preset then return nil end
    if not (preset.spells and (trigger.Added or trigger.Removed)) then
        return preset.branches
    end

    local branches = CopyTable(preset.branches)
    local map = branches[1].candidates[preset.spellField]
    for id, group in pairs(trigger.Added or {}) do
        map[id] = group
    end
    for id in pairs(trigger.Removed or {}) do
        map[id] = nil
    end

    return branches
end

---Rewrite an old Spell IDs trigger as the one Aura Filter branch it always compiled to.
---@param trigger table
function AuraTriggers:ConvertSpellIDs(trigger)
    if trigger.Type ~= Types.SpellIDs then return end

    local ids = {}
    for id in pairs(trigger.SpellIDs or {}) do
        ids[id] = 'OTHER'
    end

    trigger.branches = {
        { tokens = trigger.OnlyMine and { [AF.Player] = true } or nil, candidates = { includeSpellIDs = ids } },
    }
    trigger.Type = Types.AuraFilter
    trigger.SpellIDs, trigger.OnlyMine = nil, nil
end

---Type and branches are written out so the AceDB Preset default can't revert it on load.
---@param trigger table
function AuraTriggers:ConvertPreset(trigger)
    if trigger.Type ~= Types.Preset then return end

    local converted = self:ToAuraFilter(trigger)
    trigger.Type, trigger.Base, trigger.branches = converted.Type, converted.Base, converted.branches
    trigger.Preset, trigger.Added, trigger.Removed = nil, nil, nil
end

---@param trigger table
---@param presetKey string
function AuraTriggers:LoadPreset(trigger, presetKey)
    local loaded = self:ToAuraFilter({ Type = Types.Preset, Preset = presetKey, Unit = trigger.Unit })
    trigger.Type, trigger.Base, trigger.branches = loaded.Type, loaded.Base, loaded.branches
end

---An editable preset's spell list stays linked to the shipped one rather than copied.
---@param trigger table
---@return table trigger
function AuraTriggers:ToAuraFilter(trigger)
    self:ConvertSpellIDs(trigger)

    local branches
    if trigger.Type == Types.Preset then
        local preset = Core.AuraFiltersPremade:Get(trigger.Preset)
        branches = CopyTable(preset and preset.branches or { {} })
        if preset and preset.spells then
            branches[1].candidates[preset.spellField] = nil
            branches[1].shipped = {
                list = preset.key,
                field = preset.spellField,
                Added = trigger.Added and CopyTable(trigger.Added),
                Removed = trigger.Removed and CopyTable(trigger.Removed),
            }
        end
    else
        branches = CopyTable(trigger.branches or { {} })
    end

    local base = branches[1].type or trigger.Base or AF.Harmful
    -- Presets carry a type per branch; the editor only has the trigger-wide one, so it moves up.
    for _, branch in ipairs(branches) do
        if branch.type == base then
            branch.type = nil
        end
    end

    return self:New({ Unit = trigger.Unit, Base = base, branches = branches })
end

---Every trigger's link to a shipped list, in trigger order.
---@param trigger table?
---@return table[] shipped
function AuraTriggers:GetShippedLists(trigger)
    local lists = {}
    for _, branch in ipairs(trigger and trigger.branches or {}) do
        if branch.shipped then
            lists[#lists + 1] = branch.shipped
        end
    end
    return lists
end

-- consumers told when any trigger changes; a broadcast, since one page can reach several
-- live displays (every unit frame sharing a unit config)
local callbacks = {}

---@param consumer table
---@param callback fun(consumer: table)
function AuraTriggers:RegisterCallback(consumer, callback)
    callbacks[consumer] = callback
end

---@param consumer table
function AuraTriggers:UnregisterCallback(consumer)
    callbacks[consumer] = nil
end

---Tell every consumer a trigger changed, so live displays rebind.
function AuraTriggers:Invalidate()
    for consumer, callback in pairs(callbacks) do
        callback(consumer)
    end
end
