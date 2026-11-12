---@class NRSKNUI
local Core = select(2, ...)

local type = type
local select = select
local pcall = pcall
local ipairs = ipairs
local error = error
local tostring = tostring
local CreateFrame = CreateFrame

local _G = _G

-- Banish --

local hiddenFrame = CreateFrame('Frame')
hiddenFrame:Hide()
Core.HiddenFrame = hiddenFrame

---Take an object off screen for good.
---Frames get a roleset, which also takes their Edit Mode overlay; the rest are reparented.
---@param object Frame|string the frame (or its global name); a traversed child may be a texture
---@param ... string? keys to walk down first, e.g. 'Inset'
local function Banish(object, ...)
    if type(object) == 'string' then
        object = _G[object]
    end
    for index = 1, select('#', ...) do
        object = object and object[select(index, ...)]
    end
    if not object then return end

    if object.HideBase then
        -- Edit Mode overrides Hide and keeps the original here
        object:HideBase(true)
    else
        object:Hide()
    end
    if object.EnableMouse then
        object:EnableMouse(false)
    end
    if object.UnregisterAllEvents then
        object:UnregisterAllEvents()
        -- hides secure template based objects too
        object:SetAttribute('statehidden', true)
    end

    -- nothing below is needed once a roleset is on
    if object.SetRolesets then
        object:SetRolesets('alwaysBlocked')
        return
    end

    -- for Blizzard objects that respect user placement
    if object.SetUserPlaced then
        pcall(object.SetUserPlaced, object, true)
        pcall(object.SetDontSavePosition, object, true)
    end
    object:SetParent(hiddenFrame)
end

-- Strip --

local ACTIONS = {
    -- the region stays live, so a state-driven frame can SetAtlas it again
    Clear = function(region)
        region:SetTexture(nil)
        region:SetAtlas('')
    end,
    -- the art stays live, for frames that re-set their textures on state changes
    Alpha = function(region)
        region:SetAlpha(0)
    end,
    -- clear and hide: alpha 0 survives Blizzard re-setting the atlas, so the art can't come back
    ClearHide = function(region)
        region:SetTexture(nil)
        region:SetAtlas('')
        region:SetAlpha(0)
    end,
    Hide = function(region)
        region:Hide()
        region:SetAlpha(0)
    end,
    -- hide and block Show, for frames that keep showing their art again
    Kill = function(region)
        region:Hide()
        region.Show = region.Hide
    end,
}

-- children that commonly carry Blizzard's frame art, walked by 'Keyed'
local ART_CHILD_KEYS = {
    'Bg', 'BG', 'TitleBg', 'TopTileStreaks', 'Background', 'background', 'NineSlice', 'Inset', 'inset',
    'InsetFrame', 'LeftInset', 'RightInset', 'PortraitContainer', 'TitleContainer', 'PortraitOverlay',
    'ArtOverlayFrame', 'Border', 'border', 'BorderFrame', 'bottomInset', 'BottomInset', 'bgLeft', 'bgRight',
    'FilligreeOverlay', 'Portrait', 'portrait', 'ScrollFrameBorder', 'ScrollUpBorder', 'ScrollDownBorder',
}

---@param region Texture
---@param mode string?
---@param picked table<string, boolean>?
---@param action fun(region: Texture)
local function StripRegion(region, mode, picked, action)
    if mode == 'Layer' and not picked[region:GetDrawLayer()] then return end
    if mode == 'Atlas' and not picked[region:GetAtlas()] then return end

    action(region)
end

---Strip Blizzard art off a frame or texture; regions flagged `NUINoStrip` are skipped.
---@param object Frame|Texture|string the frame, texture or a global name
---@param mode string? nil, 'Alpha', 'ClearHide', 'Kill', 'Keyed', 'Layer' or 'Atlas' (Docs/API.md)
---@param arg string|string[]? 'Keyed': the action; 'Layer' / 'Atlas': the layer(s) or atlas(es)
local function StripTextures(object, mode, arg)
    if type(object) == 'string' then
        object = _G[object]
    end
    if not object then return end

    local actionName, picked = mode, nil
    if mode == 'Keyed' then
        actionName = arg
    elseif mode == 'Layer' or mode == 'Atlas' then
        actionName = 'Hide'
        picked = {}
        if type(arg) == 'table' then
            for _, key in ipairs(arg) do
                picked[key] = true
            end
        else
            picked[arg] = true
        end
    end
    local action = ACTIONS[actionName or 'Clear']
    if not action then
        error('NCStripTextures: unknown action ' .. tostring(actionName), 2)
    end

    if object:IsObjectType('Texture') then
        ---@cast object Texture
        StripRegion(object, mode, picked, action)
        return
    end

    if mode == 'Keyed' then
        local name = object.GetName and object:GetName()
        for _, key in ipairs(ART_CHILD_KEYS) do
            local child = object[key] or (name and _G[name .. key])
            if child and child.NCStripTextures then
                StripTextures(child, 'Keyed', arg)
            end
        end
    end
    if not object.GetRegions then return end

    ---@cast object Frame
    for _, region in ipairs({ object:GetRegions() }) do
        if region:IsObjectType('Texture') and not region.NUINoStrip then
            StripRegion(region, mode, picked, action)
        end
    end
end

local methods = Core.FrameMethods
methods.NCBanish = Banish
methods.NCStripTextures = StripTextures
