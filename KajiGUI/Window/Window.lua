--[[
# Window

* The library-owned settings window: backdrop, crisp overlay border, draggable header (config-driven logo +
* auto-laid-out buttons), resizable footer (auto-laid-out social buttons + resize handle), a content host,
* session/position persistence and an in-combat defensive guard.
* The consuming addon supplies only config + content: `gui:CreateGUIWindow(opts)`, then `AddHeaderButton` /
* `AddFooterSocial` / `RegisterPage`. All chrome colours self-restyle via OnThemeChanged (no monolithic refresh).

--]]

---@class NRSKNUI
local Core = select(2, ...)
---@class Kaji
local Kaji = Core.Kaji
---@class KajiGUIInstanceMixin
local InstanceMixin = Kaji.InstanceMixin
local Animations = Core.Animations
local safecall = Kaji.safecall

local CreateFrame = CreateFrame
local Mixin = Mixin
local ipairs = ipairs
local wipe = wipe
local type = type
local rad = math.rad
local max = math.max
local InCombatLockdown = InCombatLockdown

local C_Timer = C_Timer
local GameTooltip = GameTooltip
local UIParent = UIParent

local WHITE = Core.WhiteTexture
local HEADER_SLOT = 24 -- a header button's height and its icon's default size
local HEADER_GAP = 8 -- between the drawn shapes of neighbouring header buttons
local SOCIAL_ICON = 21 -- a footer button's height and its icon's default size
local SOCIAL_LIFT = 2 -- how far a hovered footer icon rises
local ICON_HOVER = 0.5 -- an accent icon lightens half as far as a label, a small shift on the bright colour

-- every window any addon made, so something that clears the screen (anchors, the frame chooser) puts them all away
Kaji.windows = {}

---@class KajiGUIWindowMixin
---@field gui KajiGUIInstance
---@field frame Frame & BackdropTemplate
---@field header Frame
---@field footer Frame
---@field _footerText? FontString
---@field content KajiGUIContentHost
---@field contentContainer Frame
---@field _state? table
---@field _defW number
---@field _defH number
local WindowMixin = {}

-- Resolves a logo layer anchor spec { point, [relLayerIndex], relPoint, x, y }. When the second
-- element is a number it anchors to that layer's texture, otherwise to the logo container.
local function ParseAnchor(spec, container, layerTex)
    if not spec then return "LEFT", container, "LEFT", 0, 0 end
    if type(spec[2]) == "number" then
        return spec[1], layerTex[spec[2]], spec[3], spec[4], spec[5]
    end
    return spec[1], container, spec[2], spec[3], spec[4]
end

-- a drag or resize leaves the window off the grid, re-anchor it by its top-left
local function SnapEdges(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left then return end

    frame:NCSetSize(frame:GetSize())
    frame:ClearAllPoints()
    frame:NCSetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

-- Header / Footer builders --

local function BuildHeader(window, logoCfg)
    local gui, theme, parent = window.gui, window.gui.theme, window.frame

    local header = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    header:NCSetHeight(theme.headerHeight)
    header:NCSetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    header:NCSetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    header:SetBackdrop({ bgFile = WHITE })
    Kaji.AddSurfaceTexture(header, gui)

    local bottomBorder = header:CreateTexture(nil, "BORDER")
    bottomBorder:NCSetHeight(theme.borderSize)
    bottomBorder:NCSetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    bottomBorder:NCSetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)

    Kaji.AddTopSheen(header, gui)

    local layerTex = {}
    if logoCfg then
        local container = CreateFrame("Frame", nil, header)
        container:NCSetSize(180, 32)
        container:NCSetPoint("LEFT", header, "LEFT", theme.paddingLarge, -1)

        for i, layer in ipairs(logoCfg.layers or {}) do
            local t = container:CreateTexture(nil, "ARTWORK")
            t:NCSetSize(layer.size, layer.size)
            t:NCSetPoint(ParseAnchor(layer.anchor, container, layerTex))
            t:SetTexture(layer.texture)
            t:NCDisablePixelSnap()
            layerTex[i] = t
            layer._tex = t
            layer._paintGlow = Kaji.AddIconGlow(container, t, layer.size, layer.size, layer.glow, gui)
        end

    end

    local function Restyle()
        header:SetBackdropColor(theme.bgMedium[1], theme.bgMedium[2], theme.bgMedium[3], theme.bgMedium[4])
        bottomBorder:SetColorTexture(theme.border[1], theme.border[2], theme.border[3], theme.border[4])
        if logoCfg then
            for _, layer in ipairs(logoCfg.layers or {}) do
                if layer._tex then
                    local c = theme[layer.color] or theme.textSecondary
                    layer._tex:SetVertexColor(c[1], c[2], c[3], layer.alpha or c[4] or 1)
                    layer._paintGlow(layer.alpha or 1)
                end
            end
        end
    end
    Restyle()
    gui:OnThemeChanged(Restyle)

    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() parent:StartMoving() end)
    header:SetScript("OnDragStop", function()
        parent:StopMovingOrSizing()
        SnapEdges(parent)
        window:SavePosition()
    end)

    window.header = header
