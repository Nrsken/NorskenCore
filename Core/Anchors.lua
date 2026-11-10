---@class NRSKNUI
local Private = select(2, ...)
local L = Private.L
local Animations = Private.Animations
local pixel = Private.Pixel
---@class NRSKNUI.Anchors
---@field addon table the addon this handle belongs to, see NewAnchors
local Anchors = {}
Private.Anchors = Anchors
Anchors.isActive = false
Anchors.registry = {}
Anchors.overlays = {}
Anchors.selectedKey = nil
Anchors.isShiftFaded = false
Anchors.onlyModule = nil

local math_floor, math_ceil, math_abs, math_rad = math.floor, math.ceil, math.abs, math.rad
local GetPhysicalScreenSize = GetPhysicalScreenSize
local GetCursorPosition = GetCursorPosition
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local GetTime = GetTime
local GameTooltip = GameTooltip
local wipe = wipe
local GetCurrentKeyBoardFocus = GetCurrentKeyBoardFocus
local pairs, ipairs = pairs, ipairs
local CreateFrame = CreateFrame
local format = string.format
local tonumber = tonumber
local type = type

local C_Timer = C_Timer
local UIParent = UIParent
local setmetatable = setmetatable

-- One system for every addon. Each has a handle reading this table through __index, so state only ever
-- gets written to Anchors itself: on self it would land on that one handle.
local addons = {}
local activeAddon -- the addon whose anchors show
local Theme       -- its theme, only one addon's overlays and panel exist on screen at a time
-- nudge panels, one per addon: Kaji widgets belong to the instance that built them and stay in its theme
local panels = {}

local ARROW_TEXTURE = Private.Media.GUITextures .. 'collapse.tga'

-- Overlay Config
local FILL_ALPHA = 0.8
local BOUNDS_FILL_ALPHA = 0.2 -- a box around what an anchor holds shouldn't hide what it's there to show
local BOUNDS_LABEL_INSET = 6
local LAYOUT_SETTLE_DELAY = 0.1 -- groups lay out on the next frame, the boxes around them read that layout
local BORDER_SIZE = 2
local TEXT_FONT_SIZE = 14
local SHIFT_FADE_ALPHA = 0.1
local SNAP_RANGE = 10
local FADE_DURATION = 0.25
local UNSELECTED_ALPHA = 0.8 -- The alpha of overlays that are not selected, when a selection exists.
local DRAG_ALPHA = 0.7       -- The alpha of the overlay being dragged.
local STATE_DURATION = 0.25  -- The duration of the selection fade.
local WHITE = { 1, 1, 1 }
local FOCUS_ALPHA = 0.5     -- the group being worked inside, behind its own displays
local DOUBLE_CLICK = 0.3    -- seconds between two clicks that open a group
local MARKER_SIZE = 6       -- the anchor markers on the selected box

-- Nudge panel
local PANEL_WIDTH, PANEL_HEIGHT = 180, 180
local SWITCHER_HEIGHT = 30 -- the row of addon buttons on top, only with two or more addons

-- Grid Config
local gridFrame = nil
local gridCenterX, gridCenterY = 0, 0
local GRID_SIZE = 64
local GRID_LINE_WIDTH = 1
local GRID_COLOR = { 0, 0, 0, 0.4 }
local GRID_CENTER_ALPHA = 0.4
local ShowGrid

-- Fading --

---Creates a function that fades a frame to a target alpha over time.
---@param frame Frame
---@param duration? number defaults to FADE_DURATION
---@return fun(toAlpha: number)
local function CreateFader(frame, duration) 
    local group = frame:CreateAnimationGroup()
    group:SetToFinalAlpha(true)

    local anim = group:CreateAnimation('Alpha')
    anim:SetDuration(duration or FADE_DURATION)

    group:SetScript('OnFinished', function()
        local target = anim:GetToAlpha()
        frame:SetAlpha(target)
        if target == 0 then frame:Hide() end
    end)

    return function(toAlpha)
        group:Stop()
        if toAlpha > 0 and not frame:IsShown() then
            frame:SetAlpha(0)
            frame:Show()
        end
        anim:SetFromAlpha(frame:GetAlpha())
        anim:SetToAlpha(toAlpha)
        group:Play()
    end
end

local gridFader
local function CreateGrid()
    if gridFrame then return gridFrame end

    gridFrame = CreateFrame('Frame', 'NRSKNUI_AnchorsGrid', UIParent)
    gridFrame:SetFrameStrata('BACKGROUND')
    gridFrame:SetAllPoints(UIParent)
    gridFrame.lines = {}

    gridFrame:RegisterEvent('UI_SCALE_CHANGED')
    gridFrame:RegisterEvent('DISPLAY_SIZE_CHANGED')
    gridFrame:SetScript('OnEvent', function(self)
        if self:IsShown() then ShowGrid() end
    end)

    gridFrame:Hide()
    gridFader = CreateFader(gridFrame)
    return gridFrame
end

---Pulls a line out of the pool, creating it on first use.
---@param index number
---@param isCenter boolean
---@return Texture
local function GetLine(index, isCenter)
    local line = gridFrame.lines[index]
    if not line then
        line = gridFrame:CreateTexture()
        gridFrame.lines[index] = line
    end

    if isCenter then
        line:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], GRID_CENTER_ALPHA)
        line:SetDrawLayer('BACKGROUND', 1)
    else
        line:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], GRID_COLOR[4])
        line:SetDrawLayer('BACKGROUND', 0)
    end

    line:ClearAllPoints()
    line:Show()
    return line
end

local function BuildGridLines()
    local width, height = UIParent:GetSize()
    local physWidth, physHeight = GetPhysicalScreenSize()
    if not physWidth or physWidth == 0 or physHeight == 0 then return end

    local pixel = width / physWidth
    local step = math_floor(physWidth / GRID_SIZE + 0.5) * pixel
    local lineWidth = GRID_LINE_WIDTH * pixel

    gridCenterX, gridCenterY = math_floor(physWidth * 0.5 + 0.5) * pixel, math_floor(physHeight * 0.5 + 0.5) * pixel

    local index = 0
    local function PlaceVertical(x, isCenter)
        index = index + 1
        local line = GetLine(index, isCenter)
        local thickness = isCenter and lineWidth * 2 or lineWidth
        local left = isCenter and x - lineWidth or x
        line:SetPoint('TOPLEFT', gridFrame, 'TOPLEFT', left, 0)
        line:SetPoint('BOTTOMRIGHT', gridFrame, 'BOTTOMLEFT', left + thickness, 0)
    end

    local function PlaceHorizontal(y, isCenter)
        index = index + 1
        local line = GetLine(index, isCenter)
        local thickness = isCenter and lineWidth * 2 or lineWidth
        local top = isCenter and y - lineWidth or y
        line:SetPoint('TOPLEFT', gridFrame, 'TOPLEFT', 0, -top)
        line:SetPoint('BOTTOMRIGHT', gridFrame, 'TOPRIGHT', 0, -(top + thickness))
    end

    for i = -math_ceil(gridCenterX / step), math_ceil((width - gridCenterX) / step) do
        PlaceVertical(gridCenterX + i * step, i == 0)
    end

    for i = -math_ceil(gridCenterY / step), math_ceil((height - gridCenterY) / step) do
        PlaceHorizontal(gridCenterY + i * step, i == 0)
    end

    for i = index + 1, #gridFrame.lines do
        gridFrame.lines[i]:Hide()
    end
