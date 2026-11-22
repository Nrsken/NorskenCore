--[[
# Side panel

A panel docked to a window's right edge, holding a page the caller fills. It belongs to the view it
opened on and to a key, so the box a card rebuild hands back takes it over, and any other view closes it

## Example

    row:EditBox(L['Display Text'], {
        value = element.Text,
        panel = { key = 'text1', title = L['Dynamic Text Replacements'], build = BuildCodes },
        callback = Save,
    })
]]

---@class NorskenCore
local Core = select(2, ...)
---@class Kaji
local Kaji = Core.Kaji

local CreateFrame = CreateFrame

local WIDTH = 300

---@class KajiGUISidePanelConfig
---@field key string the box's identity in its view, the same after a card rebuild
---@field title string
---@field tooltip? string the edit box button's, under the title
---@field build fun(page: KajiGUIPage, insert: fun(code: string))

---@class KajiGUISidePanel
---@field frame Frame|BackdropTemplate
---@field title FontString
---@field scrollFrame ScrollFrame
---@field scrollChild Frame
---@field scrollbar KajiGUIScrollbarMixin
---@field UpdateScrollbar fun()

---@class KajiGUISidePanelState
---@field window KajiGUIWindowMixin
---@field panel KajiGUISidePanel
---@field key string
---@field view? string
---@field box? KajiGUIEditBoxMixin
---@field cursor? number

-- One open panel over every window
local active ---@type KajiGUISidePanelState?

local function Close()
    local state = active
    if not state then return end

    active = nil
    if state.box then
        state.box:SetPanelOpen(false)
    end
    Kaji.ClearScrollChild(state.window.gui, state.panel.scrollChild)
    state.panel.frame:Hide()
end

-- The code goes at the cursor the box kept, then the box saves and takes the focus back
---@param code string
local function Insert(code)
    local box = active and active.box
    if not box then return end

    box.editBox:Insert(code)
    local cursor = box.editBox:GetCursorPosition()
    box:Commit()

    -- The save's card rebuild may have handed back another box, so ask again
    local now = active and active.box
    if now then
        now.editBox:SetFocus()
        now.editBox:SetCursorPosition(cursor)
    end
end

---@param window KajiGUIWindowMixin
---@return KajiGUISidePanel
local function CreatePanel(window)
    local gui = window.gui
    local theme = gui.theme
    local edge = theme.borderSize

    local frame = CreateFrame('Frame', nil, window.frame, 'BackdropTemplate')
    frame:NCSetPoint('TOPLEFT', window.frame, 'TOPRIGHT', theme.paddingSmall, 0)
    frame:NCSetPoint('BOTTOMLEFT', window.frame, 'BOTTOMRIGHT', theme.paddingSmall, 0)
    frame:NCSetWidth(WIDTH)
    frame:EnableMouse(true)
    frame:Hide()

    -- Edge only, as the window's, so the header and body fills don't stack on a third
    frame:SetBackdrop({ edgeFile = Core.WhiteTexture, edgeSize = edge })
    frame:NCDisablePixelSnap()
    local RestyleEdge = Kaji.StylePopup(frame, gui)
    RestyleEdge()
    gui:OnThemeChanged(RestyleEdge)

    local header = Kaji.CreateHeaderBar(gui, frame)

    local body = CreateFrame('Frame', nil, frame, 'BackdropTemplate')
    body:NCSetPoint('TOPLEFT', header, 'BOTTOMLEFT', 0, 0)
    body:NCSetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 0, 0)
    Kaji.AddPageGround(body, gui)

    local title = header:CreateFontString(nil, 'OVERLAY')
    title:NCSetPoint('CENTER', header, 'CENTER', 0, 0)
    gui:ApplyFont(title, 'large')

    local close = Kaji.HeaderIcon('close')
    close.onClick = Close
    Kaji.CreateHeaderButton(gui, header, close)

    local function PaintTitle()
        local accent = theme.accent
        title:SetTextColor(accent[1], accent[2], accent[3], 1)
    end
    PaintTitle()
    gui:OnThemeChanged(PaintTitle)

    local scrollFrame = CreateFrame('ScrollFrame', nil, body)
    scrollFrame:SetClipsChildren(true)
    scrollFrame:NCSetPoint('TOPLEFT', body, 'TOPLEFT', 0, -theme.paddingSmall)
    scrollFrame:NCSetPoint('BOTTOMRIGHT', body, 'BOTTOMRIGHT', -edge, edge)

    local scrollChild = CreateFrame('Frame', nil, scrollFrame)
    scrollChild:NCSetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    local scrollbar = gui:CreateScrollbar(scrollFrame, {
        width = theme.scrollbarWidth,
        thumbHeight = 40,
        padding = { top = 0, bottom = 0, right = 0 },
        scrollStep = 40,
    })

    local function UpdateScrollbar()
        local shown = scrollbar:UpdateVisibility(scrollChild:GetHeight(), scrollFrame:GetHeight())
        local width = scrollFrame:GetWidth()
        if width > 0 then
            scrollChild:NCSetWidth(width - (shown and theme.scrollbarWidth or 0))
        end
        scrollFrame:UpdateScrollChildRect()
    end
    scrollFrame:HookScript('OnSizeChanged', UpdateScrollbar)

    -- It hides with its window too, so one coming back can't hold a stale box
    frame:SetScript('OnHide', function()
        if active and active.panel.frame == frame then
            Close()
        end
    end)

    -- A rebuild that drops its box for good, a shut section or a removed text, closes it
    frame:NCSetScheduledUpdate(function()
        if active and active.panel.frame == frame and not active.box then
            Close()
        end
    end)

    return {
        frame = frame,
        title = title,
        scrollFrame = scrollFrame,
        scrollChild = scrollChild,
        scrollbar = scrollbar,
        UpdateScrollbar = UpdateScrollbar,
    }
