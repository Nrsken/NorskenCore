--[[
# Card & Row

* Cards are bordered containers with a vertical stack of rows.
* Rows are horizontal layout containers that manage the relative width of their child widgets.
* These are the layout primitives beneath the fluent Page layer, which is how pages are
  authored - see Page.lua. Build cards through `page:Card()` rather than calling
  CreateCard/CreateRow directly, so widgets are tracked, gated and reflowed for you.
* Both are pooled widgets. Releasing a card releases its rows, and releasing a row
  releases its widgets, so tearing down a page reclaims the whole tree (see Pool.lua).
* A collapsible section's rows go into a clipping body whose height animates on toggle, so the
  rows below it slide instead of jumping.

## Example

    local card = page:Card('Appearance', 'all')
    card:Row(40):Slider('Thickness', { width = 0.5, value = db.Thickness })

--]]

---@class NRSKNUI
local Private = select(2, ...)
---@class Kaji
local Kaji = Private.Kaji
---@class KajiGUIInstanceMixin
local InstanceMixin = Kaji.InstanceMixin
local pixel = Private.Pixel

local CreateFrame = CreateFrame
local Mixin = Mixin
local ipairs = ipairs
local wipe = wipe
local tinsert = table.insert
local abs = math.abs
local floor, max, min = math.floor, math.max, math.min
local pi = math.pi
local pairs = pairs
local C_Timer = C_Timer
local safecall = Kaji.safecall

local CARD_TYPE = "Card"
local ROW_TYPE = "Row"
local HEADER_HEIGHT = 32
local STRIPE_ALPHA = 0.05
local EXPAND_DURATION = 0.2
local COLLAPSE_DURATION = 0.15
-- A section body reaches this far past its rows on three sides, so a glow drawn around a widget
-- still fits inside the body's clip while it animates. Matches glow_small.png's falloff.
local BODY_BLEED = 8

-- Card --

---@class KajiGUICardMixin : Frame
---@field gui KajiGUIInstance
---@field content Frame
---@field header Frame|BackdropTemplate
---@field titleText FontString
---@field corners Frame holds the accent corner ticks, kept above the header band
---@field cornerTicks Texture[]
---@field headerHeight number
---@field contentHeight number
---@field rows table
---@field currentY number
---@field _leadPad? number
---@field _onHeightChanged? fun(card: KajiGUICard) set by the card stack, for rows that resize themselves
---@field _enabledHandler? fun(enabled: boolean) see FluentCard:SetEnabledHandler
---@field _yOffset number
---@field _body? KajiGUIBodyMixin the section body new rows go into, between BeginBody and EndBody; a sub-section's body sits inside its section's
---@field _bodies KajiGUIBodyMixin[] pooled section bodies
---@field _anims table<any, table> [section key] = { p, from, to, t, duration, onDone?, header? }
---@field _driver? Frame steps the section animations
local CardMixin = {}

-- Section bodies --

---How far open a section is, 0 closed .. 1 open.
---@param key any
---@return number
function CardMixin:GetSectionProgress(key)
    local anim = self._anims[key]
    return anim and anim.p or 1
end

---@param key any
---@return table? anim
function CardMixin:GetSectionAnim(key)
    return self._anims[key]
end

---Anchors a row in its host's flow; a body row grows out by the bleed so its rows stay where they'd be.
---@param row Frame
---@param host Frame
---@param left number
---@param top number
---@param right number
local function PlaceRow(row, host, left, top, right)
    if row._isBody then
        left, top, right = left - BODY_BLEED, top - BODY_BLEED, right + BODY_BLEED
    end
    row:ClearAllPoints()
    row:NCSetPoint("TOPLEFT", host, "TOPLEFT", left, -top)
    row:NCSetPoint("TOPRIGHT", host, "TOPRIGHT", right, -top)
end

