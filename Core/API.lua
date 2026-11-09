---@class NRSKNUI
local Private = select(2, ...)

local _G = _G
local LibStub = LibStub
local setmetatable = setmetatable

-- What the Norsken addons may use. Everything else in Core stays private.

---@class NorskenCoreAPI
local API = {}
_G.NorskenCore = API

-- Addons --

-- Compare with the TOC's X-NorskenCore-Minimum, see Version.lua
API.Version = Private.API_VERSION

---Creates an addon object that reads this API through `__index`, so `object:RunWhenSafe()` works
---on the addon itself and what it stores of its own (`db`, `GUI`, `Theme`) stays its own.
---@param object table usually the addon's private table
---@param name string
---@param ... string AceAddon mixins
---@return table object
function API:NewAddon(object, name, ...)
    setmetatable(object, { __index = API }) -- AceAddon copies an existing metatable, this one survives
    -- AceAddon's own annotation misses the form that takes an object
    ---@diagnostic disable-next-line: type-mismatch
    return LibStub('AceAddon-3.0'):NewAddon(object, name, ...)
end

-- Core --

API.AreAurasSecret = Private.AreAurasSecret
API.AreCooldownsSecret = Private.AreCooldownsSecret
API.CanAccessObject = Private.CanAccessObject
API.CanAccessValue = Private.CanAccessValue
API.ClearTexture = Private.ClearTexture
API.CreateBackdrop = Private.CreateBackdrop
API.CreateDynamicGroup = Private.CreateDynamicGroup
API.DeferUntilUnrestricted = Private.DeferUntilUnrestricted
API.GetRestrictionState = Private.GetRestrictionState
API.GetSafeRole = Private.GetSafeRole
API.GlobalZoom = Private.GlobalZoom
API.HiddenFrame = Private.HiddenFrame
API.InCombat = Private.InCombat
API.InjectAPI = Private.InjectAPI
API.IsFullyRestricted = Private.IsFullyRestricted
API.IsRestricted = Private.IsRestricted
API.IsSafeValue = Private.IsSafeValue
API.IsSecretTable = Private.IsSecretTable
API.IsSecretUnit = Private.IsSecretUnit
API.IsSecretValue = Private.IsSecretValue
API.IsSpellAuraSecret = Private.IsSpellAuraSecret
API.IsValidUnitToken = Private.IsValidUnitToken
API.NotSecretValue = Private.NotSecretValue
API.RegisterDynamicGroupGrower = Private.RegisterDynamicGroupGrower
API.RunWhenSafe = Private.RunWhenSafe
API.SafeValue = Private.SafeValue
API.ScrubSecrets = Private.ScrubSecrets
API.UnitIsAFK = Private.UnitIsAFK
API.UnitIsDND = Private.UnitIsDND
API.WhiteTexture = Private.WhiteTexture

-- Shared Settings --

API.GetSharedSettings = Private.GetSharedSettings
API.GetSharedDefaults = Private.GetSharedDefaults
API.HoldsSharedSettings = Private.HoldsSharedSettings
API.ChooseSharedSource = Private.ChooseSharedSource
API.AdoptSharedSettings = Private.AdoptSharedSettings
API.SharedSettingsDiffer = Private.SharedSettingsDiffer
API.ApplySharedSettings = Private.ApplySharedSettings
API.SharedSettingsChanged = Private.SharedSettingsChanged

-- Media --

API.Media = Private.Media
API.ResolveMediaPath = Private.ResolveMediaPath
API.GetFont = Private.GetFont
API.GetStatusbar = Private.GetStatusbar
API.GetBarBackground = Private.GetBarBackground
API.GetBorderColor = Private.GetBorderColor
API.GetBackdropColor = Private.GetBackdropColor
API.SetSpark = Private.SetSpark
API.PlaySafeSound = Private.PlaySafeSound

-- Fonts --

API.GetOutlineLabel = Private.GetOutlineLabel
API.GetOutlineOptions = Private.GetOutlineOptions
API.ResolveFlags = Private.ResolveFlags
API.RefreshFontStyles = Private.RefreshFontStyles

-- Colors --

