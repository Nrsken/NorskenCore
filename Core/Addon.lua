---@class NRSKNUI
---@field name string the addon's folder name, set by AceAddon
---@field GUI KajiGUIInstance
---@field Theme KajiTheme
---@field shortName string what follows Norsken in the addon's name, `UI` for NorskenUI
---@field Version string the TOC version, Development Version for a dev checkout
---@field Anchors NRSKNUI.Anchors this addon's handle on the shared anchor system
---@field PreviewManager NRSKNUI.PreviewManager
---@field launcherDB table? the minimap button's saved table, once RegisterLauncher ran
local Private = select(2, ...)
local L = Private.L

local LibStub = LibStub
local InCombatLockdown = InCombatLockdown
local UnitGUID = UnitGUID
local format = string.format
local tostring = tostring
local ipairs = ipairs
local print = print
local strtrim, strlower = strtrim, strlower
local SlashCmdList = SlashCmdList

local GetAddOnMetadata = C_AddOns.GetAddOnMetadata
local GetAddOnInfo = C_AddOns.GetAddOnInfo
local IsAddOnLoaded = C_AddOns.IsAddOnLoaded
local EnableAddOn = C_AddOns.EnableAddOn
local LoadAddOn = C_AddOns.LoadAddOn

local LDBIcon = LibStub('LibDBIcon-1.0')

-- what every Norsken addon sets up the same way: identity, settings window, commands and launcher

-- the raw value stays English, exports and the version check carry it
local DEV_VERSION = 'Development Version'
local SHARED_OPTIONS = 'NorskenCore_Options'

-- Setup --

-- the saved half of a Kaji theme, copied into each addon's own store
Private.ThemeDefaults = {
    mode           = "preset",
    selectedPreset = "NUI Neon",
    customColors   = {},
    fontFace       = Private.Media.Fonts.Expressway,
    fontSizeNormal = 12,
    fontSizeSmall  = 12,
    fontSizeLarge  = 16,
    fontOutline    = "OUTLINE",
    fontShadow     = false,
    windowOpacity  = 1, -- how solid the settings window is, 0.3-1
    zoneContrast   = 1, -- spacing between the window zones' tones, 0.5-2
    surfaceTint    = 1, -- how much of the base hue the surfaces carry, 0-3
}

---@param object table the addon object, already through AceAddon
---@param name string
---@param themeStore (fun(): table?)?
function Private.SetupAddon(object, name, themeStore)
    object.shortName = name:match('^Norsken(.+)$') -- NorskenUI -> UI, the grey half of the title

    object.Version = GetAddOnMetadata(name, 'Version')
    if object.Version == '@project-version@' then
        object.Version = DEV_VERSION
    end

    object.GUI = Private.Kaji:New({
        store = themeStore,
        classColorProvider = function() return object:GetClassColor(object.MyClass) end,
    })
    object.Theme = object.GUI:GetTheme()
    object.Anchors = Private:NewAnchors(object)
    object.PreviewManager = Private:NewPreviewManager(object)
end

-- Identity --

---The addon's title as the TOC shows it, `Norsken` in the theme colour and the rest grey.
---@return string
function Private:GetTitle()
    return self:ColorTextByTheme('Norsken') .. '|cffb3b3b3' .. self.shortName .. '|r'
end

---@return string
function Private:GetVersionText()
    if self.Version == DEV_VERSION then
        return L['Development Version']
    end
    return self.Version
end

---@param msg string
function Private:Print(msg)
    print(self:ColorTextByTheme('Norsken') .. self.shortName .. ':|r ' .. msg)
end

-- Options --

---The settings window lives in the LoadOnDemand `<addon>_Options`, loaded the first time it's opened.
---@param addon table
---@return boolean loaded
local function LoadOptions(addon)
    local options = addon.name .. '_Options'
    if IsAddOnLoaded(options) then return true end

    local _, _, _, _, reason = GetAddOnInfo(options)
    if reason == 'MISSING' then
        addon:Print(format(L['%s is missing, reinstall %s.'], options, addon.name))
        return false
    end

    -- a disabled options folder would leave the command doing nothing, so turn it back on for this character
    local guid = UnitGUID('player')
    EnableAddOn(SHARED_OPTIONS, guid)
    EnableAddOn(options, guid)

    -- the TOC only lists the shared parts as optional (see Bootstrap.lua), which doesn't load a LoadOnDemand addon
    for _, folder in ipairs({ SHARED_OPTIONS, options }) do
        local loaded, failure = LoadAddOn(folder)
        if not loaded then
            addon:Print(folder .. ': ' .. (_G['ADDON_' .. tostring(failure)] or tostring(failure)))
            return false
        end
    end

    -- folders from different releases mixed together break in odd ways, so say so up front
    -- raw TOC values on both sides: Version shows a dev checkout as Development Version
    local version = GetAddOnMetadata(options, 'Version')
    local addonVersion = GetAddOnMetadata(addon.name, 'Version')
    if version ~= addonVersion then
        addon:Print(format(L['%s is version %s but %s is %s, update both.'], options, tostring(version), addon.name, tostring(addonVersion)))
    end
    return true
