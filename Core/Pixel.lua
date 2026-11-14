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
local pairs, setmetatable = pairs, setmetatable

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
---@param step number? a region's own pixel (GetStep), UIParent's by default
---@return number
local function ToPixelGrid(value, step)
    if value == 0 then
        return value
    end
    step = step or mult
    return floor(value / step + 0.5) * step
end

---Positions are stored in tenths: whole units skip pixels at most UI scales.
---@param value number
---@return number
local function ToTenths(value)
    return floor(value * 10 + 0.5) / 10
end

---@param scale number? an effective scale, nil while unreadable
---@return number
local function StepFor(scale)
    if not (scale and scale > 0) then
        return mult
    end
    local step = perfectPixel / scale
    -- an unscaled region can be a float step off UIParent's scale
    if abs(step / mult - 1) < 0.0001 then
        return mult
    end
    return step
end

---One physical pixel in a region's own units: mult unless it has a scale of its own.
---@param region Region|Frame
---@return number
local function GetStep(region)
    return StepFor(Core:SafeValue(region:GetEffectiveScale()))
end

---Moves an offset by whole physical pixels, from the pixel it sits on, in tenths.
---@param value number
---@param pixels number
---@param step number? the frame's pixel (GetStep), UIParent's by default
---@return number
local function StepOffset(value, pixels, step)
    step = step or mult
    -- from the tenths a slider shows, so its arrows and a nudge start on the same pixel
    return ToTenths((floor(ToTenths(value) / step + 0.5) + pixels) * step)
end

---A slider's arrows stepping an offset one physical pixel of region, as a nudge does.
---@param region (Region|Frame)? UIParent's pixel when nil
---@return fun(value: number, direction: number): number
local function PixelStepper(region)
    return function(value, direction)
        return StepOffset(value, direction, region and GetStep(region))
    end
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

-- what NCSetGridPoint placed against each region and what each one hangs from
local WEAK_KEYS = { __mode = 'k' }
local children = setmetatable({}, WEAK_KEYS)
local parentOf = setmetatable({}, WEAK_KEYS)

---Whether a remembered region still hangs where NCSetGridPoint put it and may move now.
---@return boolean movable
---@return boolean? moved placed some other way since, so it's no longer ours to move
local function StillPlaced(object, parent, spot)
    -- hung off secret geometry it reads back secret, this answer too
    local secret = object:IsAnchoringSecret()
    if not canaccessvalue(secret) or secret then return false end

    local point, relativeTo, _, x, y = object:GetPoint(1)
    if relativeTo ~= parent or point ~= spot.point then
        return false, true
    end
    -- same point on the same parent but other offsets: set by hand since
    if spot.setX and (abs(x - spot.setX) > 0.01 or abs(y - spot.setY) > 0.01) then
        return false, true
    end
    if InCombatLockdown() then
        local protected = object:IsProtected()
        return canaccessvalue(protected) and not protected or false
    end
    return true
end

---Where an anchor puts a region's bottom left before its offset; nil if unreadable.
---@param object Frame|Texture|FontString|MaskTexture
---@param point string
---@param relativeTo Region|Frame
---@param relativePoint string
---@return number? left in the object's own units
---@return number? bottom
---@return number? gridLeft the same spot snapped to a pixel
---@return number? gridBottom
---@return number? step the object's pixel, see GetStep
local function GetAnchorBase(object, point, relativeTo, relativePoint)
    local objF = POINT_FRACTION[point]
    local relF = POINT_FRACTION[relativePoint]
    local relLeft = objF and relF and Core:SafeValue(relativeTo:GetLeft())
    local relBottom = relLeft and Core:SafeValue(relativeTo:GetBottom())
    local relW = relBottom and Core:SafeValue(relativeTo:GetWidth())
    local relH = relW and Core:SafeValue(relativeTo:GetHeight())
    -- a text sized to its bounds reads secret while its text is
    local width = relH and Core:SafeValue(object:GetWidth())
    local height = width and Core:SafeValue(object:GetHeight())
    if not height then return end

    -- the relative frame measures in its own scale's units
    local scale = Core:SafeValue(object:GetEffectiveScale())
    local relScale = Core:SafeValue(relativeTo:GetEffectiveScale())
    local convert = 1
    if scale and relScale and scale > 0 and abs(relScale / scale - 1) >= 0.0001 then
        convert = relScale / scale
    end
    local left = (relLeft + relF[1] * relW) * convert - objF[1] * width
    local bottom = (relBottom + relF[2] * relH) * convert - objF[2] * height
    local step = StepFor(scale)
    -- ties go up: an odd size centred lands on .5 and size readback noise would pick the side
    return left, bottom, floor(left / step + 0.51) * step, floor(bottom / step + 0.51) * step, step
