---@class NRSKNUI
local Private = select(2, ...)

local LibStub = LibStub

LibStub('AceAddon-3.0'):NewAddon(Private, 'NorskenCore', 'AceEvent-3.0')

Private.Libs = {
    LSM = LibStub('LibSharedMedia-3.0'),
    LS = LibStub('LibSpecialization'),
} --[[@as NRSKNUI.Libraries]]

-- KajiGUI's shared state: Core files hand it things before KajiGUI loads (Anchors, LoadConditions)
---@type Kaji
Private.Kaji = {}

Private.ClearTexture = 0
Private.WhiteTexture = 'Interface\\Buttons\\WHITE8X8'
Private.GlobalZoom = 0.3

Private.Restricted = Private:NewModule('Restricted', 'AceEvent-3.0')
