---@class NRSKNUI
local Private = select(2, ...)

local UnitClass = UnitClass
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local select = select

Private.MyClassLocale, Private.MyClass, Private.MyClassID = UnitClass('player')

Private.MySpec = {
    id = nil,
    role = nil,
    position = nil,
    talents = nil,
}

local function UpdateSpec()
    local spec = Private.MySpec
    ---@diagnostic disable-next-line: field-type-mismatch
    spec.id, spec.role, spec.position, spec.talents = Private.Libs.LS.MySpecialization()
end

-- Core enables first, so an addon's own OnEnable can read the spec
function Private:OnEnable()
    UpdateSpec()
end

Private.Libs.LS.RegisterPlayerSpecChange(Private, UpdateSpec)

---Check if a specific class is present in the current group, the player included (solo too).
---@param classFilenameToCheck 'WARRIOR'|'HUNTER'|'ROGUE'|'MAGE'|'PRIEST'|'WARLOCK'|'DRUID'|'SHAMAN'|'PALADIN'|'DEATHKNIGHT'|'MONK'|'DEMONHUNTER'
---@return boolean
function Private:IsClassInGroup(classFilenameToCheck)
    -- a raid's units include the player but a party's don't, so the player is checked first for both
    if Private.MyClass == classFilenameToCheck then return true end

    local numMembers = GetNumGroupMembers()
    local prefix = (IsInRaid() and 'raid') or 'party'
    local maxCheck = (IsInRaid() and numMembers) or (numMembers - 1)
    for i = 1, maxCheck do
        local unit = prefix .. i
        local classFilename = select(2, UnitClass(unit))
        ---@diagnostic disable-next-line: secret-comparison
        if classFilename == classFilenameToCheck then
            return true
        end
    end
    return false
end
