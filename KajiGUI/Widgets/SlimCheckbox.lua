--[[
# SlimCheckbox

* A compact square tick for dense grids and lists, drawn like the Checkbox knob: accent fill, checkmark
  and glow fade in when checked. An optional label sits to its right. The callback fires on the click.
* `tristate = true` steps through off, must be and must not be: left click forward, right click back, the value is
  nil, true or false. Must not be is a cross on the error colour and the label follows both.
* `align = 'CENTER'` centres the box in its share of the row, for matrix cells without a label.

## Examples

    row:SlimCheckbox('Show on bars', {
        width = 0.5,
        value = db.Show,
        callback = function(checked) db.Show = checked end,
    })

    -- A label-less matrix cell with its own tooltip.
    row:SlimCheckbox(nil, {
        width = 0.12,
        align = 'CENTER',
        value = accepted[id] == true,
        tooltip = function(t) t:SetSpellByID(spellID) end,
        callback = function(checked) accepted[id] = checked end,
    })

    -- Must be, must not be or left out.
    row:SlimCheckbox('Mounted', {
        width = 0.5,
        tristate = true,
        value = db.Mounted,
        callback = function(value) db.Mounted = value end,
    })

--]]

---@class NRSKNUI
local Private = select(2, ...)
---@class Kaji
local Kaji = Private.Kaji
---@class KajiGUIInstanceMixin
local InstanceMixin = Kaji.InstanceMixin
local safecall = Kaji.safecall
local pixel = Private.Pixel

local CreateFrame = CreateFrame
local Mixin = Mixin
local floor = math.floor

local WIDGET_TYPE = "SlimCheckbox"
local BOX_SIZE = 16
local LABEL_GAP = 6

local L = Private.L

---@param value boolean
---@return string
local function DescribeValue(value)
    return value and L["On"] or L["Off"]
end

---@param value boolean?
---@return string
local function DescribeTriState(value)
    if value == nil then
        return L["Off"]
    end
    return value and L["Must be"] or L["Must not be"]
end

---@class KajiGUISlimCheckboxMixin : Frame
---@field gui KajiGUIInstance
---@field box KajiTickBox
---@field label FontString
---@field button Button
---@field _state boolean?
---@field _tristate boolean
---@field _hovered boolean
---@field _align 'LEFT'|'CENTER'
---@field _callback? fun(checked: boolean?)
local SlimCheckboxMixin = {}

---@param instant? boolean
function SlimCheckboxMixin:ApplyState(instant)
    local theme = self.gui.theme
    local state = self._state
    -- kept through off, so a cross fades out as a cross
    if self._tristate and state ~= nil then
        self.box:SetNegated(state == false)
    end
    self.box:SetChecked(state ~= nil and (state or self._tristate), instant)
    self.box:SetHovered(self._hovered, instant)

    local text = state and theme.textPrimary or theme.textSecondary
    if self._tristate and state ~= nil then
        text = state and theme.accent or theme.error
    end
    self.label:SetTextColor(text[1], text[2], text[3], 1)
    Kaji.PaintMixed(self, self.label)
end

---Left steps forward, right steps back: off, must be, must not be.
---@param back boolean
function SlimCheckboxMixin:StepTriState(back)
    local state = self._state
    if back then
        if state == nil then
            self._state = false
        elseif state == false then
            self._state = true
        else
            self._state = nil
        end
    elseif state == nil then
        self._state = true
    elseif state == true then
        self._state = false
    else
        self._state = nil
    end
end

---Places the box for the current alignment, only final once the row has resolved the width.
---Offsets are floored to whole pixels: centring an odd leftover lands the box on a half pixel,
---and its 1px border and inset fill then round unevenly from one cell to the next.
---@param width? number
function SlimCheckboxMixin:LayoutContent(width)
    width = width or self:GetWidth()
    local mult = pixel.GetMult()
    local size = BOX_SIZE
    local x = 0
    if self._align == "CENTER" and width and width > size then
        x = floor((width - size) / 2 / mult) * mult
    end
    local y = floor((self:GetHeight() - size) / 2 / mult) * mult

    self.box:ClearAllPoints()
    pixel.SetPixelPoint(self.box, "TOPLEFT", self, "TOPLEFT", x, -y)
end

---@param width number
function SlimCheckboxMixin:OnLayout(width)
    self:LayoutContent(width)
end

---@param enabled boolean
function SlimCheckboxMixin:SetEnabled(enabled)
    self.box:SetEnabled(enabled)
    self:SetAlpha(enabled and 1 or 0.5)
    self.button:EnableMouse(enabled)