end

local function BuildFooter(window)
    local gui, theme, parent = window.gui, window.gui.theme, window.frame

    local footer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    footer:NCSetHeight(theme.footerHeight)
    footer:NCSetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    footer:NCSetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    footer:SetBackdrop({ bgFile = WHITE })
    Kaji.AddSurfaceTexture(footer, gui)

    local topBorder = footer:CreateTexture(nil, "BORDER")
    topBorder:NCSetHeight(theme.borderSize)
    topBorder:NCSetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    topBorder:NCSetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)

    local handle = CreateFrame("Button", nil, footer)
    handle:NCSetSize(23, 23)
    handle:NCSetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", -2, 2)
    handle:EnableMouse(true)

    local htex = handle:CreateTexture(nil, "OVERLAY")
    htex:SetAllPoints()
    htex:SetTexture(theme.resizeHandleTexture)
    htex:NCDisablePixelSnap()

    local function HandleColor(hover)
        local c = hover and theme.accent or theme.textSecondary
        htex:SetVertexColor(c[1], c[2], c[3], hover and 1 or 0.6)
    end
    HandleColor(false)

    handle:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            htex:SetVertexColor(theme.accent[1], theme.accent[2], theme.accent[3], 1)
            parent:StartSizing("BOTTOMRIGHT")
        end
    end)
    handle:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            HandleColor(false)
            parent:StopMovingOrSizing()
            SnapEdges(parent)
            if window.content then C_Timer.After(0.05, window.content.UpdateScrollbar) end
            window:SavePosition()
        end
    end)
    handle:SetScript("OnEnter", function() HandleColor(true) end)
    handle:SetScript("OnLeave", function() HandleColor(false) end)

    footer:EnableMouse(true)
    footer:RegisterForDrag("LeftButton")
    footer:SetScript("OnDragStart", function() parent:StartMoving() end)
    footer:SetScript("OnDragStop", function()
        parent:StopMovingOrSizing()
        SnapEdges(parent)
        window:SavePosition()
    end)

    local function Restyle()
        footer:SetBackdropColor(theme.bgMedium[1], theme.bgMedium[2], theme.bgMedium[3], theme.bgMedium[4])
        topBorder:SetColorTexture(theme.border[1], theme.border[2], theme.border[3], theme.border[4])
        HandleColor(false)
    end
    Restyle()
    gui:OnThemeChanged(Restyle)

    window.footer = footer
end

-- Public window methods --

---Adds a header button, auto-packed from the right edge in add order. Its slot is as wide as the icon's drawn
---shape and the shapes sit a fixed gap apart, so the spacing reads even whatever padding each icon's art has.
---@param config table { icon, glow?, size?, width?, xOffset?, onClick?, tooltip?, rotation?, strata?, yOffset? } width: the drawn shape's, xOffset centres off-centre art
---@return Button
function WindowMixin:AddHeaderButton(config)
    local gui, theme, header = self.gui, self.gui.theme, self.header
    local size = config.size or HEADER_SLOT
    local width = config.width or size

    local btn = CreateFrame("Button", nil, header)
    btn:NCSetSize(width, HEADER_SLOT)
    btn:NCSetPoint("RIGHT", header, "RIGHT", self._headerCursor, config.yOffset or 0)
    self._headerCursor = self._headerCursor - width - HEADER_GAP
    if config.strata then btn:SetFrameStrata(config.strata) end

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:NCSetSize(size, size)
    tex:NCSetPoint("CENTER", btn, "CENTER", config.xOffset or 0, 0)
    tex:SetTexture(config.icon)
    tex:NCDisablePixelSnap()
    if config.rotation then tex:SetRotation(rad(config.rotation)) end
    btn:SetNormalTexture(tex)
    local paintGlow = Kaji.AddIconGlow(btn, tex, size, size, config.glow, gui, config.rotation and rad(config.rotation))

    -- the accent at rest, lightened a little on hover; the setter reads the accent live for theme changes
    local function Paint(hover)
        tex:SetVertexColor(Kaji.HoverColor(theme, theme.accent, hover * ICON_HOVER))
        paintGlow(1)
    end
    Paint(0)
    local animateHover = Animations:CreateColorAnimator(btn, function(hover) Paint(hover) end, { 0, 0, 0, 0 }, theme.animDuration)

    -- A button that toggles something rests lightened, so the state reads without a hover.
    local function IdleHover()
        return btn._active and 1 or 0
    end

    ---@param active boolean
    function btn:SetActive(active)
        btn._active = active and true or false
        animateHover(IdleHover(), 0, 0, 0)
    end

    gui:OnThemeChanged(function() Paint(IdleHover()) end)

    btn:SetScript("OnEnter", function()
        animateHover(1, 0, 0, 0)
        if config.tooltip then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT", 0, 10)
            GameTooltip:SetText(config.tooltip, theme.accent[1], theme.accent[2], theme.accent[3], 1, false)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        animateHover(IdleHover(), 0, 0, 0)
        GameTooltip:Hide()
    end)
    if config.onClick then
        btn:SetScript("OnClick", function() safecall(config.onClick, btn) end)
    end

    return btn