---Lays a body's rows out and sizes the body to the open part of them, then reflows the card.
---@param body KajiGUIBodyMixin
local function RelayoutBody(body)
    local card = body._owner
    local pad = card.gui.theme.paddingSmall
    local y = 0
    for _, row in ipairs(body.rows) do
        local offset = y + (row._layoutOffsetY or 0)
        PlaceRow(row, body, BODY_BLEED + (row._layoutIndent or 0), BODY_BLEED + offset, -BODY_BLEED)
        y = y + (row._layoutHeight or 24) + (row._layoutSpacing or pad)
    end

    -- Clipping only while it moves: a settled body would cut off glows that reach past a widget's edge.
    -- The bottom is the edge that reveals, so only the other three get the bleed.
    local progress = card:GetSectionProgress(body._key)
    local height = floor(y * progress + 0.5)
    body._layoutHeight = height
    body:NCSetHeight(max(height + BODY_BLEED, 1))
    body:SetClipsChildren(progress < 1)
    body:SetShown(height > 0)
    if body._parentBody then
        RelayoutBody(body._parentBody)
    else
        card:Relayout()
    end
end

-- A body stands in for the card to the rows inside it: they reflow it, and it passes that on.
---@class KajiGUIBodyMixin : Frame
---@field _owner KajiGUICard
---@field _inUse boolean
---@field _key any
---@field _isBody boolean
---@field _parentBody? KajiGUIBodyMixin
---@field _layoutHeight number
---@field rows Frame[]
local BodyMixin = {}

function BodyMixin:Relayout()
    RelayoutBody(self)
end

function BodyMixin:_onHeightChanged()
    local card = self._owner
    if card._onHeightChanged then card._onHeightChanged(card) end
end

