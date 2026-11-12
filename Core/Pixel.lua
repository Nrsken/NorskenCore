---@class NRSKNUI
local Core = select(2, ...)
---@class NorskenPixel
local Pixel = {}
Core.Pixel = Pixel

local CreateFrame = CreateFrame
local GetPhysicalScreenSize = GetPhysicalScreenSize
local InCombatLockdown = InCombatLockdown
local canaccessvalue = canaccessvalue
local issecrettable = issecrettable
local hooksecurefunc = hooksecurefunc
local floor = math.floor
local abs = math.abs
local type = type
local pcall = pcall

local UIParent = UIParent

local physH, perfectPixel, bestPixel
local mult = 1

local function Recompute()
    -- a display mode change can briefly report 0, keep the last good height
    local _, h = GetPhysicalScreenSize()
    physH = h and h > 0 and h or physH or 768
    perfectPixel = 768 / physH

    bestPixel = perfectPixel
    if bestPixel > 1.15 then
        bestPixel = 1.15
    elseif bestPixel < 0.4 then
        bestPixel = 0.4
    end

    local scale = UIParent:GetEffectiveScale()
    if not canaccessvalue(scale) then return end

    mult = perfectPixel / scale

    -- a perfect scale is stored as a float, that noise must not reach every coordinate
    if abs(mult - 1) < 0.0005 then
        mult = 1
    end
end

Recompute()

local watcher = CreateFrame('Frame')
watcher:RegisterEvent('UI_SCALE_CHANGED')
watcher:RegisterEvent('DISPLAY_SIZE_CHANGED')
watcher:SetScript('OnEvent', Recompute)

-- SetScale fires no UI_SCALE_CHANGED, this catches it whoever calls it
hooksecurefunc(UIParent, 'SetScale', Recompute)

---The auto scale factor for the current resolution, clamped to a sane range.
---@return number
local function GetBestPixelSize()
    return bestPixel
end

---The raw perfect-pixel factor (768 / physical height), unclamped.
---@return number
local function GetPerfectPixel()
    return perfectPixel
end

---The pixel-grid multiplier. 1 means coordinates already land on whole pixels.
---@return number
local function GetMult()
    return mult
end

---Snaps a coordinate to the nearest physical pixel. At mult 1 the grid is whole units, so
---measured values (GetWidth after a drag) still need rounding, never early-out on mult == 1.
---@param value number
---@return number
local function ToPixelGrid(value)
    if value == 0 then
        return value
    end
    return floor(value / mult + 0.5) * mult
end

---Turn off Blizzard's own grid snapping / texel bias so our pixel math is authoritative.
---Works on textures directly and on status bars via their fill texture. Runs once per object.
---@param object Frame|Texture|FontString|MaskTexture|Line
local function SetPixelSnap(object)
    if not object or object.nuiPixelSnapDisabled then return end
    if (issecrettable and issecrettable(object)) or (object.IsForbidden and object:IsForbidden()) then return end

    local target = object
    if not object.SetSnapToPixelGrid and object.GetStatusBarTexture then
        target = object:GetStatusBarTexture()
    end

    if type(target) == 'table' and target.SetSnapToPixelGrid then
        target:SetSnapToPixelGrid(false)
        target:SetTexelSnappingBias(0)
    end

    -- 12.1.5+: native layout rounding, protected so it waits out combat.
    if object.SetRoundLayoutToNearestPixel and not InCombatLockdown() then
        object:SetRoundLayoutToNearestPixel(true)
    end

    object.nuiPixelSnapDisabled = true
end

---Sets the size of a frame to the nearest pixel grid.
---@param object Frame|Texture|FontString|MaskTexture
---@param width number
---@param height number
---@param ... any Additional arguments to pass to SetSize
local function SetPixelSize(object, width, height, ...)
    local w = ToPixelGrid(width)

    object:SetSize(w, height and ToPixelGrid(height) or w, ...)
end

---Sets the width of a frame to the nearest pixel grid.
---@param object Frame|Texture|FontString|MaskTexture
---@param width number
---@param ... any Additional arguments to pass to SetWidth
local function SetPixelWidth(object, width, ...)
    object:SetWidth(ToPixelGrid(width), ...)
end

---Sets the height of a frame to the nearest pixel grid.
---@param object Frame|Texture|FontString|MaskTexture
---@param height number
---@param ... any Additional arguments to pass to SetHeight
local function SetPixelHeight(object, height, ...)
    object:SetHeight(ToPixelGrid(height), ...)
end