end

---@param window KajiGUIWindowMixin
---@param box KajiGUIEditBoxMixin
---@param config KajiGUISidePanelConfig
local function Open(window, box, config)
    local gui = window.gui
    window._sidePanel = window._sidePanel or CreatePanel(window)
    local panel = window._sidePanel
    active = { window = window, panel = panel, key = config.key, view = window.content.view, box = box }

    panel.title:SetText(config.title)
    panel.frame:Show()
    panel.UpdateScrollbar()

    local page = gui:CreatePage(panel.scrollChild, 0, { onLayout = panel.UpdateScrollbar })
    config.build(page, Insert)
    page:Finish()
    panel.scrollbar:SetValue(0)
    panel.UpdateScrollbar()
    box:SetPanelOpen(true)
end

-- Exports --

---Opens the panel for a box, closing it instead when it's already that box's
---@param box KajiGUIEditBoxMixin
---@param config KajiGUISidePanelConfig
function Kaji.ToggleSidePanel(box, config)
    local same = active and active.box == box
    Close()
    if same then return end

    local window = Kaji.WindowOf(box)
    if window then
        Open(window, box, config)
    end
end

---A box with a panel key was acquired, a nil key says it was released
---@param box KajiGUIEditBoxMixin
---@param key string?
function Kaji.TrackSidePanelBox(box, key)
    if not active then return end

    -- A box's own save rebuilds it before a code click lands, so its cursor goes to the next one
    if not key then
        if active.box == box then
            active.cursor = box.editBox:GetCursorPosition()
            active.box = nil
            active.panel.frame:NCScheduleUpdate()
        end
        return
    end
    if key ~= active.key or Kaji.WindowOf(box) ~= active.window then return end

    -- Displays that disagree show a blank box, so a code there would replace all their texts
    if box._mixed then
        Close()
        return
    end
    active.box = box
    box:SetPanelOpen(true, true)
    if active.cursor then
        box.editBox:SetCursorPosition(active.cursor)
        active.cursor = nil
    end
end

---A content host built a view, any view but the panel's own closes it
---@param host table
function Kaji.ViewBuilt(host)
    if active and active.window.content == host and host.view ~= active.view then
        Close()
    end
end