end

function ShowGrid()
    if not gridFrame then CreateGrid() end
    BuildGridLines()
    gridFader(1)
end

local function HideGrid()
    if gridFader then gridFader(0) end
end

-- Descriptor resolution --

---Resolves a descriptor field that may be a literal or a function of the module.
local function Resolve(value, module)
    if type(value) == 'function' then
        return value(module)
    end
    return value
end

---The table the offsets live in, matching PositionCard's getPositionTable.
---@param entry table
---@return table? posTable
---@return table? db
local function GetTables(entry)
    -- Read module.db live rather than capturing it: modules reassign self.db in
    -- UpdateDB() on a profile switch, so a captured table would write to the old profile.
    local db
    if entry.db ~= nil then
        db = Resolve(entry.db, entry.module)
    else
        db = entry.module.db
    end
    if not db then return nil, nil end
    return db[Resolve(entry.positionKey, entry.module) or 'Position'], db
end

---Reads an offset with PositionCard's precedence: position table, then db root, then default.
local function ReadOffset(entry, key)
    local posTable, db = GetTables(entry)
    if posTable and posTable[key] ~= nil then return posTable[key] end
    if db and db[key] ~= nil then return db[key] end
    return 0
end

---@param key string
---@return number x
---@return number y
function Anchors:GetOffsets(key)
    local entry = Anchors.registry[key]
    if not entry then return 0, 0 end
    return ReadOffset(entry, entry.xKey), ReadOffset(entry, entry.yKey)
end

---Writes both offsets and re-applies the module. The only path that touches the DB.
---AnchorFrom/AnchorTo are owned by the GUI's PositionCard and are never written here.
---@param key string
---@param x number
---@param y number
function Anchors:SetOffsets(key, x, y)
    local entry = Anchors.registry[key]
    if not entry then return end

    local posTable, db = GetTables(entry)
    local target = posTable or db
    if not target then return end

    target[entry.xKey] = math_floor(x + 0.5)
    target[entry.yKey] = math_floor(y + 0.5)

    local apply = entry.apply
    if type(apply) == 'function' then
        apply(entry.module)
    elseif entry.module[apply] then
        entry.module[apply](entry.module)
    end

    -- Every offset change flows through here, so this is the one place that keeps the
    -- overlay, the nudge panel and the GUI's PositionCard sliders showing the same value.
    C_Timer.After(0, function() self:UpdateOverlay(key) end)
    self:UpdatePanel()

    local addon = entry.addon
    if addon.GUI and addon.GUIFrame and addon.GUIFrame:IsShown() then
        addon.GUI:RefreshPositionCards()
    end
end

---@param entry table
---@return Frame?
local function GetEntryFrame(entry)
    if entry.frame then return entry.frame end
    if entry.frameName then return _G[entry.frameName] end
    return nil
end

-- Registration --

---Whether an anchor belongs in the open view: every anchor or only the module the view opened for.
---@param entry table
---@return boolean
local function InView(entry)
    if entry.addon ~= activeAddon then return false end
    if entry.shown and not entry.shown(entry.module) then return false end
    if Anchors.onlyModule ~= nil and entry.module ~= Anchors.onlyModule then return false end

    -- one level at a time: the top, or the group being worked inside with its own displays
    return entry.parentKey == Anchors.focusKey or entry.key == Anchors.focusKey
end

---Whether a box opens into a group of its own boxes.
---@param key string
---@return boolean
local function HasChildren(key)
    for _, entry in pairs(Anchors.registry) do
        if entry.parentKey == key and entry.addon == activeAddon and not (entry.shown and not entry.shown(entry.module)) then
            return true
        end
    end
    return false
end

---Registers a frame as a draggable anchor.
---@param aceModule NRSKNUI.ModuleBase
---@param key string Unique anchor key.
---@param frame Frame? The frame to move; defaults to module.frame.
---@param guiPath string? Sidebar item id opened by the panel's Open Settings button.
---@param opts table? db, positionKey, xKey, yKey, apply, displayName, frameName, guiContext, shown, bounds, parentKey, locked
function Anchors:Register(aceModule, key, frame, guiPath, opts)
    if not aceModule or not key then return end
    opts = opts or {}

    frame = frame or opts.frame or aceModule.frame
    if not frame and not opts.frameName then return end

    local entry = Anchors.registry[key]
    if not entry then
        entry = { key = key }
        Anchors.registry[key] = entry
    end

    entry.addon = self.addon
    entry.module = aceModule
    entry.frame = frame
    entry.frameName = opts.frameName
    entry.db = opts.db -- nil means 'read module.db live', see GetTables
    entry.positionKey = opts.positionKey or 'Position'
    entry.xKey = opts.xKey or 'XOffset'
    entry.yKey = opts.yKey or 'YOffset'
    entry.apply = opts.apply or 'ApplySettings'
    entry.displayName = opts.displayName or (key:gsub('(%l)(%u)', '%1 %2'))
    entry.guiPath = guiPath or opts.guiPath
    entry.guiContext = opts.guiContext

    -- What the overlay covers, when that is bigger than what the drag moves:
    -- a group of chained frames is dragged by the one frame that carries the position, but should be grabbable across all of them.
    entry.overlayFrame = opts.overlayFrame

    -- shown: whether this anchor means anything right now, a loaded out group has nothing to move.
    -- bounds: for a frame that's only a handle, the left, bottom, right, top of what it carries in
    -- UIParent's units. The overlay shows that area and stays anchored to the frame, so it follows a drag.
    entry.shown = opts.shown
    entry.bounds = opts.bounds

    -- parentKey: the group it sits in, whose box opens to show it. locked: its group places it, so it only selects.
    entry.parentKey = opts.parentKey
    entry.locked = opts.locked

    if type(entry.apply) == 'string' and type(aceModule[entry.apply]) ~= 'function' then
        self.addon:Print(format("Anchor '%s' registered with apply='%s', which the module does not define.", key, entry.apply))
    end

    if Anchors.isActive and InView(entry) then
        self:CreateOverlay(key)
        self:RefreshOverlayState(key) -- a box made mid session takes the look its state calls for
    end
