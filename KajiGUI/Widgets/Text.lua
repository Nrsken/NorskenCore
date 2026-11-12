--[[
# Text

* A titled block of body text, optionally boxed, that can size itself to its wrapped
  content and push the resulting height up through the row it lives in.

## Examples

    row:Text('Note', {
        width = 1,
        text = { 'First point', 'Second point' },
        autoHeight = true,
        bgMode = 'hide',
    })

--]]

---@class NRSKNUI
local Core = select(2, ...)
---@class Kaji
local Kaji = Core.Kaji
---@class KajiGUIInstanceMixin
local InstanceMixin = Kaji.InstanceMixin

local CreateFrame = CreateFrame
local Mixin = Mixin
local type = type
local ipairs = ipairs
local abs = math.abs
local max = math.max
local tconcat = table.concat

local WIDGET_TYPE = "Text"
local BLACK = { 0, 0, 0 }

-- bgMode -> backdrop spec. Every mode builds the same frame; only visibility differs.
local BG_MODES = {
    show   = { bg = "bgDark", bgAlpha = 1, border = "widgetBorder", borderAlpha = 1 },
    border = { bg = BLACK, bgAlpha = 0, border = BLACK, borderAlpha = 1 },
    hide   = { bg = BLACK, bgAlpha = 0, border = BLACK, borderAlpha = 0 },
}

---@alias KajiGUITextBody string|string[]|fun(): string|string[]

---@class KajiGUITextMixin : Frame
---@field gui KajiGUIInstance
---@field container Frame|BackdropTemplate
---@field title FontString
---@field label FontString
---@field _autoHeight boolean
---@field _minHeight number
---@field _titleSpacer number
---@field _measured? number last settled height, nil until the first measure
local TextMixin = {}

---Flattens the body, which may be a string, a bulleted list, or a provider for either.
---@param input? KajiGUITextBody
---@return string
function TextMixin:ResolveBody(input)
    if type(input) == "function" then
        input = input()
    end
    if type(input) == "table" then
        local lines = {}
        for i, v in ipairs(input) do
            lines[i] = self.gui:ColorText("• ") .. v
        end
        return tconcat(lines, "\n")
    end
    return input or ""
end

---Sizes the block to its wrapped text at the given width and passes the height up to the row.
---@param width? number
function TextMixin:Measure(width)
    -- No width yet means the row has not been laid out; OnSizeChanged brings us back.
    if not self._autoHeight or not width or width <= 0 then return end

    self.label:NCSetWidth(width)
    local desired = max(self._titleSpacer + (self.label:GetStringHeight() or 0) + self.gui.theme.paddingSmall,
        self._minHeight)
    -- Bailing on an unchanged height is what stops resize -> OnSizeChanged -> resize looping.
    if self._measured and abs(desired - self._measured) < 0.5 then return end

    self._measured = desired
    self.container:NCSetHeight(desired)
    self:NCSetHeight(desired)

    local owner = self:GetParent()
    if owner and owner.SetContentHeight then owner:SetContentHeight(desired) end
end

---Measures against the width the row just resolved. An auto-height block released and
---re-acquired at the same width raises no OnSizeChanged, so this is the only thing that
---remeasures it - without it the block returns collapsed to its default row height.
---@param width number
function TextMixin:OnLayout(width)
    self:Measure(width)
end

---Replaces the body text, remeasuring when the block sizes itself.
---@param text KajiGUITextBody
function TextMixin:SetText(text)
    self.label:SetText(self:ResolveBody(text))
    self:Measure(self:GetWidth())
end

---@param enabled boolean
function TextMixin:SetEnabled(enabled)
    self:SetAlpha(enabled and 1 or 0.4)
end

function TextMixin:UpdateColors()
    local theme = self.gui.theme
    Kaji.RefreshBackdrop(self.container)
    self.title:SetTextColor(theme.textSecondary[1], theme.textSecondary[2], theme.textSecondary[3], 1)
    self.label:SetTextColor(theme.textSecondary[1], theme.textSecondary[2], theme.textSecondary[3], 1)
end