end

---@return boolean?
function SlimCheckboxMixin:GetValue()
    return self._state
end

---@param value boolean?
function SlimCheckboxMixin:SetValue(value)
    if self._tristate then
        self._state = value
    else
        self._state = value == true
    end
    self:ApplyState(true)
end

function SlimCheckboxMixin:UpdateColors()
    self.box:Repaint()
    self:ApplyState(true)
end

---@param parent Frame
---@param labelText? string
---@param config table
function SlimCheckboxMixin:OnAcquire(parent, labelText, config)
    self:SetParent(parent)
    self:ClearAllPoints()
    pixel.SetPixelHeight(self, config.height or BOX_SIZE + 4)
    self.explicitHeight = true

    -- mixed shows unticked, so a click ticks them all
    self._tristate = config.tristate == true
    if self._tristate then
        self._state = config.value
        if config.mixed then
            self._state = nil
        end
    else
        self._state = not config.mixed and config.value == true
    end
    self._hovered = false
    self._align = config.align == "CENTER" and "CENTER" or "LEFT"
    self._callback = config.callback

    self.label:SetText(labelText or "")
    self.label:SetShown(labelText ~= nil and labelText ~= "")
    Kaji.SetTooltip(self, self.gui, labelText, config.tooltip)
    Kaji.SetNotice(self, self.gui, self.label, config.notice)
    Kaji.SetMixed(self, config.mixed, self._tristate and DescribeTriState or DescribeValue)
    self.button:RegisterForClicks(self._tristate and "AnyUp" or "LeftButtonUp")

    self.button:EnableMouse(true)
    self.box:SetEnabled(true)
    self:SetAlpha(1)
    self:LayoutContent()
    self:UpdateColors()
    self:Show()

    if labelText then self.gui:RegisterSearchableWidget(self, labelText) end
end

function SlimCheckboxMixin:OnRelease()
    self._callback = nil
    self._state = false
    self._tristate = false
    self._hovered = false
    self.box:SetNegated(false)
    self.label:SetText("")
    Kaji.ClearTooltip(self)
end

---@class KajiGUISlimCheckbox : KajiGUISlimCheckboxMixin

---@class KajiGUISlimCheckboxConfig
---@field value? boolean
---@field callback? fun(checked: boolean?) nil only comes from a tristate one
---@field tristate? boolean nil, true or false, see the header
---@field align? 'LEFT'|'CENTER' where the box sits in its share of the row, LEFT by default
---@field height? number
---@field tooltip? any string, table or a filler function, see Kaji.SetTooltip
---@field notice? KajiGUINotice a marker after the label, see Kaji.SetNotice
---@field mixed? KajiGUIMixedEntry[] the things it edits disagree: unticked with a marked label, see Kaji.SetMixed

Kaji:RegisterWidgetType(WIDGET_TYPE, function(gui)
    local row = CreateFrame("Frame", nil, gui._poolHost) --[[@as KajiGUISlimCheckbox]]
    row.gui = gui

    local box = Kaji.CreateTickBox(gui, row, BOX_SIZE)
    row.box = box

    local label = row:CreateFontString(nil, "OVERLAY")
    pixel.SetPixelPoint(label, "LEFT", box, "RIGHT", LABEL_GAP, 0)
    pixel.SetPixelPoint(label, "RIGHT", row, "RIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    gui:ApplyFont(label, "normal")
    row.label = label

    -- The whole share clicks, box and label as one, so a matrix cell is an easy target.
    local button = CreateFrame("Button", nil, row)
    button:SetAllPoints(row)
    button:RegisterForClicks("LeftButtonUp")
    row.button = button

    Mixin(row, SlimCheckboxMixin)

    button:SetScript("OnClick", function(_, mouse)
        row._mixed = nil -- ApplyState below repaints the label plain
        if row._tristate then
            row:StepTriState(mouse == "RightButton")
        else
            row._state = not row._state
        end
        row:ApplyState()
        safecall(row._callback, row._state)
    end)
    button:SetScript("OnEnter", function()
        row._hovered = true
        row:ApplyState()
        Kaji.ShowTooltip(row)
    end)
    button:SetScript("OnLeave", function()
        row._hovered = false
        row:ApplyState()
        Kaji.HideTooltip()
    end)

    return row
end)

---@param parent Frame
---@param labelText? string
---@param config? KajiGUISlimCheckboxConfig
---@return KajiGUISlimCheckbox
function InstanceMixin:CreateSlimCheckbox(parent, labelText, config)
    return self:BuildWidget(WIDGET_TYPE, parent, labelText, config)
end
