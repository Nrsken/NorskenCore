---@class NRSKNUI
local Private = select(2, ...)
local L = Private.L

local ReloadUI = ReloadUI

---@class PromptOptions : KajiPromptOptions

---@param opts PromptOptions
function Private:CreatePrompt(opts)
    return self.GUI:Prompt(opts)
end

---@param title string
---@param text string
---@param label? string
function Private:CreateCopyDialog(title, text, label)
    return self.GUI:CopyDialog(title, text, label)
end

---@param reason? string
function Private:CreateReloadPrompt(reason)
    return self.GUI:Prompt({
        title = L["Reload Required"],
        text = reason or L["Would you like to reload your UI now?"],
        width = 340,
        onAccept = function() ReloadUI() end,
        acceptText = L["Reload Now"],
        cancelText = L["Later"],
    })
end