API.Colors = Private.Colors
API.ColorModeOptions = Private.ColorModeOptions
API.LoadCustomColors = Private.LoadCustomColors
API.GetPlayerClassColor = Private.GetPlayerClassColor
API.GetClassColor = Private.GetClassColor
API.GetClassColorRaw = Private.GetClassColorRaw
API.ColorTextByClass = Private.ColorTextByClass
API.RGBAToHex = Private.RGBAToHex
API.ColorTextByTheme = Private.ColorTextByTheme
API.GetAccentColor = Private.GetAccentColor
API.CreateColor = Private.CreateColor
API.ColorGradient = Private.ColorGradient
API.ColorText = Private.ColorText

-- Curves --

API.curves = Private.curves
API.RefreshCurves = Private.RefreshCurves

-- Formatting --

API.MINUTES_SECONDS_FORMAT = Private.MINUTES_SECONDS_FORMAT
API.FormatTime = Private.FormatTime
API.FormatTokens = Private.FormatTokens
API.GetDurationFormatUnit = Private.GetDurationFormatUnit
API.GetPrecisionDurationFormatter = Private.GetPrecisionDurationFormatter
API.GetAuraDurationFormatter = Private.GetAuraDurationFormatter
API.RefreshAuraDurationFormatter = Private.RefreshAuraDurationFormatter

-- Player --

API.MyClassLocale = Private.MyClassLocale
API.MyClass = Private.MyClass
API.MyClassID = Private.MyClassID
API.MySpec = Private.MySpec
API.IsClassInGroup = Private.IsClassInGroup

-- Dialogs --

API.CreatePrompt = Private.CreatePrompt
API.CreateCopyDialog = Private.CreateCopyDialog
API.CreateReloadPrompt = Private.CreateReloadPrompt

-- Anchors and previews --

API.NewAnchors = Private.NewAnchors
API.NewPreviewManager = Private.NewPreviewManager

-- Load conditions and auras --

API.LoadConditions = Private.LoadConditions
API.AuraFilters = Private.AuraFilters
API.AuraFiltersPremade = Private.AuraFiltersPremade
API.AuraTriggers = Private.AuraTriggers
API.AuraPreview = Private.AuraPreview
API.GetTriggerBranches = Private.GetTriggerBranches
API.GetTriggerBranchCount = Private.GetTriggerBranchCount
API.ResolveAuraGrowth = Private.ResolveAuraGrowth
API.GetAuraGridSize = Private.GetAuraGridSize
API.SkinAuraButton = Private.SkinAuraButton

-- Locale --

API.L = Private.L
API.LANGUAGES = Private.LANGUAGES
API.NewLocale = Private.NewLocale
API.SetLanguage = Private.SetLanguage
API.OnLanguageSet = Private.OnLanguageSet
API.GetLanguage = Private.GetLanguage
API.GetClientLanguage = Private.GetClientLanguage

-- Constants --

API.Enum = Private.Enum
API.MELEE_RANGE_ABILITIES = Private.MELEE_RANGE_ABILITIES
API.RANGED_RANGE_ABILITIES = Private.RANGED_RANGE_ABILITIES
API.MOVEMENT_SPELLS = Private.MOVEMENT_SPELLS
API.CLASS_INTERRUPTS = Private.CLASS_INTERRUPTS
API.PET_CLASSES = Private.PET_CLASSES
API.ITEM_SLOTS = Private.ITEM_SLOTS
API.ITEM_SLOT_INFO = Private.ITEM_SLOT_INFO
API.ITEM_TRACKS = Private.ITEM_TRACKS
API.ITEM_TRACK_INFO = Private.ITEM_TRACK_INFO
API.ITEM_VENOMFORGED = Private.ITEM_VENOMFORGED
API.PVP_ITEM_TRACKS = Private.PVP_ITEM_TRACKS
API.CRAFTED_ITEM_MARKER = Private.CRAFTED_ITEM_MARKER
API.CRAFTED_ITEM_TRACKS = Private.CRAFTED_ITEM_TRACKS
API.BATTLE_ART_ITEMS = Private.BATTLE_ART_ITEMS
API.ITEM_DIFFICULTY_TAGS = Private.ITEM_DIFFICULTY_TAGS
API.GEM_SOCKET_TYPES = Private.GEM_SOCKET_TYPES
API.SOCKETABLE_SLOTS = Private.SOCKETABLE_SLOTS
API.ENCHANT_SLOT_KEYWORDS = Private.ENCHANT_SLOT_KEYWORDS
