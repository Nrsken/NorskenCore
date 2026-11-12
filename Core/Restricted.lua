---@class NRSKNUI
local Core = select(2, ...)
---@class RestrictedModule
local Restricted = Core.Ace:NewModule('Restricted', 'AceEvent-3.0')

local type = type
local pcall = pcall
local pairs = pairs
local ipairs = ipairs
local xpcall = xpcall
local wipe = wipe
local CreateFrame = CreateFrame
local geterrorhandler = geterrorhandler
local UnitIsDND = UnitIsDND
local UnitIsAFK = UnitIsAFK
local UnitExists = UnitExists
local issecretvalue = issecretvalue
local canaccessvalue = canaccessvalue
local InCombatLockdown = InCombatLockdown
local UnitAffectingCombat = UnitAffectingCombat
local UnitGroupRolesAssigned = UnitGroupRolesAssigned

local GetAddOnRestrictionState = C_RestrictedActions.GetAddOnRestrictionState
local GetSpellAuraSecrecy = C_Secrets.GetSpellAuraSecrecy
local ShouldAurasBeSecret = C_Secrets.ShouldAurasBeSecret
local ShouldCooldownsBeSecret = C_Secrets.ShouldCooldownsBeSecret

local NeverSecret = Enum.SecrecyLevel.NeverSecret
local RestrictionType = Enum.AddOnRestrictionType
local RestrictionState = Enum.AddOnRestrictionState
local RestrictionInactive = RestrictionState and RestrictionState.Inactive

function Restricted:OnInitialize()
    self.debug = false
    self:SetEnabledState(true)
end

-- Reverse map of the restriction type enum.
local typeName = {}
if RestrictionType then
    for name, i in pairs(RestrictionType) do
        typeName[i] = name
    end
end

-- Secrets --

---Value exists and is not a secret, i.e. safe to read/compare.
---@secret-guard value accessible
---@param value any
---@return boolean
function Core:IsSafeValue(value)
    if issecretvalue(value) then return false end
    return type(value) ~= 'nil'
end

---May the current (possibly tainted) context touch this frame? Forbidden or access-restricted ones (aura buttons while auras are secret) say no.
---@param object table
---@return boolean
function Core:CanAccessObject(object)
    local access = object:CanBeAccessedInContext()
    return not issecretvalue(access) and access == true
end

---Pre-flight, can this spell hand back secrets when queried as an aura?
---@param spellID number
---@return boolean
function Core:IsSpellAuraSecret(spellID)
    return GetSpellAuraSecrecy(spellID) ~= NeverSecret
end

---Do aura queries hand back secrets in the current context? A secret answer counts as yes.
---@return boolean
function Core:AreAurasSecret()
    local secret = ShouldAurasBeSecret()
    return issecretvalue(secret) or secret == true
end

---Do cooldown queries hand back secrets in the current context? A secret answer counts as yes.
---@return boolean
function Core:AreCooldownsSecret()
    local secret = ShouldCooldownsBeSecret()
    return issecretvalue(secret) or secret == true
end

---Safely get a value if it is not secret and can be accessed, otherwise return nil.
---@param value any
---@return any|nil
function Core:SafeValue(value)
    if canaccessvalue(value) then
        return value
    end
    return nil
end

---@param unit string
---@return boolean|nil
function Core:UnitIsAFK(unit)
    local isAFK = UnitIsAFK(unit)

    return not issecretvalue(isAFK) and isAFK or nil
end

---@param unit string
---@return boolean|nil
function Core:UnitIsDND(unit)
    local isDND = UnitIsDND(unit)

    return not issecretvalue(isDND) and isDND or nil
end

---@param unit string
---@return string|nil
function Core:GetSafeRole(unit)
    if not unit or not UnitExists(unit) then return nil end
    local role = UnitGroupRolesAssigned(unit)

    return not issecretvalue(role) and role or nil
end

-- Unit Token Validation --

-- Own frame, never a live handler, probing registers and unregisters UNIT_HEALTH on it.
local unitValidator = CreateFrame('Frame')
local validTokens = {}

---Is this a unit token the event system recognises?
---@param unit string?
---@return boolean
function Core:IsValidUnitToken(unit)
    if type(unit) ~= 'string' then return false end

    local cached = validTokens[unit]
    if cached ~= nil then return cached end

    local valid = false
    if pcall(unitValidator.RegisterUnitEvent, unitValidator, 'UNIT_HEALTH', unit) then
        local registered, registeredUnit = unitValidator:IsEventRegistered('UNIT_HEALTH')
        unitValidator:UnregisterEvent('UNIT_HEALTH')
        valid = registered and registeredUnit ~= nil
    end

    validTokens[unit] = valid
    return valid
end

-- Combat Queue --