end

---@param key string
function Anchors:Unregister(key)
    if not key then return end

    local overlay = Anchors.overlays[key]
    if overlay then
        overlay:Hide()
        overlay.entry = nil
        Anchors.overlays[key] = nil
    end

    Anchors.registry[key] = nil
    if Anchors.selectedKey == key then self:Select(nil) end
end

-- Overlays --

local overlayHost = CreateFrame('Frame', 'NRSKNUI_AnchorsOverlays', UIParent)
overlayHost:SetAllPoints(UIParent)
overlayHost:SetFrameStrata('TOOLTIP')
overlayHost:Hide()

local FadeOverlays = CreateFader(overlayHost)

-- Drag --

local isDragging = false
local dragEntry = nil
local dragCursorX, dragCursorY = 0, 0
local dragPoint, dragRelTo, dragRelPoint, dragOriginX, dragOriginY
local dragDBX, dragDBY = 0, 0
local dragDeltaX, dragDeltaY = 0, 0
local dragCenterX, dragCenterY, dragRatio = 0, 0, 1
local dragBox -- the dragged box's left, right, bottom, top and centre at drag start, nil when its rect can't be read

-- What a drag snaps to: the edges and centres of the other boxes in view, in UIParent's units like the overlays.
local edgesX, edgesY, centersX, centersY = {}, {}, {}, {}

local dragUpdateFrame = CreateFrame('Frame')
dragUpdateFrame:Hide()

