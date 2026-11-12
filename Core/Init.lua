---@class NRSKNUI
local Core = select(2, ...)
_G.NorskenCore = Core

local LibStub = LibStub

-- off the addon table: addons would inherit Core's OnInitialize/OnEnable via __index
Core.Ace = LibStub('AceAddon-3.0'):NewAddon('NorskenCore', 'AceEvent-3.0')

Core.Libs = {
    LSM = LibStub('LibSharedMedia-3.0'),
    LS = LibStub('LibSpecialization'),
} --[[@as NRSKNUI.Libraries]]

-- KajiGUI's shared state: Core files hand it things before KajiGUI loads (Anchors, LoadConditions)
---@type Kaji
Core.Kaji = {}

-- every widget's NC methods: Pixel.lua and Frames/ fill it, InjectAPI.lua injects it
Core.FrameMethods = {}

Core.ClearTexture = 0
Core.WhiteTexture = 'Interface\\Buttons\\WHITE8X8'
Core.GlobalZoom = 0.3
