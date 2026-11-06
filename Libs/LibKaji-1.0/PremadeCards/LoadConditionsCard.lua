--[[
# LoadConditionsCard

* Premade card for a module's load conditions: General, then Player and Location with a collapsible section per category.
* A section's header sums up what's picked, so everything set reads at a glance with them all closed.
* Zone takes a map ID list (g/c/i prefixes, - to leave one out); its tooltip lists this season's instances and where you stand.
* `specs = true` adds Spec (specIDs, every class) and Talent (a TalentTree for the one picked spec, picks stored per spec).
* General lists the states shared with the CDM Conditions trigger as tri-state ticks (gui.loadStates, from Core/LoadConditions.lua).
* `general(row)` adds one widget of the caller's to General, top right.
* A change repaints its widget and the summaries; only what changes the rows rebuilds the card (no full page refresh).

## Examples

    page:LoadConditionsCard({
        db = db.LoadConditions,
        onChangeCallback = Apply,
    })

--]]

local lib = LibStub and LibStub("LibKaji-1.0", true)
if not lib then return end

local L = lib.L
local SPEC_NAME_HEIGHT = 18
local SPEC_ROW_HEIGHT = 30
local SPEC_COLUMNS, SPEC_COLUMNS_WIDE = 3, 4
local SPEC_WIDE_AT = 560 -- content width four columns fit in without the blocks crowding
local SPEC_ICON_SIZE = 24
local SPEC_ICON_CELL = 30 -- a fixed step, so a wider window doesn't spread the icons apart
local SPEC_DIMMED_ALPHA = 0.7
local STATE_ROW_HEIGHT = 24

lib.premadeCards = lib.premadeCards or {}

local ipairs = ipairs
local pairs = pairs
local next = next
local tostring = tostring
local tonumber = tonumber
local unpack = unpack
local wipe = wipe
local sformat = string.format
local tconcat = table.concat
local C_Timer = C_Timer

-- open sections, kept across displays so going through them shows the same part of each
local openSections = {}

-- file names from Blizzard_CooldownBroadcaster/TrackedCooldowns.lua; raceIDs also cover NPC races, so the IDs are scanned for these
local PLAYABLE_RACES = {
    Human = true, Dwarf = true, NightElf = true, Gnome = true, Draenei = true, Worgen = true,
    Orc = true, Scourge = true, Tauren = true, Troll = true, BloodElf = true, Goblin = true,
    Pandaren = true, Dracthyr = true,
    VoidElf = true, LightforgedDraenei = true, DarkIronDwarf = true, KulTiran = true, Mechagnome = true,
    Nightborne = true, HighmountainTauren = true, MagharOrc = true, ZandalariTroll = true, Vulpera = true,
    EarthenDwarf = true, Harronir = true,
}
local MAX_RACE_ID = 150
local raceList ---@type { key: string, label: string }[]?

