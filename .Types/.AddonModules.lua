---@meta

---@class NorskenCore
---@field L table<string, string> the strings in the picked language
---@field GUIFrame KajiGUIWindow? set by each addon
---@field MyGUID string the player's, never secret

---@class NorskenCore.ModuleBase
---@field SetEnabledState fun(self: NorskenCore.ModuleBase, state: boolean)
---@field db table
---@field Defaults table? profile defaults; ModulePrototype:OnInitialize registers a namespace for them
---@field dbKey string? the profile key the settings used to sit under, when it isn't the module name
---@field namespace AceDBObject-3.0? the module's own namespace inside NorskenUIDB
---@field IsEnabled fun(self: NorskenCore.ModuleBase): boolean
---@field SetEnabledState fun(self: NorskenCore.ModuleBase, state: boolean)

---@class AceModule : NorskenCore.ModuleBase
---@field ApplySettings fun(self: AceModule)

---@class RestrictedModule : NorskenCore.ModuleBase, AceEvent-3.0