---Sets the point of a frame to the nearest pixel grid.
---@param object Frame|Texture|FontString|MaskTexture
---@param point string
---@param arg2 Frame|Texture|FontString|MaskTexture|string|number? The frame (or its global name) to anchor to, or a number for xOffset if omitted.
---@param arg3 string|number? The point on the anchor frame to attach to, or a number for yOffset if omitted.
---@param arg4 number? The xOffset, or nil if omitted.
---@param arg5 number? The yOffset, or nil if omitted.
---@param ... any Additional arguments to pass to SetPoint
local function SetPixelPoint(object, point, arg2, arg3, arg4, arg5, ...)
    if not arg2 then arg2 = object:GetParent() end
    if type(arg2) == 'number' then
        arg2 = ToPixelGrid(arg2)
    end
    if type(arg3) == 'number' then
        arg3 = ToPixelGrid(arg3)
    end
    if type(arg4) == 'number' then
        arg4 = ToPixelGrid(arg4)
    end
    if type(arg5) == 'number' then
        arg5 = ToPixelGrid(arg5)
    end

    -- Overloaded passthrough: arg2/arg3 may be a relativeTo frame + relativePoint, or the
    -- short x/y offset form. The union is intentional and can't match SetPoint's typed overloads.
    ---@diagnostic disable-next-line: param-type-mismatch
    object:SetPoint(point, arg2, arg3, arg4, arg5, ...)
end

---Sets the point of a frame to the nearest pixel grid, inset from another frame's corners.
---@param object Frame|Texture|FontString|MaskTexture
---@param anchor Frame|Texture|FontString|MaskTexture
---@param xOffset number
---@param yOffset number
---@param anchor2 Frame|Texture|FontString|MaskTexture? Optional second anchor frame for the bottom-right corner. Defaults to `anchor`.
local function SetPixelInside(object, anchor, xOffset, yOffset, anchor2)
    anchor = anchor or object:GetParent()
    local x = ToPixelGrid(xOffset or 1)
    local y = ToPixelGrid(yOffset or 1)

    -- some Blizzard frames error on ClearAllPoints while they have no points yet
    if pcall(object.GetPoint, object) then
        object:ClearAllPoints()
    end
    SetPixelSnap(object)
    object:SetPoint('TOPLEFT', anchor, 'TOPLEFT', x, -y)
    object:SetPoint('BOTTOMRIGHT', anchor2 or anchor, 'BOTTOMRIGHT', -x, y)
end

-- Fractional position of each anchor point within a frame.
-- x and y, where 0 = left/bottom, 1 = right/top.
local POINT_FRACTION = {
    TOPLEFT     = { 0, 1 },
    TOP         = { 0.5, 1 },
    TOPRIGHT    = { 1, 1 },
    LEFT        = { 0, 0.5 },
    CENTER      = { 0.5, 0.5 },
    RIGHT       = { 1, 0.5 },
    BOTTOMLEFT  = { 0, 0 },
    BOTTOM      = { 0.5, 0 },
    BOTTOMRIGHT = { 1, 0 },
}

---Sets the point of a frame to the nearest pixel grid, snapping the resulting edges onto the pixel grid.
---@param object Frame|Texture|FontString|MaskTexture
---@param point string
---@param relativeTo Frame|Texture|FontString|MaskTexture|string? Anchor frame or its global name. Defaults to the object's parent.
---@param relativePoint string? Point on the anchor frame. Defaults to `point`.
---@param offsetX number? Defaults to 0.
---@param offsetY number? Defaults to 0.
local function SetGridPoint(object, point, relativeTo, relativePoint, offsetX, offsetY)
    if type(relativeTo) == 'string' then relativeTo = _G[relativeTo] end
    relativeTo = relativeTo or object:GetParent()
    relativePoint = relativePoint or point
    offsetX = offsetX or 0
    offsetY = offsetY or 0

    local objF = POINT_FRACTION[point]
    local relF = POINT_FRACTION[relativePoint]

    local relLeft = objF and relF and Core:SafeValue(relativeTo:GetLeft())
    local relBottom = relLeft and Core:SafeValue(relativeTo:GetBottom())
    local relW = relBottom and Core:SafeValue(relativeTo:GetWidth())
    local relH = relW and Core:SafeValue(relativeTo:GetHeight())

    -- Unknown point or secret/unlaid-out geometry, fall back to a plain offset-rounded placement.
    if not relH then
        SetPixelPoint(object, point, relativeTo, relativePoint, offsetX, offsetY)
        return
    end

    -- Where the object's bottom-left lands with this anchor, derived from the relative frame's geometry.
    local objLeft = relLeft + relF[1] * relW - objF[1] * object:GetWidth() + offsetX
    local objBottom = relBottom + relF[2] * relH - objF[2] * object:GetHeight() + offsetY

    -- Correction pulling that edge onto the nearest grid line.
    local dx = floor(objLeft / mult + 0.5) * mult - objLeft
    local dy = floor(objBottom / mult + 0.5) * mult - objBottom
    object:SetPoint(point, relativeTo, relativePoint, offsetX + dx, offsetY + dy)
end

-- what InjectAPI puts on every region as the NC methods
local methods = Core.FrameMethods
methods.NCDisablePixelSnap = SetPixelSnap
methods.NCSetSize = SetPixelSize
methods.NCSetWidth = SetPixelWidth
methods.NCSetHeight = SetPixelHeight
methods.NCSetPoint = SetPixelPoint
methods.NCSetInside = SetPixelInside
methods.NCSetGridPoint = SetGridPoint

-- the grid values and number maths; placing a region goes through the NC methods
Pixel.ToPixelGrid = ToPixelGrid
Pixel.GetMult = GetMult
Pixel.GetPerfectPixel = GetPerfectPixel
Pixel.GetBestPixelSize = GetBestPixelSize