---@param parent Frame
---@param titleText? string
---@param config table
function TextMixin:OnAcquire(parent, titleText, config)
    local rowHeight = config.height or 34

    -- A height means the caller sized the box themselves, so honour it unless they opt back in.
    local autoHeight = config.autoHeight
    if autoHeight == nil then autoHeight = config.height == nil end

    self._autoHeight = autoHeight and true or false
    self._minHeight = config.minHeight or 0
    self._measured = nil

    self:SetParent(parent)
    self:ClearAllPoints()
    self:NCSetHeight(rowHeight)
    self.container:NCSetHeight(rowHeight)
    -- Keeps the row it is added to from stamping its own height back over the measured one.
    self.explicitHeight = self._autoHeight or nil

    self.container._kajiBackdrop = BG_MODES[config.bgMode] or BG_MODES.hide
    Kaji.RefreshBackdrop(self.container)

    local hasTitle = titleText ~= nil and titleText ~= ""
    self.title:SetText(hasTitle and titleText or "")
    self._titleSpacer = hasTitle and (self.title:GetStringHeight() + 6) or 0

    -- Auto sizing anchors one corner and sets the width itself, so GetStringHeight reports the
    -- wrapped height right away. Pinning both sides only resolves the width on the next layout
    -- pass, which would leave us measuring against the previous one.
    self.label:ClearAllPoints()
    self.label:NCSetPoint("TOPLEFT", self.container, "TOPLEFT", 0, -self._titleSpacer)
    -- Set both ways: a pooled block that was auto-sized last time would keep TOP.
    if self._autoHeight then
        self.label:SetJustifyV("TOP")
    else
        self.label:SetJustifyV("MIDDLE")
        self.label:NCSetPoint("BOTTOMRIGHT", self.container, "BOTTOMRIGHT", 0, 0)
    end
    self.label:SetJustifyH(config.justify or "LEFT")
    self.label:SetText(self:ResolveBody(config.text))

    self:SetAlpha(1)
    self:UpdateColors()
    self:Show()
end

function TextMixin:OnRelease()
    self.title:SetText("")
    self.label:SetText("")
    self.label:SetJustifyH("LEFT")
    self.explicitHeight = nil
    self._measured = nil
end

---@class KajiGUIText : KajiGUITextMixin

---@class KajiGUITextConfig
---@field text? KajiGUITextBody
---@field height? number fixed height; omitting it sizes the block to its wrapped text
---@field autoHeight? boolean force auto sizing even with a height set, which is then only the row's size until measured
---@field minHeight? number shortest the block may get while auto sizing
---@field bgMode? "show"|"border"|"hide"
---@field justify? "LEFT"|"CENTER"|"RIGHT" body alignment, LEFT by default

Kaji:RegisterWidgetType(WIDGET_TYPE, function(gui)
    local row = CreateFrame("Frame", nil, gui._poolHost) --[[@as KajiGUIText]]
    row.gui = gui

    local container = CreateFrame("Frame", nil, row, "BackdropTemplate")
    container:NCSetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    container:NCSetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    Kaji.SetBackdrop(container, gui, BG_MODES.hide)
    row.container = container

    local title = container:CreateFontString(nil, "OVERLAY")
    title:NCSetPoint("TOPLEFT", container, "TOPLEFT", 1, -1)
    title:NCSetPoint("TOPRIGHT", container, "TOPRIGHT", -1, -1)
    title:NCSetHeight(18)
    title:SetJustifyH("LEFT")
    gui:ApplyFont(title, "large")
    row.title = title

    local label = container:CreateFontString(nil, "OVERLAY")
    label:SetJustifyH("LEFT")
    label:SetSpacing(4)
    label:SetWordWrap(true)
    label:SetNonSpaceWrap(true)
    gui:ApplyFont(label, "small")
    row.label = label
    container.label = label

    Mixin(row, TextMixin)
    row:SetScript("OnSizeChanged", function(self, width) self:Measure(width) end)

    return row
end)

---@param parent Frame
---@param titleText? string
---@param config? KajiGUITextConfig
---@return KajiGUIText
function InstanceMixin:CreateText(parent, titleText, config)
    return self:BuildWidget(WIDGET_TYPE, parent, titleText, config)
end