end

---Adds a footer social button, an icon auto-packed from the left edge in add order. It rests muted and takes its
---own colour on hover, with its glow and a small lift. As in the header, its slot is as wide as the icon's drawn
---shape and the shapes sit a fixed gap apart.
---@param config table { icon, glow?, size?, width?, color?, onClick?, tooltip?, tooltipText? } color: the icon's rgb on hover and its tooltip title's, the accent without it
---@return Button
function WindowMixin:AddFooterSocial(config)
    local gui, theme, footer = self.gui, self.gui.theme, self.footer
    local size = config.size or SOCIAL_ICON
    local width = config.width or size

    local btn = CreateFrame("Button", nil, footer)
    btn:NCSetSize(width, SOCIAL_ICON)
    btn:NCSetPoint("LEFT", footer, "LEFT", self._footerCursor, 0)
    self._footerCursor = self._footerCursor + width + theme.paddingMedium

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:NCSetSize(size, size)
    tex:SetTexture(config.icon)
    tex:NCDisablePixelSnap()
    local paintGlow = Kaji.AddIconGlow(btn, tex, size, size, config.glow, gui)

    local function Paint(hover)
        local rest, color = theme.textSecondary, config.color or theme.accent
        tex:SetVertexColor(rest[1] + (color[1] - rest[1]) * hover, rest[2] + (color[2] - rest[2]) * hover, rest[3] + (color[3] - rest[3]) * hover)
        paintGlow(hover, color)
        tex:NCSetPoint("CENTER", btn, "CENTER", 0, hover * SOCIAL_LIFT)
    end
    Paint(0)
    local animateHover = Animations:CreateColorAnimator(btn, function(hover) Paint(hover) end, { 0, 0, 0, 0 }, theme.animDuration)
    gui:OnThemeChanged(function() Paint(0) end)

    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function() safecall(config.onClick) end)
    btn:SetScript("OnEnter", function()
        animateHover(1, 0, 0, 0)
        if config.tooltip then
            local color, secondary = config.color or theme.accent, theme.textSecondary
            GameTooltip:SetOwner(btn, "ANCHOR_TOP", 0, 4)
            GameTooltip:SetText(config.tooltip, color[1], color[2], color[3], 1, false)
            if config.tooltipText then
                GameTooltip:AddLine(config.tooltipText, secondary[1], secondary[2], secondary[3])
            end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        animateHover(0, 0, 0, 0)
        GameTooltip:Hide()
    end)

    return btn
end

---Puts a line of muted text in the footer after the socials, so add them first; the right end is the resize handle's.
---@param text string
function WindowMixin:SetFooterText(text)
    local label = self._footerText
    if not label then
        local gui, theme = self.gui, self.gui.theme
        label = self.footer:CreateFontString(nil, "OVERLAY")
        label:NCSetPoint("LEFT", self.footer, "LEFT", self._footerCursor + theme.paddingSmall, 0)
        gui:ApplyFont(label, "small")
        label:SetShadowColor(0, 0, 0, 0)
        local function Restyle()
            label:SetTextColor(theme.textMuted[1], theme.textMuted[2], theme.textMuted[3], 1)
        end
        Restyle()
        gui:OnThemeChanged(Restyle)
        self._footerText = label
    end
    label:SetText(text)
