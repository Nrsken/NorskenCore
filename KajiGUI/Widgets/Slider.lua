--[[
# Slider

* A horizontal slider with stepper buttons and an editable value box.

## Examples

    row:Slider('Thickness', {
        width = 0.5,
        min = 3,
        max = 20,
        step = 1,
        value = db.Thickness,
        callback = function(v)
            db.Thickness = v
        end,
    })

`stepper` decides where an arrow click goes when it isn't `step`: a position in tenths whose
arrows move one physical pixel, `stepper = Pixel.PixelStepper(frame)`.

--]]

---@class NRSKNUI
local Core = select(2, ...)
---@class Kaji
local Kaji = Core.Kaji
---@class KajiGUIInstanceMixin
local InstanceMixin = Kaji.InstanceMixin
local Animations = Core.Animations
local safecall = Kaji.safecall
local pixel = Core.Pixel

local tostring = tostring
local tonumber = tonumber
local CreateFrame = CreateFrame
local Mixin = Mixin
local GetTime = GetTime
local ipairs, pairs = ipairs, pairs
local type = type
local rad = math.rad
local floor, max, min = math.floor, math.max, math.min

local C_Timer = C_Timer

local WIDGET_TYPE = "Slider"
local FILL_GLOW_HEIGHT = 4 -- halo above and below the fill
local THUMB_WIDTH, THUMB_HEIGHT = 19, 12
local THUMB_GLOW_REACH = 8 -- the small glow
local STEPPER_SIZE = 20
local THROTTLE_DELAY = 0.1

---@param value number?
---@return string
local function DescribeValue(value)
    return value and tostring(floor(value * 100 + 0.5) / 100) or ""
end

-- Drag --

local held -- the slider whose thumb is down
local afterDrag = {}

--[[
# Kaji.AfterSliderDrag

Runs `fn` now, or once the slider being dragged is let go: for work that only
needs a drag's last value, like a rebuild.

## Example

    Kaji.AfterSliderDrag(DrawTree)
--]]
---@param fn fun() the same function each time, so it runs once however often it's asked
function Kaji.AfterSliderDrag(fn)
    if not held then
        fn()
        return
    end
    afterDrag[fn] = true
end

---@class KajiGUISliderMixin : Frame
---@field gui KajiGUIInstance
---@field label FontString
---@field slider Slider
---@field sliderBG Frame|BackdropTemplate
---@field fillBar StatusBar
---@field fillGlow Texture[] halo above and below the fill
---@field thumb Texture
---@field thumbFrame Frame|BackdropTemplate
---@field thumbFrameBG Frame|BackdropTemplate
---@field leftStepper Button
---@field rightStepper Button
---@field valueContainer Frame|BackdropTemplate
---@field valueEdit EditBox
---@field _step number
---@field _stepper? fun(value: number, direction: number): number see the config's stepper
---@field _showMixedValue? boolean
---@field _shownText? string what UpdateFill last put in the box
---@field _callback? fun(value: number)
---@field _callbackOnRelease? boolean
---@field _dragging boolean
---@field _updating boolean
---@field _suppressCallback boolean
---@field _lastUpdate number
---@field _thumbSyncPending boolean
---@field _animateThumb fun(r: number, g: number, b: number, a?: number)
---@field _syncThumb fun(r: number, g: number, b: number, a?: number)
---@field _syncLeftStepper fun(r: number, g: number, b: number, a?: number)
---@field _syncRightStepper fun(r: number, g: number, b: number, a?: number)
---@field _syncValueBorder fun(r: number, g: number, b: number, a?: number)
---@field _paintThumbGlow fun()
---@field _paintValueGlow fun()
local SliderMixin = {}

---Re-trues the thumb's sub-pixel offset against the pixel grid.
function SliderMixin:UpdateThumbPosition()
    local dx = 0
    local thumbCenter = self.thumb:GetCenter()
    local sliderLeft = self.slider:GetLeft()
    if thumbCenter and sliderLeft then
        local left = (thumbCenter - sliderLeft) - THUMB_WIDTH / 2
        dx = pixel.ToPixelGrid(left) - left
    end
    self.thumbFrameBG:ClearAllPoints()
    self.thumbFrameBG:SetPoint("CENTER", self.thumb, "CENTER", dx, 0)
    self.thumbFrame:ClearAllPoints()
    self.thumbFrame:SetPoint("CENTER", self.thumb, "CENTER", dx, 0)
end