---@param dragKey string
local function CollectSnapLines(dragKey)
    wipe(edgesX)
    wipe(edgesY)
    wipe(centersX)
    wipe(centersY)

    for key, overlay in pairs(Anchors.overlays) do
        -- the open group's box holds what's dragged and doesn't follow it, so it isn't a line to snap to
        if key ~= dragKey and key ~= Anchors.focusKey and overlay:IsShown() and InView(overlay.entry) then
            -- a box around a display holding an aura can't be read while auras are secret, it's skipped
            local left, bottom, width, height = Private:ScrubSecrets(overlay:GetRect())
            if left and bottom and width and height then
                edgesX[#edgesX + 1], edgesX[#edgesX + 2] = left, left + width
                edgesY[#edgesY + 1], edgesY[#edgesY + 2] = bottom, bottom + height
                centersX[#centersX + 1] = left + width / 2
                centersY[#centersY + 1] = bottom + height / 2
            end
        end
    end
end

---The nearest line to `from` within the snap range, if nearer than the one found so far.
---@param from number?
---@param lines number[]
---@param shift number?
---@param line number?
---@return number? shift
---@return number? line
local function Nearest(from, lines, shift, line)
    if not from then return shift, line end

    for i = 1, #lines do
        local gap = lines[i] - from
        if math_abs(gap) < SNAP_RANGE and (not shift or math_abs(gap) < math_abs(shift)) then
            shift, line = gap, lines[i]
        end
    end
    return shift, line
end

-- one entry, so the screen centre goes through Nearest without a table each frame
local screenLine = { 0 }

---Snap one axis: the box's edges to other edges, its centre to other centres with Ctrl, and always its centre to the screen's.
---@return number? shift
---@return number? line
local function SnapAxis(low, high, mid, edges, centers, screenCenter)
    local shift, line
    if IsControlKeyDown() then
        shift, line = Nearest(mid, centers, shift, line)
    else
        shift, line = Nearest(low, edges, shift, line)
        shift, line = Nearest(high, edges, shift, line)
    end
    screenLine[1] = screenCenter
    return Nearest(mid, screenLine, shift, line)
end

local guideX, guideY, readout -- the snap guide lines and the offset readout, made on the first drag

-- Guides, readout and anchor markers draw above every box: regions of overlayHost itself would sit under its child frames.
local decorHost = CreateFrame('Frame', nil, overlayHost)
decorHost:SetAllPoints()
decorHost:SetFrameLevel(overlayHost:GetFrameLevel() + 500)

---@param x number? where the vertical guide sits, nil hides it
---@param y number?
local function ShowGuides(x, y)
    guideX:SetShown(x ~= nil)
    guideY:SetShown(y ~= nil)
    if x then
        guideX:ClearAllPoints()
        pixel.SetPixelPoint(guideX, 'TOP', overlayHost, 'TOPLEFT', x, 0)
        pixel.SetPixelPoint(guideX, 'BOTTOM', overlayHost, 'BOTTOMLEFT', x, 0)
    end
    if y then
        guideY:ClearAllPoints()
        pixel.SetPixelPoint(guideY, 'LEFT', overlayHost, 'BOTTOMLEFT', 0, y)
        pixel.SetPixelPoint(guideY, 'RIGHT', overlayHost, 'BOTTOMRIGHT', 0, y)
    end
end

---Take down what a drag draws, whether it ended or was cut short.
local function EndDragVisuals()
    if not guideX then return end

    ShowGuides(nil, nil)
    readout:Hide()
end

local function UpdateDrag()
    if not isDragging or not dragEntry then return end

    local frame = GetEntryFrame(dragEntry)
    if not frame then return end

    local scale = frame:GetEffectiveScale()
    local curX, curY = GetCursorPosition()
    curX, curY = curX / scale, curY / scale

    local dx = math_floor(curX - dragCursorX + 0.5)
    local dy = math_floor(curY - dragCursorY + 0.5)

    -- snap onto other boxes and the screen centre, live with a guide line; Shift turns it off
    local lineX, lineY
    if not IsShiftKeyDown() then
        local moveX, moveY = dx * dragRatio, dy * dragRatio
        local shiftX, shiftY
        if dragBox then
            shiftX, lineX = SnapAxis(dragBox[1] + moveX, dragBox[2] + moveX, dragBox[5] + moveX, edgesX, centersX, gridCenterX)
            shiftY, lineY = SnapAxis(dragBox[3] + moveY, dragBox[4] + moveY, dragBox[6] + moveY, edgesY, centersY, gridCenterY)
        else
            shiftX, lineX = SnapAxis(nil, nil, dragCenterX and dragCenterX + moveX, edgesX, centersX, gridCenterX)
            shiftY, lineY = SnapAxis(nil, nil, dragCenterY and dragCenterY + moveY, edgesY, centersY, gridCenterY)
        end
        if shiftX then
            dx = dx + math_floor(shiftX / dragRatio + 0.5)
        end
        if shiftY then
            dy = dy + math_floor(shiftY / dragRatio + 0.5)
        end
    end
    ShowGuides(lineX, lineY)
    readout:SetFormattedText('%d, %d', math_floor(dragDBX + dx + 0.5), math_floor(dragDBY + dy + 0.5))

    dragDeltaX, dragDeltaY = dx, dy
    frame:ClearAllPoints()
    frame:SetPoint(dragPoint, dragRelTo, dragRelPoint, dragOriginX + dx, dragOriginY + dy)
end

dragUpdateFrame:SetScript('OnUpdate', UpdateDrag)

local function OnDragStart(overlay)
    -- Overlays stay mouse-live while they fade out, so re-check the session is open.
    if not Anchors.isActive or Anchors.switching or Private:InCombat() then return end

    local entry = overlay.entry
    if entry.locked then return end
    local frame = GetEntryFrame(entry)
    if not frame then return end

    -- Anchors drives frames positioned by ApplyPosition, which always sets exactly one point.
    if frame:GetNumPoints() ~= 1 then
        activeAddon:Print(format(L["Anchor '%s' has %d anchor points and cannot be dragged."], entry.displayName, frame:GetNumPoints()))
        return
    end

    dragPoint, dragRelTo, dragRelPoint, dragOriginX, dragOriginY = frame:GetPoint(1)
    dragRelTo = dragRelTo or UIParent

    local scale = frame:GetEffectiveScale()
    dragCursorX, dragCursorY = GetCursorPosition()
    dragCursorX, dragCursorY = dragCursorX / scale, dragCursorY / scale

    dragRatio = scale / UIParent:GetEffectiveScale()
    local left, bottom, width, height = Private:ScrubSecrets(frame:GetRect()) -- a text display's size turns secret with its text
    dragCenterX = left and width and (left + width / 2) * dragRatio or nil
    dragCenterY = bottom and height and (bottom + height / 2) * dragRatio or nil

    -- the box is what snaps, it can be bigger than the frame (a group's area)
    local boxLeft, boxBottom, boxWidth, boxHeight = Private:ScrubSecrets(overlay:GetRect())
    if boxLeft and boxBottom and boxWidth and boxHeight then
        dragBox = { boxLeft, boxLeft + boxWidth, boxBottom, boxBottom + boxHeight, boxLeft + boxWidth / 2, boxBottom + boxHeight / 2 }
    else
        dragBox = nil
    end
    CollectSnapLines(entry.key)

    if not guideX then
        guideX = decorHost:CreateTexture(nil, 'OVERLAY')
        pixel.SetPixelWidth(guideX, 1)
        guideY = decorHost:CreateTexture(nil, 'OVERLAY')
        pixel.SetPixelHeight(guideY, 1)
        readout = decorHost:CreateFontString(nil, 'OVERLAY')
        readout:SetFont(Private.Media.Fonts.Expressway, 12, 'OUTLINE')
    end
    guideX:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.8)
    guideY:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.8)
    readout:SetTextColor(1, 1, 1, 1)
    readout:ClearAllPoints()
    readout:SetPoint('TOP', overlay, 'BOTTOM', 0, -4)
    readout:Show()

    dragDBX, dragDBY = Anchors:GetOffsets(entry.key)
    dragDeltaX, dragDeltaY = 0, 0

    isDragging = true
    dragEntry = entry
    overlay.didDrag = true
    Anchors:RefreshOverlayState(entry.key)
    dragUpdateFrame:Show()
end

local function OnDragStop(overlay)
    if not isDragging then return end

    isDragging = false
    dragUpdateFrame:Hide()
    EndDragVisuals()

    local entry = dragEntry
    dragEntry = nil
    if not entry then return end

    -- SetOffsets re-syncs the overlay, the panel and the GUI sliders.
    Anchors:SetOffsets(entry.key, dragDBX + dragDeltaX, dragDBY + dragDeltaY)
    Anchors:Select(entry.key)
end

local function OnOverlayEnter(overlay)
    if isDragging then return end
    overlay.isHovered = true
    Anchors:RefreshOverlayState(overlay.entry.key)

    -- what a box does that its look doesn't say
    local entry = overlay.entry
    local hint = entry.locked and L['Its group places it, move the group instead.']
        or HasChildren(entry.key) and L['Double-click to work inside this group.']
    if hint then
        GameTooltip:SetOwner(overlay, 'ANCHOR_TOP')
        GameTooltip:SetText(entry.displayName, 1, 1, 1)
        GameTooltip:AddLine(hint, Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], true)
        GameTooltip:Show()
    end
end

local function OnOverlayLeave(overlay)
    overlay.isHovered = false
    if GameTooltip:IsOwned(overlay) then
        GameTooltip:Hide()
    end
    if isDragging then return end
    Anchors:RefreshOverlayState(overlay.entry.key)
end

local function OnOverlayMouseDown(overlay, button)
    if button == 'LeftButton' then overlay.didDrag = false end
end

local function OnOverlayMouseUp(overlay, button)
    if button ~= 'LeftButton' or overlay.didDrag or Anchors.switching then return end

    -- a second click on the same box opens its group
    local key, now = overlay.entry.key, GetTime()
    if overlay.lastClick and now - overlay.lastClick < DOUBLE_CLICK and HasChildren(key) then
        overlay.lastClick = nil
        Anchors:Focus(key)
        return
    end

    overlay.lastClick = now
    Anchors:Select(key)
end

---@param overlay table
local function PaintFill(overlay)
    local alpha = overlay.entry.bounds and BOUNDS_FILL_ALPHA or FILL_ALPHA
    overlay.fill:SetColorTexture(Theme.bgDark[1], Theme.bgDark[2], Theme.bgDark[3], alpha)
end

-- each edge: the two corners it runs between and the side it's thick along
local EDGES = {
    { 'TOPLEFT', 'TOPRIGHT', 'height' },
    { 'BOTTOMLEFT', 'BOTTOMRIGHT', 'height' },
    { 'TOPLEFT', 'BOTTOMLEFT', 'width' },
    { 'TOPRIGHT', 'BOTTOMRIGHT', 'width' },
}

---@param key string
function Anchors:CreateOverlay(key)
    local entry = Anchors.registry[key]
    if not entry then return end

    if Anchors.overlays[key] then
        self:UpdateOverlay(key)
        return
    end

    local frame = GetEntryFrame(entry)
    if not frame then return end

    -- Plain textures, no backdrop: a box hangs off its display, whose size turns secret while it holds an aura,
    -- and Backdrop does arithmetic on it.
    local overlay = CreateFrame('Frame', 'NRSKNUI_Anchor_' .. key, overlayHost)
    overlay.entry = entry
    overlay.fill = overlay:CreateTexture(nil, 'BACKGROUND')
    overlay.fill:SetAllPoints()
    PaintFill(overlay)

    overlay.edges = {}
    for index, edge in ipairs(EDGES) do
        local texture = overlay:CreateTexture(nil, 'BORDER')
        pixel.SetPixelPoint(texture, edge[1], overlay, edge[1], 0, 0)
        pixel.SetPixelPoint(texture, edge[2], overlay, edge[2], 0, 0)
        if edge[3] == 'height' then
            pixel.SetPixelHeight(texture, BORDER_SIZE)
        else
            pixel.SetPixelWidth(texture, BORDER_SIZE)
        end
        texture:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        overlay.edges[index] = texture
    end

    local text = overlay:CreateFontString(nil, 'OVERLAY')
    text:SetFont(Private.Media.Fonts.Expressway, TEXT_FONT_SIZE, 'OUTLINE')
    text:SetShadowOffset(0, 0)
    text:SetShadowColor(0, 0, 0, 0)
    text:SetText(entry.displayName)
    text:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    overlay.text = text

    overlay.didDrag = false
    overlay.isHovered = false
    overlay.animateBorder = Animations:CreateColorAnimator(
        overlay,
        function(r, g, b, a)
            for _, texture in ipairs(overlay.edges) do
                texture:SetColorTexture(r, g, b, a)
            end
        end,
        Theme.accent,
        STATE_DURATION
    )
    overlay.fadeTo = CreateFader(overlay, STATE_DURATION)

    overlay:EnableMouse(true)
    overlay:RegisterForDrag('LeftButton')
    overlay:SetScript('OnDragStart', OnDragStart)
    overlay:SetScript('OnDragStop', OnDragStop)
    overlay:SetScript('OnEnter', OnOverlayEnter)
    overlay:SetScript('OnLeave', OnOverlayLeave)
    overlay:SetScript('OnMouseDown', OnOverlayMouseDown)
    overlay:SetScript('OnMouseUp', OnOverlayMouseUp)

    Anchors.overlays[key] = overlay
    self:UpdateOverlay(key)
end

---@param key string
function Anchors:UpdateOverlay(key)
    local overlay = Anchors.overlays[key]
    if not overlay then return end

    local frame = GetEntryFrame(overlay.entry)
    if not frame then
        overlay:Hide()
        return
    end

    overlay:ClearAllPoints()
    overlay.text:ClearAllPoints()

    local entry = overlay.entry
    local left, bottom, right, top
    if entry.bounds then
        left, bottom, right, top = entry.bounds(entry.module)
    end

    local frameLeft, frameBottom = Private:ScrubSecrets(frame:GetRect())
    if left and frameLeft then
        -- bounds are in UIParent's units and the overlay's offsets too, the frame's rect isn't
        local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        frameLeft, frameBottom = frameLeft * ratio, frameBottom * ratio
        overlay:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', left - frameLeft, bottom - frameBottom)
        overlay:SetPoint('TOPRIGHT', frame, 'BOTTOMLEFT', right - frameLeft, top - frameBottom)
        overlay.text:SetPoint('TOP', overlay, 'TOP', 0, -BOUNDS_LABEL_INSET)
    else
        -- Only the geometry follows overlayFrame, dragging still reads the entry's own frame, so a chained
        -- group keeps one set of stored offsets. It tracks a live drag because it hangs off that frame.
        overlay:SetAllPoints(entry.overlayFrame or frame)
        overlay.text:SetPoint('CENTER')
    end

    overlay:Show()
end

-- Selection --

---Animates one overlay to the look like its current state calls for.
---@param key string
---@param overlay NRSKNUI.AnchorOverlay
local function ApplyOverlayState(key, overlay)
    local entry = overlay.entry
    local selected = (Anchors.selectedKey == key)
    local focused = (Anchors.focusKey == key)

    -- the group being worked inside is only a backdrop to its displays
    overlay:EnableMouse(not focused)

    -- Border colour, selection outranks hover; one its group places is muted.
    local color = entry.locked and Theme.textMuted or Theme.accent
    if selected then
        color = WHITE
    elseif overlay.isHovered then
        color = Theme.textSecondary
    end
    overlay.animateBorder(color[1], color[2], color[3], 1)

    if selected then
        overlay.text:SetTextColor(1, 1, 1, 1)
    else
        overlay.text:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    end

    -- a display inside a group is often icon sized, its name would cover its neighbours until it's pointed at
    overlay.text:SetShown(not entry.parentKey or focused or selected or overlay.isHovered)

    -- Alpha, shift makes the selection see-through.
    local alpha = 1
    if focused then
        alpha = FOCUS_ALPHA
    elseif isDragging and dragEntry and dragEntry.key == key then
        alpha = DRAG_ALPHA
    elseif selected then
        if Anchors.isShiftFaded then alpha = SHIFT_FADE_ALPHA end
    elseif Anchors.selectedKey then
        alpha = UNSELECTED_ALPHA
    end
    overlay.fadeTo(alpha)
end

---Re-applies the state look to one overlay.
---@param key string
function Anchors:RefreshOverlayState(key)
    local overlay = Anchors.overlays[key]
    if overlay then ApplyOverlayState(key, overlay) end
end

---Re-applies the state look to every live overlay in the view.
function Anchors:RefreshOverlayStates()
    for key, overlay in pairs(Anchors.overlays) do
        -- the fade shows what it fades in, so one put away for a single module's view would come back
        if InView(overlay.entry) then
            ApplyOverlayState(key, overlay)
        end
    end
end

---@param key string?
function Anchors:Select(key)
    Anchors.selectedKey = key
    if not key then Anchors.isShiftFaded = false end

    self:RefreshOverlayStates()
    self:UpdateMarkers()
    self:UpdatePanel()
end

local markerOwn, markerTarget, markerLine -- made on the first selection

---Mark the selected box's own anchor point and the point it hangs from, with a line between.
function Anchors:UpdateMarkers()
    local entry = Anchors.isActive and Anchors.selectedKey and Anchors.registry[Anchors.selectedKey]
    local frame = entry and GetEntryFrame(entry)
    local point, relTo, relPoint
    if frame and frame:GetNumPoints() == 1 then
        point, relTo, relPoint = frame:GetPoint(1)
        relTo = relTo or UIParent
    end

    -- a frame the game locks can't be anchored to
    if not (point and Private:CanAccessObject(relTo)) then
        if markerOwn then
            markerOwn:Hide()
            markerTarget:Hide()
            markerLine:Hide()
        end
        return
    end

    if not markerOwn then
        markerOwn = decorHost:CreateTexture(nil, 'OVERLAY', nil, 7)
        pixel.SetPixelSize(markerOwn, MARKER_SIZE, MARKER_SIZE)
        markerTarget = decorHost:CreateTexture(nil, 'OVERLAY', nil, 7)
        pixel.SetPixelSize(markerTarget, MARKER_SIZE, MARKER_SIZE)
        markerLine = decorHost:CreateLine(nil, 'OVERLAY', nil, 6)
        markerLine:SetThickness(1)
    end

    markerOwn:ClearAllPoints()
    markerOwn:SetPoint('CENTER', frame, point, 0, 0)
    markerTarget:ClearAllPoints()
    markerTarget:SetPoint('CENTER', relTo, relPoint, 0, 0)
    markerLine:SetStartPoint('CENTER', markerOwn)
    markerLine:SetEndPoint('CENTER', markerTarget)

    markerOwn:SetColorTexture(1, 1, 1, 1)
    markerTarget:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    markerLine:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.6)
    markerOwn:Show()
    markerTarget:Show()
    markerLine:Show()
end

---Moves the selected anchor by a whole-number offset delta.
---@param deltaX number
---@param deltaY number
function Anchors:Nudge(deltaX, deltaY)
    if not Anchors.selectedKey then
        activeAddon:Print(L['No anchor selected. Click an overlay to select it.'])
        return
    end
    local entry = Anchors.registry[Anchors.selectedKey]
    if entry and entry.locked then return end

    -- SetOffsets re-syncs the overlay, the panel and the GUI sliders.
    local x, y = self:GetOffsets(Anchors.selectedKey)
    self:SetOffsets(Anchors.selectedKey, x + deltaX, y + deltaY)
end

-- Shift fade --

function Anchors:ApplyShiftFade(fade)
    if Anchors.isShiftFaded == fade then return end
    Anchors.isShiftFaded = fade
    if not Anchors.selectedKey then return end

    self:RefreshOverlayState(Anchors.selectedKey)
end

-- Session handlers --

-- Above the nudge panel, its offset boxes take the keyboard the moment an anchor is selected.
local keyHandler = CreateFrame('Frame', 'NRSKNUI_AnchorsKeys', UIParent)
keyHandler:SetFrameStrata('TOOLTIP')
keyHandler:SetFrameLevel(10000)
keyHandler:Hide()
keyHandler:EnableKeyboard(true)
keyHandler:SetPropagateKeyboardInput(true)

local NUDGE_KEYS = {
    LEFT = { -1, 0 },
    RIGHT = { 1, 0 },
    UP = { 0, 1 },
    DOWN = { 0, -1 },
}

keyHandler:SetScript('OnKeyDown', function(self, key)
    -- Typing in an offset box owns the keyboard, arrows move its cursor there.
    if GetCurrentKeyBoardFocus() then
        self:SetPropagateKeyboardInput(true)
        return
    end

    if key == 'ESCAPE' then
        self:SetPropagateKeyboardInput(false)
        if Anchors.selectedKey then
            Anchors:Select(nil)
        elseif Anchors.focusKey then
            local focused = Anchors.registry[Anchors.focusKey]
            Anchors:Focus(focused and focused.parentKey)
        else
            Anchors:Exit()
        end
        return
    end

    local delta = NUDGE_KEYS[key]
    if delta and Anchors.selectedKey then
        self:SetPropagateKeyboardInput(false)
        local step = IsShiftKeyDown() and 10 or 1
        Anchors:Nudge(delta[1] * step, delta[2] * step)
        return
    end

    self:SetPropagateKeyboardInput(true)
end)

local eventHandler = CreateFrame('Frame')
eventHandler:SetScript('OnEvent', function(_, event, key)
    if event == 'PLAYER_REGEN_DISABLED' then
        if Anchors.isActive then
            activeAddon:Print(L['Anchors closed due to entering combat.'])
            Anchors:Exit()
        end
    elseif event == 'MODIFIER_STATE_CHANGED' then
        if key == 'LSHIFT' or key == 'RSHIFT' then
            Anchors:ApplyShiftFade(IsShiftKeyDown())
        end
    end
end)

-- Lifecycle --

-- The active addon's anchors, previews and panel; overlays outlive a session, so ones from another view are put away.
-- Boxes for what's in view, the rest put away.
local function PlaceOverlays()
    for key, entry in pairs(Anchors.registry) do
        if InView(entry) then
            Anchors:CreateOverlay(key)
        elseif Anchors.overlays[key] then
            Anchors.overlays[key]:Hide()
        end
    end
end

local function ShowView()
    -- only the active addon previews, even with another addon's window put away behind the anchors
    for _, addon in ipairs(addons) do
        addon.PreviewManager:SetHidden(addon ~= activeAddon)
    end
    activeAddon.PreviewManager:SetAnchorsActive(true, Anchors.onlyModule)

    Anchors.focusKey = nil
    PlaceOverlays()

    Anchors.selectedKey = nil
    Anchors.isShiftFaded = false
    Anchors:RefreshOverlayStates()
    Anchors:UpdateMarkers()

    Anchors:ShowPanel()
    Anchors:RefreshTheme() -- overlays and panels outlive a session, the theme may have changed since
    C_Timer.After(LAYOUT_SETTLE_DELAY, function() Anchors:OnExternalPositionChange() end)
    Private:SendMessage('NRSKNUI_ANCHORS_CHANGED')
end

---Work inside a group: its own displays get boxes and the rest of the view steps away. nil goes back to the top.
---@param key string?
function Anchors:Focus(key)
    if isDragging then return end -- the dragged box could leave the view under the mouse
    Anchors.focusKey = key
    self:Select(nil)
    PlaceOverlays()
    self:RefreshOverlayStates()
    self:UpdatePanel()
end

---@param aceModule? table show only this module's anchors, from its settings header; every anchor without it
function Anchors:Enter(aceModule)
    if Anchors.isActive then return end
    if Private:InCombat() then
        self.addon:Print(L['Cannot open Anchors during combat.'])
        return
    end

    Anchors.isActive = true
    Anchors.onlyModule = aceModule
    activeAddon, Theme = self.addon, self.addon.Theme

    -- every settings window steps aside while positioning, Exit brings back the ones that were open
    Anchors.suspended = {}
    for _, window in ipairs(Private.Kaji.windows) do
        if window:Suspend() then
            Anchors.suspended[#Anchors.suspended + 1] = window
        end
    end

    ShowGrid()
    FadeOverlays(1)

    keyHandler:Show()
    keyHandler:SetPropagateKeyboardInput(true)
    eventHandler:RegisterEvent('PLAYER_REGEN_DISABLED')
    eventHandler:RegisterEvent('MODIFIER_STATE_CHANGED')

    ShowView()
end

---Hand the open anchors to another addon: its overlays, previews and panel take over, the windows stay put away.
---@param addon table
function Anchors:Switch(addon)
    if not Anchors.isActive or addon == activeAddon or Anchors.switching or isDragging then return end
    -- a token per switch, so a timer left from one that Exit cut short can't land in a later one
    local switch = {}
    Anchors.switching = switch

    self:Select(nil)
    local old = panels[activeAddon]
    old.fader(0)
    FadeOverlays(0)

    -- the views swap while both are faded out, the previews with them; Exit or a new Enter on the way drops it
    C_Timer.After(FADE_DURATION, function()
        if Anchors.switching ~= switch then return end
        Anchors.switching = nil

        activeAddon.PreviewManager:SetAnchorsActive(false)
        Anchors.onlyModule = nil
        activeAddon, Theme = addon, addon.Theme
        BuildGridLines() -- the centre lines take the accent
        ShowView()
        FadeOverlays(1)

        -- the new panel takes the old one's place
        local panel = panels[activeAddon]
        panel:ClearAllPoints()
        panel:SetPoint(old:GetPoint())
    end)
end

function Anchors:Exit()
    if not Anchors.isActive then return end
    Anchors.isActive = false
    Anchors.switching = nil

    isDragging = false
    dragUpdateFrame:Hide()
    dragEntry = nil
    EndDragVisuals()

    self:Select(nil)
    Anchors.isShiftFaded = false
    Anchors.focusKey = nil

    HideGrid()
    Anchors.onlyModule = nil
    activeAddon.PreviewManager:SetAnchorsActive(false)
    for _, addon in ipairs(addons) do
        addon.PreviewManager:SetHidden(false)
    end

    FadeOverlays(0)

    keyHandler:Hide()
    eventHandler:UnregisterAllEvents()
    self:HidePanel()
    for _, window in ipairs(Anchors.suspended or {}) do
        window:Resume()
    end
    Anchors.suspended = nil
    Private:SendMessage('NRSKNUI_ANCHORS_CHANGED')
end

-- a settings window opened while positioning ends it, the suspended windows come back with it
Private.Kaji.beforeWindowShow = function()
    Anchors:Exit()
end

---Open this addon's anchors, close them, or take them over when another addon's show.
function Anchors:Toggle()
    if Anchors.isActive and self.addon ~= activeAddon then
        self:Switch(self.addon)
    elseif Anchors.isActive then
        self:Exit()
    else
        self:Enter()
    end
end

---Whether this addon's anchors are the ones showing.
---@return boolean
function Anchors:IsActive()
    return Anchors.isActive and self.addon == activeAddon
end

-- Nudge Panel --

function Anchors:CreatePanel()
    local panel = panels[activeAddon]
    if panel then return panel end

    local GUI = activeAddon.GUI
    panel = CreateFrame('Frame', nil, UIParent, 'BackdropTemplate')
    panels[activeAddon] = panel
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetPoint('CENTER', UIParent, 'CENTER', 200, 0)
    panel:SetFrameStrata('FULLSCREEN_DIALOG')
    panel:SetFrameLevel(1001)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag('LeftButton')
    panel:SetScript('OnDragStart', panel.StartMoving)
    panel:SetScript('OnDragStop', panel.StopMovingOrSizing)
    panel:SetBackdrop({
        bgFile = Private.WhiteTexture,
        edgeFile = Private.WhiteTexture,
        edgeSize = 1,
    })
    panel:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
    panel:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)

    -- one button per addon, this panel's own one lit; ShowPanel picks and lays out the ones that show
    if addons[2] then
        local switcher = CreateFrame('Frame', nil, panel)
        switcher:SetPoint('TOPLEFT', panel, 'TOPLEFT', 10, -8)
        switcher:SetPoint('TOPRIGHT', panel, 'TOPRIGHT', -10, -8)
        switcher:SetHeight(SWITCHER_HEIGHT - 8)
        panel.switcher = switcher
        panel.switchButtons = {}

        for _, addon in ipairs(addons) do
            local button = GUI:CreateButton(switcher, addon.shortName, {
                height = SWITCHER_HEIGHT - 8,
                bgColor = Theme.bgDark,
                callback = function() Anchors:Switch(addon) end,
            })
            button:SetSelected(addon == activeAddon)
            button:SetTooltip(addon.name)
            panel.switchButtons[addon] = button
        end
    end

    local body = CreateFrame('Frame', nil, panel)
    body:SetPoint('TOPLEFT')
    body:SetPoint('BOTTOMRIGHT')
    panel.body = body

    local title = body:CreateFontString(nil, 'OVERLAY')
    title:SetPoint('TOP', body, 'TOP', 0, -6)
    title:SetWidth(PANEL_WIDTH - 20)
    title:SetWordWrap(false)
    panel.title = title
    title:SetFont(Private.Media.Fonts.Expressway, 16, 'OUTLINE')
    title:SetShadowOffset(0, 0)
    title:SetShadowColor(0, 0, 0, 0)
    title:SetText(L['Nudge Tool'])
    title:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)

    local selected = body:CreateFontString(nil, 'OVERLAY')
    selected:SetPoint('TOP', title, 'BOTTOM', 0, -2)
    selected:SetFont(Private.Media.Fonts.Expressway, 12, 'OUTLINE')
    selected:SetShadowOffset(0, 0)
    selected:SetShadowColor(0, 0, 0, 0)
    selected:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    panel.selected = selected

    local function CommitOffsets()
        if not Anchors.selectedKey then return end
        local x = tonumber(panel.xBox:GetValue())
        local y = tonumber(panel.yBox:GetValue())
        if not x or not y then
            Anchors:UpdatePanel()
            return
        end

        -- SetOffsets re-syncs the overlay, the panel and the GUI sliders.
        Anchors:SetOffsets(Anchors.selectedKey, x, y)
    end

    local xBox = GUI:CreateEditBox(body, L['X Offset:'], { inlineLabel = true, labelWidth = 60, callback = CommitOffsets })
    xBox:SetPoint('TOPLEFT', body, 'TOPLEFT', 10, -46)
    xBox:SetPoint('TOPRIGHT', body, 'TOPRIGHT', -10, -46)
    panel.xBox = xBox

    local yBox = GUI:CreateEditBox(body, L['Y Offset:'], { inlineLabel = true, labelWidth = 60, callback = CommitOffsets })
    yBox:SetPoint('TOPLEFT', xBox, 'BOTTOMLEFT', 0, -4)
    yBox:SetPoint('TOPRIGHT', xBox, 'BOTTOMRIGHT', 0, -4)
    panel.yBox = yBox

    -- Left, up, down, right in a single row.
    local ARROWS = {
        { rotation = -90, dx = -1, dy = 0 },
        { rotation = 180, dx = 0,  dy = 1 },
        { rotation = 0,   dx = 0,  dy = -1 },
        { rotation = 90,  dx = 1,  dy = 0 },
    }

    local buttonSize, gap = 26, 4
    local rowWidth = #ARROWS * buttonSize + (#ARROWS - 1) * gap
    panel.arrows = {}

    for index, arrow in ipairs(ARROWS) do
        local button = GUI:CreateButton(body, '', {
            width = buttonSize,
            height = buttonSize,
            image = ARROW_TEXTURE,
            imageSize = buttonSize - 6,
            imageRotation = math_rad(arrow.rotation),
            imageColor = Theme.accent,
            bgColor = Theme.bgDark,
            callback = function()
                local step = IsShiftKeyDown() and 10 or 1
                Anchors:Nudge(arrow.dx * step, arrow.dy * step)
            end,
        })
        button:SetPoint('TOPLEFT', body, 'TOP', -rowWidth / 2 + (index - 1) * (buttonSize + gap), -110)
        panel.arrows[index] = button
    end

    local settings = GUI:CreateButton(body, L['Open Settings'], {
        width = 160,
        height = 24,
        bgColor = Theme.bgDark,
        callback = function() Anchors:OpenSelectedSettings() end,
    })
    settings:SetPoint('BOTTOM', body, 'BOTTOM', 0, 8)
    panel.settings = settings

    panel:Hide()
    panel.fader = CreateFader(panel)
    return panel
