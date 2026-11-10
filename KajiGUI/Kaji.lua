--[[
# KajiGUI

* NorskenCore's GUI: windows, sidebars, pages, cards and widgets with consistent theming and behavior.
* Every addon gets its own instance from `NewAddon` as `addon.GUI`, so two addons never share theme or state.
* Helpers any addon can use (pixel snapping, animations) live in Core, not here.

For comment styling I am using Better Comments extension for VSCode, with a custom theme for API tags:
{
    "tag": "API",
    "color": "#C678DD",
    "strikethrough": false,
    "underline": false,
    "backgroundColor": "transparent",
    "bold": false,
    "italic": false
},
{
    "tag": "A!",
    "color": "#C678DD",
    "strikethrough": false,
    "underline": false,
    "backgroundColor": "transparent",
    "bold": false,
    "italic": false
}

## Example

    local window = addon.GUI:CreateGUIWindow({ name = 'MyAddonGUI', defaultPage = 'general' })

    addon.GUI:RegisterPage('general', {
        build = function(page)
            page:Card('Options', 'all'):Row(40):Checkbox('Enable', {
                value = db.Enabled,
                callback = function(v) db.Enabled = v end
            })
        end
    })

--]]

---@class NRSKNUI
local Private = select(2, ...)
---@class Kaji
---@field windows KajiGUIWindowMixin[] every settings window, see Window.lua
---@field beforeWindowShow fun(window: KajiGUIWindowMixin)? runs before any window shows, Anchors.lua sets it
---@field loadStates table? the load conditions' state list, LoadConditions.lua hands it over
local Kaji = Private.Kaji

local Mixin = Mixin

-- Method table shared by every instance. Every file that adds methods re-declares
-- `---@class KajiGUIInstanceMixin` on its own local, so each definition's own
-- @param/@return annotations register on the class instead of being listed here.
-- The instance's own data is listed here, since the methods read it through `self`.
---@class KajiGUIInstanceMixin
---@field services KajiGUIServices
---@field overlay Frame?
---@field theme KajiTheme
---@field presets table
---@field presetNames string[]
---@field colorKeys table[]
---@field defaultPreset string
---@field classColorProvider (fun(): ColorMixin?)?
---@field _storeAccessor (fun(): table?)?
---@field _acquired table<table, string> widget -> its type, while in use
---@field _themeCallbacks table<function, true>
---@field _classColorKeys table?
---@field _colorKeyList table?
---@field _pools table
---@field _poolHost Frame
---@field _pages table?
---@field _flashContainer Frame?
---@field _flashToken number?
---@field _frameChooser table?
---@field _contextMenu table? the open menu: its frame and armed state
---@field _activePrompt Frame?
---@field _activeDropdown Frame?
---@field _dropdownPool table?
---@field _noticesSeen table?
---@field _releasedHoverKey any
---@field _releasedHoverCard any
Kaji.InstanceMixin = {}
local InstanceMixin = Kaji.InstanceMixin

-- every premade card registers itself here, Page.lua builds them by name
Kaji.premadeCards = {}

---Systems that can be provided by the consuming addon to extend the GUI's functionality.
---@class KajiGUIServices
---@field positionSync? { Changed: fun() } notified when the GUI edits a position, so the host's mover overlay can follow
---@field frameChooser? table the addon's frame picker (for PositionCard)
---@field registerSearchable? fun(widget: Frame, label: string) host search-index hook

---@class KajiGUIOptions
---@field theme? table overrides merged over the default theme
---@field positionSync? { Changed: fun() }
---@field frameChooser? table
---@field registerSearchable? fun(widget: Frame, label: string)
---@field overlay? Frame high-strata frame open dropdowns reparent to (defaults to UIParent)
---@field store? fun(): table? accessor to the host's persisted theme table (mode/selectedPreset/customColors/fonts)
---@field classColorProvider? fun(): ColorMixin? the active class colour for class mode, nil while there's none
---@field presets? table override the bundled preset set (defaults to Kaji.THEME_PRESETS)
---@field presetNames? string[] override the ordered preset name list (defaults to Kaji.THEME_PRESET_NAMES)
---@field colorKeys? table[] override the color-key editor metadata (defaults to Kaji.THEME_COLOR_KEYS)
---@field defaultPreset? string preset used before the store exists / on reset (defaults to "NUI Neon")

-- an instance is the mixin plus its data, one type for both
---@alias KajiGUIInstance KajiGUIInstanceMixin

---Creates an isolated GUI instance for an addon.
---@param opts? KajiGUIOptions
---@return KajiGUIInstance
function Kaji:New(opts)
    opts                        = opts or {}

    ---@type KajiGUIInstance
    local instance              = Mixin({}, InstanceMixin)

    ---@type KajiGUIServices
    instance.services           = {
        positionSync = opts.positionSync,
        frameChooser = opts.frameChooser,
        registerSearchable = opts.registerSearchable,
    }
    instance.overlay            = opts.overlay

    -- Theme engine wiring.
    instance.presets            = opts.presets or Kaji.THEME_PRESETS
    instance.presetNames        = opts.presetNames or Kaji.THEME_PRESET_NAMES
    instance.colorKeys          = opts.colorKeys or Kaji.THEME_COLOR_KEYS
    instance.defaultPreset      = opts.defaultPreset or "NUI Neon"
    instance._storeAccessor     = opts.store
    instance.classColorProvider = opts.classColorProvider

    instance:_InitTheme(opts.theme)
    instance:_InitPool()

    return instance
end