function SliderMixin:UpdateFill()
    local val = self.slider:GetValue()
    self.fillBar:SetValue(val)

    if not self._updating then
        self._updating = true
        local text = tostring(floor(val * 100 + 0.5) / 100)
        -- mixed has no one value to show, its tooltip lists them
        if self._mixed and not self._showMixedValue then
            text = ""
        end
        self._shownText = text
        self.valueEdit:SetText(text)
        self._updating = false
    end
end

---@param toHover boolean
---@param toDrag boolean
function SliderMixin:AnimateThumbColor(toHover, toDrag)
    local theme = self.gui.theme
    if toDrag then
        self._animateThumb(theme.accent[1], theme.accent[2], theme.accent[3], 1)
    elseif toHover then
        self._animateThumb(theme.textSecondary[1], theme.textSecondary[2], theme.textSecondary[3], 1)
    else
        self._animateThumb(theme.textSecondary[1], theme.textSecondary[2], theme.textSecondary[3], 0.6)
    end
end

---@param val number
function SliderMixin:FireCallback(val)
    if self._suppressCallback then return end
    safecall(self._callback, val)
end

---Hiding and releasing end it too: a slider gone mid-drag may never see OnMouseUp.
function SliderMixin:EndDrag()
    self._dragging = false
    if held ~= self then return end

    held = nil
    local queued = afterDrag
    afterDrag = {}
    for fn in pairs(queued) do
        safecall(fn)
    end
end

---@param val number
function SliderMixin:SetValue(val)
    self.slider:SetValue(val)
end

---Updates the displayed value without firing the callback. For syncing a slider
---to a value that was changed elsewhere (e.g. by dragging the frame it controls).
---@param val number
function SliderMixin:SetValueSilent(val)
    self._suppressCallback = true
    self.slider:SetValue(val)
    self._suppressCallback = false
end

---@return number
function SliderMixin:GetValue()
    return self.slider:GetValue()
end

---@param minVal number
---@param maxVal number
function SliderMixin:SetMinMaxValues(minVal, maxVal)
    self.fillBar:SetMinMaxValues(minVal, maxVal)
    self.slider:SetMinMaxValues(minVal, maxVal)
    self:UpdateFill()
end

---@param enabled boolean
function SliderMixin:SetEnabled(enabled)
    for _, halo in ipairs(self.fillGlow) do halo:SetShown(enabled) end
    if not enabled then
        self._thumbHovered, self._valueHovered = false, false
        self._paintThumbGlow()
        self._paintValueGlow()
    end
    self:SetAlpha(enabled and 1 or 0.4)
    self.slider:EnableMouse(enabled)
    self.valueEdit:EnableMouse(enabled)
    self.valueContainer:EnableMouse(enabled)
    self.leftStepper:EnableMouse(enabled)
    self.rightStepper:EnableMouse(enabled)
end

---Parses the value box, clamping and wobbling on anything out of range or unparseable.
function SliderMixin:CommitText()
    -- clicking in and out of a mixed slider's box changes nothing, blank or showing its rest
    if self._mixed and self.valueEdit:GetText() == self._shownText then return end

    local num = tonumber(self.valueEdit:GetText())
    if not num then
        Animations:Wobble(self.valueContainer)
        self:UpdateFill()
        return
    end

    local minVal, maxVal = self.slider:GetMinMaxValues()
    local clamped = max(minVal, min(maxVal, num))
    if clamped ~= num then Animations:Wobble(self.valueContainer) end
    self._updating = true
    self.slider:SetValue(clamped)
    self._updating = false
    -- the box shows what the step made of it, not what was typed
    self:UpdateFill()
end

