---@class NRSKNUI
local Core = select(2, ...)

Core.Enum = {}

---@enum NRSKNUI.DispelType
local DispelType = {
    -- Source: https://wago.tools/db2/SpellDispelType
    None = 0,
    Magic = 1,
    Curse = 2,
    Disease = 3,
    Poison = 4,
    Enrage = 9,
    Bleed = 11,
}
Core.Enum.DispelType = DispelType