end

function Anchors:UpdatePanel()
    local panel = panels[activeAddon]
    if not panel then return end

    -- inside a group the title names it, Escape goes back up
    local focused = Anchors.focusKey and Anchors.registry[Anchors.focusKey]
    panel.title:SetText(focused and ('< ' .. focused.displayName) or L['Nudge Tool'])

    local entry = Anchors.selectedKey and Anchors.registry[Anchors.selectedKey]

    if not entry or entry.locked then
        panel.selected:SetText(entry and entry.displayName or focused and L['Click to select, Esc to go back'] or L['Click to select'])
        panel.selected:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
        panel.xBox:SetValue('--')
        panel.yBox:SetValue('--')
        panel.xBox:SetEnabled(false)
        panel.yBox:SetEnabled(false)
        -- one its group places can't move, but its settings still open
        panel.settings:SetEnabled(entry ~= nil)
        panel.settings:SetAlpha(entry and 1 or 0.4)
        for _, arrow in ipairs(panel.arrows) do
            arrow:SetEnabled(false)
            arrow:SetAlpha(0.4)
        end
        return
    end

    panel.selected:SetText(entry.displayName)
    panel.selected:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    panel.xBox:SetEnabled(true)
    panel.yBox:SetEnabled(true)
    panel.settings:SetEnabled(true)
    panel.settings:SetAlpha(1)
    for _, arrow in ipairs(panel.arrows) do
        arrow:SetEnabled(true)
        arrow:SetAlpha(1)
    end

    local x, y = self:GetOffsets(Anchors.selectedKey)
    panel.xBox:SetValue(format('%d', x))
    panel.yBox:SetValue(format('%d', y))
