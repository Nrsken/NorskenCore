---@class NRSKNUI
local Core = _G.NorskenCore
---@class NRSKNUI.GUITriggerEditor
local TriggerEditor = {}
Core.GUITriggerEditor = TriggerEditor
local L = Core.L
local rowH = Core.KajiGUI.DEFAULT_THEME.rowHeight

local AuraTriggers = Core.AuraTriggers
local Premade = Core.AuraFiltersPremade
local SpellList = Core.GUISpellList
local AF = AuraUtil.AuraFilters

local ipairs, tonumber, tostring = ipairs, tonumber, tostring
local format = string.format
local setmetatable = setmetatable
local tinsert, tremove = table.insert, table.remove
local min, rad = math.min, math.rad
local CopyTable = CopyTable
local nop = nop

local TEX = Core.Media.GUITextures
local DELETE_COLOR = { 1, 0, 0 }

-- A "trigger" here is one branch of the saved trigger: an aura group inside the display's container.

local AURA_TYPES = {
    { value = AF.Helpful, text = L['Buffs'] },
    { value = AF.Harmful, text = L['Debuffs'] },
}
local SPELL_MODES = {
    { value = 'all',  text = L['All Spells'] },
    { value = 'only', text = L['Whitelist'] },
    { value = 'hide', text = L['Blacklist'] },
}
local MODE_FIELD = { only = 'includeSpellIDs', hide = 'excludeSpellIDs' }

---A set filter shows its Yes or No in the accent, so it stands out from the rows left on Any.
---@param theme table
---@param yesOnly? boolean
---@return table[]
local function StateOptions(theme, yesOnly)
    local options = {
        { value = 'any', text = L['Any'] },
        { value = 'yes', text = L['Yes'], valueColor = theme.accent },
    }
    if not yesOnly then options[3] = { value = 'no', text = L['No'], valueColor = theme.accent } end
    return options
end

---@param state boolean?
---@return string
local function StateValue(state)
    if state == true then return 'yes' end
    if state == false then return 'no' end
    return 'any'
end

---@param value string
---@return boolean?
local function ValueState(value)
    if value == 'yes' then return true end
    if value == 'no' then return false end
    return nil
end

---@param branch table
---@param key string
---@return table
local function Sub(branch, key)
    branch[key] = branch[key] or {}
    return branch[key]
end

-- Each group reads and writes one kind of branch field, so a group is a list of keys plus how to reach them.
local GROUPS = {
    {
        key = 'aura',
        title = L['Aura Filters'],
        desc = L['The tags Blizzard puts on the aura. Yes needs the tag, No hides auras that have it.'],
        fields = {
            { key = AF.Player,                label = L['Player'] },
            { key = AF.Raid,                  label = L['Raid'] },
            { key = AF.Cancelable,            label = L['Cancelable'] },
            { key = AF.ExternalDefensive,     label = L['External Defensive'] },
            { key = AF.CrowdControl,          label = L['Crowd Control'] },
            { key = AF.RaidInCombat,          label = L['Raid In Combat'] },
            { key = AF.RaidPlayerDispellable, label = L['Raid Player Dispellable'] },
            { key = AF.BigDefensive,          label = L['Big Defensive'] },
            { key = AF.Important,             label = L['Important'] },
            { key = AF.Dispellable,           label = L['Dispellable'] },
            { key = AF.IncludeNameplateOnly,  label = L['Include Nameplate Only'], yesOnly = true }, -- not negatable
        },
        get = function(branch, key) return branch.tokens and branch.tokens[key] end,
        set = function(branch, key, state) Sub(branch, 'tokens')[key] = state end,
    },
    {
        key = 'candidate',
        title = L['Candidate Filters'],
        desc = L['Checked after the aura filters, every one that is set has to match.'],
        duration = true,
    },
    {
        key = 'dispel',
        title = L['Dispel Types'],
        desc = L['Yes shows only these types, No hides them.'],
        fields = {
            { key = 'Magic',   label = L['Magic'] },
            { key = 'Curse',   label = L['Curse'] },
            { key = 'Disease', label = L['Disease'] },
            { key = 'Poison',  label = L['Poison'] },
            { key = 'Enrage',  label = L['Enrage'] },
            { key = 'Stealth', label = L['Stealth'] },
            { key = 'Special', label = L['Special'] },
        },
        get = function(branch, key)
            local c = branch.candidates
            if c and c.includeDispelTypes and c.includeDispelTypes[key] then return true end
            if c and c.excludeDispelTypes and c.excludeDispelTypes[key] then return false end
            return nil
        end,
        set = function(branch, key, state)
            local candidates = Sub(branch, 'candidates')
            Sub(candidates, 'includeDispelTypes')[key] = (state == true) or nil
            Sub(candidates, 'excludeDispelTypes')[key] = (state == false) or nil
        end,
    },
    {
        key = 'props',
        title = L['Aura Properties'],
        desc = L['What the aura is and what can be done with it.'],
        fields = {
            { key = 'isFromPlayerOrPlayerPet', label = L['From Player or Pet'] },
            { key = 'isRoleAura',              label = L['Role Aura'] },
            { key = 'isPriorityAura',          label = L['Priority Aura'] },
            { key = 'isStealable',             label = L['Stealable'] },
            { key = 'canApplyAura',            label = L['Can Apply Aura'] },
            { key = 'nameplateShowAll',        label = L['Nameplate: Show All'] },
            { key = 'nameplateShowPersonal',   label = L['Nameplate: Personal'] },
            { key = 'isBossAura',              label = L['Boss Aura'] },
            { key = 'isBossOrRoleAura',        label = L['Boss or Role Aura'] },
        },
        get = function(branch, key) return branch.candidates and branch.candidates[key] end,
        set = function(branch, key, state) Sub(branch, 'candidates')[key] = state end,
    },
}

