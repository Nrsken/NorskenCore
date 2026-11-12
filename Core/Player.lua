---@class NRSKNUI
local Core = select(2, ...)

local UnitClass = UnitClass
local UnitFullName = UnitFullName
local UnitGUID = UnitGUID
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local select = select

Core.MyClassLocale, Core.MyClass, Core.MyClassID = UnitClass('player')
Core.MyName, Core.MyRealm = UnitFullName('player')
Core.MyGUID = UnitGUID('player') --[[@as string]] -- the player always has one

Core.MySpec = {
    id = nil,
    role = nil,
    position = nil,
    talents = nil,
}

local function UpdateSpec()
    local spec = Core.MySpec
    ---@diagnostic disable-next-line: field-type-mismatch
    spec.id, spec.role, spec.position, spec.talents = Core.Libs.LS.MySpecialization()
end

-- Core enables first, so an addon's own OnEnable can read the spec
function Core.Ace:OnEnable()
    UpdateSpec()
    Core:CheckAddonVersions() -- every addon that needs Core has loaded by now
end

Core.Libs.LS.RegisterPlayerSpecChange(Core, UpdateSpec)

---The group's unit tokens: raid1..N in a raid, which include the player, party1..N-1 in a party, which don't.
---@return fun(): string? iterator
function Core:IterateGroupUnits()
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
function Core:IsClassInGroup(classFilenameToCheck)
    -- a raid's units include the player but a party's don't, so the player is checked first for both
    if Core.MyClass == classFilenameToCheck then return true end

    for unit in Core:IterateGroupUnits() do
        local classFilename = select(2, UnitClass(unit))
        ---@diagnostic disable-next-line: secret-comparison
        if classFilename == classFilenameToCheck then
            return true
        end
    end
    return false
end
