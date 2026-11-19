---@class NorskenCore
local Core = select(2, ...)
_G.NorskenCore = Core

local LibStub = LibStub

-- Kept off the addon table so addons don't inherit Core's OnInitialize and OnEnable
Core.Ace = LibStub('AceAddon-3.0'):NewAddon('NorskenCore', 'AceEvent-3.0')

Core.Libs = {
    LSM = LibStub('LibSharedMedia-3.0'),
    LS = LibStub('LibSpecialization'),
} --[[@as NorskenCore.Libraries]]

-- KajiGUI's shared state, Core files fill it before KajiGUI loads
---@type Kaji
Core.Kaji = {}

-- Every widget's NC methods, filled by Pixel.lua and Frames/, injected by InjectAPI.lua
Core.FrameMethods = {}

Core.ClearTexture = 0
Core.WhiteTexture = 'Interface\\Buttons\\WHITE8X8'
Core.QuestionMarkTexture = 134400
Core.GlobalZoom = 0.3
Core.GCD_SPELL = 61304