end

---Open the settings window, on a page when given one.
---@param pageId string?
---@param context table? { tabId, itemKey } inside that page
function Private:OpenOptions(pageId, context)
    -- loading builds the whole window, which waits until combat is over
    if InCombatLockdown() then
        self:Print(L['Options will open after combat ends.'])
        self:RunWhenSafe(function()
            self:OpenOptions(pageId, context)
        end)
        return
    end
    if not LoadOptions(self) then return end

    local window = self.PageWindows and self.PageWindows[pageId] or self.GUIFrame
    if not window:IsShown() then
        window:Show()
    end
    if pageId then
        window:ShowPage(pageId, context)
    end
end

function Private:ToggleOptions()
    local window = self.GUIFrame
    if window and window:IsShown() then
        window:Hide()
    else
        self:OpenOptions()
    end
end

---Wipe the saved window position and size and snap the open window back to its defaults.
function Private:ResetGUIState()
    -- rebuilt rather than nil'd, AceDB only refills defaults on load
    self.db.global.GUIState = { frame = {} }
    if self.GUIFrame then
        self.GUIFrame:ResetPosition()
    end

    self:Print(L['GUI position and size reset to defaults.'])
end

-- Commands --

-- what every addon's slash command answers to; anything else, nothing included, toggles the window
local COMMANDS = {
    anchors = function(addon) addon.Anchors:Toggle() end,
    reset = function(addon) addon:ResetGUIState() end,
}

---The addon's slash commands with the shared words, plus any of its own.
---@param slashes string[] e.g. { '/nui', '/norskenui' }
---@param own table<string, fun(addon: table)>? extra words, lowercase
function Private:RegisterCommands(slashes, own)
    local addon = self
    local key = self.name:upper()
    self.slashCommand = slashes[1]
    for index, slash in ipairs(slashes) do
        _G['SLASH_' .. key .. index] = slash
    end

    SlashCmdList[key] = function(input)
        local command = strlower(strtrim(input or ''))
        local handler = (own and own[command]) or COMMANDS[command]
        if handler then
            handler(addon)
        else
            addon:ToggleOptions()
        end
    end
end

-- Launcher --

---Minimap button and broker launcher, with the TOC's icon tinted in the theme accent. Called again with
---another table (a profile switch), it moves the button onto that one.
---@param db table where the button keeps its position and hidden state
function Private:RegisterLauncher(db)
    if self.launcherDB then
        self.launcherDB = db
        LDBIcon:Refresh(self.name, db)
        return
    end

    self.launcherDB = db

    local addon = self
    local accent = self.Theme.accent
    ---@type LibDataBroker.QuickLauncher
    local data = {
        type = 'launcher',
        text = self.name,
        icon = GetAddOnMetadata(self.name, 'IconTexture') --[[@as string]], -- every Norsken TOC has one
        iconR = accent[1],
        iconG = accent[2],
        iconB = accent[3],
        OnClick = function(_, button)
            if button == 'LeftButton' then
                addon:ToggleOptions()
            elseif button == 'RightButton' then
                addon.Anchors:Toggle()
            elseif button == 'MiddleButton' then
                addon:ResetGUIState()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(addon:GetTitle())
            tooltip:AddLine(L['Left-Click to open options'], 0.70, 0.70, 0.70)
            tooltip:AddLine(L['Right-Click to toggle anchors'], 0.70, 0.70, 0.70)
            tooltip:AddLine(L['Middle-Click to reset the options window position'], 0.70, 0.70, 0.70)
        end,
    }
    local launcher = LibStub('LibDataBroker-1.1'):NewDataObject(self.name, data)
    ---@cast db LibDBIcon.button.DB
    LDBIcon:Register(self.name, launcher, db)
end

---@param hidden boolean
function Private:SetLauncherHidden(hidden)
    -- LibDBIcon's Show and Hide only touch the button, the saved flag is ours to set
    self.launcherDB.hide = hidden
    if hidden then
        LDBIcon:Hide(self.name)
    else
        LDBIcon:Show(self.name)
    end
end
