---@class NRSKNUI
local Core = select(2, ...)
local L = Core.L

local C_AddOns = C_AddOns
local tonumber = tonumber
local format = string.format

--[[
Which Norsken addons this Core can run. Each one names the lowest API it works with in its TOC,
`## X-NorskenCore-Minimum`. Core warns when that's newer than it is or older than it still supports, it never blocks.
Raise API_VERSION when Core adds something an addon starts to need, MIN_SUPPORTED only when something is removed.
]]

local API_VERSION = 1
local MIN_SUPPORTED = 1

local PREFIX = '|cffe677f9Norsken|r|cffb3b3b3Core|r: '

---Warn in chat about every loaded addon built for a different Core.
function Core:CheckAddonVersions()
    for index = 1, C_AddOns.GetNumAddOns() do
        local minimum = C_AddOns.IsAddOnLoaded(index) and tonumber(C_AddOns.GetAddOnMetadata(index, 'X-NorskenCore-Minimum'))
        if minimum and minimum > API_VERSION then
            DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. format(L['%s needs a newer NorskenCore, update NorskenCore.'], (C_AddOns.GetAddOnInfo(index))))
        elseif minimum and minimum < MIN_SUPPORTED then
            local name = C_AddOns.GetAddOnInfo(index)
            DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. format(L['%s is too old for this NorskenCore, update %s.'], name, name))
        end
    end
end
