--[[
# SectionHeader

* A clickable bar that opens and closes a run of rows inside one card: arrow, title, and an optional
  right-aligned cluster of icon actions (move up, move down, duplicate, delete).
* Built for repeating lists that live in a single card rather than a card each, so a list of branches
  or conditions reads as one thing. Modelled on the WeakAuras Conditions tab.
* The header owns no rows. Collapsing is the caller omitting the body on the next build, which is why
  this stays a plain row and needs nothing from the card's layout (see FluentCard:Section).

## Examples

API: card:Section('1. Big Defensives', { collapsed = false, onToggle = fn, onDelete = fn })
API: GUI:CreateSectionHeader(parent, 'Conditions', { onToggle = fn })
API: card:SubSection('Anchors', { key = 'anchors', summary = "Anchored to frame's Center" })

--]]

---@class NRSKNUI
local Core = select(2, ...)
---@class Kaji
local Kaji = Core.Kaji
---@class KajiGUIInstanceMixin
local InstanceMixin = Kaji.InstanceMixin
local safecall = Kaji.safecall
local L = Core.L

local CreateFrame = CreateFrame
local format = string.format
local Mixin = Mixin
local ipairs = ipairs
local mpi = math.pi
local min = math.min
local GetAtlasInfo = C_Texture.GetAtlasInfo

local WIDGET_TYPE = "SectionHeader"
local HEIGHT = 26
local ARROW_SIZE = 10
local ACTION_SIZE = 18
local ACTION_SPACING = 2
local ACTION_ALPHA = 0.7
local ACTION_ALPHA_INERT = 0.2 -- a move with nowhere to go keeps its slot so every row's cluster lines up
local SUMMARY_GAP = 4
local SUMMARY_MIN = 24 -- narrower than this the summary would only be an ellipsis
local TOOLTIP_OPTIONS = { anchor = "ANCHOR_TOP", x = 0, y = 4 }
local HOVER_CLAIM_WINDOW = 0.05 -- how long a rebuilt row waits for OnEnter before it stops assuming the pointer

-- Right to left, so the rightmost action is the destructive one and the cluster keeps its order
-- however many of them a caller opts into.
local ACTIONS = {
    { key = "onDelete",    texture = "crossCustomTexture",    color = "error",       size = 14,           rotation = 0,                  title = "Delete",    tooltipKey = "deleteTooltip" },
    { key = "onDuplicate", texture = "duplicateTexture",      color = "textPrimary", size = 16,           rotation = 0,                  title = "Duplicate", tooltipKey = "duplicateTooltip" },
    { key = "onMoveDown",  atlas = "channels-icon-arrowdown", rotation = 0,          title = "Move Down", tooltipKey = "moveDownTooltip" },
    { key = "onMoveUp",    atlas = "channels-icon-arrowup",   rotation = mpi,        title = "Move Up",   tooltipKey = "moveUpTooltip" },
}

---Atlas if the client still has one by that name, otherwise fall back to theme media so a button is
---never invisible. Move up/down share one fallback and are told apart by rotation.
---@param texture Texture
---@param action table
---@param theme table
local function SetIcon(texture, action, theme)
    if action.texture then
        local color = theme[action.color]
        texture:SetTexture(theme[action.texture])
        texture:SetRotation(action.rotation)
        texture:SetVertexColor(color[1], color[2], color[3])
        return
    end
    if GetAtlasInfo and GetAtlasInfo(action.atlas) then
        texture:SetAtlas(action.atlas)
        texture:SetRotation(0)
        return
    end

    texture:SetTexture(action.key == "onDelete" and theme.crossTexture or theme.stepperTexture)
    texture:SetRotation(action.rotation or 0)
end

---@class KajiGUISectionHeaderAction : Button
---@field icon Texture
---@field _callback fun()?
---@field _restAlpha number

---@class KajiGUISectionHeaderMixin : Button, BackdropTemplate
---@field gui KajiGUIInstance
---@field arrow Texture
---@field hoverBg Texture
---@field _syncHover fun(r: number, g: number, b: number, a?: number)
---@field _setHovered fun(hovered: boolean)
---@field _hovered boolean? the pointer is on the row or one of its buttons
---@field _hoverCard table?
---@field _hoverKey any
---@field label FontString
---@field summary FontString
---@field actions table<string, KajiGUISectionHeaderAction>
---@field _title string
---@field _summary string?
---@field _summaryColor number[]?
---@field _textLeft number
---@field _textRight number negative, the action cluster's left edge from the row's right
local SectionHeaderMixin = {}

---@param enabled boolean
function SectionHeaderMixin:SetEnabled(enabled)
    self:SetAlpha(enabled and 1 or 0.5)
    self:EnableMouse(enabled)
end

function SectionHeaderMixin:UpdateColors()
    local theme = self.gui.theme
    Kaji.RefreshBackdrop(self)
    self.label:SetTextColor(theme.textPrimary[1], theme.textPrimary[2], theme.textPrimary[3], 1)
    self.arrow:SetVertexColor(theme.accent[1], theme.accent[2], theme.accent[3], 1)
    for _, action in ipairs(ACTIONS) do
        if action.texture then
            SetIcon(self.actions[action.key].icon, action, theme)
        end
    end
    self:SetSummary(self._summary, self._summaryColor)