end

---Sets the point of a frame so its edges land on the pixel grid.
---@param object Frame|Texture|FontString|MaskTexture
---@param point string
---@param relativeTo Frame|Texture|FontString|MaskTexture|string? Anchor frame or its global name. Defaults to the object's parent.
---@param relativePoint string? Point on the anchor frame. Defaults to `point`.
---@param offsetX number? Defaults to 0.
---@param offsetY number? Defaults to 0.
local function SetGridPoint(object, point, relativeTo, relativePoint, offsetX, offsetY)
    if type(relativeTo) == 'string' then
        relativeTo = _G[relativeTo]
    end
    relativeTo = relativeTo or object:GetParent()
    relativePoint = relativePoint or point
    offsetX = offsetX or 0
    offsetY = offsetY or 0

    -- remembered, so moving the parent later places this again
    local previous = parentOf[object]
    if previous and previous ~= relativeTo and children[previous] then
        children[previous][object] = nil
    end
    parentOf[object] = relativeTo
    local siblings = children[relativeTo] or setmetatable({}, WEAK_KEYS)
    children[relativeTo] = siblings
    local spot = siblings[object] or {}
    siblings[object] = spot
    spot.point, spot.relativePoint, spot.x, spot.y = point, relativePoint, offsetX, offsetY
    spot.width, spot.height = Core:SafeValue(object:GetWidth()), Core:SafeValue(object:GetHeight())

    -- unknown point or secret or unlaid-out geometry: only the offsets get rounded
    local baseLeft, baseBottom, gridLeft, gridBottom, step = GetAnchorBase(object, point, relativeTo, relativePoint)
    if baseLeft and baseBottom and gridLeft and gridBottom then
        -- snapped apart: in the sum an offset's float noise picks which way a .5 rounds
        local x = gridLeft - baseLeft + ToPixelGrid(offsetX, step)
        local y = gridBottom - baseBottom + ToPixelGrid(offsetY, step)
        object:SetPoint(point, relativeTo, relativePoint, x, y)
        spot.setX, spot.setY = x, y
    else
        SetPixelPoint(object, point, relativeTo, relativePoint, offsetX, offsetY)
        spot.setX, spot.setY = nil, nil
    end

    -- each child's snap was worked out against where this was
    local own = children[object]
    if not own then return end

    for child, childSpot in pairs(own) do
        local movable, moved = StillPlaced(child, object, childSpot)
        if moved then
            own[child] = nil
        elseif movable then
            SetGridPoint(child, childSpot.point, object, childSpot.relativePoint, childSpot.x, childSpot.y)
        end
    end
end

---Places a region again where its last NCSetGridPoint put it, for after it resized.
---Does nothing while its size is the one it was placed at.
---@param object Frame|Texture|FontString|MaskTexture
local function RefreshGridPoint(object)
    local parent = parentOf[object]
    local spot = parent and children[parent] and children[parent][object]
    if not spot then return end

    local width, height = Core:SafeValue(object:GetWidth()), Core:SafeValue(object:GetHeight())
    if width and width == spot.width and height == spot.height then return end

    local movable, moved = StillPlaced(object, parent, spot)
    if moved then
        children[parent][object] = nil
    end
    if not movable then return end

    SetGridPoint(object, spot.point, parent, spot.relativePoint, spot.x, spot.y)
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
methods.NCRefreshGridPoint = RefreshGridPoint

-- the grid values and number maths; placing a region goes through the NC methods
Pixel.ToPixelGrid = ToPixelGrid
Pixel.GetStep = GetStep
Pixel.ToTenths = ToTenths
Pixel.StepOffset = StepOffset
Pixel.PixelStepper = PixelStepper
Pixel.GetMult = GetMult
Pixel.GetPerfectPixel = GetPerfectPixel
Pixel.GetBestPixelSize = GetBestPixelSize
Pixel.POINT_FRACTION = POINT_FRACTION
Pixel.GetAnchorBase = GetAnchorBase
