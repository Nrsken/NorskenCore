---@class NRSKNUI
local Private = select(2, ...)

local LibStub = LibStub

LibStub('AceAddon-3.0'):NewAddon(Private, 'NorskenCore', 'AceEvent-3.0')

Private.Libs = {
    KAJI = LibStub('LibKaji-1.0'),
    LSM = LibStub('LibSharedMedia-3.0'),
    LS = LibStub('LibSpecialization'),
} --[[@as NRSKNUI.Libraries]]

Private.ClearTexture = 0
Private.WhiteTexture = 'Interface\\Buttons\\WHITE8X8'
Private.GlobalZoom = 0.3

Private.Restricted = Private:NewModule('Restricted', 'AceEvent-3.0')