---@param branch table
---@param group table
---@return number
local function CountSet(branch, group)
    if group.duration then
        return (branch.candidates and branch.candidates.maxDuration) and 1 or 0
    end
    local count = 0
    for _, field in ipairs(group.fields) do
        if group.get(branch, field.key) ~= nil then count = count + 1 end
    end
    return count
end

-- Weak keys: a branch or trigger that goes away takes its state with it.
local openState = setmetatable({}, { __mode = 'k' })
local pickedBranch = setmetatable({}, { __mode = 'k' })

---@param trigger table
---@return number
local function Picked(trigger)
    local index = min(pickedBranch[trigger] or 1, #trigger.branches)
    pickedBranch[trigger] = index
    return index
end

-- Spells --

---@param branch table
---@return string
local function GetSpellMode(branch)
    if branch.shipped then return branch.shipped.field == MODE_FIELD.hide and 'hide' or 'only' end
    local c = branch.candidates
    if c and c.includeSpellIDs then return 'only' end
    if c and c.excludeSpellIDs then return 'hide' end
    return 'all'
end

---Moves the list to the field the new mode reads; All Spells parks it, so switching back restores it.
---@param branch table
---@param mode string
local function SetSpellMode(branch, mode)
    local current = GetSpellMode(branch)
    if mode == current then return end
    local candidates = Sub(branch, 'candidates')

    local list = branch.parkedSpells
    if current ~= 'all' then
        list = branch.shipped and { shipped = branch.shipped } or { map = candidates[MODE_FIELD[current]] }
        branch.shipped = nil
        candidates[MODE_FIELD[current]] = nil
    end

    if mode == 'all' then
        branch.parkedSpells = list
        return
    end

    branch.parkedSpells = nil
    local field = MODE_FIELD[mode]
    if list and list.shipped then
        list.shipped.field = field
        branch.shipped = list.shipped
    else
        candidates[field] = list and list.map or {}
    end
end

---Typeless branches inherit the base, so pin them first or a trigger 1 change would retype them all.
---@param trigger table
---@param index number
---@param value string
local function SetAuraType(trigger, index, value)
    for i, branch in ipairs(trigger.branches) do
        if i ~= index and not branch.type then branch.type = trigger.Base end
    end

    -- Trigger 1 keeps living on the base, which the display's own dispel settings read.
    local branch = trigger.branches[index]
    if index == 1 then
        trigger.Base, branch.type = value, nil
    else
        branch.type = value
    end
end

---Give every trigger its own type before the list changes order, so none of them retypes with trigger 1.
---@param trigger table
local function PinTypes(trigger)
    for _, branch in ipairs(trigger.branches) do
        branch.type = branch.type or trigger.Base
    end
end

---Trigger 1 lives on the base again after the list changed order: every type was pinned first, so nothing retypes.
---@param trigger table
local function Rebase(trigger)
    local first = trigger.branches[1]
    if first and first.type then
        trigger.Base, first.type = first.type, nil
    end
end

---@param theme table
---@param text string
---@return string
local function Muted(theme, text)
    return Core:ColorText(text, theme.textMuted)
end

-- Container card --

---@param theme table
---@param trigger table
---@param index number
---@return string
function TriggerEditor:Label(theme, trigger, index)
    local auraType = (trigger.branches[index].type or trigger.Base) == AF.Helpful and L['Buffs'] or L['Debuffs']
    return format('%s  %s', format(L['Trigger %d'], index), Muted(theme, auraType))
end

---Duplicate and delete on every row of the trigger dropdown.
---@param trigger table
---@param changed fun(picked: number)
---@return fun(index: number): KajiGUIDropdownItemAction[]
local function TriggerActions(gui, trigger, changed)
    local branches = trigger.branches
    return function(index)
        return {
            {
                icon = TEX .. 'plus-sign.png',
                tooltip = L['Duplicate'],
                onClick = function()
                    TriggerEditor:DuplicateBranch(trigger, index)
                    changed(#branches)
                end,
            },
            {
                icon = TEX .. 'NorskenCustomCrossv3.png', -- same cross, tint and rotation as skinned close buttons
                color = DELETE_COLOR,
                rotation = rad(45),
                tooltip = L['Delete Trigger'],
                -- The last one stays: a display without any matches everything its base allows.
                disabled = #branches == 1,
                onClick = function()
                    gui:Prompt({
                        title = L['Delete Trigger'],
                        text = format(L['Delete Trigger %d and everything set on it?\nThis cannot be undone.'], index),
                        onAccept = function()
                            TriggerEditor:RemoveBranch(trigger, index)
                            changed(min(index, #branches))
                        end,
                        acceptText = L['Delete'],
                        cancelText = L['Cancel'],
                    })
                end,
            },
        }
    end
end

---The Load Preset dropdown: it replaces every trigger, or only the one at `index`.
---@param gui table
---@param trigger table
---@param changed fun(picked: number)
---@param refresh fun() puts the dropdown back when the prompt is cancelled
---@param index number?
---@return table config
function TriggerEditor:LoadPresetConfig(gui, trigger, changed, refresh, index)
    local options = {}
    for i, preset in ipairs(Premade:GetList()) do
        options[i] = { value = preset.key, text = preset.text }
    end

    return {
        width = 1,
        options = options,
        tooltip = index and L['Replace this trigger with a preset, as a starting point to edit.']
            or L['Replace the triggers with a preset, as a starting point to edit.'],
        callback = function(key)
            local preset = Premade:Get(key)
            local name = preset and preset.name or key
            gui:Prompt({
                title = L['Load Preset'],
                text = index and format(L['Replace Trigger %d with %s?\nThis cannot be undone.'], index, name)
                    or format(L['Replace every trigger with %s?\nThis cannot be undone.'], name),
                onAccept = function()
                    if index then
                        TriggerEditor:LoadPresetInto(trigger, index, key)
                    else
                        AuraTriggers:LoadPreset(trigger, key)
                    end
                    changed(index or 1)
                end,
                onCancel = refresh, -- the dropdown already shows the preset it was asked for
                acceptText = L['Load'],
                cancelText = L['Cancel'],
            })
        end,
    }
end

---@param page table
---@param trigger table
---@param ctx table
---@param apply fun()
---@param show fun(picked: number) shows another trigger
---@param changed fun(picked: number) after the trigger list changed
---@return KajiGUIFluentCard
local function BuildContainerCard(page, trigger, ctx, apply, show, changed)
    local gui = page.gui
    local card
    card = page:Card(ctx.title, ctx.group):Rebuild(function(c)
        local index = Picked(trigger)
        local options = {}
        for i = 1, #trigger.branches do
            options[i] = { value = i, text = TriggerEditor:Label(gui.theme, trigger, i) }
        end

        local editing = {
            width = 0.5,
            options = options,
            value = index,
            tooltip = L['Each trigger is its own group of auras, shown together in this display.'],
            itemActions = TriggerActions(gui, trigger, changed),
            callback = function(value)
                if value ~= index then show(value) end
            end,
        }
        local addTrigger = {
            height = 24,
            callback = function()
                TriggerEditor:AddBranch(trigger)
                changed(#trigger.branches)
            end,
        }
        local loadPreset = TriggerEditor:LoadPresetConfig(gui, trigger, changed, function() card:Rebuild() end)

        local first = c:Row(rowH)
        if ctx.showUnit then
            first:Dropdown(L['Unit'], {
                width = 0.5,
                options = AuraTriggers.UnitOptions,
                value = trigger.Unit,
                tooltip = L['Every trigger in this display watches this unit.'],
                callback = function(value)
                    trigger.Unit = value
                    apply()
                end,
            })
            first:Dropdown(L['Editing'], editing)

            local second = c:Row(rowH, 0)
            second:Dropdown(L['Load Preset'], loadPreset)
            addTrigger.width, addTrigger.yOffset = 0.5, -14 -- level with the dropdown box beside it
            second:Button(L['Add Trigger'], addTrigger)
        else
            first:Dropdown(L['Editing'], editing)
            first:Dropdown(L['Load Preset'], loadPreset)

            addTrigger.width = 1
            c:Row(24, 0):Button(L['Add Trigger'], addTrigger)
        end
    end)
    return card
end

-- Trigger card --

---@param card KajiGUIFluentCard
---@param branch table
---@param group table
---@param changed fun()
local function BuildGroupRows(card, branch, group, changed)
    if group.duration then
        card:Row(rowH):EditBox(L['Max Duration (seconds)'], {
            width = 0.5,
            value = tostring(branch.candidates and branch.candidates.maxDuration or ''),
            callback = function(text)
                local n = tonumber(text)
                local value = (n and n > 0) and n or nil
                if value == (branch.candidates and branch.candidates.maxDuration) then return end
                Sub(branch, 'candidates').maxDuration = value
                changed()
            end,
        })
        return
    end

    local fields = group.fields
    for index = 1, #fields, 2 do
        local row = card:Row(rowH)
        for i = index, index + 1 do
            local field = fields[i]
            if field then
                row:Dropdown(field.label, {
                    width = 0.5,
                    options = StateOptions(card.page.gui.theme, field.yesOnly),
                    value = StateValue(group.get(branch, field.key)),
                    callback = function(value)
                        group.set(branch, field.key, ValueState(value))
                        changed()
                    end,
                })
            end
        end
    end
end

---@param card KajiGUIFluentCard
---@param branch table
---@param changed fun()
---@param nest { key: string }? inside a section the groups are its sub-sections
local function BuildFilters(card, branch, changed, nest)
    local theme = card.page.gui.theme
    local open = openState[branch] or {}
    openState[branch] = open

    for _, group in ipairs(GROUPS) do
        local count = CountSet(branch, group)
        local isOpen = open[group.key] == true -- closed until the user opens one

        local title = count > 0 and (group.title .. '  ' .. Muted(theme, format(L['%d active'], count))) or group.title
        local config = {
            key = nest and (nest.key .. ':' .. group.key),
            collapsed = not isOpen,
            onToggle = function()
                open[group.key] = not isOpen
                card:Rebuild()
            end,
        }
        local expanded
        if nest then
            expanded = card:SubSection(title, config)
        else
            expanded = card:Section(title, config)
        end
        if expanded then
            card:Row(20):Text(nil, { width = 1, text = Muted(theme, group.desc), bgMode = 'hide' })
            BuildGroupRows(card, branch, group, changed)
        end
    end
    if nest then
        card:EndSubSection()
    end
end

---One trigger's rows: its aura type, its spells and its filters.
---@param c KajiGUIFluentCard
---@param trigger table
---@param index number
---@param apply fun()
---@param changed fun() after an edit that changes the rows
---@param retype fun() after the aura type changed, which titles name
---@param nest { key: string }? set when the rows sit inside a section of the caller's
local function BuildBranch(c, trigger, index, apply, changed, retype, nest)
    local branch = trigger.branches[index]
    local separator = { useLabel = true, inSection = nest ~= nil, centered = true } -- a plain separator would end the caller's section

    local row = c:Row(rowH)
    row:Dropdown(L['Aura Type'], {
        width = 0.5,
        options = AURA_TYPES,
        value = branch.type or trigger.Base,
        callback = function(value)
            SetAuraType(trigger, index, value)
            apply()
            retype()
        end,
    })
    row:Dropdown(L['Spells'], {
        width = 0.5,
        options = SPELL_MODES,
        value = GetSpellMode(branch),
        callback = function(value)
            SetSpellMode(branch, value)
            changed()
        end,
    })

    local mode = GetSpellMode(branch)
    if mode ~= 'all' then
        local shipped = branch.shipped
        local source = shipped and SpellList:ShippedSource(shipped, shipped.list, changed)
            or SpellList:MapSource(branch.candidates[MODE_FIELD[mode]], changed)

        c:Separator(mode == 'only' and L['Whitelist'] or L['Blacklist'], separator)
        SpellList:BuildAdd(c, source)
        SpellList:BuildList(c, source)
    end

    c:Separator(L['Filters'], separator)
    BuildFilters(c, branch, changed, nest)
end

---@param page table
---@param trigger table
---@param apply fun()
---@param retype fun() after the aura type changed, which the container card names
---@param group string? the page condition group its widgets join
---@return KajiGUIFluentCard
local function BuildTriggerCard(page, trigger, apply, retype, group)
    local card
    card = page:Card(format(L['Trigger %d'], Picked(trigger)), group):Rebuild(function(c)
        BuildBranch(c, trigger, Picked(trigger), apply, function()
            apply()
            card:Rebuild()
        end, retype)
    end)
    return card
end

---Bring an old trigger up to the shape the editor writes, before anything reads its branches.
---@param trigger table
function TriggerEditor:Prepare(trigger)
    AuraTriggers:ConvertSpellIDs(trigger)
    AuraTriggers:ConvertPreset(trigger)
    trigger.branches = trigger.branches or { {} }
end

-- Sections --

-- For a page that lays every trigger out as a section of its own, as the Cooldown & Aura Manager does.

---@param c KajiGUIFluentCard
---@param trigger table
---@param index number
---@param changed fun() after any edit, which rebuilds the rows
---@param nest { key: string } the section's key
function TriggerEditor:BuildBranch(c, trigger, index, changed, nest)
    c:Row(rowH):Dropdown(L['Load Preset'], self:LoadPresetConfig(c.page.gui, trigger, changed, function() c:Rebuild() end, index))
    BuildBranch(c, trigger, index, nop, changed, changed, nest) -- changed applies too, so a retype runs it once
end

---A preset in place of one trigger; one with several triggers of its own puts them all there.
---@param trigger table
---@param index number
---@param key string
function TriggerEditor:LoadPresetInto(trigger, index, key)
    local loaded = AuraTriggers:ToAuraFilter({ Type = AuraTriggers.Types.Preset, Preset = key, Unit = trigger.Unit })
    PinTypes(trigger)
    tremove(trigger.branches, index)
    for i, branch in ipairs(loaded.branches) do
        branch.type = branch.type or loaded.Base
        tinsert(trigger.branches, index + i - 1, branch)
    end
    Rebase(trigger)
end

---A new trigger at the end, of the last one's aura type.
---@param trigger table
function TriggerEditor:AddBranch(trigger)
    local last = trigger.branches[#trigger.branches]
    tinsert(trigger.branches, { type = last and last.type or trigger.Base })
end

---A copy at the end, so no other trigger's number changes.
---@param trigger table
---@param index number
function TriggerEditor:DuplicateBranch(trigger, index)
    local copy = CopyTable(trigger.branches[index])
    copy.type = copy.type or trigger.Base
    tinsert(trigger.branches, copy)
end

---@param trigger table
---@param from number
---@param to number
function TriggerEditor:MoveBranch(trigger, from, to)
    local branches = trigger.branches
    PinTypes(trigger)
    branches[from], branches[to] = branches[to], branches[from]
    Rebase(trigger)
end

---@param trigger table
---@param index number
function TriggerEditor:RemoveBranch(trigger, index)
    PinTypes(trigger)
    tremove(trigger.branches, index)
    Rebase(trigger)
end

-- Card --

---@param page table
---@param trigger table
---@param ctx { title: string, group?: string, showUnit?: boolean, onChange: fun() }
function TriggerEditor:Build(page, trigger, ctx)
    self:Prepare(trigger)

    local function Apply()
        ctx.onChange()
        AuraTriggers:Invalidate()
    end

    -- Both cards rebuild in place rather than the page reloading, so the scroll stays where it was.
    local containerCard, triggerCard
    local function Show(picked)
        pickedBranch[trigger] = picked
        containerCard:Rebuild()
        triggerCard:SetTitle(format(L['Trigger %d'], Picked(trigger)))
        triggerCard:Rebuild()
    end
    local function Changed(picked)
        Apply()
        Show(picked)
    end

    containerCard = BuildContainerCard(page, trigger, ctx, Apply, Show, Changed)
    triggerCard = BuildTriggerCard(page, trigger, Apply, function() containerCard:Rebuild() end, ctx.group)
end
