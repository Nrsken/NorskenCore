---@class NRSKNUI
local Private = select(2, ...)

local LibStub = LibStub
local setmetatable = setmetatable

-- What the Norsken addons may use. Everything else in Core stays private, a line here is a promise.

---@class NorskenCoreAPI
local API = {}
_G.NorskenCore = API

-- Addons --

---Creates an addon object that reads this API through `__index`, so `object:RunWhenSafe()` works
---on the addon itself and what it stores of its own (`db`, `GUI`, `Theme`) stays its own.
---@param object table usually the addon's private table
---@param name string
---@param ... string AceAddon mixins
---@return table object
function API:NewAddon(object, name, ...)
    setmetatable(object, { __index = API }) -- AceAddon copies an existing metatable, this one survives
    return LibStub('AceAddon-3.0'):NewAddon(object, name, ...)
end

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
