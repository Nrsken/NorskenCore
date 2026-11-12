---@class NRSKNUI
local Core = select(2, ...)
---@class AuraFilters
local AuraFilters = {}
Core.AuraFilters = AuraFilters

local tinsert = table.insert
local ipairs, pairs = ipairs, pairs
local CopyTable = CopyTable
local unpack = unpack
local type = type
local next = next

local AuraUtil = AuraUtil
local Filters = AuraUtil.AuraFilters
local NEG = AuraUtil.AuraFilterNegationPrefix

-- These two ignore negation, so we never emit '!' for them.
local NON_NEGATABLE = {
    [Filters.IncludeNameplateOnly] = true,
    [Filters.Maw] = true,
}

-- Boolean candidate fields that can be true, false or nil.
AuraFilters.BoolCandidateFields = {
    'isBossAura',
    'isBossOrRoleAura',
    'isRoleAura',
    'isPriorityAura',
    'isStealable',
    'isFromPlayerOrPlayerPet',
    'canApplyAura',
    'nameplateShowAll',
    'nameplateShowPersonal',
}

-- Table candidate fields that can be a table or nil. The spell ID fields are handled on their own.
AuraFilters.TableCandidateFields = {
    'includeDispelTypes',
    'excludeDispelTypes',
}

-- BL Debuffs that are never secret.
AuraFilters.BloodlustDebuffs = {
    [160455] = true, -- Hunter Pet Fatigued
    [264689] = true, -- Hunter Pet Fatigued
    [390435] = true, -- Exhaustion
    [57723] = true,  -- Exhaustion
    [57724] = true,  -- Sated
    [80354] = true,  -- Temporal Displacement
    [95809] = true,  -- Hunter Pet Insanity
}

-- Miscellaneous debuffs that are never secret.
AuraFilters.Misc = {
    [26013] = true,  -- Deserter
    [71041] = true,  -- Dungeon Deserter
}

local SPELLID_CANDIDATE_FIELDS = {
    'includeSpellIDs',
    'excludeSpellIDs',
}

local BOOL_CANDIDATE_FIELDS = AuraFilters.BoolCandidateFields
local TABLE_CANDIDATE_FIELDS = AuraFilters.TableCandidateFields

---Assemble the parse filter string from a branch's base type + triple state tokens.
---The base is the trigger's, so a branch only carries its own type when a preset gave it one.
---@param branch table
---@param baseType string?
---@return string
local function BuildFilterString(branch, baseType)
    local parts = { branch.type or baseType or Filters.Harmful }

    if branch.tokens then
        for token, state in pairs(branch.tokens) do
            if state == true then
                tinsert(parts, token)
            elseif state == false and not NON_NEGATABLE[token] then
                tinsert(parts, NEG .. token)
            end
        end
    end

    local filterString = AuraUtil.CreateFilterString(unpack(parts))
    if not AuraUtil.IsValidFilterString(filterString) then -- Make sure we always return a valid filter string.
        return branch.type or baseType or Filters.Harmful
    end
    return filterString
end

---The preset's shipped spells, plus Added, minus Removed.
---@param shipped table { list, field, Added?, Removed? }
---@return table map
local function ShippedSpells(shipped)
    local map = {}
    for id in pairs(Core.AuraFiltersPremade:GetShippedSpells(shipped.list) or {}) do map[id] = true end
    for id in pairs(shipped.Added or {}) do map[id] = true end
    for id in pairs(shipped.Removed or {}) do map[id] = nil end
    return map
end

---Build the candidateFilters table from a branch's candidate fields. Returns nil when none are defined.
---@param branch table
---@return table?
local function BuildCandidateFilters(branch)
    local shipped = branch.shipped
    if not branch.candidates and not shipped then return nil end
    local specCandidates = branch.candidates or {}

    local cFilter

    -- Copy the boolean candidate fields from the spec into a new table, ignoring nils.
    for _, field in ipairs(BOOL_CANDIDATE_FIELDS) do
        local value = specCandidates[field]
        if value == true then
            cFilter = cFilter or {}
            cFilter[field] = true
        elseif value == false then
            cFilter = cFilter or {}
            cFilter[field] = false
        end
    end

    -- Copy the table candidate fields from the spec into a new table, ignoring nils.
    for _, field in ipairs(TABLE_CANDIDATE_FIELDS) do
        local map = specCandidates[field]
        if type(map) == 'table' and next(map) ~= nil then
            cFilter = cFilter or {}
            cFilter[field] = CopyTable(map) -- copy so the native side never mutates the stored trigger
        end
    end

    -- Spell lists store their group as the value, the client gets plain true.
    for _, field in ipairs(SPELLID_CANDIDATE_FIELDS) do
        local map = specCandidates[field]
        if shipped and shipped.field == field then map = ShippedSpells(shipped) end
        if type(map) == 'table' then
            local ids = {}
            for id, value in pairs(map) do
                if value then ids[id] = true end
            end
            if next(ids) ~= nil then
                cFilter = cFilter or {}
                cFilter[field] = ids
            elseif field == 'includeSpellIDs' then
                -- An empty "only these" list would be no filter at all to the client, so it matches nothing instead.
                cFilter = cFilter or {}
                cFilter[field] = { [0] = true }
            end
        end
    end

    if type(specCandidates.maxDuration) == 'number' and specCandidates.maxDuration > 0 then
        cFilter = cFilter or {}
        cFilter.maxDuration = specCandidates.maxDuration
    end

    -- Matching on AuraUtil.ProcessAura's classification. This only works while the container runs
    -- the ProcessAura policy, container:AddFilteredGroup turns it on when it sees this field.
    local processedAuraType = specCandidates.processedAuraType
    if type(processedAuraType) == 'number' and processedAuraType ~= AuraUtil.AuraUpdateChangedType.None then
        cFilter = cFilter or {}
        cFilter.processedAuraType = processedAuraType
    end

    return cFilter
end

---Compile a stored branch list into the groups a container adds, one per branch.
---@param branches table[]? stored branches, each { type?, tokens?, candidates? }
---@param baseType string? the trigger's HELPFUL/HARMFUL, used by every branch that carries no type of its own
---@return table[] compiled { filterString: string, candidateFilters: table?, type: string }
function AuraFilters:Compile(branches, baseType)
    local compiled = {}

    for index, branch in ipairs(branches or {}) do
        compiled[index] = {
            filterString = BuildFilterString(branch, baseType),
            candidateFilters = BuildCandidateFilters(branch),
            -- The base type on its own, which the filter string no longer separates out. Only the
            -- summary reads it, to say which way round a spellID restriction bites.
            type = branch.type or baseType or Filters.Harmful,
        }
    end

    if not compiled[1] then
        compiled[1] = { filterString = baseType or Filters.Harmful, type = baseType or Filters.Harmful }
    end

    return compiled
end

---Does this branch decide what to show from a spellID include list?
---@param candidates table? compiled candidateFilters
---@return boolean
function AuraFilters:HasSpellIDCandidates(candidates)
    if not candidates then return false end

    for _ in pairs(candidates.includeSpellIDs or {}) do return true end
    return false
end

