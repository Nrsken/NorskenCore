---@class NRSKNUI
local Private = select(2, ...)

local UnitClass = UnitClass
local UnitFullName = UnitFullName
local UnitGUID = UnitGUID
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local select = select

Private.MyClassLocale, Private.MyClass, Private.MyClassID = UnitClass('player')
Private.MyName, Private.MyRealm = UnitFullName('player')
Private.MyGUID = UnitGUID('player') --[[@as string]] -- the player always has one

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
    self:CheckAddonVersions() -- every addon that needs Core has loaded by now
end

Private.Libs.LS.RegisterPlayerSpecChange(Private, UpdateSpec)

---The group's unit tokens: raid1..N in a raid, which include the player, party1..N-1 in a party, which don't.
---@return fun(): string? iterator
function Private:IterateGroupUnits()
    local inRaid = IsInRaid()
    local prefix = inRaid and 'raid' or 'party'
    local count = inRaid and GetNumGroupMembers() or GetNumGroupMembers() - 1
    local index = 0
    return function()
        index = index + 1
        if index > count then return nil end

        return prefix .. index
    end
end

---Check if a specific class is present in the current group, the player included (solo too).
---@param classFilenameToCheck 'WARRIOR'|'HUNTER'|'ROGUE'|'MAGE'|'PRIEST'|'WARLOCK'|'DRUID'|'SHAMAN'|'PALADIN'|'DEATHKNIGHT'|'MONK'|'DEMONHUNTER'
---@return boolean
function Private:IsClassInGroup(classFilenameToCheck)
    -- a raid's units include the player but a party's don't, so the player is checked first for both
    if Private.MyClass == classFilenameToCheck then return true end

    for unit in Private:IterateGroupUnits() do
        local classFilename = select(2, UnitClass(unit))
        ---@diagnostic disable-next-line: secret-comparison
        if classFilename == classFilenameToCheck then
            return true
        end
    end
    return false
end