local combatQueue = {}
local queuedFns = {}
-- Combat lockdown only, never the Combat restriction: a reload in combat may still do protected setup until
-- PLAYER_REGEN_DISABLED, which follows PLAYER_ENTERING_WORLD (warcraft.wiki.gg, AddOn loading process).
local lockdown = false

---Run fn now if out of combat lockdown, otherwise defer to PLAYER_REGEN_ENABLED.
---Used for any protected function call.
---@param fn function
function Core:RunWhenSafe(fn)
    if not fn then return end
    if lockdown or InCombatLockdown() then
        if queuedFns[fn] then return end -- the same function queued twice would only redo the same work
        queuedFns[fn] = true
        combatQueue[#combatQueue + 1] = fn
    else
        fn()
    end
end

-- Restriction State Tracking --

local active = {}
local restrictionState = 0
local pending = {}

---Check combat state, including the active.Combat flag which is set by PLAYER_REGEN_DISABLED/ENABLED events.
---@return boolean
function Core:InCombat()
    return active.Combat or InCombatLockdown()
end

---Whether any restriction is on. Read live: a handler for the same event can run before ours sets the flags.
---@return boolean
function Core:IsRestricted()
    for i, name in pairs(typeName) do
        -- Chat only limits addon messages, it's no restriction on what we show
        if name ~= 'Chat' and GetAddOnRestrictionState(i) ~= RestrictionInactive then return true end
    end
    return false
end

---Current restriction state (0 none, 1 partial, 2 full).
---@return integer
function Core:GetRestrictionState()
    return restrictionState
end

---Fully restricted i.e combat, encounter, M+, or PvP?
---@return boolean
function Core:IsFullyRestricted()
    return restrictionState == 2
end

---Defer fn until the restriction state is at or below targetState (0 none, 1 partial, 2 full).
---@param targetState integer
---@param fn function
function Core:DeferUntilUnrestricted(targetState, fn)
    if not fn then return end
    if restrictionState <= targetState then
        fn()
        return
    end
    pending[#pending + 1] = { target = targetState, fn = fn }
end

-- Recompute the overall state from the active type flags and flush eligible pending callbacks.
local function Recompute()
    local newState =
        (active.Combat or
            active.Encounter or
            active.ChallengeMode or
            active.PvPMatch) and 2
        or active.Map and 1
        or 0

    if newState == restrictionState then return end

    local old = restrictionState
    restrictionState = newState

    if newState < old then -- Restrictions released, run anything now eligible.
        local run, keep = {}, {}
        for _, e in ipairs(pending) do
            if e.target >= newState then
                run[#run + 1] = e.fn
            else
                keep[#keep + 1] = e
            end
        end
        pending = keep -- Swap first so callbacks may re-queue safely.
        -- One erroring callback must not abandon the rest of the queue.
        for i = 1, #run do xpcall(run[i], geterrorhandler()) end
    end
end

-- Lifecycle --

function Restricted:PLAYER_REGEN_DISABLED()
    lockdown = true
    active.Combat = true
    Recompute()
end

function Restricted:PLAYER_REGEN_ENABLED()
    lockdown = false
    active.Combat = false
    Recompute()

    -- Flush protected work queued during combat.
    if #combatQueue > 0 then
        local snapshot = combatQueue
        combatQueue = {}
        wipe(queuedFns)
        -- One erroring callback must not strand the protected work queued behind it.
        for i = 1, #snapshot do
            xpcall(snapshot[i], geterrorhandler())
        end
    end
end

function Restricted:ADDON_RESTRICTION_STATE_CHANGED(_, restrictionType, state)
    -- Activating(1) and Active(2) both count as 'on', only Inactive(0) is off.
    active[typeName[restrictionType]] = state ~= RestrictionInactive
    Recompute()
end

function Restricted:OnActionViolation(event, source, funcName)
    print(('|cffff0000Protected violation:|r %s (%s, %s)'):format(funcName or '?', event, source or '?'))
end

function Restricted:OnEnable()
    -- Seed from the live state so an Encounter/M+/PvP already active on /reload is caught.
    for i, name in pairs(typeName) do
        active[name] = GetAddOnRestrictionState(i) ~= RestrictionInactive
    end

    active.Combat = active.Combat or InCombatLockdown() or UnitAffectingCombat('Player')
    lockdown = InCombatLockdown()
    Recompute()

    self:RegisterEvent('ADDON_RESTRICTION_STATE_CHANGED')
    self:RegisterEvent('PLAYER_REGEN_DISABLED')
    self:RegisterEvent('PLAYER_REGEN_ENABLED')

    if self.debug then
        self:RegisterEvent('ADDON_ACTION_BLOCKED', 'OnActionViolation')
        self:RegisterEvent('ADDON_ACTION_FORBIDDEN', 'OnActionViolation')
    end
end
