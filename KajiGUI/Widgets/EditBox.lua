--[[
# EditBox

* A single-line text input with a label, either above the box or inline to its left.

## Examples

    row:EditBox('Name', {
        width = 0.5,
        value = db.Name,
        callback = function(text) db.Name = text end,
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
local tostring = tostring

local WIDGET_TYPE = 'EditBox'
local PANEL_BUTTON_SIZE = 24
local PANEL_ICON_SIZE = 14
local PANEL_BUTTON_GAP = 4

---An unset value lists as blank, not "nil".
---@param value any
---@return string
local function DescribeValue(value)
    return (value == nil or value == false) and "" or tostring(value)
end

---@class KajiGUIEditBoxMixin : Frame
---@field gui KajiGUIInstance
---@field editBox EditBox
---@field container Frame|BackdropTemplate
---@field label FontString
---@field _callback? fun(text: string)
---@field _onTextChanged? fun(text: string)
---@field _animateBorder fun(isHover: boolean)
---@field _syncBorder fun(r: number, g: number, b: number, a?: number)
---@field _paintGlow fun()
---@field panelButton Button|BackdropTemplate
---@field panelIcon Texture
---@field _panel? KajiGUISidePanelConfig
---@field _panelOpen boolean
---@field _animatePanelButton fun(r: number, g: number, b: number, a: number)
---@field _setPanelButton fun(r: number, g: number, b: number, a: number)
---@field _committed string the text it was given or last saved
local EditBoxMixin = {}

---@param val string
function EditBoxMixin:SetValue(val)
    self.editBox:SetText(val or '')
    self._committed = self.editBox:GetText()
end

-- A box with a panel skips a save that changes nothing, as a code click takes its focus
-- first and the save's card rebuild would lose the cursor
function EditBoxMixin:Commit()
    local text = self.editBox:GetText()
    if self._panel and text == self._committed then return end

    self._committed = text
    safecall(self._callback, text)
end

---@param open boolean
---@param instant boolean? no fade, for a box taking over an open panel
function EditBoxMixin:SetPanelOpen(open, instant)
    self._panelOpen = open
    local p = open and 1 or 0
    if instant then
        self._setPanelButton(p, 0, 0, 0)
        self:PaintPanelButton(p)
    else
        self._animatePanelButton(p, 0, 0, 0)
    end
end

---@param p number 0 at rest to 1 hovered or open
function EditBoxMixin:PaintPanelButton(p)
    local theme = self.gui.theme
    local rest, accent, border = theme.textMuted, theme.accent, theme.widgetBorder
    self.panelIcon:SetVertexColor(rest[1] + (accent[1] - rest[1]) * p, rest[2] + (accent[2] - rest[2]) * p,
        rest[3] + (accent[3] - rest[3]) * p, 1)
    self.panelButton:SetBackdropBorderColor(border[1] + (accent[1] - border[1]) * p,
        border[2] + (accent[2] - border[2]) * p, border[3] + (accent[3] - border[3]) * p, 1)
end

---@return string
function EditBoxMixin:GetValue()
    return self.editBox:GetText()
end

---@param enabled boolean
function EditBoxMixin:SetEnabled(enabled)
    self:SetAlpha(enabled and 1 or 0.4)
    self.editBox:EnableMouse(enabled)
    self.editBox:EnableKeyboard(enabled)
    self.panelButton:EnableMouse(enabled and not self._mixed)
    -- A box switched off takes no codes
    if not enabled and self._panelOpen then
        Kaji.ToggleSidePanel(self, self._panel)
    end
    if not enabled then
        self.editBox:ClearFocus()
        self._hovered = false
        self._paintGlow()
    end
end

function EditBoxMixin:UpdateColors()
    local theme = self.gui.theme
    Kaji.RefreshBackdrop(self.container)
    self.label:SetTextColor(theme.textSecondary[1], theme.textSecondary[2], theme.textSecondary[3], 1)
    self.editBox:SetTextColor(theme.textPrimary[1], theme.textPrimary[2], theme.textPrimary[3], 1)
    self._syncBorder(theme.widgetBorder[1], theme.widgetBorder[2], theme.widgetBorder[3], theme.widgetBorder[4] or 1)
    Kaji.PaintMixed(self, self.label)
    -- The refresh resets the border, so the button's paint goes after it
    Kaji.RefreshBackdrop(self.panelButton)
    self:PaintPanelButton(self._panelOpen and 1 or 0)
end

---@param parent Frame
---@param labelText? string
---@param config table
function EditBoxMixin:OnAcquire(parent, labelText, config)
    local inlineLabel = config.inlineLabel
    local labelWidth = config.labelWidth or 60
    local autoFocus = config.autoFocus or false

    self:SetParent(parent)
    self:ClearAllPoints()
    self:NCSetHeight(inlineLabel and 24 or 34)

    -- The label sits left of the box or above it; both layouts re-anchor from scratch so
    -- a recycled widget cannot keep the other one's points.
    local panel = config.panel
    local right = panel and -(PANEL_BUTTON_SIZE + PANEL_BUTTON_GAP) or 0
    self.label:ClearAllPoints()
    self.container:ClearAllPoints()
    if inlineLabel then
        self.label:NCSetPoint('LEFT', self, 'LEFT', 0, 0)
        self.label:NCSetWidth(labelWidth)
        self.container:NCSetPoint('TOPLEFT', self, 'TOPLEFT', labelWidth, 0)
        self.container:NCSetPoint('TOPRIGHT', self, 'TOPRIGHT', right, 0)
    else
        self.label:NCSetPoint('TOPLEFT', self, 'TOPLEFT', 0, 1)
        self.container:NCSetPoint('TOPLEFT', self, 'TOPLEFT', 0, -14)
        self.container:NCSetPoint('TOPRIGHT', self, 'TOPRIGHT', right, -14)
    end

    -- A blank box standing for several values can't take a code
    self._panel = panel
    self.panelButton:SetShown(panel ~= nil)
    self.panelButton:EnableMouse(not config.mixed)
    self.panelButton:SetAlpha(config.mixed and 0.4 or 1)
    Kaji.SetTooltip(self.panelButton, self.gui, panel and panel.title, panel and panel.tooltip)
    self:SetPanelOpen(false, true)

    self.label:SetText(labelText or "")
    self._callback = config.callback
    self._onTextChanged = config.onTextChanged

    Kaji.SetMixed(self, config.mixed, DescribeValue)
    self.editBox:SetAutoFocus(autoFocus)
    self.editBox:SetText(not config.mixed and tostring(config.value or '') or '') -- Mixed is blank, as WA's
    self._committed = self.editBox:GetText()
    self.editBox:EnableMouse(true)
    self.editBox:EnableKeyboard(true)

    Kaji.SetTooltip(self, self.gui, labelText, config.tooltip, config.tooltipBeside and { owner = self.container, beside = true } or nil)
    Kaji.SetNotice(self, self.gui, self.label, config.notice)

    self:SetAlpha(1)
    self:UpdateColors()
    self:Show()

    if autoFocus then
        self.editBox:SetFocus()
    end
    if panel then
        Kaji.TrackSidePanelBox(self, panel.key)
    end
end

function EditBoxMixin:OnRelease()
    if self._panel then
        Kaji.TrackSidePanelBox(self, nil)
        self._panel = nil
    end
    self._hovered = false
    self._paintGlow()
    self._callback = nil
    self._onTextChanged = nil
    -- A released box that kept keyboard focus would go on swallowing input.
    self.editBox:ClearFocus()
    self.editBox:SetAutoFocus(false)
    self.editBox:SetText("")
    self.label:SetText("")
    Kaji.ClearTooltip(self)
end

---@class KajiGUIEditBox : KajiGUIEditBoxMixin

---@class KajiGUIEditBoxConfig
---@field value? string
---@field callback? fun(text: string)
---@field onTextChanged? fun(text: string) fires on every keystroke the user types
---@field autoFocus? boolean
---@field tooltip? any
---@field tooltipBeside? boolean the tooltip opens to the right of the input box instead of at the cursor
---@field inlineLabel? boolean Place the label left of the box instead of above it.
---@field labelWidth? number Width reserved for an inline label.
---@field notice? KajiGUINotice a marker after the label, see Kaji.SetNotice
---@field mixed? KajiGUIMixedEntry[] the things it edits disagree: blank until typed in, see Kaji.SetMixed
---@field panel? KajiGUISidePanelConfig a button right of the box opening a side panel that can type into it

Kaji:RegisterWidgetType(WIDGET_TYPE, function(gui)
    local theme = gui.theme

    local row = CreateFrame("Frame", nil, gui._poolHost) --[[@as KajiGUIEditBox]]
    row.gui = gui

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetJustifyH("LEFT")
    gui:ApplyFont(label, "small")
    row.label = label

    local container = CreateFrame("Frame", nil, row, "BackdropTemplate")
    container:NCSetHeight(24)
    Kaji.SetBackdrop(container, gui, { bg = "bgDark", bgAlpha = 0.9, border = "widgetBorder", borderAlpha = 1 })
    row.container = container

    -- EditBox frames autofocus by default, and OnAcquire reparents before it can turn
    -- that off, so a freshly built box would steal the keyboard the moment it is shown.
    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetAutoFocus(false)
    editBox:NCSetPoint("TOPLEFT", container, "TOPLEFT", 6, -4)
    editBox:NCSetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -6, 4)
    editBox:SetFontObject("GameFontNormal")
    row.editBox = editBox

    -- Reads the panel off the row, so a pooled box never opens an old one
    local panelButton = CreateFrame('Button', nil, row, 'BackdropTemplate')
    panelButton:NCSetSize(PANEL_BUTTON_SIZE, PANEL_BUTTON_SIZE)
    panelButton:NCSetPoint('LEFT', container, 'RIGHT', PANEL_BUTTON_GAP, 0)
    Kaji.SetBackdrop(panelButton, gui, { bg = 'bgDark', bgAlpha = 0.9, border = 'widgetBorder', borderAlpha = 1 })
    panelButton:Hide()
    row.panelButton = panelButton

    local panelIcon = panelButton:CreateTexture(nil, 'ARTWORK')
    panelIcon:NCSetSize(PANEL_ICON_SIZE, PANEL_ICON_SIZE)
    panelIcon:NCSetPoint('CENTER', panelButton, 'CENTER', 0, 0)
    panelIcon:SetTexture(theme.panelTexture)
    row.panelIcon = panelIcon

    Mixin(row, EditBoxMixin)

    row._animatePanelButton, row._setPanelButton = Animations:CreateColorAnimator(panelButton,
        function(p) row:PaintPanelButton(p) end, { 0, 0, 0, 0 }, theme.animDuration)
    panelButton:SetScript('OnEnter', function()
        row._animatePanelButton(1, 0, 0, 0)
        Kaji.ShowTooltip(panelButton)
    end)
    panelButton:SetScript('OnLeave', function()
        row._animatePanelButton(row._panelOpen and 1 or 0, 0, 0, 0)
        Kaji.HideTooltip()
    end)
    panelButton:SetScript('OnClick', function()
        if row._panel then
            Kaji.ToggleSidePanel(row, row._panel)
        end
    end)

    row._animateBorder, row._syncBorder = Animations:CreateHoverColorAnimator(container,
        function(r, g, b, a) container:SetBackdropBorderColor(r, g, b, a) end,
        theme.widgetBorder, theme.accent, theme.animDuration)

    -- Neon: the field glows faintly while hovered, fully while focused.
    local fieldGlow = Kaji.CreateFrameGlow(container, gui, Kaji.FIELD_GLOW_REACH, row)
    row._paintGlow = function()
        Kaji.SetFrameGlow(fieldGlow, gui, editBox:HasFocus() and Kaji.GLOW_ACTIVE or (row._hovered and Kaji.GLOW_HOVER or 0))
    end

    -- Set once, reading the callback off the row, so a recycled box never fires the
    -- previous consumer's handler.
    editBox:SetScript("OnTextChanged", function(eb, userInput)
        if userInput then
            Kaji.ClearMixed(row) -- typed text is the one value they all get
            safecall(row._onTextChanged, eb:GetText())
        end
    end)
    editBox:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    -- clearing focus runs OnEditFocusLost, which commits; a second call here could reach a field a rebuild re-pooled this box for
    editBox:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
    editBox:SetScript("OnEditFocusLost", function(eb)
        local border = row.gui.theme.widgetBorder
        container:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        row._paintGlow()
        -- A mixed box nobody typed in stays as it was, rather than giving them all an empty value
        if row._mixed then return end
        row:Commit()
    end)
    editBox:SetScript("OnEditFocusGained", function()
        local accent = row.gui.theme.accent
        container:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        row._paintGlow()
    end)
    editBox:SetScript("OnEnter", function(eb)
        row._hovered = true
        row._paintGlow()
        if not eb:HasFocus() then row._animateBorder(true) end
        Kaji.ShowTooltip(row)
    end)
    editBox:SetScript("OnLeave", function(eb)
        row._hovered = false
        row._paintGlow()
        if not eb:HasFocus() then row._animateBorder(false) end
        Kaji.HideTooltip()
    end)

    return row
end)

---@param parent Frame
---@param labelText? string
---@param config? KajiGUIEditBoxConfig
---@return KajiGUIEditBox
function InstanceMixin:CreateEditBox(parent, labelText, config)
    return self:BuildWidget(WIDGET_TYPE, parent, labelText, config)
end
