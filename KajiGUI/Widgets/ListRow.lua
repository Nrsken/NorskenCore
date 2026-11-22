--[[
# ListRow

A clickable list line, a short accent label left and its description right

## Example

    card:Row(20, 0):Stripe(even):ListRow('%1.p', {
        width = 1,
        text = 'Time left',
        callback = function() Insert('%1.p') end,
    })
--]]

---@class NorskenCore
local Core = select(2, ...)
---@class Kaji
local Kaji = Core.Kaji
---@class KajiGUIInstanceMixin
local InstanceMixin = Kaji.InstanceMixin
local Animations = Core.Animations
local safecall = Kaji.safecall

local CreateFrame = CreateFrame
local Mixin = Mixin

local WIDGET_TYPE = 'ListRow'
local LABEL_WIDTH = 96
local HOVER_ALPHA = 0.15
local GAP = 8

---@class KajiGUIListRowMixin : Button
---@field gui KajiGUIInstance
---@field label FontString
---@field text FontString
---@field hover Texture
---@field _hover number 0 at rest to 1 hovered
---@field _callback? fun()
---@field _animateHover fun(r: number, g: number, b: number, a: number)
---@field _setHover fun(r: number, g: number, b: number, a: number)
local ListRowMixin = {}

---@param p number 0 at rest to 1 hovered
function ListRowMixin:PaintHover(p)
    self._hover = p
    local accent = self.gui.theme.accent
    self.hover:SetColorTexture(accent[1], accent[2], accent[3], p * HOVER_ALPHA)
end

---@param enabled boolean
function ListRowMixin:SetEnabled(enabled)
    self:SetAlpha(enabled and 1 or 0.4)
    self:EnableMouse(enabled)
end

function ListRowMixin:UpdateColors()
    local theme = self.gui.theme
    local secondary, accent = theme.textSecondary, theme.accent
    self.label:SetTextColor(accent[1], accent[2], accent[3], 1)
    self.text:SetTextColor(secondary[1], secondary[2], secondary[3], 1)
    self:PaintHover(self._hover)
end

---@param parent Frame
---@param labelText string
---@param config KajiGUIListRowConfig
function ListRowMixin:OnAcquire(parent, labelText, config)
    self:SetParent(parent)
    self:ClearAllPoints()
    self:NCSetHeight(config.height or 20)

    self.label:NCSetWidth(config.labelWidth or LABEL_WIDTH)
    self.label:SetText(labelText)
    self.text:SetText(config.text or '')
    self._callback = config.callback
    Kaji.SetTooltip(self, self.gui, labelText, config.tooltip)

    self:EnableMouse(true)
    self:SetAlpha(1)
    self:UpdateColors()
    self:Show()
end

function ListRowMixin:OnRelease()
    self._callback = nil
    self.label:SetText('')
    self.text:SetText('')
    self._setHover(0, 0, 0, 0)
    self:PaintHover(0)
    Kaji.ClearTooltip(self)
end

---@class KajiGUIListRow : KajiGUIListRowMixin

---@class KajiGUIListRowConfig
---@field text? string the description after the label
---@field labelWidth? number room for the label, 96 by default
---@field height? number 20 by default
---@field tooltip? any
---@field callback? fun()

Kaji:RegisterWidgetType(WIDGET_TYPE, function(gui)
    ---@type KajiGUIListRow
    local row = Mixin(CreateFrame('Button', nil, gui._poolHost), ListRowMixin)
    row.gui = gui
    row._hover = 0

    -- As wide as the row's stripe, which reaches past the row by its padding
    local inset = gui.theme.paddingSmall
    local hover = row:CreateTexture(nil, 'BACKGROUND', nil, 1)
    hover:NCSetPoint('TOPLEFT', row, 'TOPLEFT', -inset, 0)
    hover:NCSetPoint('BOTTOMRIGHT', row, 'BOTTOMRIGHT', inset, 0)
    row.hover = hover

    local label = row:CreateFontString(nil, 'OVERLAY')
    label:NCSetPoint('LEFT', row, 'LEFT', GAP / 2, 0)
    label:SetJustifyH('LEFT')
    label:SetWordWrap(false)
    gui:ApplyFont(label, 'small')
    row.label = label

    local text = row:CreateFontString(nil, 'OVERLAY')
    text:NCSetPoint('LEFT', label, 'RIGHT', GAP, 0)
    text:NCSetPoint('RIGHT', row, 'RIGHT', -GAP / 2, 0)
    text:SetJustifyH('RIGHT')
    text:SetWordWrap(false)
    gui:ApplyFont(text, 'small')
    row.text = text

    row._animateHover, row._setHover = Animations:CreateColorAnimator(row, function(p) row:PaintHover(p) end,
        { 0, 0, 0, 0 }, gui.theme.animDuration)

    row:SetScript('OnEnter', function(self)
        self._animateHover(1, 0, 0, 0)
        Kaji.ShowTooltip(self)
    end)
    row:SetScript('OnLeave', function(self)
        self._animateHover(0, 0, 0, 0)
        Kaji.HideTooltip()
    end)
    row:SetScript('OnClick', function(self) safecall(self._callback) end)

    return row
end)

---@param parent Frame
---@param labelText string
---@param config? KajiGUIListRowConfig
---@return KajiGUIListRow
function InstanceMixin:CreateListRow(parent, labelText, config)
    return self:BuildWidget(WIDGET_TYPE, parent, labelText, config)
end
