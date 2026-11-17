---@class NorskenCore
local Core = select(2, ...)

Core.Enum = {}

---@enum NorskenCore.DispelType
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

---@enum NorskenCore.Apply
local Apply = {
    All = 0,
    Position = 1,   -- where it sits: anchor, offsets, strata
    Layout = 2,     -- size, spacing, growth, counts
    Look = 3,       -- textures, borders, backdrops
    Text = 4,       -- fonts, sizes, outlines, text formats
    Color = 5,      -- colours only, no texture or size changes
    Visibility = 6, -- what shows and when
}
Core.Enum.Apply = Apply
