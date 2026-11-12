---@class NRSKNUI
local Core = select(2, ...)

local ipairs = ipairs
local Mixin = Mixin
local CreateFrame = CreateFrame

-- not frame:CreateTexture, aura preview dummies replace theirs with a pool (AuraPreview.lua)
local CreateTexture = CreateFrame('Frame').CreateTexture

-- Mixins --

-- two halves, so bordering a Blizzard frame keeps its own SetBackgroundColor

---@class PublicBackdropMixin : Frame
---@field backdropBackground Texture?
---@field Borders Texture[]?

---@type PublicBackdropMixin
local BackgroundMixin = {}

---@type PublicBackdropMixin
local BorderMixin = {}

---@param r number
---@param g number
---@param b number
---@param a? number
function BackgroundMixin:SetBackgroundColor(r, g, b, a)
    local background = self.backdropBackground
    if not background then return end

    if self._backgroundTexture then
        background:SetTexture(self._backgroundTexture)
        background:SetVertexColor(r, g, b, a)
    else
        background:SetColorTexture(r, g, b, a)
        background:SetVertexColor(1, 1, 1, 1)
    end
end

---nil goes back to a flat fill. Applies on the next SetBackgroundColor, so call this first.
---@param path string?
function BackgroundMixin:SetBackgroundTexture(path)
    self._backgroundTexture = path
end

---@param r number
---@param g number
---@param b number
---@param a? number
function BorderMixin:SetBorderColor(r, g, b, a)
    if not self.Borders then return end

    for _, edge in ipairs(self.Borders) do
        edge:SetVertexColor(r, g, b, a)
    end
end

---@param db table
function BackgroundMixin:UpdateBackdropFromDB(db)
    if self.backdropBackground then
        local background = Core:GetBackdropColor(db, 'BackgroundColor')
        self:SetBackgroundColor(background[1], background[2], background[3], background[4])
    end
    if self.Borders then
        local border = Core:GetBorderColor(db)
        self:SetBorderColor(border[1], border[2], border[3], border[4])
    end
end

---@param shown boolean
function BackgroundMixin:SetBackdropShown(shown)
    if self.backdropBackground then
        self.backdropBackground:SetShown(shown)
    end
    if self.Borders then
        self:SetBorderShown(shown)
    end
end

---@param shown boolean
function BorderMixin:SetBorderShown(shown)
    if not self.Borders then return end

    for _, edge in ipairs(self.Borders) do
        edge:SetShown(shown)
    end
end

---@param parent Frame
function BorderMixin:SetBorderParent(parent)
    if not self.Borders then return end

    for _, edge in ipairs(self.Borders) do
        edge:SetParent(parent)
    end
end

---@param layer DrawLayer
---@param sublevel number?
function BorderMixin:SetBorderLayer(layer, sublevel)
    if not self.Borders then return end

    for _, edge in ipairs(self.Borders) do
        edge:SetDrawLayer(layer, sublevel)
    end
end

-- Builders --

---The background, 0.8 black until coloured. Does nothing on a frame that has one.
---@param frame Frame
---@param inset number? from the frame's edges, default 1 so edges at 0 sit around it
---@param insetY number? vertical inset, default `inset`; negatives sit outside the frame
local function CreateBackdrop(frame, inset, insetY)
    if frame.backdropBackground then return end
    ---@cast frame Frame & PublicBackdropMixin
    Mixin(frame, BackgroundMixin, BorderMixin)

    local x = inset or 1
    local y = insetY or x
    local background = CreateTexture(frame, nil, 'BACKGROUND')
    background:NCSetPoint('TOPLEFT', frame, 'TOPLEFT', x, -y)
    background:NCSetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -x, y)
    background:NCDisablePixelSnap()
    frame.backdropBackground = background
    frame:SetBackgroundColor(0, 0, 0, 0.8)
end

---@param frame Frame
---@param keepPixelSnap boolean?
---@return Texture
local function CreateEdge(frame, keepPixelSnap)
    local edge = CreateTexture(frame, nil, 'OVERLAY')
    edge:SetTexture(Core.WhiteTexture)
    if not keepPixelSnap then
        edge:NCDisablePixelSnap()
    end
    return edge
end

---Four 1px edges above the frame's art, black until coloured. Once per frame.
---Placed by anchors only, so they work on a frame whose size is secret.
---@param frame Frame
---@param inset number? from the frame's edges, default 0
---@param keepPixelSnap boolean? leave Blizzard's grid snapping on, for edges on a frame we don't position
local function AddBorders(frame, inset, keepPixelSnap)
    if not frame or frame.Borders then return end
    ---@cast frame Frame & PublicBackdropMixin
    Mixin(frame, BorderMixin)

    local i = inset or 0
    local top = CreateEdge(frame, keepPixelSnap)
    top:NCSetPoint('TOPLEFT', frame, 'TOPLEFT', i, -i)
    top:NCSetPoint('TOPRIGHT', frame, 'TOPRIGHT', -i, -i)
    top:NCSetHeight(1)

    local bottom = CreateEdge(frame, keepPixelSnap)
    bottom:NCSetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', i, i)
    bottom:NCSetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -i, i)
    bottom:NCSetHeight(1)

    -- sides fit between top and bottom, so translucent corners aren't drawn twice
    local left = CreateEdge(frame, keepPixelSnap)
    left:NCSetPoint('TOPLEFT', top, 'BOTTOMLEFT')
    left:NCSetPoint('BOTTOMLEFT', bottom, 'TOPLEFT')
    left:NCSetWidth(1)

    local right = CreateEdge(frame, keepPixelSnap)
    right:NCSetPoint('TOPRIGHT', top, 'BOTTOMRIGHT')
    right:NCSetPoint('BOTTOMRIGHT', bottom, 'TOPRIGHT')
    right:NCSetWidth(1)

    frame.Borders = { top, left, bottom, right }
    frame:SetBorderColor(0, 0, 0, 1)
end

-- an AuraButton never gets the injected methods, so it takes its backdrop through these
Core.CreateBackdrop = CreateBackdrop
Core.AddBorders = AddBorders

---@param frame Frame
---@return boolean
local function HasBackdrop(frame)
    return frame.backdropBackground ~= nil or frame.Borders ~= nil
end

-- Fit to text --

---Size a backdrop to fit a FontString's widest possible text.
---@param self Frame
---@param fontString FontString measured; after a resize it holds the measuring text
---@param text string the exact (possibly coloured) text about to be shown
---@param padX number added to each side
---@param padY number added to each side
---@return boolean resized the caller has to set its text again
local function FitBackdropToText(self, fontString, text, padX, padY)
    -- strip colour escapes and mask digits: two values with the same skeleton keep one width
    local bare = text:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
    local key = (bare:gsub('%d', '#'))
    if key == self.NUIBackdropShape then return false end
    self.NUIBackdropShape = key

    -- the widest glyph in every digit slot bounds this shape, so it can't overflow
    local worst = (bare:gsub('%d', fontString:GetWidestDigit()))
    fontString:SetText(worst)
    self:NCSetSize(fontString:GetStringWidth() + padX * 2, fontString:GetStringHeight() + padY * 2)
    return true
end

local methods = Core.FrameMethods
methods.NCCreateBackdrop = CreateBackdrop
methods.NCAddBorders = AddBorders
methods.NCHasBackdrop = HasBackdrop
methods.NCFitBackdropToText = FitBackdropToText