function SliderMixin:UpdateColors()
    local theme = self.gui.theme
    Kaji.RefreshBackdrop(self.sliderBG)
    Kaji.RefreshBackdrop(self.thumbFrameBG)
    Kaji.RefreshBackdrop(self.thumbFrame)
    Kaji.RefreshBackdrop(self.valueContainer)

    self.label:SetTextColor(theme.textSecondary[1], theme.textSecondary[2], theme.textSecondary[3], 1)
    self.fillBar:SetStatusBarColor(theme.accent[1], theme.accent[2], theme.accent[3], 1)
    -- VERTICAL runs bottom (first color) to top (second color): each halo is brightest at the bar.
    local ac = theme.accent
    local lit, clear = CreateColor(ac[1], ac[2], ac[3], theme.glowControlAlpha), CreateColor(ac[1], ac[2], ac[3], 0)
    self.fillGlow[1]:SetGradient("VERTICAL", lit, clear)
    self.fillGlow[2]:SetGradient("VERTICAL", clear, lit)
    self.valueEdit:SetTextColor(theme.textPrimary[1], theme.textPrimary[2], theme.textPrimary[3], 1)

    for _, stepper in ipairs({ self.leftStepper, self.rightStepper }) do
        stepper.icon:SetTexture(theme.stepperTexture)
        stepper.icon:SetVertexColor(theme.textSecondary[1], theme.textSecondary[2], theme.textSecondary[3], 1)
    end

    -- Reseat every animator's resting color so the next hover tweens from the new palette.
    self._syncThumb(theme.textSecondary[1], theme.textSecondary[2], theme.textSecondary[3], 0.6)
    self._syncLeftStepper(theme.textSecondary[1], theme.textSecondary[2], theme.textSecondary[3], 1)
    self._syncRightStepper(theme.textSecondary[1], theme.textSecondary[2], theme.textSecondary[3], 1)
    self._syncValueBorder(theme.widgetBorder[1], theme.widgetBorder[2], theme.widgetBorder[3], theme.widgetBorder[4] or 1)
    Kaji.PaintMixed(self, self.label)
end

---@param parent Frame
---@param labelText? string
---@param config table
function SliderMixin:OnAcquire(parent, labelText, config)
    local sliderMin = config.min or 0
    local sliderMax = config.max or 100
    local step = config.step or 1

    self:SetParent(parent)
    self:ClearAllPoints()
    -- Reparenting resets levels; keep the thumb above the fill bar.
    self.thumbFrameBG:SetFrameLevel(self.fillBar:GetFrameLevel() + 1)
    self.thumbFrame:SetFrameLevel(self.fillBar:GetFrameLevel() + 1)
    self:NCSetHeight(36)

    self.label:SetText(labelText or "")
    self._step = step
    self._stepper = config.stepper
    self._showMixedValue = config.showMixedValue
    self._callbackOnRelease = config.callbackOnRelease
    self._dragging = false
    self._updating = false
    self._thumbSyncPending = false
    self._lastUpdate = 0

    -- Seeded with the callback suppressed: SetValue fires OnValueChanged, and a fresh
    -- acquire must not look like the user just moved the slider.
    self._callback = nil
    self._suppressCallback = true
    Kaji.SetMixed(self, config.mixed, DescribeValue)
    self.fillBar:SetMinMaxValues(sliderMin, sliderMax)
    self.slider:SetMinMaxValues(sliderMin, sliderMax)
    self.slider:SetValueStep(step)
    -- mixed rests at 0, so an arrow sets every pick one step from it, not from the minimum
    self.slider:SetValue(not config.mixed and config.value or max(sliderMin, min(sliderMax, 0)))
    self._suppressCallback = false
    self._callback = config.callback

    -- The "Default: x" line is only meaningful for a cvar-backed slider.
    local spec = config.tooltip
    if type(spec) == "table" and not config.cvartooltip then
        spec = { text = spec.text }
    end
    Kaji.SetTooltip(self, self.gui, labelText, spec)
    Kaji.SetNotice(self, self.gui, self.label, config.notice)

    self:SetEnabled(true)
    self:SetAlpha(1)
    self:UpdateColors()
    self:Show()

    self:UpdateFill()
    local alive = Kaji.Generation(self)
    C_Timer.After(0, function()
        if not alive() then return end
        self:UpdateThumbPosition()
    end)

    self.gui:RegisterSearchableWidget(self, labelText)
end

function SliderMixin:OnRelease()
    self._callback = nil
    self:EndDrag()
    self._thumbHovered = false
    self._paintThumbGlow()
    self._valueHovered = false
    self._paintValueGlow()
    self._suppressCallback = false
    self.valueEdit:ClearFocus()
    self.label:SetText("")
    Kaji.ClearTooltip(self)
end

---@class KajiGUISlider : KajiGUISliderMixin

---@class KajiGUISliderConfig
---@field min? number
---@field max? number
---@field step? number
---@field stepper? fun(value: number, direction: number): number the value an arrow click moves to, `value ± step` by default
---@field value? number
---@field callback? fun(value: number)
---@field callbackOnRelease? boolean fire callback only when the drag is released
---@field tooltip? any
---@field cvartooltip? boolean
---@field notice? KajiGUINotice a marker after the label, see Kaji.SetNotice
---@field mixed? KajiGUIMixedEntry[] the things it edits disagree: blank, resting at 0, see Kaji.SetMixed
---@field showMixedValue? boolean a mixed box shows its resting 0 instead of a blank (offsets)

