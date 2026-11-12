---@class NRSKNUI
local Core = select(2, ...)
local L = Core.L

local ReloadUI = ReloadUI

---@param reason? string
function Core:CreateReloadPrompt(reason)
    return self.GUI:Prompt({
        title = L["Reload Required"],
        text = reason or L["Would you like to reload your UI now?"],
        width = 340,
        onAccept = function() ReloadUI() end,
        acceptText = L["Reload Now"],
        cancelText = L["Later"],
    })
end