end

---Builds and shows the page registered under id, remembering it as the current page.
---Mirrors what selecting the entry in the sidebar does, so external navigation also
---expands the owning header rather than selecting an entry that stays hidden.
---@param id string
---@param target? table optional page target, e.g. { tabId = ..., itemKey = ... }
function WindowMixin:ShowPage(id, target)
    self._currentId = id
    if self.content then self.content:ShowPage(id, target) end
    if self.sidebar then
        if self.sidebar:EnsureExpandedFor(id) then self.sidebar:Refresh() end
        self.sidebar:SetSelected(id)
    end
end

---Builds the navigation sidebar + search box from a config list and wires selection to ShowPage.
---@param config table[] sidebar entry list (headers / items)
---@param opts? table { isDisabled?: fun(entry): boolean, redirect?: fun(id): boolean, search?: table[] entries searched like the config's but not listed }
---@return table sidebar
function WindowMixin:SetSidebar(config, opts)
    opts = opts or {}
    local gui, theme, frame = self.gui, self.gui.theme, self.frame
    self._sidebarConfig = config
    local searchConfig = {} -- the config's entries, then opts.search's: the config gains entries after this runs
    local searchBoxHeight = Kaji.SearchBoxHeight(theme)

    -- Inset the content to the right of the sidebar column.
    self.contentContainer:ClearAllPoints()
    self.contentContainer:NCSetPoint("TOPLEFT", frame, "TOPLEFT", theme.sidebarWidth, -theme.headerHeight)
    self.contentContainer:NCSetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, theme.footerHeight)

    -- the search tops the sidebar's panel, the list under it; the scrollbar's track runs past it, so it steps aside
    local sidebar, search
    local scrollbarShown = false
    local function AnchorSearch(shown)
        scrollbarShown = shown
        if not search then return end

        search:ClearAllPoints()
        search:NCSetPoint("TOPLEFT", sidebar.panel, "TOPLEFT", theme.borderSize, -theme.borderSize)
        search:NCSetPoint("TOPRIGHT", sidebar.panel, "TOPRIGHT", -(shown and theme.scrollbarWidth or theme.borderSize), -theme.borderSize)
    end

    sidebar = gui:CreateSidebar(frame, {
        config = config,
        top = searchBoxHeight,
        onScrollbar = AnchorSearch,
        isDisabled = opts.isDisabled,
        onSelect = function(id, searchResult)
            -- an entry can open something else rather than one of this window's pages
            if opts.redirect and opts.redirect(id) then return end

            self._currentId = id
            if searchResult and searchResult.isWidget then
                -- Open on the tab / sidebar item that owns the matched widget, then scroll to it.
                self.content:ShowPage(id, { tabId = searchResult.tabId, itemKey = searchResult.itemKey })
                self.content:ScrollToLabel(searchResult.text)
            else
                self.content:ShowPage(id)
            end
            sidebar:EnsureExpandedFor(id)
            self:SavePosition()
        end,
    })
    sidebar.frame:NCSetPoint("TOPLEFT", frame, "TOPLEFT", 0, -theme.headerHeight)
    sidebar.frame:NCSetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, theme.footerHeight)
    sidebar.frame:NCSetWidth(theme.sidebarWidth)
    self.sidebar = sidebar

    search = gui:CreateSearchBox(sidebar.panel, {
        height = searchBoxHeight,
        onChanged = function(text)
            if text == "" then
                sidebar:ClearResults()
            else
                wipe(searchConfig)
                for _, entry in ipairs(config) do
                    searchConfig[#searchConfig + 1] = entry
                end
                for _, entry in ipairs(opts.search or {}) do
                    searchConfig[#searchConfig + 1] = entry
                end
                sidebar:ShowResults(gui:Search(text, searchConfig))
            end
        end,
    })
    AnchorSearch(scrollbarShown)
    self.searchBox = search

    -- Initial render with config defaults. Session (expansion/selection) restores on first Show
    -- via RestorePosition, once the saved DB is available (it isn't at file-load time).
    if self._currentId then sidebar:EnsureExpandedFor(self._currentId) end
    sidebar:Refresh()
    if self._currentId then sidebar:SetSelected(self._currentId) end

    return sidebar
end

function WindowMixin:Show()
    if self._showing then return end
    self._showing = true

    if self.inCombat then
        if self._onCombatDefer then safecall(self._onCombatDefer) end
        self.reopenAfterCombat = true
        self._showing = false
        return
    end

    if not self._restored then
        self:RestorePosition()
        self._restored = true
    end

    -- whatever puts windows away (a positioning mode) ends first, which can bring this one back itself
    if Kaji.beforeWindowShow then safecall(Kaji.beforeWindowShow, self) end

    -- still put away by something else: asked for, so it's back for good; no onShow, it never closed
    if self._suspended then
        self._suspended = nil
        self.frame:Show()
        if self._currentId then self:ShowPage(self._currentId) end
    end
    if self:IsShown() then
        self.frame:Raise()
        self._showing = false
        return
    end

    Kaji.ResetNoticePulses(self.gui)

    self.frame:Show()
    self.frame:Raise()
    if self._currentId then self:ShowPage(self._currentId) end
    if self._onShow then safecall(self._onShow) end

    self._showing = false
end

function WindowMixin:Hide()
    self.reopenAfterCombat = nil -- closed on purpose, the end of combat doesn't bring it back

    -- a suspended window is already off screen, so closing it is only the close itself
    if self._suspended then
        self._suspended = nil
        if self._onClose then safecall(self._onClose) end
        return
    end

    self.frame:Hide() -- OnHide handles persistence + onClose
end

---Steps aside without closing: no onClose, so previews and pending prompts stay as they are.
---Counted, so a window two things put away comes back when the last of them resumes it.
---@return boolean suspended false when it wasn't open, so the caller has nothing to resume
function WindowMixin:Suspend()
    if not (self:IsShown() or self._suspended) then return false end

    self._suspended = (self._suspended or 0) + 1
    self.frame:Hide()
    return true
end

---Brings a suspended window back on its page, rebuilt so it shows whatever changed meanwhile.
function WindowMixin:Resume()
    if not self._suspended then return end

    self._suspended = self._suspended > 1 and self._suspended - 1 or nil
    if self._suspended then return end

    self.frame:Show()
    self.frame:Raise()
    if self._currentId then self:ShowPage(self._currentId) end
end

function WindowMixin:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end

---@return boolean
function WindowMixin:IsShown()
    return self.frame:IsShown() and true or false
end

function WindowMixin:SavePosition()
    local state = self._state
    if not state or not state.save then return end
    local frame = self.frame
    local point, _, relPoint, x, y = frame:GetPoint()
    state.save({
        frame = {
            point = point,
            relativePoint = relPoint,
            xOffset = x,
            yOffset = y,
            width = frame:GetWidth(),
            height = frame:GetHeight(),
        },
        currentPage = self._currentId,
        sidebarExpanded = self.sidebar and self.sidebar:GetExpanded() or nil,
    })
end

function WindowMixin:RestorePosition()
    local state = self._state
    local data = state and state.load and state.load()
    if not data then return end
    if data.frame then
        local f = data.frame
        self.frame:ClearAllPoints()
        self.frame:NCSetPoint(f.point or "CENTER", UIParent, f.relativePoint or "CENTER", f.xOffset or 0, f.yOffset or 50)
        -- Clamped so a size saved under an older/smaller layout can never restore below the current minimum.
        if f.width and f.height then
            self.frame:NCSetSize(max(f.width, self._minW or 0), max(f.height, self._minH or 0))
        end
    end
    if data.currentPage then self._currentId = data.currentPage end
    if self.sidebar then
        if data.sidebarExpanded then self.sidebar:SetExpanded(data.sidebarExpanded) end
        if self._currentId then self.sidebar:EnsureExpandedFor(self._currentId) end
        self.sidebar:Refresh()
        self.sidebar:SetSelected(self._currentId)
    end
end

---Snaps the window back to the anchor and size it was created with, then persists that.
---The frame is not clamped to the screen, so this is the escape hatch for one dragged out of view.
function WindowMixin:ResetPosition()
    self.frame:ClearAllPoints()
    self.frame:NCSetPoint("CENTER", UIParent, "CENTER", 0, 50)
    self.frame:NCSetSize(self._defW, self._defH)
    -- The saved position is now the default one, so a later Show has nothing left to restore.
    self._restored = true
    self:SavePosition()
end

-- Constructor --

---@class KajiGUIWindowOptions
---@field name? string global frame name
---@field size? number[] { width, height }
---@field minSize? number[] { minWidth, minHeight }
---@field logo? table { layers = { {texture,size,anchor,color,alpha}, ... } }
---@field state? table { load: fun(): table?, save: fun(data: table) } addon-owned persistence
---@field defaultPage? string page id shown on first open
---@field onShow? fun()
---@field onClose? fun()
---@field onCombatDefer? fun() called when Show is blocked by combat

---Creates the library-owned settings window.
---@param opts? KajiGUIWindowOptions
---@return KajiGUIWindow
function InstanceMixin:CreateGUIWindow(opts)
    opts = opts or {}
    local gui = self
    local theme = self.theme

    -- The high-strata reparent target for open dropdowns (folds in the old GUIOverlay).
    if not self.overlay then
        local overlay = CreateFrame("Frame", nil, UIParent)
        overlay:SetAllPoints(UIParent)
        overlay:SetFrameStrata("FULLSCREEN_DIALOG") -- below TOOLTIP so item tooltips draw over the list
        overlay:SetFrameLevel(200) -- above prompts at level 100
        overlay:EnableMouse(false)
        self.overlay = overlay
    end

    local w = (opts.size and opts.size[1]) or 950
    local h = (opts.size and opts.size[2]) or 700
    local minW = (opts.minSize and opts.minSize[1]) or w
    local minH = (opts.minSize and opts.minSize[2]) or h

    local frame = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
    frame:NCSetSize(w, h)
    frame:NCSetPoint("CENTER", UIParent, "CENTER", 0, 50)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(false)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(minW, minH)
    frame:EnableMouse(true)
    -- Border only: header, sidebar, footer and content each paint their own single fill. A base fill
    -- here would stack under all of them, and translucent theme colours would compound.
    frame:SetBackdrop({ edgeFile = WHITE, edgeSize = theme.borderSize })
    frame:NCDisablePixelSnap()

    -- Frames don't clip their own regions; the glow's clear centre leaves the translucent window undarkened.
    local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    shadow:SetTexture(theme.glowTexture)
    shadow:SetTextureSliceMargins(16, 16, 16, 16)
    shadow:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    shadow:SetPoint("TOPLEFT", frame, "TOPLEFT", -theme.shadowSize, theme.shadowSize)
    shadow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", theme.shadowSize, -theme.shadowSize)
    shadow:SetVertexColor(0, 0, 0, theme.shadowAlpha)
    frame:Hide()

    ---@class KajiGUIWindow : KajiGUIWindowMixin
    local window = Mixin({ gui = gui, frame = frame }, WindowMixin)
    window._state = opts.state
    window._onShow = opts.onShow
    window._onClose = opts.onClose
    window._onCombatDefer = opts.onCombatDefer
    window._currentId = opts.defaultPage
    window._minW, window._minH = minW, minH
    window._defW, window._defH = w, h
    window._headerCursor = -(theme.paddingMedium + 2) -- running right edge for header buttons
    window._footerCursor = theme.paddingMedium       -- running left edge for footer socials
    window.inCombat = InCombatLockdown() and true or false

    local function RestyleFrame()
        local a = theme.accent
        frame:SetBackdropBorderColor(a[1], a[2], a[3], theme.windowEdgeAlpha)
    end
    RestyleFrame()
    gui:OnThemeChanged(RestyleFrame)

    BuildHeader(window, opts.logo)

    -- Content fills the area between header and footer. SetSidebar insets the left edge later.
    local container = CreateFrame("Frame", nil, frame)
    container:NCSetPoint("TOPLEFT", frame, "TOPLEFT", 0, -theme.headerHeight)
    container:NCSetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, theme.footerHeight)
    window.contentContainer = container
    window.content = gui:CreateContentHost(container, {})

    BuildFooter(window)

    -- Keyboard: ESC closes, everything else propagates.
    frame:EnableKeyboard(true)
    frame:SetScript("OnKeyDown", function(f, key)
        if key == "ESCAPE" then
            f:SetPropagateKeyboardInput(false)
            window:Hide()
        else
            f:SetPropagateKeyboardInput(true)
        end
    end)

    frame:SetScript("OnHide", function()
        window:SavePosition()
        if window._suspended then return end

        if window._onClose then safecall(window._onClose) end
    end)

    -- Defensive combat guard: hide on combat start, reopen after if it was open.
    local combatFrame = CreateFrame("Frame")
    combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            window.inCombat = true
            -- one put away counts as open, or it would come back mid fight without ever having closed
            if window:IsShown() or window._suspended then
                window:Hide()
                window.reopenAfterCombat = true
            end
        else
            window.inCombat = false
            if window.reopenAfterCombat then
                window.reopenAfterCombat = nil
                window:Show()
            end
        end
    end)

    Kaji.windows[#Kaji.windows + 1] = window
    return window
end