---Starts a section body: rows added until EndBody are clipped to how far the section is open.
---A nested body is a sub-section's: it opens inside the current section and ends at EndNestedBody.
---@param key any the section's key, stable across rebuilds
---@param nested? boolean
function CardMixin:BeginBody(key, nested)
    if nested then self:EndNestedBody() else self:EndBody() end
    local parent = self._body

    local body
    for _, b in ipairs(self._bodies) do
        if not b._inUse then body = b break end
    end
    if not body then
        body = Mixin(CreateFrame("Frame", nil, self.content), BodyMixin) --[[@as KajiGUIBodyMixin]]
        body:SetClipsChildren(true)
        body._owner = self
        body.rows = {}
        self._bodies[#self._bodies + 1] = body
    end

    body._inUse = true
    body._key = key
    body._isBody = true
    body._parentBody = parent
    body:SetParent(parent or self.content)
    body:Show()
    self:AddRow(body, 1, 0)
    self._body = body
    RelayoutBody(body)
end

function CardMixin:EndBody()
    self._body = nil
end

---Ends a sub-section's body, back to the section around it.
function CardMixin:EndNestedBody()
    local body = self._body
    if body and body._parentBody then self._body = body._parentBody end
end

---Eases a section's body open or shut, then calls onDone; reversing mid-way starts from where it is.
---@param key any
---@param to 0|1
---@param onDone? fun()
---@return table anim
function CardMixin:AnimateSection(key, to, onDone)
    local running = self._anims[key]
    local from = running and running.p or (to == 1 and 0 or 1)
    local anim = {
        p = from,
        from = from,
        to = to,
        t = 0,
        duration = to == 1 and EXPAND_DURATION or COLLAPSE_DURATION,
        onDone = onDone,
        header = running and running.header,
    }
    self._anims[key] = anim

    if not self._driver then
        self._driver = CreateFrame("Frame", nil, self)
    end
    self._driver:SetScript("OnUpdate", function(_, elapsed) self:StepSections(elapsed) end)
    return anim
end

---@param elapsed number
function CardMixin:StepSections(elapsed)
    local finished, running = {}, false
    for key, anim in pairs(self._anims) do
        anim.t = min(anim.t + elapsed, anim.duration)
        local x = anim.t / anim.duration
        -- Opening eases out (decelerates), closing eases in (accelerates).
        local eased = anim.to > anim.from and (1 - (1 - x) ^ 3) or x * x
        anim.p = anim.from + (anim.to - anim.from) * eased
        if anim.header then anim.header.arrow:SetRotation((1 - anim.p) * pi / 2) end
        if x >= 1 then finished[#finished + 1] = key else running = true end
    end

    for _, body in ipairs(self._bodies) do
        if body._inUse and self._anims[body._key] then RelayoutBody(body) end
    end
    if self._onHeightChanged then self._onHeightChanged(self) end

    if not running then self._driver:SetScript("OnUpdate", nil) end
    for _, key in ipairs(finished) do
        local anim = self._anims[key]
        self._anims[key] = nil
        if anim.onDone then safecall(anim.onDone) end
    end
end

---Re-anchors every entry in the vertical flow from the top, using the height each one was added
---with. Cheap enough to be the single layout path: a card holds a handful of rows.
function CardMixin:Relayout()
    local pad = self.gui.theme.paddingSmall
    local y = self._leadPad or 0

    for _, row in ipairs(self.rows) do
        local offset = y + (row._layoutOffsetY or 0)
        PlaceRow(row, self.content, row._layoutIndent or 0, offset, 0)
        y = y + (row._layoutHeight or 24) + (row._layoutSpacing or pad)
    end

    self.currentY = y
    self.content:NCSetHeight(y > 0 and y or 1)
    self:UpdateHeight()
end

---Adds a row (or any frame) below the previous one.
---@param widget Frame
---@param height? number
---@param spacing? number trailing spacing; pass 0 for the last row
---@return Frame
function CardMixin:AddRow(widget, height, spacing)
    local body = self._body
    local host = body or self
    widget:SetParent(body or self.content)
    widget._card = host
    widget._layoutHeight = height or widget:GetHeight() or 24
    widget._layoutSpacing = spacing or self.gui.theme.paddingSmall

    tinsert(host.rows, widget)
    host:Relayout()

    return widget
end

function CardMixin:UpdateHeight()
    local totalHeight = self.headerHeight + self.currentY + self.gui.theme.paddingSmall * 2
    self:NCSetHeight(totalHeight)
    self.contentHeight = totalHeight
end

---@return number
function CardMixin:GetContentHeight()
    return self.contentHeight
end

---Clears every row so the card can be repopulated (used by fluent card:Rebuild).
---Rows go back to the pool, and each takes its own widgets with it.
function CardMixin:Reset()
    for _, row in ipairs(self.rows) do
        -- Cut the link back to us first: a discarded row must not reflow the card we are rebuilding.
        row._card = nil
        if not row._isBody then self.gui:ReleaseWidget(row) end
    end
    wipe(self.rows)
    for _, body in ipairs(self._bodies) do
        for _, row in ipairs(body.rows) do
            row._card = nil
            if not row._isBody then self.gui:ReleaseWidget(row) end
        end
        wipe(body.rows)
        body._inUse = false
        body:Hide()
    end
    self._body = nil

    self.currentY = 0
    self.contentHeight = 0
    self._leadPad = nil
    self.content:NCSetHeight(1)
    self:NCSetHeight(self.headerHeight + self.gui.theme.paddingMedium * 2)
end

---Dims the card when disabled by the state manager. A card whose inner controls gate
---each other (see FluentCard:SetEnabledHandler) settles them here, after the manager
---has applied the plain per-widget state.
---@param enabled boolean
function CardMixin:SetEnabled(enabled)
    local alpha = enabled and 1 or 0.5
    self:SetAlpha(alpha)
    self.header:SetAlpha(alpha)
    self.titleText:SetAlpha(alpha)

    if self._enabledHandler then self._enabledHandler(enabled) end
end

---@param title string
function CardMixin:SetTitle(title)
    self.titleText:SetText(title)
    self:LayoutHeaderCut()
end

---A marker after the title for a message about the whole card; nil removes it.
---@param notice? KajiGUINotice
function CardMixin:SetNotice(notice)
    Kaji.SetNotice(self, self.gui, self.titleText, notice)
    self:LayoutHeaderCut()
end

---Places the band's 45° slash just past the title and its notice marker.
function CardMixin:LayoutHeaderCut()
    local width = self.titleText:GetStringWidth()
    local tab = pixel.ToPixelGrid(self.gui.theme.paddingMedium * 2 + width + Kaji.NoticeWidth(self))
    local h = pixel.ToPixelGrid(HEADER_HEIGHT)
    local px = pixel.ToPixelGrid(1)
    -- one physical pixel through the centres of the card's top edge and the band's foot, so the corners meet
    self.slope:SetThickness(px)
    self.slope:SetStartPoint("TOPLEFT", self.header, tab, -px / 2)
    self.slope:SetEndPoint("TOPLEFT", self.header, tab + h, px / 2 - h)

    -- a cold font measures 0 on a fresh login's first pass, so place it again once it has loaded
    if width == 0 and (self.titleText:GetText() or "") ~= "" then
        C_Timer.After(0, function()
            if self.header:IsShown() then
                self:LayoutHeaderCut()
            end
        end)
    end
end

---Y position the next card in a stack should start at.
---@return number
function CardMixin:GetNextOffset()
    return self._yOffset + self:GetContentHeight() + self.gui.theme.paddingSmall
end

---An icon action at the right end of the header, tinted in the accent; nil removes it.
---@param config? { atlas?: string, texture?: string|number, size?: number, rotation?: number, tooltip?: string, onClick: fun() }
function CardMixin:SetHeaderButton(config)
    local button = self.headerButton
    if not config then
        if button then
            button:Hide()
            button._onClick = nil
            Kaji.ClearTooltip(button)
        end
        return
    end
    if not button then
        button = CreateFrame("Button", nil, self.header)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:NCSetInside(button, 0, 0)
        icon:NCDisablePixelSnap()
        button.icon = icon
        button:SetScript("OnEnter", function(b)
            local text = self.gui.theme.textPrimary
            b.icon:SetVertexColor(text[1], text[2], text[3])
            Kaji.ShowTooltip(b)
        end)
        button:SetScript("OnLeave", function(b)
            local accent = self.gui.theme.accent
            b.icon:SetVertexColor(accent[1], accent[2], accent[3])
            Kaji.HideTooltip()
        end)
        button:SetScript("OnClick", function(b) if b._onClick then safecall(b._onClick) end end)
        self.headerButton = button
    end

    local size = config.size or 16
    button:ClearAllPoints()
    button:NCSetSize(size, size)
    button:NCSetPoint("RIGHT", self.header, "RIGHT", -self.gui.theme.paddingMedium, 0)
    if config.atlas then
        button.icon:SetAtlas(config.atlas, false)
    else
        button.icon:SetTexture(config.texture)
        button.icon:SetTexCoord(0, 1, 0, 1) -- an atlas leaves its texcoords behind
    end
    button.icon:SetRotation(config.rotation or 0)
    button.icon:SetDesaturated(true)
    button._onClick = config.onClick
    Kaji.SetTooltip(button, self.gui, config.tooltip)
    self:UpdateColors()
    button:Show()
end

---Only the card's own chrome. Rows and widgets are acquired in their own right, so the
---theme fire reaches them directly rather than being recursed into from here.
function CardMixin:UpdateColors()
    local theme = self.gui.theme
    Kaji.RefreshBackdrop(self)
    local band, edge = theme.bgMedium, theme.border
    self.band:SetColorTexture(band[1], band[2], band[3], band[4])
    self.slope:SetColorTexture(edge[1], edge[2], edge[3], edge[4])
    self.baseline:SetColorTexture(edge[1], edge[2], edge[3], edge[4])
    self.titleText:SetTextColor(theme.accent[1], theme.accent[2], theme.accent[3], 1)
    if self.headerButton then self.headerButton.icon:SetVertexColor(theme.accent[1], theme.accent[2], theme.accent[3]) end
    Kaji.PaintCornerTicks(self.cornerTicks, theme)
end

---@param parent Frame
---@param title? string
---@param config table `{ yOffset?: number, width?: number }`
function CardMixin:OnAcquire(parent, title, config)
    local theme = self.gui.theme
    local yOffset = config.yOffset or 0
    local hasHeader = title ~= nil and title ~= ""

    self:SetParent(parent)
    self:ClearAllPoints()
    if config.width then
        self:NCSetWidth(config.width)
        self:NCSetPoint("TOPLEFT", parent, "TOPLEFT", theme.paddingSmall, -yOffset)
    else
        self:NCSetPoint("TOPLEFT", parent, "TOPLEFT", theme.paddingSmall, -yOffset)
        self:NCSetPoint("RIGHT", parent, "RIGHT", -theme.paddingSmall, 0)
    end

    self._yOffset = yOffset
    self._enabledHandler = nil
    self._hasInternalWidgetState = nil
    self._refreshPositions = nil
    self.currentY = 0
    self.contentHeight = 0
    self._leadPad = nil

    -- The header always exists and is hidden for an untitled card, so the height it
    -- contributes is the only thing that varies.
    self.headerHeight = hasHeader and HEADER_HEIGHT or 0
    self.header:SetShown(hasHeader)
    self.titleText:SetText(title or "")
    Kaji.SetNotice(self, self.gui, self.titleText, nil)
    self:LayoutHeaderCut()

    self.content:ClearAllPoints()
    self.content:NCSetPoint("TOPLEFT", self, "TOPLEFT",
        theme.paddingMedium, -self.headerHeight - theme.paddingSmall)
    self.content:NCSetPoint("TOPRIGHT", self, "TOPRIGHT",
        -theme.paddingMedium, -self.headerHeight - theme.paddingSmall)
    self.content:NCSetHeight(1)

    self:SetAlpha(1)
    self.header:SetAlpha(1)
    self.titleText:SetAlpha(1)
    -- Reparenting resets levels, so the ticks are lifted above the header band on every acquire.
    self.corners:SetFrameLevel(self.header:GetFrameLevel() + 1)
    self:UpdateColors()
    self:UpdateHeight()
    self:Show()
end

function CardMixin:OnRelease()
    self:Reset()
    self:SetHeaderButton(nil)
    wipe(self._anims)
    if self._driver then self._driver:SetScript("OnUpdate", nil) end
    self._onHeightChanged = nil
    self._enabledHandler = nil
    self._hasInternalWidgetState = nil
    self._refreshPositions = nil
    self.titleText:SetText("")
end

---@alias KajiGUICard KajiGUICardMixin

Kaji:RegisterWidgetType(CARD_TYPE, function(gui)
    local theme = gui.theme

    local card = CreateFrame("Frame", nil, gui._poolHost, "BackdropTemplate")
    card:EnableMouse(false)
    Kaji.SetBackdrop(card, gui, { bg = "bgLight", border = "border", edgeSize = "borderSize" })

    card.gui = gui
    card.contentHeight = 0
    card.rows = {}
    card._bodies = {}
    card._anims = {}
    card.currentY = 0
    card.headerHeight = 0
    card._yOffset = 0

    local header = CreateFrame("Frame", nil, card)
    header:NCSetHeight(HEADER_HEIGHT)
    header:NCSetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    header:NCSetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    card.header = header

    local band = header:CreateTexture(nil, "BACKGROUND")
    band:NCSetInside(header, 0, 0)
    card.band = band

    -- a 45° slash across the band just past the title, as the portrait skins' tabs; LayoutHeaderCut places it
    card.slope = header:CreateLine(nil, "BORDER")

    -- the band's foot, running on past the cut to the card's edge
    local baseline = header:CreateTexture(nil, "BORDER")
    baseline:NCSetHeight(theme.borderSize)
    baseline:NCSetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    baseline:NCSetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    baseline:NCDisablePixelSnap()
    card.baseline = baseline

    local titleText = header:CreateFontString(nil, "OVERLAY")
    titleText:NCSetPoint("LEFT", header, "LEFT", theme.paddingMedium, 0)
    gui:ApplyFont(titleText, "large")
    card.titleText = titleText

    local content = CreateFrame("Frame", nil, card)
    content:NCSetHeight(1)
    content:EnableMouse(false)
    card.content = content

    -- Body only: a second grain layer on the header band read as noise.
    Kaji.AddSurfaceTexture(card, gui)

    -- Own frame above the header band, which would otherwise cover the top-left ticks.
    local corners = CreateFrame("Frame", nil, card)
    corners:NCSetInside(card, 0, 0)
    corners:EnableMouse(false)
    card.corners = corners

    card.cornerTicks = Kaji.CreateCornerTicks(corners, card, theme)

    -- Highlight on the corners frame so the header band never covers it.
    Kaji.AddTopSheen(header, gui)
    Kaji.AddTopHighlight(corners, gui, "ARTWORK")

    return Mixin(card, CardMixin)
end)

---Creates a card. Anchors full-width to the parent unless an explicit width is given.
---@param parent Frame
---@param title? string
---@param yOffset? number
---@param width? number
---@return KajiGUICard
function InstanceMixin:CreateCard(parent, title, yOffset, width)
    return self:BuildWidget(CARD_TYPE, parent, title, { yOffset = yOffset, width = width })
end

-- Row --

---@class KajiGUIRowMixin : Frame
---@field gui KajiGUIInstance
---@field widgets table
---@field _rowHeight number
---@field _indent number left inset before the first widget
---@field _divider? Texture the bottom rule SetDivider shows
---@field _card? KajiGUICard set when the row is added to a card
local RowMixin = {}

---Resizes the row to fit a widget that measured its own content, and reflows the card around it.
---This is the upward half of the layout: everything above the widget is anchored, so a taller
---widget only becomes visible once the row, the card and the stack all know about it.
---@param height number
function RowMixin:SetContentHeight(height)
    height = pixel.ToPixelGrid(height)
    if abs(height - (self._rowHeight or 0)) < 0.5 then return end

    self._rowHeight = height
    self._layoutHeight = height
    self:NCSetHeight(height)

    local card = self._card
    if not card then return end

    card:Relayout()
    if card._onHeightChanged then card._onHeightChanged(card) end
end

---SetContentHeight for several self-sizing widgets side by side; the row takes the tallest.
---@param widget Frame
---@param height number
function RowMixin:SetWidgetHeight(widget, height)
    self._widgetHeights = self._widgetHeights or {}
    self._widgetHeights[widget] = height

    local tallest = 0
    for _, h in pairs(self._widgetHeights) do
        if h > tallest then tallest = h end
    end
    self:SetContentHeight(tallest)
end

---Adds a widget at a relative width. Widths in a row should sum to 1.0.
---@param widget Frame
---@param widthPct? number
---@param spacing? number
---@param xOffset? number
---@param yOffset? number
---@param fixedWidth? number pixels, in place of a share of the row
---@param columnAt? number where in the row (0..1) it starts
function RowMixin:AddWidget(widget, widthPct, spacing, xOffset, yOffset, fixedWidth, columnAt)
    widthPct = widthPct or 0.5
    spacing = spacing or self.gui.theme.paddingSmall
    xOffset = xOffset or 0
    yOffset = yOffset or 0

    widget:SetParent(self)

    if not widget.explicitHeight then
        widget:NCSetHeight(self._rowHeight)
    end

    widget._widthPct = widthPct
    widget._spacing = spacing
    widget._xOffset = xOffset
    widget._yOffset = yOffset
    widget._fixedWidth = fixedWidth
    widget._columnAt = columnAt
    tinsert(self.widgets, widget)

    self:LayoutWidgets(self:GetWidth())
end

---Resolves every child's width from the row's own, left to right.
---Laid out on every insert rather than only from OnSizeChanged: a pooled row comes back
---at the width it was released at, so the size never changes and that event never fires.
---@param width number
function RowMixin:LayoutWidgets(width)
    if not width or width <= 0 then return end

    local pad = self.gui.theme.paddingSmall
    local indent = self._indent
    local x = indent
    width = width - x
    local count = #self.widgets
    -- An even row takes its shares from the width left after the gaps, so equal shares come out equally wide;
    -- otherwise each widget starts at its share of the full width, which keeps columns lined up across rows.
    local gaps = 0
    if self._even then
        for i, widget in ipairs(self.widgets) do
            if i < count then gaps = gaps + (widget._spacing or pad) end
        end
    end

    for i, widget in ipairs(self.widgets) do
        local spacing = (i == count) and 0 or (widget._spacing or pad)
        local widgetWidth = widget._fixedWidth or (self._even and (width - gaps) * widget._widthPct or width * widget._widthPct - spacing)
        if widget._columnAt then
            x = indent + width * widget._columnAt
        end
        widget:ClearAllPoints()
        widget:NCSetPoint("TOPLEFT", self, "TOPLEFT", x + (widget._xOffset or 0), widget._yOffset or 0)
        widget:NCSetWidth(widgetWidth)
        -- Widgets that derive their inner layout from their width are told directly, for the
        -- same reason: an unchanged width raises no OnSizeChanged for them either.
        if widget.OnLayout then widget:OnLayout(widgetWidth) end
        x = x + widgetWidth + spacing
    end
end

---@param parent Frame
---@param _ any unused; Row takes (parent, config)
---@param config table `{ height?: number, indent?: number }`
function RowMixin:OnAcquire(parent, _, config)
    local height = config.height or 24
    self._indent = config.indent or 0

    self:SetParent(parent)
    self:ClearAllPoints()
    self:NCSetHeight(height)
    self._rowHeight = height
    self:SetAlpha(1)
    self:Show()
end

---A thin rule along the row's bottom edge, for table-like lists.
---@param shown boolean
function RowMixin:SetDivider(shown)
    if shown and not self._divider then
        local line = self:CreateTexture(nil, "BACKGROUND")
        line:NCSetHeight(self.gui.theme.borderSize)
        line:NCSetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, 0)
        line:NCSetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
        line:NCDisablePixelSnap()
        self._divider = line
    end
    if not self._divider then return end

    local color = self.gui.theme.border
    self._divider:SetColorTexture(color[1], color[2], color[3], 1)
    self._divider:SetShown(shown)
end

---A light band behind the row for striping long lists; it reaches into the card's side padding.
---@param shown boolean
function RowMixin:SetStripe(shown)
    if shown and not self._stripe then
        local band = self:CreateTexture(nil, "BACKGROUND", nil, -1)
        local inset = self.gui.theme.paddingSmall
        band:NCSetPoint("TOPLEFT", self, "TOPLEFT", -inset, 0)
        band:NCSetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", inset, 0)
        self._stripe = band
    end
    if not self._stripe then return end

    -- A white wash rather than a theme shade: the background shades sit too close together to read.
    self._stripe:SetColorTexture(1, 1, 1, STRIPE_ALPHA)
    self._stripe:SetShown(shown)
end

function RowMixin:OnRelease()
    -- A row owns its widgets, so releasing it hands them back too. This is what makes a
    -- card teardown reclaim the whole subtree rather than orphaning it.
    self.gui:ReleaseAll(self.widgets)
    if self._divider then self._divider:Hide() end
    if self._stripe then self._stripe:Hide() end
    self._card = nil
    self._rowHeight = 24
    self._indent = 0
    self._even = nil
    self._layoutHeight = nil
    self._layoutSpacing = nil
    self._layoutOffsetY = nil
    self._widgetHeights = nil
end

---@alias KajiGUIRow KajiGUIRowMixin

Kaji:RegisterWidgetType(ROW_TYPE, function(gui)
    local row = CreateFrame("Frame", nil, gui._poolHost) --[[@as KajiGUIRow]]
    row.gui = gui
    row:EnableMouse(false)
    row.widgets = {}
    row._rowHeight = 24
    row._indent = 0

    Mixin(row, RowMixin)
    row:SetScript("OnSizeChanged", function(self, width) self:LayoutWidgets(width) end)

    return row
end)

---Horizontal layout container. Widget widths resolve on resize.
---@param parent Frame
---@param height? number
---@param indent? number left inset before the first widget
---@return KajiGUIRow
function InstanceMixin:CreateRow(parent, height, indent)
    return self:BuildWidget(ROW_TYPE, parent, nil, { height = height, indent = indent })
end