end

---@param title string
function SectionHeaderMixin:SetTitle(title)
    self._title = title or ""
    self:SetSummary(self._summary, self._summaryColor)
end

---The text after the title, in the secondary text colour unless given one; nil shows the title alone.
---@param summary string?
---@param color? number[]
function SectionHeaderMixin:SetSummary(summary, color)
    self._summary, self._summaryColor = summary, color
    self.summary:SetText(summary or "")
    local text = color or self.gui.theme.textSecondary
    self.summary:SetTextColor(text[1], text[2], text[3], 1)
    Kaji.SetTooltip(self, self.gui, self._title, summary, TOOLTIP_OPTIONS)
    self:LayoutText()
end

---The title takes the width it needs and the summary what's left, so a long list of changes truncates before the name does.
function SectionHeaderMixin:LayoutText()
    local room = self:GetWidth() - self._textLeft + self._textRight
    local fits = false
    self.label:SetText(self._title)
    if room > 0 then
        local titleWidth = self.label:GetUnboundedStringWidth()
        fits = self._summary ~= nil and room - titleWidth - SUMMARY_GAP >= SUMMARY_MIN
        if fits then
            self.label:SetText(format("%s:", self._title))
            titleWidth = self.label:GetUnboundedStringWidth()
        end
        -- one pixel over the measured width since snapping it down truncates a title that fits
        self.label:NCSetWidth(min(titleWidth + 1, room))
    else
        -- not laid out yet: the title sizes itself until OnSizeChanged brings the real width
        self.label:SetWidth(0)
    end
    self.summary:SetShown(fits)
end

---@param parent Frame
---@param labelText? string
---@param config table
function SectionHeaderMixin:OnAcquire(parent, labelText, config)
    local theme = self.gui.theme

    self:SetParent(parent)
    self:ClearAllPoints()
    self:NCSetHeight(HEIGHT)
    -- Read by FluentCard:Section, so the card lays the row out to a known height rather than
    -- whatever GetHeight happens to report before the frame has been drawn.
    self.layoutHeight = HEIGHT
    self:NCSetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    self:NCSetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

    self._onToggle = config.onToggle
    -- Collapsed points right, expanded points down, matching the main sidebar's headers.
    self.arrow:SetRotation(config.collapsed and mpi / 2 or 0)

    self.gui:ApplyFont(self.label, "normal")
    self.gui:ApplyFont(self.summary, "normal")
    self._title, self._summary, self._summaryColor = labelText or "", config.summary, config.summaryColor

    -- Actions are laid out right to left, so an omitted one leaves no gap; in a list both moves keep a slot.
    local inList = config.onMoveUp ~= nil or config.onMoveDown ~= nil
    local x = -theme.paddingSmall
    for _, action in ipairs(ACTIONS) do
        local button = self.actions[action.key]
        local callback = config[action.key]
        local shown = callback ~= nil or inList and (action.key == "onMoveUp" or action.key == "onMoveDown")

        button:SetShown(shown)
        button._callback = callback
        button._restAlpha = callback and ACTION_ALPHA or ACTION_ALPHA_INERT
        button.icon:SetAlpha(button._restAlpha)
        -- an inert slot lets clicks and hover through to the row
        button:EnableMouse(callback ~= nil)
        if callback then
            Kaji.SetTooltip(button, self.gui, L[action.title], config[action.tooltipKey], TOOLTIP_OPTIONS)
        else
            Kaji.ClearTooltip(button)
        end

        if shown then
            button:ClearAllPoints()
            button:NCSetPoint("RIGHT", self, "RIGHT", x, 0)
            x = x - ACTION_SIZE - ACTION_SPACING
        end
    end

    -- The text stops where the action cluster starts, so it truncates instead of running under it.
    self._textLeft, self._textRight = theme.paddingSmall + ARROW_SIZE + 6, x - theme.paddingSmall
    self.label:ClearAllPoints()
    self.label:NCSetPoint("LEFT", self, "LEFT", self._textLeft, 0)
    self.summary:ClearAllPoints()
    self.summary:NCSetPoint("LEFT", self.label, "RIGHT", SUMMARY_GAP, 0)
    self.summary:NCSetPoint("RIGHT", self, "RIGHT", self._textRight, 0)

    self:SetAlpha(1)
    self:EnableMouse(true)
    self:UpdateColors()
    self:Show()
end

---Ties the row to its section, and starts it lit when it replaces a hovered row, as a rebuild under the pointer does.
---@param card table
---@param key any
function SectionHeaderMixin:ClaimHover(card, key)
    local gui = self.gui
    self._hoverCard, self._hoverKey = card, key
    if gui._releasedHoverCard ~= card or gui._releasedHoverKey ~= key then return end

    gui._releasedHoverCard, gui._releasedHoverKey = nil, nil
    self._syncHover(0, 0, 0, 1)
    self.hoverBg:SetAlpha(1)

    -- the new row hears OnEnter a frame later, or never if the pointer left during a collapse
    local alive = Kaji.Generation(self)
    C_Timer.After(HOVER_CLAIM_WINDOW, function()
        if alive() and not self._hovered then
            self._setHovered(false)
        end
    end)
