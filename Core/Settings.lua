---@class NRSKNUI
local Private = select(2, ...)

local LibStub = LibStub
local CopyTable = CopyTable
local ipairs, next, pairs, type = ipairs, next, pairs, type

-- What every Norsken addon shares: one account wide copy that any of them can edit.

local defaults = {
    global = {
        Language = 'auto', -- 'auto' follows the client, otherwise a locale from LANGUAGES
        -- Shared color palette, built into NRSKNUI.Colors by NRSKNUI:LoadCustomColors().
        -- Mainly consumed by UnitFrames.
        Colors = {
            -- Original power colors from blizzard's PowerBarColor table.
            Power = {
                [0] = { 0, 0, 1 },                 -- Mana
                [1] = { 1, 0, 0 },                 -- Rage
                [2] = { 1, 0.5, 0.25 },            -- Focus
                [3] = { 1, 1, 0 },                 -- Energy
                [6] = { 0, 0.82, 1 },              -- Runic Power
                [8] = { 0.3, 0.52, 0.9 },          -- Lunar / Astral Power
                [11] = { 0, 0.5, 1 },              -- Maelstrom
                [13] = { 0.4, 0, 0.8 },            -- Insanity
                [17] = { 0.788, 0.259, 0.992 },    -- Fury
                [18] = { 1, 0.61176470588235, 0 }, -- Pain
                [4] = { 1, 0.96, 0.41 },           -- Combo Points
                [5] = { 0.5, 0.5, 0.5 },           -- Runes
                [7] = { 0.5, 0.32, 0.55 },         -- Soul Shards
                [9] = { 0.95, 0.9, 0.6 },          -- Holy Power
                [12] = { 0.71, 1, 0.92 },          -- Chi
                [16] = { 0.1, 0.1, 0.98 },         -- Arcane Charges
                [19] = { 0.392, 0.678, 0.808 },    -- Essence (oUF's, Blizzard has none)
            },
            -- oUF's rune colors per Death Knight spec: Blood, Frost, Unholy.
            Runes = {
                [1] = { 0.969, 0.255, 0.224 },
                [2] = { 0.580, 0.796, 0.969 },
                [3] = { 0.678, 0.922, 0.259 },
            },
            -- Blizzard's PowerBarColor.STAGGER: light, moderate, heavy.
            Stagger = {
                [1] = { 0.52, 1, 0.52 },
                [2] = { 1, 0.98, 0.72 },
                [3] = { 1, 0.42, 0.42 },
            },
            -- Original reaction colors from blizzard's FACTION_BAR_COLORS table.
            Reaction = {
                [1] = { 0.80000007152557, 0.30196079611778, 0.21960785984993 }, -- Hated
                [2] = { 0.80000007152557, 0.30196079611778, 0.21960785984993 }, -- Hostile
                [3] = { 0.74901962280273, 0.27058824896812, 0 },                -- Unfriendly
                [4] = { 0.90196084976196, 0.70196080207825, 0 },                -- Neutral
                [5] = { 0, 0.60000002384186, 0.10196079313755 },                -- Friendly
                [6] = { 0, 0.60000002384186, 0.10196079313755 },                -- Honored
                [7] = { 0, 0.60000002384186, 0.10196079313755 },                -- Revered
                [8] = { 0, 0.60000002384186, 0.10196079313755 },                -- Exalted
            },
            -- Original class colors from blizzard.
            Class = {
                DEATHKNIGHT = { 0.76862752437592, 0.11764706671238, 0.22745099663734 },
                DEMONHUNTER = { 0.63921570777893, 0.18823531270027, 0.78823536634445 },
                DRUID = { 1, 0.48627454042435, 0.039215687662363 },
                EVOKER = { 0.20000001788139, 0.57647061347961, 0.49803924560547 },
                HUNTER = { 0.66666668653488, 0.82745105028152, 0.44705885648727 },
                MAGE = { 0.24705883860588, 0.78039222955704, 0.9215686917305 },
                MONK = { 0, 1, 0.59607845544815 },
                PALADIN = { 0.95686280727386, 0.54901963472366, 0.7294117808342 },
                PRIEST = { 1, 1, 1 },
                ROGUE = { 1, 0.95686280727386, 0.4078431725502 },
                SHAMAN = { 0, 0.43921571969986, 0.8666667342186 },
                WARLOCK = { 0.52941179275513, 0.53333336114883, 0.93333339691162 },
                WARRIOR = { 0.77647066116333, 0.60784316062927, 0.42745101451874 },
            },
            -- Custom status colors for various unit states
            Status = {
                Tapped = { 0.6, 0.6, 0.6, 1 },
                Disconnected = { 0.5, 0.5, 0.5, 1 },
                Dead = { 0.35, 0, 0.05, 1 },
            },
            -- Custom dispel colors
            Dispel = {
                None = { 0.80000007152557, 0, 0, 0 },
                Magic = { 0, 0.50588238239288, 1, 1 },
                Curse = { 0.6235294342041, 0.023529414087534, 0.89411771297455, 1 },
                Disease = { 0.94509810209274, 0.41568630933762, 0.035294119268656, 1 },
                Poison = { 0.48235297203064, 0.78039222955704, 0, 1 },
                Bleed = { 0.72156864404678, 0, 0.05882353335619, 1 },
                Enrage = { 0.95294117927551, 0.37254902720451, 0.95686280727386, 1 },
            },
        },
        globalMedia = {
            Enabled = true,
            profileFont = { Enabled = true, FontFace = "Expressway", },
            profileBar = { statusBar = "NorskenUI" },
            profileSpark = { sparkTexture = "Solid", Scale = 1, Width = 2, color = { 1, 1, 1, 1 } },
            profileBorder = { BorderColor = { 0, 0, 0, 1 }, BackdropColor = { 0, 0, 0, 0.8 } },
            -- Addons global formatter defaults.
            durationBreakpointColors = true,
            durationCurveColors = false,
            durationSingleColor = false,
            profileBreakPoints = {
                pointOne = { threshold = 0, step = 0.1, format = '%0.1f', },
                pointTwo = { threshold = 1, step = 1, format = '%d', },
                pointThree = { threshold = 60, format = '%d:%02d', },
                pointFour = { threshold = 600, format = '%dm', },
                pointFive = { threshold = 3600, format = '%dh', },
                pointSix = { threshold = 86400, format = '%dd', },
            },
            profileColorCurve = {
                colorOne = { 1, 0.25, 0.25, 1 },
                colorTwo = { 1.00, 0.25, 0.25, 1 },
                colorThree = { 1.00, 0.75, 0.20, 1 },
                colorFour = { 1.00, 0.95, 0.70, 1 },
                colorFive = { 1.00, 0.95, 0.70, 1 },
                colorSix = { 1.00, 0.95, 0.70, 1 },
            },
            profileColorBreakPoint = {
                colorOne = { 1, 0.25, 0.25, 1 },
                colorTwo = { 1, 1, 1, 1 },
                colorThree = { 1, 1, 1, 1 },
                colorFour = { 1, 1, 1, 1 },
                colorFive = { 1, 1, 1, 1 },
                colorSix = { 1, 1, 1, 1 },
            },
            durationSingleColorValue = { 1, 1, 1, 1 },
        },
    },
}

local hadSavedValues

function Private:OnInitialize()
    -- read before AceDB fills in the defaults: an addon's own settings only count on a fresh store
    local saved = _G.NorskenCoreDB
    hadSavedValues = saved ~= nil and saved.global ~= nil and next(saved.global) ~= nil
    self.sharedDB = LibStub('AceDB-3.0'):New('NorskenCoreDB', defaults, true)
    self:RefreshCurves()
end

---@return NRSKNUI.SharedSettings shared
function Private:GetSharedSettings()
    return Private.sharedDB.global
end

---@return table defaults what GetSharedSettings starts from
function Private:GetSharedDefaults()
    return defaults.global
end

-- a namespace of the skinning addon lives under globalMedia in old saves and isn't shared
local NOT_SHARED = 'blizzardFonts'

local function Merge(into, from)
    for key, value in pairs(from) do
        -- pasted strings land here and these settings reach every addon, so a value can't change type
        if key ~= NOT_SHARED and (into[key] == nil or type(into[key]) == type(value)) then
            if type(value) ~= 'table' then
                into[key] = value
            elseif type(into[key]) == 'table' then
                Merge(into[key], value)
            else
                into[key] = CopyTable(value)
            end
        end
    end
end

---In place, open pages hold these tables.
local function Restore(into, from)
    for key, value in pairs(into) do
        if from[key] == nil then
            into[key] = nil
        elseif type(value) == 'table' and type(from[key]) == 'table' then
            Restore(value, from[key])
        end
    end
    Merge(into, from)
end

local function Same(one, other)
    if type(one) ~= 'table' or type(other) ~= 'table' then return one == other end

    for key, value in pairs(one) do
        if key ~= NOT_SHARED and not Same(value, other[key]) then return false end
    end
    for key in pairs(other) do
        if key ~= NOT_SHARED and one[key] == nil then return false end
    end
    return true
end

---Works on anything with these settings at the top: an old profile, or a block from an export string.
---@param data table
---@return boolean
function Private:HoldsSharedSettings(data)
    if type(data.Colors) == 'table' then return true end

    local media = data.globalMedia
    if type(media) ~= 'table' then return false end

    for key in pairs(media) do
        if key ~= NOT_SHARED then return true end
    end
    return false
end

---Which profile an account's shared settings come from. An alt on an untouched profile mustn't decide
---for everyone, so past the active one it's the customised profile most characters use.
---@param profiles table<string, table>
---@param active string
---@param profileKeys table<string, string>? character to profile name
---@return table? profile nil when no profile was ever customised
function Private:ChooseSharedSource(profiles, active, profileKeys)
    if profiles[active] and Private:HoldsSharedSettings(profiles[active]) then
        return profiles[active]
    end

    local users = {}
    for _, name in pairs(profileKeys or {}) do
        users[name] = (users[name] or 0) + 1
    end

    local best
    for name, profile in pairs(profiles) do
        if Private:HoldsSharedSettings(profile) then
            local count, top = users[name] or 0, users[best] or 0
            if not best or count > top or (count == top and name < best) then
                best = name
            end
        end
    end
    return best and profiles[best] or nil
end

---Takes one addon's own copy of the shared settings, once per account. It reads them and leaves the
---originals where they are, so the old values stay as a way back.
---@param globalMedia table?
---@param colors table?
---@param language string?
---@return boolean adopted whether this call copied anything over
function Private:AdoptSharedSettings(globalMedia, colors, language)
    local shared = Private:GetSharedSettings()
    if shared.Adopted then return false end

    shared.Adopted = true
    if hadSavedValues then return false end

    if globalMedia then
        Merge(shared.globalMedia, globalMedia)
    end
    if colors then
        Merge(shared.Colors, colors)
    end
    if language then
        shared.Language = language
    end
    return true
end

---@param profiles table<string, table>
---@param source table the profile the settings were copied from
---@return boolean differ
function Private:SharedSettingsDiffer(profiles, source)
    for _, profile in pairs(profiles) do
        if not Same(profile.globalMedia or {}, source.globalMedia or {})
            or not Same(profile.Colors or {}, source.Colors or {}) then
            return true
        end
    end
    return false
end

---Takes on the look an export string carries. Old strings only hold what differed from the defaults,
---so everything goes back to the defaults first or the result would be half theirs and half ours.
---@param block table
function Private:ApplySharedSettings(block)
    local shared = Private:GetSharedSettings()
    for _, section in ipairs({ 'globalMedia', 'Colors' }) do
        Restore(shared[section], defaults.global[section])
        if type(block[section]) == 'table' then
            Merge(shared[section], block[section])
        end
    end
end