Kaji:RegisterWidgetType(WIDGET_TYPE, function(gui)
    local theme = gui.theme

    local row = CreateFrame("Frame", nil, gui._poolHost) --[[@as KajiGUISlider]]
    row.gui = gui

    local label = row:CreateFontString(nil, "OVERLAY")
    label:NCSetPoint("TOPLEFT", row, "TOPLEFT", 0, 1)
    label:SetJustifyH("LEFT")
    gui:ApplyFont(label, "small")
    row.label = label

    local sliderBG = CreateFrame("Frame", nil, row, "BackdropTemplate")
    sliderBG:NCSetHeight(8)
    sliderBG:NCSetPoint("TOPLEFT", row, "TOPLEFT", 68, -22)
    sliderBG:NCSetPoint("TOPRIGHT", row, "TOPRIGHT", -18, -22)
    Kaji.SetBackdrop(sliderBG, gui, { bg = "bgDark", bgAlpha = 0.9, border = "widgetBorder", borderAlpha = 1 })
    sliderBG:EnableMouse(false)
    row.sliderBG = sliderBG

    local slider = CreateFrame("Slider", nil, row, "BackdropTemplate")
    slider:NCSetHeight(8)
    slider:NCSetPoint("TOPLEFT", row, "TOPLEFT", 77, -22)
    slider:NCSetPoint("TOPRIGHT", row, "TOPRIGHT", -27, -22)
    slider:SetOrientation("HORIZONTAL")
    slider:SetObeyStepOnDrag(true)
    slider:SetHitRectInsets(-9, -9, -5, -5)
    -- Fully transparent: this frame is only the hit area, sliderBG draws the track.
    Kaji.SetBackdrop(slider, gui, { bg = { 0, 0, 0 }, bgAlpha = 0, border = { 0, 0, 0 }, borderAlpha = 0 })
    row.slider = slider

    -- StatusBar so the engine sizes the fill at layout, never from unresolved geometry.
    local fillBar = CreateFrame("StatusBar", nil, slider)
    fillBar:NCSetHeight(6)
    fillBar:NCSetPoint("LEFT", sliderBG, "LEFT", 1, 0)
    fillBar:NCSetPoint("RIGHT", slider, "RIGHT", -10, 0)
    fillBar:SetStatusBarTexture(Core.WhiteTexture)
    local fill = fillBar:GetStatusBarTexture()
    fill:NCDisablePixelSnap()
    row.fillBar = fillBar

    local function Halo(point, relPoint)
        local t = fillBar:CreateTexture(nil, "ARTWORK", nil, -1)
        t:SetTexture(Core.WhiteTexture)
        t:NCSetHeight(FILL_GLOW_HEIGHT)
        t:NCSetPoint(point .. "LEFT", fill, relPoint .. "LEFT", 0, 0)
        t:NCSetPoint(point .. "RIGHT", fill, relPoint .. "RIGHT", 0, 0)
        return t
    end
    row.fillGlow = { Halo("BOTTOM", "TOP"), Halo("TOP", "BOTTOM") }

    local thumbFrameBG = CreateFrame("Frame", nil, slider, "BackdropTemplate")
    thumbFrameBG:NCSetSize(THUMB_WIDTH, THUMB_HEIGHT)
    Kaji.SetBackdrop(thumbFrameBG, gui, { bg = "bgLight", bgAlpha = 0.9, border = { 0, 0, 0 }, borderAlpha = 1 })
    row.thumbFrameBG = thumbFrameBG

    local thumbFrame = CreateFrame("Frame", nil, slider, "BackdropTemplate")
    thumbFrame:NCSetSize(THUMB_WIDTH, THUMB_HEIGHT)
    Kaji.SetBackdrop(thumbFrame, gui, { bg = "textSecondary", bgAlpha = 0.9, border = { 0, 0, 0 }, borderAlpha = 1 })
    row.thumbFrame = thumbFrame

    -- Neon: the thumb glows faintly while hovered, fully while dragged.
    local thumbGlow = Kaji.CreateFrameGlow(thumbFrame, gui, THUMB_GLOW_REACH, slider)
    local function PaintThumbGlow()
        Kaji.SetFrameGlow(thumbGlow, gui, row._dragging and Kaji.GLOW_ACTIVE or (row._thumbHovered and Kaji.GLOW_HOVER or 0))
    end
    row._paintThumbGlow = PaintThumbGlow

    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(0, 0, 0, 0)
    slider:SetThumbTexture(thumb)
    row.thumb = thumb

    local function MakeStepper(point, relPoint, rotation)
        local stepper = CreateFrame("Button", nil, row)
        stepper:NCSetSize(STEPPER_SIZE, STEPPER_SIZE)
        stepper:NCSetPoint(point, sliderBG, relPoint, 0, 0)

        local icon = stepper:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture(theme.stepperTexture)
        icon:SetRotation(rad(rotation))
        icon:NCDisablePixelSnap()
        stepper.icon = icon

        return stepper
    end

    local leftStepper = MakeStepper("RIGHT", "LEFT", -90)
    local rightStepper = MakeStepper("LEFT", "RIGHT", 90)
    row.leftStepper = leftStepper
    row.rightStepper = rightStepper

    local valueContainer = CreateFrame("Frame", nil, slider, "BackdropTemplate")
    valueContainer:NCSetSize(48, 24)
    valueContainer:NCSetPoint("RIGHT", leftStepper, "LEFT", 0, 0)
    Kaji.SetBackdrop(valueContainer, gui, { bg = "bgDark", bgAlpha = 1, border = "widgetBorder", borderAlpha = 1 })
    row.valueContainer = valueContainer

    local valueEdit = CreateFrame("EditBox", nil, valueContainer)
    valueEdit:NCSetPoint("TOPLEFT", 0, 0)
    valueEdit:NCSetPoint("BOTTOMRIGHT", 0, 0)
    valueEdit:SetFontObject("GameFontNormal")
    valueEdit:SetJustifyH("CENTER")
    valueEdit:SetAutoFocus(false)
    row.valueEdit = valueEdit

    Mixin(row, SliderMixin)

    row._animateThumb, row._syncThumb = Animations:CreateColorAnimator(thumbFrame,
        function(r, g, b, a) thumbFrame:SetBackdropColor(r, g, b, a) end,
        { theme.textSecondary[1], theme.textSecondary[2], theme.textSecondary[3], 0.6 }, theme.animDuration)

    row._animateLeftStepper, row._syncLeftStepper = Animations:CreateHoverColorAnimator(leftStepper,
        function(r, g, b, a) leftStepper.icon:SetVertexColor(r, g, b, a) end,
        theme.textSecondary, theme.accent, theme.animDuration)

    row._animateRightStepper, row._syncRightStepper = Animations:CreateHoverColorAnimator(rightStepper,
        function(r, g, b, a) rightStepper.icon:SetVertexColor(r, g, b, a) end,
        theme.textSecondary, theme.accent, theme.animDuration)

    row._animateValueBorder, row._syncValueBorder = Animations:CreateHoverColorAnimator(valueContainer,
        function(r, g, b, a) valueContainer:SetBackdropBorderColor(r, g, b, a) end,
        theme.widgetBorder, theme.accent, theme.animDuration)

    local function Step(direction)
        local minVal, maxVal = slider:GetMinMaxValues()
        local value = slider:GetValue()
        if row._stepper then
            value = row._stepper(value, direction)
        else
            value = value + direction * row._step
        end
        slider:SetValue(max(minVal, min(maxVal, value)))
    end

    leftStepper:SetScript("OnClick", function() Step(-1) end)
    leftStepper:SetScript("OnEnter", function() row._animateLeftStepper(true); Kaji.ShowTooltip(row) end)
    leftStepper:SetScript("OnLeave", function() row._animateLeftStepper(false); Kaji.HideTooltip() end)

    rightStepper:SetScript("OnClick", function() Step(1) end)
    rightStepper:SetScript("OnEnter", function() row._animateRightStepper(true); Kaji.ShowTooltip(row) end)
    rightStepper:SetScript("OnLeave", function() row._animateRightStepper(false); Kaji.HideTooltip() end)

    slider:SetScript("OnValueChanged", function(_, val)
        -- a drag, a step or a typed number gives them all one value
        if not row._suppressCallback then
            Kaji.ClearMixed(row)
        end
        row:UpdateFill()
        row:UpdateThumbPosition()
        -- a recycled slider gets here twice while seeding, the second would arm a flush that fires the real callback
        if row._suppressCallback then return end
        if row._callbackOnRelease and row._dragging then return end
        local now = GetTime()
        if now - row._lastUpdate < THROTTLE_DELAY then
            -- the value a quick drag stops on still lands once the window passes, or the setting lags what the slider shows
            if not row._flushPending then
                row._flushPending = true
                local alive = Kaji.Generation(row)
                C_Timer.After(THROTTLE_DELAY - (now - row._lastUpdate), function()
                    row._flushPending = false
                    if not alive() then return end
                    row._lastUpdate = GetTime()
                    row:FireCallback(slider:GetValue())
                end)
            end
            return
        end
        row._lastUpdate = now
        row:FireCallback(val)
    end)

    -- The thumb re-lays out a frame after the slider resizes, so re-true the sub-pixel
    -- correction once the new geometry has settled.
    slider:SetScript("OnSizeChanged", function()
        row:UpdateThumbPosition()
        if row._thumbSyncPending then return end
        row._thumbSyncPending = true
        local alive = Kaji.Generation(row)
        C_Timer.After(0, function()
            row._thumbSyncPending = false
            if not alive() then return end
            row:UpdateThumbPosition()
        end)
    end)

    slider:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local accent = row.gui.theme.accent
        thumbFrame:SetBackdropColor(accent[1], accent[2], accent[3], 1)
        row._syncThumb(accent[1], accent[2], accent[3], 1)
        row._dragging = true
        held = row
        PaintThumbGlow()
    end)
    slider:SetScript("OnMouseUp", function(sliderFrame, button)
        if button ~= "LeftButton" then return end
        row:EndDrag()
        PaintThumbGlow()
        if row._callbackOnRelease then
            row:FireCallback(sliderFrame:GetValue())
        end
        row:AnimateThumbColor(sliderFrame:IsMouseOver(), false)
    end)
    slider:SetScript("OnHide", function()
        row:EndDrag()
    end)
    slider:SetScript("OnEnter", function()
        row._thumbHovered = true
        PaintThumbGlow()
        if not row._dragging then row:AnimateThumbColor(true, false) end
        Kaji.ShowTooltip(row)
    end)
    slider:SetScript("OnLeave", function()
        row._thumbHovered = false
        PaintThumbGlow()
        if not row._dragging then row:AnimateThumbColor(false, false) end
        Kaji.HideTooltip()
    end)

    valueEdit:SetScript("OnEscapePressed", function(editBox)
        editBox:ClearFocus()
        row:UpdateFill()
    end)
    valueEdit:SetScript("OnEnterPressed", function(editBox)
        editBox:ClearFocus()
        row:CommitText()
    end)
    -- Neon: the value box glows faintly while hovered, fully while it's being typed in.
    local valueGlow = Kaji.CreateFrameGlow(valueContainer, gui, Kaji.FIELD_GLOW_REACH, row)
    row._paintValueGlow = function()
        Kaji.SetFrameGlow(valueGlow, gui, valueEdit:HasFocus() and Kaji.GLOW_ACTIVE or (row._valueHovered and Kaji.GLOW_HOVER or 0))
    end

    valueEdit:SetScript("OnEditFocusGained", function(editBox)
        local accent = row.gui.theme.accent
        valueContainer:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        row._paintValueGlow()
        editBox:HighlightText()
    end)
    valueEdit:SetScript("OnEditFocusLost", function(editBox)
        local border = row.gui.theme.widgetBorder
        valueContainer:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        row._paintValueGlow()
        editBox:HighlightText(0, 0)
        row:CommitText()
    end)
    valueEdit:SetScript("OnEnter", function()
        row._valueHovered = true
        row._paintValueGlow()
        if not valueEdit:HasFocus() then row._animateValueBorder(true) end
        Kaji.ShowTooltip(row)
    end)
    valueEdit:SetScript("OnLeave", function()
        row._valueHovered = false
        row._paintValueGlow()
        if not valueEdit:HasFocus() then row._animateValueBorder(false) end
        Kaji.HideTooltip()
    end)

    -- The value box's frame has no hover styling of its own, so these are its only scripts.
    valueContainer:SetScript("OnEnter", function() Kaji.ShowTooltip(row) end)
    valueContainer:SetScript("OnLeave", Kaji.HideTooltip)

    return row
end)

---@param parent Frame
---@param labelText? string
---@param config? KajiGUISliderConfig
---@return KajiGUISlider
function InstanceMixin:CreateSlider(parent, labelText, config)
    return self:BuildWidget(WIDGET_TYPE, parent, labelText, config)
end