end

function SectionHeaderMixin:OnRelease()
    self._onToggle, self._summary = nil, nil
    self.label:SetText("")
    self.summary:SetText("")
    Kaji.ClearTooltip(self)
    if self._hovered then
        self.gui._releasedHoverCard, self.gui._releasedHoverKey = self._hoverCard, self._hoverKey
    end
    self._hovered, self._hoverCard, self._hoverKey = nil, nil, nil
    self._syncHover(0, 0, 0, 0)
    self.hoverBg:SetAlpha(0)
    for _, action in ipairs(ACTIONS) do
        local button = self.actions[action.key]
        button._callback = nil
        Kaji.ClearTooltip(button)
        button:Hide()
    end
end

---@class KajiGUISectionHeader : KajiGUISectionHeaderMixin

Kaji:RegisterWidgetType(WIDGET_TYPE, function(gui)
    local header = CreateFrame("Button", nil, gui._poolHost, "BackdropTemplate") --[[@as KajiGUISectionHeader]]
    header.gui = gui
    header._textLeft, header._textRight = 0, 0 -- OnSizeChanged can come before the first OnAcquire sets them
    header:RegisterForClicks("LeftButtonUp")

    local hoverBg = header:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(1, 1, 1, 0.04)
    hoverBg:SetAlpha(0)
    header.hoverBg = hoverBg

    -- only the tween's alpha channel is used
    local fadeHover, syncHover = Core.Animations:CreateColorAnimator(header, function(_, _, _, alpha)
        hoverBg:SetAlpha(alpha)
    end, { 0, 0, 0, 0 }, gui.theme.animDuration)
    header._syncHover = syncHover

    local function SetHovered(hovered)
        header._hovered = hovered
        fadeHover(0, 0, 0, hovered and 1 or 0)
    end
    header._setHovered = SetHovered

    -- the full text only when the row can't show it
    header:SetScript("OnEnter", function(self)
        SetHovered(true)
        if self.label:IsTruncated() or self.summary:IsTruncated() or self._summary and not self.summary:IsShown() then
            Kaji.ShowTooltip(self)
        end
    end)
    header:SetScript("OnLeave", function()
        SetHovered(false)
        Kaji.HideTooltip()
    end)
    header:SetScript("OnSizeChanged", function(self)
        self:LayoutText()
    end)
    header:SetScript("OnClick", function(self)
        if self._onToggle then safecall(self._onToggle) end
    end)

    local arrow = header:CreateTexture(nil, "OVERLAY")
    arrow:NCSetSize(ARROW_SIZE, ARROW_SIZE)
    arrow:SetTexture(gui.theme.stepperTexture)
    arrow:NCDisablePixelSnap()
    header.arrow = arrow

    local label = header:CreateFontString(nil, "OVERLAY")
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    header.label = label

    local summary = header:CreateFontString(nil, "OVERLAY")
    summary:SetJustifyH("LEFT")
    summary:SetWordWrap(false)
    header.summary = summary

    -- The arrow is placed after the label so both exist before anchoring.
    arrow:NCSetPoint("LEFT", header, "LEFT", gui.theme.paddingSmall, 0)

    -- Every action button is created up front and hidden when unused, so a recycled header never
    -- finds itself missing one.
    header.actions = {}
    for _, action in ipairs(ACTIONS) do
        local button = CreateFrame("Button", nil, header) --[[@as KajiGUISectionHeaderAction]]
        button:NCSetSize(ACTION_SIZE, ACTION_SIZE)

        local icon = button:CreateTexture(nil, "ARTWORK")
        if action.size then
            icon:NCSetSize(action.size, action.size)
            icon:SetPoint("CENTER")
        else
            icon:SetAllPoints()
        end
        icon:NCDisablePixelSnap()
        SetIcon(icon, action, gui.theme)
        button.icon = icon

        -- entering a child fires the row's OnLeave, the row stays lit because the pointer is still on it
        button:SetScript("OnEnter", function(self)
            SetHovered(true)
            if self._callback then
                icon:SetAlpha(1)
            end
            Kaji.ShowTooltip(self)
        end)
        button:SetScript("OnLeave", function(self)
            SetHovered(false)
            icon:SetAlpha(self._restAlpha)
            Kaji.HideTooltip()
        end)
        button:SetScript("OnClick", function(self)
            if self._callback then safecall(self._callback) end
        end)

        button:Hide()
        header.actions[action.key] = button
    end

    return Mixin(header, SectionHeaderMixin)
end)

---@param parent Frame
---@param labelText? string
---@param config? { collapsed?: boolean, summary?: string, onToggle?: fun(), onMoveUp?: fun(), onMoveDown?: fun(), onDuplicate?: fun(), onDelete?: fun() }
---@return KajiGUISectionHeader
function InstanceMixin:CreateSectionHeader(parent, labelText, config)
    return self:BuildWidget(WIDGET_TYPE, parent, labelText, config)
end