---Every playable race by name, each once.
---@return { key: string, label: string }[]
local function PlayableRaces()
    if raceList then
        return raceList
    end

    local list, seen = {}, {}
    for raceID = 1, MAX_RACE_ID do
        local info = C_CreatureInfo.GetRaceInfo(raceID)
        local key = info and info.clientFileString
        if key and PLAYABLE_RACES[key] and not seen[key] then
            seen[key] = true
            list[#list + 1] = { key = key, label = info.raceName }
        end
    end

    table.sort(list, function(a, b) return a.label < b.label end)
    raceList = list
    return list
end

---@param db table
---@return number? specID the only spec picked, which the Talent category needs
local function SingleSpec(db)
    local single
    for specID, enabled in pairs(db.Spec and db.Spec.Types or {}) do
        if enabled then
            if single then return nil end
            single = specID
        end
    end
    return single
end

-- Difficulty --

-- The game's own names, with where it's played on the ones that read the same for a dungeon and a raid.
local DIFFICULTIES = {
    { id = 1, place = "Dungeon" },
    { id = 2, place = "Dungeon" },
    { id = 23, place = "Dungeon" },
    { id = 8 },
    { id = 24, place = "Dungeon" },
    { id = 205 },
    { id = 208 },
    { id = 17 },
    { id = 220, place = "Raid" },
    { id = 14, place = "Raid" },
    { id = 15, place = "Raid" },
    { id = 16, place = "Raid" },
    { id = 33, place = "Raid" },
}

---@return { key: number, label: string }[]
local function DifficultyList()
    local list = {}
    for _, difficulty in ipairs(DIFFICULTIES) do
        local name = GetDifficultyInfo(difficulty.id)
        if name then
            list[#list + 1] = { key = difficulty.id, label = difficulty.place and sformat("%s (%s)", L[difficulty.place], name) or name }
        end
    end
    return list
end

-- Summaries --

---@param target table
---@param list { key: string, label: string }[]
---@return string?
local function PickedLabels(target, list)
    local picked = {}
    for _, entry in ipairs(list) do
        if target[entry.key] then
            picked[#picked + 1] = entry.label
        end
    end
    return #picked > 0 and tconcat(picked, ", ") or nil
end

---Names up to two specs, past that a count reads better than a line that runs out of room.
---@param db table
---@return string?
local function SpecSummary(db)
    local names, count = {}, 0
    for specID, enabled in pairs(db.Spec.Types) do
        if enabled then
            local _, name = GetSpecializationInfoByID(specID)
            count = count + 1
            names[#names + 1] = name
        end
    end

    if count > 2 then
        return sformat(L["%d picked"], count)
    end
    table.sort(names)
    return count > 0 and tconcat(names, ", ") or nil
end

---@param db table
---@return string?
local function TalentSummary(db)
    local spec = SingleSpec(db)
    local count = 0
    for _ in pairs(spec and db.Talent.Specs[spec] or {}) do
        count = count + 1
    end
    return count > 0 and sformat(L["%d picked"], count) or nil
end

---@param db table
---@return string?
local function ZoneSummary(db)
    local text = db.Zone.MapIDs
    return text and text:find("%d") and text or nil
end

---@param db table
---@return string?
local function RaceSummary(db)
    local picked = {}
    for _, race in ipairs(PlayableRaces()) do
        if db.Race.Types[race.key] then
            picked[#picked + 1] = race.label
        end
    end

    if #picked > 2 then
        return sformat(L["%d picked"], #picked)
    end
    return #picked > 0 and tconcat(picked, ", ") or nil
end

---@param db table
---@return string?
local function SpellsSummary(db)
    local known, notKnown = db.Spells.Known, db.Spells.NotKnown
    local parts = {}
    if known then
        parts[#parts + 1] = C_Spell.GetSpellName(known) or tostring(known)
    end
    if notKnown then
        parts[#parts + 1] = sformat(L["Not %s"], C_Spell.GetSpellName(notKnown) or tostring(notKnown))
    end
    return #parts > 0 and tconcat(parts, ", ") or nil
end

---Appends a plain map ID unless that exact entry is already there, a g486 or c486 is a different entry.
---@param text string
---@param mapID number
---@return string
local function AddMapID(text, mapID)
    local entry = tostring(mapID)
    for token in text:gmatch("[^,%s]+") do
        if token == entry then return text end
    end
    return text:find("%d") and (text .. ", " .. entry) or entry
end

-- Zone tooltip --

local seasonZones ---@type { title: string, zones: { name: string, id: string }[] }[]?

---A map group covers every floor of a dungeon, so it is the entry worth suggesting.
---@param mapID number
---@return string
local function ZoneEntry(mapID)
    local groupID = C_Map.GetMapGroupID(mapID)
    return groupID and ("g" .. groupID) or tostring(mapID)
end

---The current tier's dungeons and raids from the Encounter Journal, kept once both sections came back filled.
---@return { title: string, zones: { name: string, id: string }[] }[]
local function GetSeasonZones()
    if seasonZones then return seasonZones end
    local sections, complete = {}, true

    -- Selecting a tier is shared journal state, so the one the player had open is put back after.
    local previousTier = EJ_GetCurrentTier()
    EJ_SelectTier(EJ_GetNumTiers())
    for _, isRaid in ipairs({ false, true }) do
        local section = { title = isRaid and L["Current Season Raids"] or L["Current Season Dungeons"], zones = {} }
        local index = 1
        local instanceID = EJ_GetInstanceByIndex(index, isRaid)
        while instanceID do
            -- A dungeon reports map 0 until it is the selected instance, raids answer either way.
            EJ_SelectInstance(instanceID)
            local name, _, _, _, _, _, mapID = EJ_GetInstanceInfo(instanceID)
            if name and mapID and mapID ~= 0 then
                section.zones[#section.zones + 1] = { name = name, id = ZoneEntry(mapID) }
            end
            index = index + 1
            instanceID = EJ_GetInstanceByIndex(index, isRaid)
        end
        if #section.zones > 0 then
            sections[#sections + 1] = section
        else
            complete = false
        end
    end
    if previousTier then EJ_SelectTier(previousTier) end

    if complete then seasonZones = sections end
    return sections
end

---Built on every hover, so the current zone is always the one the player stands in.
---@param tooltip GameTooltip
---@param theme table
local function FillZoneTooltip(tooltip, theme)
    local accent, text, muted = theme.accent, theme.textPrimary, theme.textSecondary
    local function Header(title)
        tooltip:AddLine(" ")
        tooltip:AddLine(title, accent[1], accent[2], accent[3])
    end
    local function Entry(name, id)
        tooltip:AddDoubleLine(name, id, text[1], text[2], text[3], muted[1], muted[2], muted[3])
    end

    tooltip:SetText(L["Map IDs"], accent[1], accent[2], accent[3])

    for _, section in ipairs(GetSeasonZones()) do
        Header(section.title)
        for _, zone in ipairs(section.zones) do Entry(zone.name, zone.id) end
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    local mapInfo = mapID and C_Map.GetMapInfo(mapID)
    if mapID and mapInfo then
        Header(L["Current Zone"])
        Entry(mapInfo.name, tostring(mapID))
        local groupID = C_Map.GetMapGroupID(mapID)
        if groupID then
            Entry(L["All floors"], "g" .. groupID)
        end

        local parentInfo = mapInfo.parentMapID and mapInfo.parentMapID > 0 and C_Map.GetMapInfo(mapInfo.parentMapID)
        if parentInfo then
            Header(L["Parent Zone"])
            Entry(parentInfo.name, "c" .. mapInfo.parentMapID)
        end
    end

    local instanceName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceID and instanceID > 0 then
        Header(L["Current Instance"])
        Entry(instanceName, "i" .. instanceID)
    end

    Header(L["How To Write Them"])
    tooltip:AddLine(L["Separate entries with commas."], muted[1], muted[2], muted[3], true)
    local zoneSyntax = {
        { "2393", L["A map"] },
        { "g486", L["Every floor of a map group"] },
        { "c2395", L["A map and every map inside it"] },
        { "i2912", L["An instance"] },
        { "-2393", L["Leave a map out, works with any prefix"] },
    }
    for _, syntax in ipairs(zoneSyntax) do
        tooltip:AddDoubleLine(syntax[1], syntax[2], text[1], text[2], text[3], muted[1], muted[2], muted[3])
    end
end

---Every class with its specs by name, the player's class first.
---@return { name: string, color: string, mine: boolean, specs: { id: number, name: string, icon: number }[] }[]
local function ClassSpecs()
    local classes = {}
    local _, _, playerClassID = UnitClass("player")
    for classID = 1, GetNumClasses() do
        local info = C_CreatureInfo.GetClassInfo(classID)
        if info then
            local color = C_ClassColor.GetClassColor(info.classFile)
            local entry = { name = info.className, color = color and color:GenerateHexColor() or "ffffffff", mine = classID == playerClassID, specs = {} }
            for index = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) do
                local specID, name, _, icon = GetSpecializationInfoForClassID(classID, index)
                if specID then entry.specs[#entry.specs + 1] = { id = specID, name = name, icon = icon } end
            end
            classes[#classes + 1] = entry
        end
    end

    table.sort(classes, function(a, b)
        if a.mine ~= b.mine then
            return a.mine
        end
        return a.name < b.name
    end)
    return classes
end

lib.premadeCards.LoadConditionsCard = {
    title = "Load Conditions",

    ---@param card KajiGUIFluentCard
    ---@param config table
    ---@param gui KajiGUIInstance
    build = function(card, config, gui)
        local theme = gui.theme
        local db = config.db
        local onChange = config.onChangeCallback

        db.Instance = db.Instance or { Types = {} }
        db.Group = db.Group or { Types = {} }
        db.Role = db.Role or { Types = {} }
        db.Position = db.Position or { Types = {} }
        db.Zone = db.Zone or {}
        db.Race = db.Race or { Types = {} }
        db.Spells = db.Spells or {}
        db.Difficulty = db.Difficulty or { Types = {} }
        db.State = db.State or {}
        if config.specs then
            db.Spec = db.Spec or { Types = {} }
            db.Talent = db.Talent or { Specs = {} }
        end

        -- the setting that changed, so a caller editing several things writes only that; nil after a bulk change
        local function fireChange(path, value)
            if onChange then
                onChange(path, value)
            end
        end

        -- what each of the things edited together has at a path, when they disagree (config.mixed)
        local function Mixed(path)
            return config.mixed and config.mixed(path) or nil
        end

        -- Rebuild hides the row that owns the clicked widget, so it waits a frame; the guard on the card stops a doubled rebuild.
        local function ScheduleRebuild()
            if card._rebuildPending then return end
            card._rebuildPending = true
            C_Timer.After(0, function()
                card._rebuildPending = false
                card:Rebuild()
            end)
        end

        local categories, headers = {}, {}

        ---What a section's header says: a category that differs between the things edited takes the mixed colour.
        ---@param category table
        ---@return string? summary
        ---@return number[]? color
        local function Describe(category)
            if Mixed({ category.key }) then
                return L["Differs"], theme.mixed
            end
            return category.summary()
        end

        -- a change can reach beyond its own section, Spec decides what Talent reads
        local function Summarize()
            for _, category in ipairs(categories) do
                local header = headers[category.key]
                if header then
                    header:SetSummary(Describe(category))
                end
            end
        end

        -- Emits one or two checkboxes for { key, label } entries bound to a target table, which sits at `prefix` in db.
        local function AddCheckRow(target, prefix, entry1, entry2, isLast)
            local height = isLast and theme.rowHeightLast or theme.rowHeight
            local row = card:Row(height, isLast and 0 or nil)

            for _, entry in ipairs({ entry1, entry2 }) do
                local path = { unpack(prefix) }
                path[#path + 1] = entry.key
                row:Checkbox(entry.label, {
                    width = entry2 and 0.5 or 1,
                    value = target[entry.key] == true,
                    mixed = Mixed(path),
                    callback = function(checked)
                        target[entry.key] = checked or nil
                        fireChange(path, checked or nil)
                        Summarize()
                    end,
                })
            end
        end

        ---A category of plain checkboxes, two to a row.
        ---@param key string
        ---@param nested? string the subtable the checkboxes write to
        ---@param list { key: string, label: string }[]
        ---@return table category
        local function CheckCategory(key, nested, list)
            local target, prefix = db[key], { key }
            if nested then
                target[nested] = target[nested] or {}
                target = target[nested]
                prefix[2] = nested
            end

            return {
                key = key,
                summary = function() return PickedLabels(target, list) end,
                body = function()
                    for i = 1, #list, 2 do
                        AddCheckRow(target, prefix, list[i], list[i + 1], i + 2 > #list)
                    end
                end,
            }
        end

        ---@return number width the card's content, 400 before it has been laid out
        local function ContentWidth()
            local width = card.real and card.real.content and card.real.content:GetWidth() or 0
            return width > 0 and width or 400
        end

        local function SelectMyClass()
            local _, _, classID = UnitClass("player")
            for index = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) do
                local specID = GetSpecializationInfoForClassID(classID, index)
                if specID then
                    db.Spec.Types[specID] = true
                end
            end
            fireChange()
            ScheduleRebuild()
        end

        local function ClearSpecs()
            wipe(db.Spec.Types)
            fireChange()
            ScheduleRebuild()
        end

        local function BuildSpec()
            local types = db.Spec.Types
            local shortcuts = card:Row(30)
            shortcuts:Button(L["Select My Class"], { width = 0.5, height = 24, callback = SelectMyClass })
            shortcuts:Button(L["Clear"], { width = 0.5, height = 24, callback = ClearSpecs })

            -- A block per class, its name over its icons: picked ones in full colour on an accent border, like the talent tree.
            local classes = ClassSpecs()
            local pickedTip, unpickedTip = L["Loads in this spec. Click to remove it."], L["Click to load in this spec."]
            local columns = ContentWidth() >= SPEC_WIDE_AT and SPEC_COLUMNS_WIDE or SPEC_COLUMNS
            for first = 1, #classes, columns do
                local nameRow, iconRow = card:Row(SPEC_NAME_HEIGHT, 0), card:Row(SPEC_ROW_HEIGHT, 0)

                for column = 1, columns do
                    local class = classes[first + column - 1]
                    local at = (column - 1) / columns
                    if class then
                        nameRow:Text(nil, {
                            width = 1 / columns,
                            columnAt = at,
                            height = SPEC_NAME_HEIGHT,
                            text = sformat("|c%s%s|r", class.color, class.name),
                            bgMode = "hide",
                        })
                    end

                    for specIndex, spec in ipairs(class and class.specs or {}) do
                        local path = { "Spec", "Types", spec.id }
                        local mixed = Mixed(path)
                        -- mixed reads as unpicked, so a click turns it on for them all, as a mixed checkbox does
                        local picked = types[spec.id] == true and not mixed
                        local title = sformat("|c%s%s|r", class.color, spec.name)
                        local icon
                        icon = iconRow:Icon({
                            fixedWidth = SPEC_ICON_CELL,
                            columnAt = specIndex == 1 and at or nil,
                            spacing = 0,
                            size = SPEC_ICON_SIZE,
                            texture = spec.icon,
                            dimmed = not picked,
                            dimmedAlpha = SPEC_DIMMED_ALPHA,
                            hover = true,
                            borderColor = mixed and theme.mixed or picked and theme.accent or nil,
                            mixed = mixed,
                            tooltipTitle = title,
                            tooltip = picked and pickedTip or unpickedTip,
                            onClick = function()
                                local talentSpec = SingleSpec(db)
                                picked = not picked
                                types[spec.id] = picked or nil
                                fireChange(path, picked or nil)

                                lib.ClearMixed(icon)
                                icon:SetToggleState(not picked, picked and theme.accent or nil)
                                lib.SetTooltip(icon, gui, title, picked and pickedTip or unpickedTip)
                                lib.ShowTooltip(icon)
                                Summarize()

                                -- an open Talent section draws the one picked spec's tree
                                if openSections.Talent and SingleSpec(db) ~= talentSpec then
                                    ScheduleRebuild()
                                end
                            end,
                        })
                    end
                end
            end
        end

        local function BuildTalent()
            local spec = SingleSpec(db)
            if not spec then
                card:Row(theme.rowHeightLast, 0):Text(nil, { width = 1, text = L["Pick exactly one spec under Spec to filter by talents."], bgMode = "hide" })
                return
            end

            db.Talent.Specs[spec] = db.Talent.Specs[spec] or {}
            local picks = db.Talent.Specs[spec]
            local width = ContentWidth()
            local sectionTitles = { main = L["Class & Spec Talents"], apex = L["Apex Talents"], hero = L["Hero Talents"] }
            for _, section in ipairs(lib.TalentTreeSections(spec)) do
                card:Separator(sectionTitles[section], { useLabel = true, centered = true, height = 20, spacing = 10, inSection = true })
                card:Row(lib.TalentTreeHeight(spec, width, section)):Widget("TalentTree", nil, {
                    width = 1,
                    specID = spec,
                    section = section,
                    entries = picks,
                    onChange = function()
                        fireChange()
                        Summarize()
                    end,
                })
            end

            card:Separator(nil, { inSection = true })
            card:Row(30, 0):Button(L["Clear"], {
                width = 1,
                height = 24,
                callback = function()
                    for entryID in pairs(picks) do
                        picks[entryID] = nil
                    end
                    fireChange()
                    ScheduleRebuild()
                end,
            })
        end

        ---One spell box with what it resolved to under it.
        ---@param key string
        ---@param label string
        local function AddSpellField(key, label)
            local spells = db.Spells
            local path = { "Spells", key }
            local spellID = spells[key]
            card:Row(theme.rowHeight):EditBox(label, {
                width = 1,
                value = spellID and tostring(spellID) or "",
                mixed = Mixed(path),
                tooltip = L["A spell ID or the name of a spell you know. Pet spells count."],
                callback = function(text)
                    local info = text ~= "" and C_Spell.GetSpellInfo(tonumber(text) or text) or nil
                    spells[key] = info and info.spellID or nil
                    fireChange(path, spells[key])
                    ScheduleRebuild()
                end,
            })

            local info = spellID and C_Spell.GetSpellInfo(spellID)
            if info then
                card:Row(24):Icon({
                    width = 1,
                    size = 20,
                    texture = info.iconID,
                    tooltip = function(tooltip) tooltip:SetSpellByID(spellID) end,
                    text = { text = info.name, position = "RIGHT" },
                })
            end
        end

        local function BuildSpells()
            AddSpellField("Known", L["Spell Known"])
            AddSpellField("NotKnown", L["Not Spell Known"])
        end

        local function BuildRace()
            local types = db.Race.Types
            local options = {}
            local picked = {}
            for i, race in ipairs(PlayableRaces()) do
                options[i] = { key = race.key, text = race.label }
                if types[race.key] then
                    picked[#picked + 1] = race.key
                end
            end

            -- the dropdown reads a list of picks where the save keeps a set
            local mixed = Mixed({ "Race", "Types" })
            for _, entry in ipairs(mixed or {}) do
                local list = {}
                for raceKey in pairs(entry.value or {}) do
                    list[#list + 1] = raceKey
                end
                table.sort(list)
                entry.value = list
            end

            card:Row(theme.rowHeightLast, 0):Dropdown(L["Race"], {
                width = 1,
                multiSelect = true,
                options = options,
                value = mixed and {} or picked,
                mixed = mixed,
                callback = function(values)
                    wipe(types)
                    for _, raceKey in ipairs(values) do
                        types[raceKey] = true
                    end
                    fireChange({ "Race", "Types" }, types)
                    Summarize()
                end,
            })
        end

        local function BuildZone()
            local zoneDb = db.Zone
            card:Row(theme.rowHeight):EditBox(L["Map IDs"], {
                width = 1,
                value = zoneDb.MapIDs or "",
                mixed = Mixed({ "Zone", "MapIDs" }),
                tooltip = function(tooltip) FillZoneTooltip(tooltip, theme) end,
                tooltipBeside = true,
                callback = function(text)
                    zoneDb.MapIDs = text
                    fireChange({ "Zone", "MapIDs" }, text)
                    Summarize()
                end,
            })

            local mapID = C_Map.GetBestMapForUnit("player")
            local mapInfo = mapID and C_Map.GetMapInfo(mapID)
            if mapID and mapInfo then
                card:Row(24):Button(sformat(L["Add Current Zone: %s (%d)"], mapInfo.name, mapID), {
                    width = 1,
                    callback = function()
                        zoneDb.MapIDs = AddMapID(zoneDb.MapIDs or "", mapID)
                        fireChange()
                        ScheduleRebuild()
                    end,
                })
            end
        end

        local function Add(group, category)
            category.group = group
            categories[#categories + 1] = category
        end

        local player, location = L["Player"], L["Location"]
        if config.specs then
            Add(player, { key = "Spec", summary = function() return SpecSummary(db) end, body = BuildSpec })
            Add(player, { key = "Talent", summary = function() return TalentSummary(db) end, body = BuildTalent })
        end
        Add(player, { key = "Spells", summary = function() return SpellsSummary(db) end, body = BuildSpells })
        Add(player, { key = "Race", summary = function() return RaceSummary(db) end, body = BuildRace })
        Add(player, CheckCategory("Role", "Types", {
            { key = "TANK",    label = L["Tank"] },
            { key = "HEALER",  label = L["Healer"] },
            { key = "DAMAGER", label = L["DPS"] },
        }))
        Add(player, CheckCategory("Position", "Types", {
            { key = "MELEE",  label = L["Melee"] },
            { key = "RANGED", label = L["Ranged"] },
        }))
        Add(player, CheckCategory("Group", "Types", {
            { key = "solo",  label = L["Solo"] },
            { key = "party", label = L["Party"] },
            { key = "raid",  label = L["Raid"] },
        }))
        Add(location, CheckCategory("Instance", "Types", {
            { key = "none",     label = L["Open World"] },
            { key = "party",    label = L["Dungeon"] },
            { key = "raid",     label = L["Raid"] },
            { key = "pvp",      label = L["Battleground"] },
            { key = "arena",    label = L["Arena"] },
            { key = "scenario", label = L["Scenario"] },
        }))
        Add(location, CheckCategory("Difficulty", "Types", DifficultyList()))
        Add(location, { key = "Zone", summary = function() return ZoneSummary(db) end, body = BuildZone })

        -- General --

        card:Separator(L["General"], { useLabel = true })

        local cells = {}
        for _, state in ipairs(gui.loadStates) do
            if not state.triggerOnly then
                local path = { "State", state.key }
                cells[#cells + 1] = function(row)
                    row:SlimCheckbox(L[state.label], {
                        width = 0.5,
                        tristate = true,
                        value = db.State[state.key],
                        mixed = Mixed(path),
                        callback = function(value)
                            db.State[state.key] = value
                            fireChange(path, value)
                        end,
                    })
                end
            end
        end

        -- the caller's own toggle takes the top right
        if config.general then
            table.insert(cells, 2, config.general)
        end

        for i = 1, #cells, 2 do
            local row = card:Row(STATE_ROW_HEIGHT, 0)
            cells[i](row)
            if cells[i + 1] then
                cells[i + 1](row)
            end
        end

        -- Sections --

        local group
        for index, category in ipairs(categories) do
            if category.group ~= group then
                group = category.group
                card:Separator(group, { useLabel = true })
            end

            local key = category.key
            local summary, color = Describe(category)
            local expanded, header = card:Section(L[key], {
                key = "load:" .. key,
                collapsed = not openSections[key],
                summary = summary,
                summaryColor = color,
                onToggle = function()
                    openSections[key] = not openSections[key] or nil
                    card:Rebuild()
                end,
            })
            headers[key] = header
            if expanded then
                category.body()

                -- closes the open section off; the next heading draws its own rule
                local nextCategory = categories[index + 1]
                if nextCategory and nextCategory.group == group then
                    card:Separator(nil, { inSection = true })
                end
            end
        end
    end,
}