end

function Anchors:ShowPanel()
    local panel = self:CreatePanel()

    -- an addon only gets a button while it has anchors to show (NorskenDev has none), and those come and go
    local switchable = {}
    if panel.switcher then
        for _, addon in ipairs(addons) do
            local hasAnchors = addon == activeAddon
            if not hasAnchors then
                for _, entry in pairs(Anchors.registry) do
                    if entry.addon == addon then
                        hasAnchors = true
                        break
                    end
                end
            end
            panel.switchButtons[addon]:SetShown(hasAnchors)
            if hasAnchors then
                switchable[#switchable + 1] = addon
            end
        end
    end

    -- a view opened for one module stays on its addon
    local switching = switchable[2] ~= nil and Anchors.onlyModule == nil
    if switching then
        local gap = 4
        local width = (PANEL_WIDTH - 20 - (#switchable - 1) * gap) / #switchable
        for index, addon in ipairs(switchable) do
            local button = panel.switchButtons[addon]
            button:NUISetPixelWidth(width)
            button:ClearAllPoints()
            button:SetPoint('TOPLEFT', panel.switcher, 'TOPLEFT', (index - 1) * (width + gap), 0)
        end
    end
    if panel.switcher then
        panel.switcher:SetShown(switching)
    end
    local top = switching and SWITCHER_HEIGHT or 0
    panel:SetHeight(PANEL_HEIGHT + top)
    panel.body:SetPoint('TOPLEFT', panel, 'TOPLEFT', 0, -top)

    -- Populate before fading in, so the panel doesn't animate up showing stale values.
    self:UpdatePanel()
    panel.fader(1)
end

function Anchors:HidePanel()
    local panel = panels[activeAddon]
    if panel then panel.fader(0) end
end

function Anchors:OpenSelectedSettings()
    if not Anchors.selectedKey then
        activeAddon:Print(L['No anchor selected.'])
        return
    end

    local entry = Anchors.registry[Anchors.selectedKey]
    if not entry then return end

    -- ShowPage expects a { tabId, itemKey } target, a bare context names the item.
    local context = entry.guiContext
    if type(context) == 'string' then
        context = { itemKey = context }
    end

    self:Exit() -- the window can't sit on top of the anchors

    -- ShowPage resolves and expands the owning sidebar header itself.
    entry.addon:OpenOptions(entry.guiPath, context)
end

---Called by the GUI (via services.positionSync) when a PositionCard edits a position,
---so the overlay geometry and the panel readout follow the sliders. The module has
---already re-applied by then, so this only re-reads.
function Anchors:OnExternalPositionChange()
    if not Anchors.isActive then return end

    for key, entry in pairs(Anchors.registry) do
        if InView(entry) then
            self:UpdateOverlay(key)
        end
    end
    self:UpdatePanel()
end

---Re-themes live overlays and the panel after a theme change.
function Anchors:RefreshTheme()
    if not Anchors.isActive then return end

    for _, overlay in pairs(Anchors.overlays) do
        if InView(overlay.entry) then
            PaintFill(overlay)
        end
    end
    self:RefreshOverlayStates()

    local panel = panels[activeAddon]
    if panel then
        panel:SetBackdropColor(Theme.bgLight[1], Theme.bgLight[2], Theme.bgLight[3], 1)
        panel:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 1)
        self:UpdatePanel()
    end
end

---An addon's own handle on the anchor system. What it registers is its own and it opens on its own theme.
---@param addon table needs GUI, Theme, Print, OpenOptions and PreviewManager
---@return NRSKNUI.Anchors
function Private:NewAnchors(addon)
    addons[#addons + 1] = addon
    return setmetatable({ addon = addon }, { __index = Anchors })
end
