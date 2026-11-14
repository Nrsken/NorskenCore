---@class NRSKNUI
local Core = select(2, ...)
local L = Core.L
local Animations = Core.Animations
local Pixel = Core.Pixel
local Kaji = Core.Kaji
local ToPixelGrid = Pixel.ToPixelGrid
local ToTenths = Pixel.ToTenths
---@class NRSKNUI.Anchors
---@field addon table the addon this handle belongs to, see NewAnchors
---@field boxOnly boolean? its displays move in its window's box, it has no anchors mode
---@field snapshot table? key -> saved fields, what Undo All goes back to
local Anchors = {}
Core.Anchors = Anchors
Anchors.isActive = false
Anchors.registry = {}
Anchors.overlays = {}
Anchors.selectedKey = nil
Anchors.onlyModule = nil

local math_floor, math_ceil, math_abs, math_rad = math.floor, math.ceil, math.abs, math.rad
local math_min, math_max = math.min, math.max
local sort = table.sort
local GetPhysicalScreenSize = GetPhysicalScreenSize
local GetCursorPosition = GetCursorPosition
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsAltKeyDown = IsAltKeyDown
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
local scrubsecretvalues = scrubsecretvalues

-- One system for every addon. Each has a handle reading this table through __index, so state only ever
-- gets written to Anchors itself: on self it would land on that one handle.
local addons = {}
local activeAddon -- the addon whose anchors or box show
local Theme       -- its theme, only one addon's overlays exist on screen at a time
local spareOverlays = {} -- named frames, so one per key is reused

---@class NRSKNUI.AnchorsWindow : Frame
---@field fader fun(alpha: number)
---@field [string] any its widgets

local panel, popup ---@type NRSKNUI.AnchorsWindow?, NRSKNUI.AnchorsWindow? made on the first Enter
local boxArrows ---@type table? the nudge arrows around a box, made on the first box

local ARROW_TEXTURE = Core.Media.GUITextures .. 'collapse.tga'

-- Overlay Config
local FILL_ALPHA = 0.8
local BOUNDS_FILL_ALPHA = 0.2 -- a box around what an anchor holds shouldn't hide what it's there to show
local SELECTED_FILL_ALPHA = 0.15
local BOUNDS_LABEL_INSET = 6
local LAYOUT_SETTLE_DELAY = 0.1 -- groups lay out on the next frame, the boxes around them read that layout
local BORDER_SIZE = 2 -- physical pixels
local TEXT_FONT_SIZE = 14
local HOVER_DIM_ALPHA = 0.5
local DIM_DURATION = 0.75 -- slow, so passing over boxes doesn't strobe the rest
local SNAP_RANGE = 8
local SNAP_RELEASE = 12 -- so a held snap can't flicker
local FADE_DURATION = 0.25
local UNSELECTED_ALPHA = 0.8 -- The alpha of overlays that are not selected, when a selection exists.
local DRAG_ALPHA = 0.7       -- The alpha of the overlay being dragged.
local STATE_DURATION = 0.25  -- The duration of the selection fade.
local WHITE = { 1, 1, 1 }
local MARKER_SIZE = 6       -- physical pixels
local BOX_ARROW_SIZE, BOX_ARROW_IMAGE = 16, 12

-- Grid Config
local gridFrame = nil
local gridCenterX, gridCenterY = 0, 0
local gridLinesX, gridLinesY = {}, {} -- from the bottom left
local gridStep = 0
local GRID_SIZE = 64
local GRID_LINE_WIDTH = 1
local GRID_COLOR = { 0, 0, 0, 0.4 }
local GRID_CENTER_ALPHA = 0.4
local ShowGrid
local BuildGridLines
local StackOverlays

-- Fading --

---Creates a function that fades a frame to a target alpha over time.
---@param frame Frame
---@param duration? number defaults to FADE_DURATION
---@return fun(toAlpha: number)
local function CreateFader(frame, duration)
    -- an Alpha animation reads back the resting alpha, not the one on screen
    local target
    local animate, setCurrent = Animations:CreateColorAnimator(frame, function(_, _, _, alpha)
        frame:SetAlpha(alpha)
        -- a fade in starts at 0 too
        if alpha == 0 and target == 0 then
            frame:Hide()
        end
    end, { 0, 0, 0, frame:GetAlpha() }, duration or FADE_DURATION)

    return function(toAlpha)
        if not frame:IsShown() then
            if toAlpha == 0 then return end

            frame:SetAlpha(0)
            setCurrent(0, 0, 0, 0)
            frame:Show()
        end
        target = toAlpha
        animate(0, 0, 0, toAlpha)
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
    gridFrame:SetScript('OnEvent', function()
        if not Anchors.isActive then return end

        BuildGridLines()
        Anchors:OnExternalPositionChange()
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

function BuildGridLines()
    local width, height = UIParent:GetSize()
    local physWidth, physHeight = GetPhysicalScreenSize()
    if not physWidth or physWidth == 0 or physHeight == 0 then return end

    local pixel = Pixel.GetMult()
    local step = math_floor(physWidth / GRID_SIZE + 0.5) * pixel
    gridStep = step
    local lineWidth = GRID_LINE_WIDTH * pixel

    -- drawn from the top, snapped from the bottom
    local centerFromTop = math_floor(physHeight * 0.5 + 0.5) * pixel
    gridCenterX = math_floor(physWidth * 0.5 + 0.5) * pixel
    gridCenterY = ToPixelGrid(height - centerFromTop)
    wipe(gridLinesX)
    wipe(gridLinesY)

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
        local x = gridCenterX + i * step
        PlaceVertical(x, i == 0)
        gridLinesX[#gridLinesX + 1] = x
    end

    for i = -math_ceil(centerFromTop / step), math_ceil((height - centerFromTop) / step) do
        local y = centerFromTop + i * step
        PlaceHorizontal(y, i == 0)
        gridLinesY[#gridLinesY + 1] = ToPixelGrid(height - y)
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

---The module and every view of its position: box, popup and settings sliders.
---@param key string
local function Reapply(key)
    local entry = Anchors.registry[key]
    local apply = entry.apply
    if type(apply) == 'function' then
        apply(entry.module)
    elseif entry.module[apply] then
        entry.module[apply](entry.module)
    end

    -- a box out of view stays put away
    C_Timer.After(0, function()
        local overlay = Anchors.overlays[key]
        if overlay and overlay:IsShown() then
            Anchors:UpdateOverlay(key)
        end
        Anchors:UpdateMarkers()
        -- snapped against the box, so only once the box has moved
        Anchors:UpdatePopup()
        Anchors:UpdateUndoAll()
    end)

    local addon = entry.addon
    if addon.GUI and addon.GUIFrame and addon.GUIFrame:IsShown() then
        addon.GUI:RefreshPositionCards()
    end
end

---Writes both offsets and re-applies the module.
---@param key string
---@param x number
---@param y number
function Anchors:SetOffsets(key, x, y)
    local entry = Anchors.registry[key]
    if not entry then return end

    local posTable, db = GetTables(entry)
    local target = posTable or db
    if not target then return end

    target[entry.xKey] = ToTenths(x)
    target[entry.yKey] = ToTenths(y)
    Reapply(key)
end

---@return any[]? path the keys from root down to target
local function FindPath(root, target, path, depth)
    if root == target then
        return path
    end
    if depth > 8 then return end

    for key, value in pairs(root) do
        if type(value) == 'table' then
            path[#path + 1] = key
            if FindPath(value, target, path, depth + 1) then
                return path
            end
            path[#path] = nil
        end
    end
end

---AceDB copies defaults into the profile, so a field set to nil doesn't fall back to them.
---@param entry table
---@return table[]? sources the defaults to read, wildcards after the named key
local function DefaultPosition(entry)
    local namespace = entry.module.namespace
    local defaults = namespace and namespace.defaults and namespace.defaults.profile
    if not defaults then return end

    -- the keys don't change with the profile, so the search runs once
    if entry.defaultPath == nil then
        local posTable = GetTables(entry)
        entry.defaultPath = posTable and FindPath(namespace.profile, posTable, {}, 0) or false
    end
    if not entry.defaultPath then return end

    -- '**' covers every key, '*' only keys the defaults don't name
    local sources = { defaults }
    for _, key in ipairs(entry.defaultPath) do
        local below = {}
        for _, source in ipairs(sources) do
            local named = source[key]
            if type(named) == 'table' then
                below[#below + 1] = named
            elseif type(source['*']) == 'table' then
                below[#below + 1] = source['*']
            end
            if type(source['**']) == 'table' then
                below[#below + 1] = source['**']
            end
        end
        sources = below
    end
    return sources[1] and sources or nil
end

---@param entry table
---@return Frame?
local function GetEntryFrame(entry)
    return entry.frame or entry.frameName and _G[entry.frameName] or nil
end

---Its anchor count, nil while it's hung off secret geometry and reads secret.
---@param frame Frame
---@return number?
local function NumPoints(frame)
    return Core:SafeValue(frame:GetNumPoints())
end

-- Registration --

---Whether an anchor belongs in the open view: all, one module's or the one box.
---@param entry table
---@return boolean
local function InView(entry)
    if entry.addon ~= activeAddon then return false end
    if Anchors.boxKey then
        return entry.key == Anchors.boxKey
    end
    if entry.shown and not entry.shown(entry.module) then return false end
    if Anchors.onlyModule ~= nil and entry.module ~= Anchors.onlyModule then return false end

    -- a view opened for one module ignores the Show group
    local show = Anchors.onlyModule == nil and Core:GetAnchorsSettings().Show[activeAddon.shortName]
    return not show or show == 'all' or (entry.groups and entry.groups[show]) == true
end

---Registers a frame as a draggable anchor.
---@param aceModule NRSKNUI.ModuleBase
---@param key string Unique anchor key.
---@param frame Frame? The frame to move; defaults to module.frame.
---@param guiPath string? Sidebar item id a right-click on its box opens.
---@param opts table? db, positionKey, xKey, yKey, fromKey, toKey, apply, displayName, frameName, guiContext, shown, bounds, locked, groups
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
    entry.fromKey = opts.fromKey or 'AnchorFrom'
    entry.toKey = opts.toKey or 'AnchorTo'
    entry.fields = { entry.xKey, entry.yKey, entry.fromKey, entry.toKey }
    entry.defaultPath = nil

    -- the panel's Show groups it's listed under, one name or several
    local groups = opts.groups
    entry.groups = nil
    if groups then
        entry.groups = {}
        for _, group in ipairs(type(groups) == 'table' and groups or { groups }) do
            entry.groups[group] = true
        end
    end
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

    -- something else places it, so it only selects; a string says what, true means its group
    entry.locked = opts.locked

    if type(entry.apply) == 'string' and type(aceModule[entry.apply]) ~= 'function' then
        self.addon:Print(format("Anchor '%s' registered with apply='%s', which the module does not define.", key, entry.apply))
    end

    if Anchors.isActive and InView(entry) then
        self:CreateOverlay(key)
        self:RefreshOverlayState(key) -- a box made mid session takes the look its state calls for
        StackOverlays()
        -- a display built again keeps its box
        if key == Anchors.boxKey and Anchors.selectedKey ~= key then
            self:Select(key)
        end
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
        spareOverlays[key] = overlay
    end

    Anchors.registry[key] = nil
    if Anchors.selectedKey == key then self:Select(nil) end
end

-- Overlays --

local overlayHost = CreateFrame('Frame', 'NRSKNUI_AnchorsOverlays', UIParent)
overlayHost:SetAllPoints(UIParent)
overlayHost:Hide()

local FadeOverlays = CreateFader(overlayHost)

-- Drag --

local isDragging = false
local dragEntry = nil
local dragCursorX, dragCursorY = 0, 0
local dragPoint, dragRelTo, dragRelPoint, dragOriginX, dragOriginY
local dragDBX, dragDBY = 0, 0
local dragMoveX, dragMoveY = 0, 0
local dragRatio = 1
local dragStep = 1 -- a physical pixel in the frame's units
local dragSnap = true
local dragBox -- left, right, bottom, top, centre x, centre y

local snapBoxes = {} -- left, right, bottom, top of each other box
local edgesX, edgesY, centersX, centersY = {}, {}, {}, {}
local screenX, screenY, noLines = {}, {}, {}
local probes = { 0, 0, 0 } -- low edge, high edge, centre
local heldX, heldY = {}, {}

local dragUpdateFrame = CreateFrame('Frame')
dragUpdateFrame:Hide()

---A region's rect in UIParent's units, nil while it's secret or not laid out.
---@param region Region
---@return number? left
---@return number? bottom
---@return number? width
---@return number? height
local function ScreenRect(region)
    -- a display holding an aura can have a secret rect
    local x, y, width, height = scrubsecretvalues(region:GetRect())
    if not (x and y and width and height) then return end

    local ratio = region:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * ratio, y * ratio, width * ratio, height * ratio
end

---@param region Region
---@param other Region
---@return boolean
local function IsInside(region, other)
    local parent = region:GetParent()
    while parent do
        if parent == other then return true end
        parent = parent:GetParent()
    end
    return false
end

---@param moving table the dragged entry
local function CollectSnapLines(moving)
    wipe(snapBoxes)
    wipe(centersX)
    wipe(centersY)

    local dragKey, dragged = moving.key, GetEntryFrame(moving)
    for key, entry in pairs(Anchors.registry) do
        local left, bottom, width, height
        local overlay = Anchors.overlays[key]
        local frame = GetEntryFrame(entry)
        local other = key ~= dragKey and entry.addon == activeAddon and frame and dragged
        if other and not Anchors.boxKey then
            if overlay and overlay:IsShown() and InView(entry) then
                left, bottom, width, height = ScreenRect(overlay)
            end
        -- the box is alone on screen, so the other displays themselves; not what moves with it
        elseif other and frame:IsVisible() and not IsInside(frame, dragged) and not IsInside(dragged, frame) then
            local right, top
            if entry.bounds then
                left, bottom, right, top = entry.bounds(entry.module)
            end
            if left and bottom and right and top then
                width, height = right - left, top - bottom
            else
                left, bottom, width, height = ScreenRect(frame)
            end
        end
        if left and bottom and width and height then
            snapBoxes[#snapBoxes + 1] = { left, left + width, bottom, bottom + height }
            centersX[#centersX + 1] = left + width / 2
            centersY[#centersY + 1] = bottom + height / 2
        end
    end
    screenX[1], screenY[1] = gridCenterX, gridCenterY
end

---Far boxes would pull from across the screen.
---@param edges number[]
---@param low number the dragged box's low edge on the other axis
---@param high number
---@param across number 1 for vertical lines (left, right), 3 for horizontal ones
local function CollectNearEdges(edges, low, high, across)
    wipe(edges)
    local other = across == 1 and 3 or 1
    for _, box in ipairs(snapBoxes) do
        local gap = math_max(box[other] - high, low - box[other + 1], 0)
        if gap <= gridStep then
            edges[#edges + 1], edges[#edges + 2] = box[across], box[across + 1]
        end
    end
end

---@param index number
---@param lines number[]
---@param range number
---@param shift number?
---@param line number?
---@param won number? the probe holding the best so far
---@return number? shift
---@return number? line
---@return number? won
local function Catch(index, lines, range, shift, line, won)
    local from = probes[index]
    for i = 1, #lines do
        local gap = lines[i] - from
        if math_abs(gap) <= range and (not shift or math_abs(gap) < math_abs(shift)) then
            shift, line, won = gap, lines[i], index
        end
    end
    return shift, line, won
end

---@param edges number[]
---@param centers number[]
---@param screen number[]
---@param gridLines number[]
---@param held table
---@return number? shift
---@return number? line
local function SnapAxis(edges, centers, screen, gridLines, held)
    local mult = Pixel.GetMult()
    local ctrl = IsControlKeyDown()
    local heldGap
    if held.line and held.ctrl == ctrl then
        heldGap = held.line - probes[held.index]
        if math_abs(heldGap) > SNAP_RELEASE * mult then
            heldGap = nil
        elseif not held.grid then
            return heldGap, held.line
        end
    end

    local range = SNAP_RANGE * mult
    local shift, line, won
    if ctrl then
        shift, line, won = Catch(3, centers, range, shift, line, won)
    else
        shift, line, won = Catch(1, edges, range, shift, line, won)
        shift, line, won = Catch(2, edges, range, shift, line, won)
    end
    shift, line, won = Catch(3, screen, range, shift, line, won)

    -- lining up with another box beats a grid line, even one already held
    local grid = false
    if not line and heldGap then
        return heldGap, held.line
    elseif not line then
        shift, line, won = Catch(1, gridLines, range, shift, line, won)
        shift, line, won = Catch(2, gridLines, range, shift, line, won)
        grid = true
    end

    held.line, held.index, held.ctrl, held.grid = line, won, ctrl, grid
    return shift, line
end

local guideX, guideY, readout -- the snap guide lines and the offset readout, made on the first drag

-- Guides, readout and anchor markers draw above every box: regions of overlayHost itself would sit under its child frames.
local decorHost = CreateFrame('Frame', nil, overlayHost)
decorHost:SetAllPoints()
decorHost:SetFrameLevel(overlayHost:GetFrameLevel() + 500)

---A texture over a screen rect, in UIParent's units from the bottom left.
---@param texture Texture
local function PlaceRect(texture, left, bottom, right, top)
    texture:ClearAllPoints()
    texture:SetPoint('BOTTOMLEFT', decorHost, 'BOTTOMLEFT', left, bottom)
    texture:SetPoint('TOPRIGHT', decorHost, 'BOTTOMLEFT', right, top)
    texture:Show()
end

---@param x number? where the vertical guide sits, nil hides it
---@param y number?
local function ShowGuides(x, y)
    -- from the line out, centred on it a guide would straddle two pixels
    local pixel = Pixel.GetMult()
    local width, height = decorHost:GetSize()
    guideX:Hide()
    guideY:Hide()
    if x then
        PlaceRect(guideX, x, 0, x + pixel, height)
    end
    if y then
        PlaceRect(guideY, 0, y, width, y + pixel)
    end
end

---Take down what a drag draws, whether it ended or was cut short.
local function EndDragVisuals()
    if not guideX then return end

    ShowGuides(nil, nil)
    readout:Hide()
end

---@param value number
---@return string
local function FormatOffset(value)
    value = ToTenths(value)
    return value == math_floor(value) and format('%d', value) or format('%.1f', value)
end

local function UpdateDrag()
    if not isDragging or not dragEntry then return end

    local frame = GetEntryFrame(dragEntry)
    if not frame then return end

    local scale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    local moveX, moveY = cursorX / scale - dragCursorX, cursorY / scale - dragCursorY

    local lineX, lineY
    if dragBox and dragSnap and not IsShiftKeyDown() then
        local grid = gridFrame and gridFrame:IsShown()
        local shiftX, shiftY
        CollectNearEdges(edgesX, dragBox[3] + moveY, dragBox[4] + moveY, 1)
        CollectNearEdges(edgesY, dragBox[1] + moveX, dragBox[2] + moveX, 3)
        probes[1], probes[2], probes[3] = dragBox[1] + moveX, dragBox[2] + moveX, dragBox[5] + moveX
        shiftX, lineX = SnapAxis(edgesX, centersX, screenX, grid and gridLinesX or noLines, heldX)
        probes[1], probes[2], probes[3] = dragBox[3] + moveY, dragBox[4] + moveY, dragBox[6] + moveY
        shiftY, lineY = SnapAxis(edgesY, centersY, screenY, grid and gridLinesY or noLines, heldY)
        moveX, moveY = moveX + (shiftX or 0), moveY + (shiftY or 0)
    else
        heldX.line, heldY.line = nil, nil
    end
    ShowGuides(lineX, lineY)

    -- placed like the modules' apply, so nothing hops on release
    local x = ToPixelGrid(dragDBX + moveX / dragRatio, dragStep) - dragDBX
    local y = ToPixelGrid(dragDBY + moveY / dragRatio, dragStep) - dragDBY
    if x == dragMoveX and y == dragMoveY then return end

    dragMoveX, dragMoveY = x, y
    readout:SetText(FormatOffset(dragDBX + x) .. ', ' .. FormatOffset(dragDBY + y))
    frame:ClearAllPoints()
    frame:NCSetGridPoint(dragPoint, dragRelTo --[[@as Frame]], dragRelPoint, dragOriginX + x, dragOriginY + y)
    Anchors:UpdateMarkers()
end

dragUpdateFrame:SetScript('OnUpdate', UpdateDrag)

local function OnDragStart(overlay)
    -- Overlays stay mouse-live while they fade out, so re-check the session is open.
    if not Anchors.isActive or Core:InCombat() then return end

    local entry = overlay.entry
    if entry.locked then return end
    local frame = GetEntryFrame(entry)
    if not frame then return end

    -- Anchors drives frames positioned by ApplyPosition, which always sets exactly one point.
    local points = NumPoints(frame)
    if points ~= 1 then
        if points then
            activeAddon:Print(format(L["Anchor '%s' has %d anchor points and cannot be dragged."], entry.displayName, points))
        end
        return
    end

    dragPoint, dragRelTo, dragRelPoint, dragOriginX, dragOriginY = frame:GetPoint(1)
    dragRelTo = dragRelTo or UIParent
    -- the drag places through NCSetGridPoint too, which adds its own snap back on
    local baseLeft, baseBottom, gridLeft, gridBottom = Pixel.GetAnchorBase(frame, dragPoint, dragRelTo --[[@as Frame]], dragRelPoint)
    if baseLeft and baseBottom and gridLeft and gridBottom then
        dragOriginX = dragOriginX - (gridLeft - baseLeft)
        dragOriginY = dragOriginY - (gridBottom - baseBottom)
    end

    dragCursorX, dragCursorY = overlay.downX, overlay.downY
    if not dragCursorX then
        local scale = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        dragCursorX, dragCursorY = x / scale, y / scale
    end
    dragRatio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    dragStep = Pixel.GetStep(frame)

    -- the box is what snaps, it can be bigger than the frame (a group's area)
    local boxLeft, boxBottom, boxWidth, boxHeight = scrubsecretvalues(overlay:GetRect())
    if boxLeft and boxBottom and boxWidth and boxHeight then
        dragBox = { boxLeft, boxLeft + boxWidth, boxBottom, boxBottom + boxHeight, boxLeft + boxWidth / 2, boxBottom + boxHeight / 2 }
    else
        dragBox = nil
    end
    CollectSnapLines(entry)

    if not guideX then
        guideX = decorHost:CreateTexture(nil, 'OVERLAY')
        guideX:NCDisablePixelSnap()
        guideY = decorHost:CreateTexture(nil, 'OVERLAY')
        guideY:NCDisablePixelSnap()
        readout = decorHost:CreateFontString(nil, 'OVERLAY')
        readout:SetFont(Core.Media.Fonts.Expressway, 12, 'OUTLINE')
    end
    guideX:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.8)
    guideY:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.8)
    readout:SetTextColor(1, 1, 1, 1)
    readout:ClearAllPoints()
    readout:SetPoint('TOP', overlay, 'BOTTOM', 0, -4)
    readout:Show()

    dragDBX, dragDBY = Anchors:GetOffsets(entry.key)
    dragMoveX, dragMoveY = 0, 0
    heldX.line, heldY.line = nil, nil
    dragSnap = Core:GetAnchorsSettings().Snap
    readout:SetText(FormatOffset(dragDBX) .. ', ' .. FormatOffset(dragDBY))

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

    -- a drag can end off the box, where no OnLeave fires
    Anchors.hoverKey = overlay:IsMouseOver() and entry.key or nil
    Anchors:SetOffsets(entry.key, dragDBX + dragMoveX, dragDBY + dragMoveY)
    Anchors:Select(entry.key)
end

local function OnOverlayEnter(overlay)
    if isDragging then return end
    overlay.isHovered = true
    Anchors.hoverKey = overlay.entry.key
    Anchors:RefreshOverlayStates()

    -- what a box does that its look doesn't say
    local entry = overlay.entry
    if entry.locked then
        GameTooltip:SetOwner(overlay, 'ANCHOR_TOP')
        GameTooltip:SetText(entry.displayName, 1, 1, 1)
        local why = type(entry.locked) == 'string' and entry.locked or L['Its group places it, move the group instead.']
        GameTooltip:AddLine(why, Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], true)
        GameTooltip:Show()
    end
end

local function OnOverlayLeave(overlay)
    overlay.isHovered = false
    if GameTooltip:IsOwned(overlay) then
        GameTooltip:Hide()
    end
    if Anchors.hoverKey == overlay.entry.key then
        Anchors.hoverKey = nil
    end
    if isDragging then return end

    Anchors:RefreshOverlayStates()
end

local function OnOverlayMouseDown(overlay, button)
    if button ~= 'LeftButton' then return end

    overlay.didDrag = false
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    overlay.downX, overlay.downY = x / scale, y / scale
end

local function OnOverlayMouseUp(overlay, button)
    -- boxes stay mouse-live while they fade out
    if not Anchors.isActive or isDragging then return end

    -- the box's settings are the window it was picked in
    if button == 'RightButton' and not Anchors.boxKey then
        Anchors:Select(overlay.entry.key)
        if IsControlKeyDown() then
            Anchors:ResetSelected()
        else
            Anchors:OpenSelectedSettings()
        end
        return
    end
    if button ~= 'LeftButton' or overlay.didDrag then return end

    local key = overlay.entry.key
    local stacked = {}
    for _, other in pairs(Anchors.overlays) do
        if other:IsShown() and other:IsMouseEnabled() and other:IsMouseOver() then
            stacked[#stacked + 1] = other
        end
    end
    if not stacked[2] then
        Anchors:Select(key)
        return
    end

    -- several boxes under the cursor: pick one by name
    sort(stacked, function(a, b) return (a.area or 0) < (b.area or 0) end)
    local entries = {}
    for index, other in ipairs(stacked) do
        local otherKey = other.entry.key
        entries[index] = { text = other.entry.displayName, onClick = function() Anchors:Select(otherKey) end }
    end
    activeAddon.GUI:ShowContextMenu(entries)
end

---Up and down, Shift for sideways.
local function OnOverlayMouseWheel(overlay, delta)
    if not Anchors.isActive or isDragging then return end

    Anchors:Select(overlay.entry.key)
    if IsShiftKeyDown() then
        Anchors:Nudge(delta, 0)
    else
        Anchors:Nudge(0, delta)
    end
end

-- the selected box fades its fill so what it moves shows through, its border stays
---@param overlay table
---@param selected boolean?
---@return number
local function FillAlpha(overlay, selected)
    -- a box alone is only a frame around the display it moves
    if Anchors.boxKey then
        return 0
    elseif selected then
        return SELECTED_FILL_ALPHA
    end
    return overlay.entry.bounds and BOUNDS_FILL_ALPHA or FILL_ALPHA
end

---The resting fill at once, for a box made or taken back out of the spares.
---@param overlay table
local function PaintFill(overlay)
    local bg, alpha = Theme.bgDark, FillAlpha(overlay)
    overlay.setFill(bg[1], bg[2], bg[3], alpha)
    overlay.fill:SetColorTexture(bg[1], bg[2], bg[3], alpha)
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

    local overlay = spareOverlays[key]
    if overlay then
        spareOverlays[key] = nil
        overlay.entry = entry
        overlay.isHovered = false
        overlay.text:SetText(entry.displayName)
        PaintFill(overlay)
        Anchors.overlays[key] = overlay
        self:UpdateOverlay(key)
        return
    end

    -- no backdrop: its arithmetic fails on a secret size
    overlay = CreateFrame('Frame', 'NRSKNUI_Anchor_' .. key, overlayHost)
    overlay.entry = entry
    local fill = overlay:CreateTexture(nil, 'BACKGROUND')
    fill:SetAllPoints()
    overlay.fill = fill
    overlay.animateFill, overlay.setFill = Animations:CreateColorAnimator(overlay, function(r, g, b, a)
        fill:SetColorTexture(r, g, b, a)
    end, Theme.bgDark, STATE_DURATION)
    PaintFill(overlay)

    overlay.edges = {}
    for index, edge in ipairs(EDGES) do
        local texture = overlay:CreateTexture(nil, 'BORDER')
        texture:NCDisablePixelSnap()
        texture:SetPoint(edge[1])
        texture:SetPoint(edge[2])
        texture:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
        overlay.edges[index] = texture
    end

    local text = overlay:CreateFontString(nil, 'OVERLAY')
    text:SetFont(Core.Media.Fonts.Expressway, TEXT_FONT_SIZE, 'OUTLINE')
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
    overlay.fadeTo = CreateFader(overlay, DIM_DURATION)

    overlay:EnableMouse(true)
    overlay:RegisterForDrag('LeftButton')
    overlay:SetScript('OnDragStart', OnDragStart)
    overlay:SetScript('OnDragStop', OnDragStop)
    overlay:SetScript('OnEnter', OnOverlayEnter)
    overlay:SetScript('OnLeave', OnOverlayLeave)
    overlay:SetScript('OnMouseDown', OnOverlayMouseDown)
    overlay:SetScript('OnMouseUp', OnOverlayMouseUp)
    overlay:EnableMouseWheel(true)
    overlay:SetScript('OnMouseWheel', OnOverlayMouseWheel)

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

    local mult = Pixel.GetMult()
    for index, texture in ipairs(overlay.edges) do
        if EDGES[index][3] == 'height' then
            texture:SetHeight(BORDER_SIZE * mult)
        else
            texture:SetWidth(BORDER_SIZE * mult)
        end
    end

    overlay:ClearAllPoints()
    overlay.text:ClearAllPoints()

    local entry = overlay.entry
    local left, bottom, right, top
    if entry.bounds then
        left, bottom, right, top = entry.bounds(entry.module)
    end
    local hasBounds = left ~= nil

    -- only the box follows overlayFrame, a drag still moves the entry's own frame
    local target = hasBounds and frame or entry.overlayFrame or frame
    local x, y, width, height = scrubsecretvalues(target:GetRect())
    if x and y and width and height then
        local ratio = target:GetEffectiveScale() / UIParent:GetEffectiveScale()
        x, y, width, height = x * ratio, y * ratio, width * ratio, height * ratio
        if not hasBounds then
            left, bottom, right, top = x, y, x + width, y + height
        end

        -- hangs off the frame so it follows a drag
        overlay:SetPoint('BOTTOMLEFT', target, 'BOTTOMLEFT', ToPixelGrid(left) - x, ToPixelGrid(bottom) - y)
        if hasBounds then
            overlay:SetPoint('TOPRIGHT', target, 'BOTTOMLEFT', ToPixelGrid(right) - x, ToPixelGrid(top) - y)
        else
            overlay:SetPoint('TOPRIGHT', target, 'TOPRIGHT', ToPixelGrid(right) - right, ToPixelGrid(top) - top)
        end
    else
        overlay:SetAllPoints(target)
    end

    if hasBounds then
        overlay.text:SetPoint('TOP', overlay, 'TOP', 0, -BOUNDS_LABEL_INSET)
    else
        overlay.text:SetPoint('CENTER')
    end

    overlay:Show()
end

---Smaller boxes on top, so one inside another can be grabbed.
function StackOverlays()
    local stack = {}
    for _, overlay in pairs(Anchors.overlays) do
        if overlay:IsShown() then
            local width, height = scrubsecretvalues(overlay:GetSize())
            overlay.area = (width or 0) * (height or 0)
            stack[#stack + 1] = overlay
        end
    end
    sort(stack, function(a, b) return a.area > b.area end)

    local base = overlayHost:GetFrameLevel() + 1
    for index, overlay in ipairs(stack) do
        overlay:SetFrameLevel(base + index)
    end
end

-- Selection --

---Animates one overlay to the look like its current state calls for.
---@param key string
---@param overlay NRSKNUI.AnchorOverlay
local function ApplyOverlayState(key, overlay)
    local entry = overlay.entry
    local selected = (Anchors.selectedKey == key)

    -- the border marks the selection, hover only lights the name
    -- a box alone needs no white or grey to stand out, its greyed arrows say it can't move
    local color = Theme.accent
    if selected and not Anchors.boxKey then
        color = WHITE
    elseif entry.locked and not Anchors.boxKey then
        color = Theme.textMuted
    end
    overlay.animateBorder(color[1], color[2], color[3], 1)
    local bg = Theme.bgDark
    overlay.animateFill(bg[1], bg[2], bg[3], FillAlpha(overlay, selected))

    local hovered = Anchors.hoverKey == key and not selected
    if selected or hovered then
        overlay.text:SetTextColor(1, 1, 1, 1)
    else
        overlay.text:SetTextColor(Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], 1)
    end

    -- the window it was picked in names it, an icon sized box would only be covered
    overlay.text:SetShown(not Anchors.boxKey)

    -- the box pointed at fades, so what it covers shows through
    local alpha = 1
    if isDragging and dragEntry and dragEntry.key == key then
        alpha = DRAG_ALPHA
    elseif selected then
        alpha = 1
    elseif hovered then
        alpha = HOVER_DIM_ALPHA
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
    -- the flyout belonged to the old selection
    if key ~= Anchors.selectedKey then
        Anchors.pointsOpen = false
    end
    Anchors.selectedKey = key

    self:RefreshOverlayStates()
    self:UpdateMarkers()
    self:UpdatePopup()
end

local markers -- made on the first selection

---@param region Region
---@param point string
---@return number? x on whole pixels, in UIParent's units
---@return number? y
local function PointOnScreen(region, point)
    local left, bottom, width, height = scrubsecretvalues(region:GetRect())
    local fraction = Pixel.POINT_FRACTION[point]
    if not (left and bottom and width and height and fraction) then return end

    local ratio = region:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return ToPixelGrid((left + width * fraction[1]) * ratio), ToPixelGrid((bottom + height * fraction[2]) * ratio)
end

---Mark the selected box's own anchor point and the point it hangs from, with a line between.
function Anchors:UpdateMarkers()
    local entry = Anchors.isActive and Anchors.selectedKey and Anchors.registry[Anchors.selectedKey]
    local frame = entry and GetEntryFrame(entry)
    -- only where its own position settings place it
    local point, relTo, relPoint
    if frame and not entry.locked and NumPoints(frame) == 1 then
        point, relTo, relPoint = frame:GetPoint(1)
        relTo = relTo or UIParent
    end

    -- only a link to another frame we're allowed to touch
    local ownX, ownY, targetX, targetY
    if point and Core:CanAccessObject(relTo) and relTo ~= UIParent then
        ownX, ownY = PointOnScreen(frame, point)
        targetX, targetY = PointOnScreen(relTo, relPoint)
    end
    if not (ownX and targetX) then
        for _, texture in pairs(markers or {}) do
            texture:Hide()
        end
        return
    end

    if not markers then
        markers = {
            own = decorHost:CreateTexture(nil, 'OVERLAY', nil, 7),
            target = decorHost:CreateTexture(nil, 'OVERLAY', nil, 7),
            across = decorHost:CreateTexture(nil, 'OVERLAY', nil, 6),
            upDown = decorHost:CreateTexture(nil, 'OVERLAY', nil, 6),
        }
        for _, texture in pairs(markers) do
            texture:NCDisablePixelSnap()
        end
    end
    markers.own:SetColorTexture(1, 1, 1, 1)
    markers.target:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
    markers.across:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.6)
    markers.upDown:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.6)

    local pixel = Pixel.GetMult()
    local half = MARKER_SIZE / 2 * pixel
    PlaceRect(markers.own, ownX - half, ownY - half, ownX + half, ownY + half)
    PlaceRect(markers.target, targetX - half, targetY - half, targetX + half, targetY + half)

    -- across to the target's column, then up or down to it
    PlaceRect(markers.across, math_min(ownX, targetX), ownY, math_max(ownX, targetX) + pixel, ownY + pixel)
    PlaceRect(markers.upDown, targetX, math_min(ownY, targetY), targetX + pixel, math_max(ownY, targetY) + pixel)
end

---Moves the selected anchor by whole physical pixels.
---@param deltaX number
---@param deltaY number
function Anchors:Nudge(deltaX, deltaY)
    if not Anchors.selectedKey then
        activeAddon:Print(L['No anchor selected. Click an overlay to select it.'])
        return
    end
    local entry = Anchors.registry[Anchors.selectedKey]
    local frame = entry and not entry.locked and GetEntryFrame(entry)
    if not frame then return end

    local step = Pixel.GetStep(frame)
    local x, y = self:GetOffsets(Anchors.selectedKey)
    self:SetOffsets(Anchors.selectedKey, Pixel.StepOffset(x, deltaX, step), Pixel.StepOffset(y, deltaY, step))
end

-- Session handlers --

-- above the popup, whose offset boxes take the keyboard
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

    -- the box's window closes on it
    if key == 'ESCAPE' and Anchors.boxKey then
        self:SetPropagateKeyboardInput(true)
        return
    elseif key == 'ESCAPE' then
        self:SetPropagateKeyboardInput(false)
        if Anchors.pointsOpen and Anchors.selectedKey then
            Anchors.pointsOpen = false
            Anchors:UpdatePopup()
        elseif Anchors.selectedKey then
            Anchors:Select(nil)
        else
            Anchors:Exit()
        end
        return
    end

    local delta = NUDGE_KEYS[key]
    local entry = delta and Anchors.selectedKey and Anchors.registry[Anchors.selectedKey]
    local settings = Core:GetAnchorsSettings()
    -- off, they stay movement keys
    local allowed = Anchors.boxKey and settings.BoxArrowKeys or not Anchors.boxKey and settings.ArrowKeys
    if entry and not entry.locked and allowed then
        self:SetPropagateKeyboardInput(false)
        local step = IsShiftKeyDown() and 10 or 1
        if IsAltKeyDown() then
            step = math_floor(gridStep / Pixel.GetMult() + 0.5)
        end
        Anchors:Nudge(delta[1] * step, delta[2] * step)
        return
    end

    self:SetPropagateKeyboardInput(true)
end)

local eventHandler = CreateFrame('Frame')
eventHandler:SetScript('OnEvent', function()
    if not Anchors.isActive then return end

    -- the box goes with its window, which says so itself
    if not Anchors.boxKey then
        activeAddon:Print(L['Anchors closed due to entering combat.'])
    end
    Anchors:Exit()
end)

-- Lifecycle --

-- boxes outlive a session, so ones from another view are put away
local function PlaceOverlays()
    for key, entry in pairs(Anchors.registry) do
        if InView(entry) then
            Anchors:CreateOverlay(key)
        elseif Anchors.overlays[key] then
            Anchors.overlays[key]:Hide()
        end
    end
    StackOverlays()
end

---What anchors mode and the box both open with.
---@param addon table
---@param strata FrameStrata where the boxes draw
local function Open(addon, strata)
    Anchors.isActive = true
    Anchors.pointsOpen = false
    activeAddon, Theme = addon, addon.Theme
    overlayHost:SetFrameStrata(strata)

    -- built even when hidden: the screen centre a drag snaps to comes from it
    if Core:GetAnchorsSettings().Grid then
        ShowGrid()
    else
        CreateGrid()
        BuildGridLines()
    end
    FadeOverlays(1)

    keyHandler:Show()
    keyHandler:SetPropagateKeyboardInput(true)
    eventHandler:RegisterEvent('PLAYER_REGEN_DISABLED')
end

---@param aceModule? table show only this module's anchors, from its settings header; every anchor without it
function Anchors:Enter(aceModule)
    if Anchors.isActive and not Anchors.boxKey then return end
    if Core:InCombat() then
        self.addon:Print(L['Cannot open Anchors during combat.'])
        return
    end

    -- a box goes with the window it belongs to, which is put away below
    Anchors:Exit()
    Anchors.onlyModule = aceModule
    -- under the panel, whose dropdown lists open at FULLSCREEN_DIALOG
    Open(self.addon, 'FULLSCREEN')

    -- every settings window steps aside, Exit brings back the ones that were open
    Anchors.suspended = {}
    for _, window in ipairs(Core.Kaji.windows) do
        if window:Suspend() then
            Anchors.suspended[#Anchors.suspended + 1] = window
        end
    end

    -- only the active addon previews, even with another addon's window put away behind it
    for _, addon in ipairs(addons) do
        addon.PreviewManager:SetHidden(addon ~= activeAddon)
    end
    activeAddon.PreviewManager:SetAnchorsActive(true, Anchors.onlyModule)
    PlaceOverlays()

    -- what Undo All goes back to; raw, so a field a wildcard default serves stays unset
    Anchors.snapshot = {}
    for key, entry in pairs(Anchors.registry) do
        local posTable, db = GetTables(entry)
        local target = entry.addon == activeAddon and (posTable or db)
        if target then
            local saved = {}
            for index, field in ipairs(entry.fields) do
                saved[index] = rawget(target, field)
            end
            Anchors.snapshot[key] = saved
        end
    end

    Anchors.selectedKey = nil
    Anchors.hoverKey = nil
    Anchors:RefreshOverlayStates()
    Anchors:UpdateMarkers()

    local ribbon = Anchors:CreatePanel()
    Anchors:CreatePopup()
    Anchors:UpdatePopup()
    -- account-wide, the box's grid toggle may have changed it
    local settings = Core:GetAnchorsSettings()
    ribbon.show:SetValue(settings.Show[activeAddon.shortName] or 'all', true)
    ribbon.grid:SetValue(settings.Grid)
    ribbon.snap:SetValue(settings.Snap)
    Anchors:UpdateUndoAll()
    ribbon.fader(1)
    Anchors:UpdateHelp()

    Anchors:RefreshTheme() -- overlays and panels outlive a session, the theme may have changed since
    C_Timer.After(LAYOUT_SETTLE_DELAY, function() Anchors:OnExternalPositionChange() end)
    Core.Ace:SendMessage('NRSKNUI_ANCHORS_CHANGED')
end

---Box mode: the display picked in an addon's window gets a box, without the panels.
---@param key string? nil takes it away
function Anchors:SetBox(key)
    if Anchors.isActive and not Anchors.boxKey then return end

    local entry = key and Anchors.registry[key]
    if not (entry and entry.addon == self.addon) or Core:InCombat() then
        Anchors:Exit()
        return
    end

    if not Anchors.isActive then
        -- under the window, which is DIALOG
        Open(self.addon, 'HIGH')
        Anchors.hoverKey = nil
        Anchors.boxKey = key
        PlaceOverlays()
        self:RefreshTheme()
    elseif key ~= Anchors.boxKey then
        Anchors.boxKey = key
        PlaceOverlays()
    end
    self:Select(key)
    self:OnExternalPositionChange()
end

function Anchors:Exit()
    if not Anchors.isActive then return end
    Anchors.isActive = false

    -- a drag cut short saved nothing, so it goes back; REGEN_DISABLED still allows it
    local cut = isDragging and dragEntry and GetEntryFrame(dragEntry)
    if cut then
        cut:ClearAllPoints()
        cut:NCSetGridPoint(dragPoint, dragRelTo --[[@as Frame]], dragRelPoint, dragOriginX, dragOriginY)
    end
    isDragging = false
    dragUpdateFrame:Hide()
    dragEntry = nil
    EndDragVisuals()

    self:Select(nil)
    -- a box never opens one, the menu up is the window's own
    if not Anchors.boxKey then
        activeAddon.GUI:CloseContextMenu()
    end
    HideGrid()
    FadeOverlays(0)
    keyHandler:Hide()
    eventHandler:UnregisterAllEvents()

    local boxed = Anchors.boxKey ~= nil
    Anchors.boxKey = nil
    if boxed then return end

    Anchors.onlyModule = nil
    activeAddon.PreviewManager:SetAnchorsActive(false)
    for _, addon in ipairs(addons) do
        addon.PreviewManager:SetHidden(false)
    end

    if panel then
        panel.fader(0)
        panel.help.fader(0)
    end
    if popup then
        popup.fader(0)
    end
    for _, window in ipairs(Anchors.suspended or {}) do
        window:Resume()
    end
    Anchors.suspended = nil
    Core.Ace:SendMessage('NRSKNUI_ANCHORS_CHANGED')
end

-- a window opened while positioning ends it, the suspended windows come back with it
Core.Kaji.beforeWindowShow = function()
    if not Anchors.boxKey then
        Anchors:Exit()
    end
end

---Open this addon's anchors or close them.
function Anchors:Toggle()
    if Anchors.isActive and not Anchors.boxKey then
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

-- Panel and popup --

local GAP = 6
local BUTTON_HEIGHT = 24
local SHOW_WIDTH, REVERT_WIDTH = 140, 90
local GROUP_SPACE = 10 -- either side of the hairline between two groups
local CAPTION_GAP = 4
local PANEL_LEVEL = 110 -- under the strip, so a strip beside a box near it stays on top
local ICON_SIZE, ICON_GAP = 24, 3
local STRIP_PAD, GROUP_GAP = 4, 6
local FIELD_WIDTH, PICKER_WIDTH = 63, 120 -- two icons side by side fill a field in the vertical strip
local STRIP_LEVEL = 120 -- over the panel's 110
local GRIP_DOT = 3 -- physical pixels, the gap the same
local GRIP_COLUMNS, GRIP_ROWS, GRIP_ALPHA = 2, 4, 0.7
local KEY_HEIGHT, KEY_PAD, KEY_GAP = 16, 4, 2
local CENTER_X_TEXTURE = Core.Media.GUITextures .. 'align-center-vertical.png'
local CENTER_Y_TEXTURE = Core.Media.GUITextures .. 'align-center-horizontal.png'
local ANCHOR_TEXTURE = Core.Media.GUITextures .. 'anchor.png'
local UNDO_TEXTURE = Core.Media.GUITextures .. 'undo-2.png'

-- per side of the box: the strip's point on the box's, the gap's direction
local STRIP_SIDES = {
    right = { point = 'LEFT', relPoint = 'RIGHT', x = 1, y = 0 },
    left = { point = 'RIGHT', relPoint = 'LEFT', x = -1, y = 0 },
    above = { point = 'BOTTOM', relPoint = 'TOP', x = 0, y = 1 },
    below = { point = 'TOP', relPoint = 'BOTTOM', x = 0, y = -1 },
}
-- the flyout on the strip, further from the box
local FLYOUT_SIDES = {
    right = { point = 'TOPLEFT', relPoint = 'TOPRIGHT', x = 1, y = 0 },
    left = { point = 'TOPRIGHT', relPoint = 'TOPLEFT', x = -1, y = 0 },
    above = { point = 'BOTTOMLEFT', relPoint = 'TOPLEFT', x = 0, y = 1 },
    below = { point = 'TOPLEFT', relPoint = 'BOTTOMLEFT', x = 0, y = -1 },
}

-- an entry names its groups when it registers; the English keys of name and tooltip
local SHOW_GROUPS = {
    { 'all', 'All', 'Every element.' },
    { 'solo', 'Solo', 'Player, target, focus and pet frames, their targets and the focus castbar.' },
    { 'party', 'Party', 'The party frames.' },
    { 'raid', 'Raid', 'The raid frames.' },
    { 'bossArena', 'Boss & Arena', 'The boss frames.' },
    { 'actionBars', 'Action Bars', 'Every action bar, the pet and stance bars and the micro menu.' },
    { 'interface', 'Interface', 'Minimap, buffs, debuffs, chat, the tooltip, the experience bar and Details backdrops.' },
    { 'alerts', 'Alerts & Combat', 'Alerts, timers, combat texts, BigWigs bars, dungeon casts and missing buffs.' },
}

-- left, up, down, right: the arrow's rotation, its step and the English key of its name
local ARROWS = {
    { rotation = -90, dx = -1, dy = 0, name = 'Nudge Left', pair = 'row', point = 'LEFT' },
    { rotation = 180, dx = 0, dy = 1, name = 'Nudge Up', pair = 'column', point = 'TOP' },
    { rotation = 0, dx = 0, dy = -1, name = 'Nudge Down', pair = 'column', point = 'BOTTOM' },
    { rotation = 90, dx = 1, dy = 0, name = 'Nudge Right', pair = 'row', point = 'RIGHT' },
}

-- the keys card: a string heads a section, a number in keys is one of ARROWS
local KEY_ROWS = {
    'Selected Box',
    { keys = { 1, 2, 3, 4 }, text = 'Nudge one pixel' },
    { keys = { 'Shift' }, text = 'With the arrows, ten pixels' },
    { keys = { 'Alt' }, text = 'With the arrows, one grid cell' },
    { keys = { 'Wheel' }, text = 'Nudge up and down, Shift sideways' },
    { keys = { 'RMB' }, text = 'Open its settings' },
    { keys = { 'Ctrl', 'RMB' }, text = 'Reset it to default' },
    'Anywhere',
    { keys = { 'Esc' }, text = 'Leave anchors' },
}

---@param key string
---@return table? target where its position lives
---@return table? saved its fields when the view opened
---@return table? entry
local function Snapshotted(key)
    local entry = Anchors.registry[key]
    local saved = Anchors.snapshot and Anchors.snapshot[key]
    if not (entry and saved) then return end

    local posTable, db = GetTables(entry)
    local target = posTable or db
    if not target then return end

    return target, saved, entry
end

---@param key string
---@return boolean
local function MovedSinceOpen(key)
    local target, saved, entry = Snapshotted(key)
    if not (target and saved and entry) then return false end

    for index, field in ipairs(entry.fields) do
        if rawget(target, field) ~= saved[index] then return true end
    end
    return false
end

---Undo All only while something has moved since the view opened, as the toolbar's Undo.
function Anchors:UpdateUndoAll()
    if not (panel and Anchors.snapshot) then return end

    for key in pairs(Anchors.snapshot) do
        if MovedSinceOpen(key) then
            panel.undoAll:SetEnabled(true)
            return
        end
    end
    panel.undoAll:SetEnabled(false)
end

---The keys card under the panel, above it once the panel sits in the lower half.
function Anchors:UpdateHelp()
    -- the panel takes clicks while it fades out, the card mustn't come back then
    if not (panel and Anchors.isActive) then return end

    local open = Core:GetAnchorsSettings().Help
    local help = panel.help
    panel.helpButton:SetActive(open)
    local _, centerY = panel:GetCenter()
    local below = not centerY or centerY >= UIParent:GetHeight() / 2
    help:ClearAllPoints()
    if below then
        help:NCSetGridPoint('TOPRIGHT', panel, 'BOTTOMRIGHT', 0, -GAP)
    else
        help:NCSetGridPoint('BOTTOMRIGHT', panel, 'TOPRIGHT', 0, GAP)
    end
    help.fader(open and 1 or 0)
end

---Back to where it was when the view opened; only what moved re-applies.
---@param key string
local function RevertKey(key)
    if not MovedSinceOpen(key) then return end

    local target, saved, entry = Snapshotted(key)
    for index, field in ipairs(entry.fields) do
        rawset(target, field, saved[index])
    end
    Reapply(key)
end

---A frame in the dialogs' look: their border, glow and shadow.
---@return NRSKNUI.AnchorsWindow
local function NewStrip(gui)
    local frame = CreateFrame('Frame', nil, UIParent, 'BackdropTemplate') --[[@as NRSKNUI.AnchorsWindow]]
    frame:SetFrameStrata('FULLSCREEN_DIALOG')
    frame:SetFrameLevel(STRIP_LEVEL)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:Hide()
    Kaji.SetBackdrop(frame, gui, { bg = 'bgLight', border = 'border', edgeSize = 'borderSize' })
    local stylePopup = Kaji.StylePopup(frame, gui)
    stylePopup()
    gui:OnThemeChanged(function()
        Kaji.RefreshBackdrop(frame)
        stylePopup()
    end)
    frame.fader = CreateFader(frame)
    return frame
end

---@param gui table
---@param parent Frame
---@param image string
---@param rotation number
---@param title string?
---@param tooltip string?
---@param onClick fun()
---@param size number? ICON_SIZE by default
---@param imageSize number? 8 under the size by default
local function IconButton(gui, parent, image, rotation, title, tooltip, onClick, size, imageSize)
    size = size or ICON_SIZE
    local button = gui:CreateButton(parent, '', {
        width = size,
        height = size,
        image = image,
        imageSize = imageSize or size - 8,
        imageRotation = math_rad(rotation),
        imageColor = gui.theme.accent,
        bgColor = gui.theme.bgDark,
        callback = onClick,
    })
    if title then
        button:SetTooltip(title, tooltip)
    end
    return button
end

---The strip's and the box's arrows: one pixel, with Shift ten.
---@param gui table
---@param parent Frame
---@param arrow table one of ARROWS
---@param size number?
---@param imageSize number?
local function ArrowButton(gui, parent, arrow, size, imageSize)
    return IconButton(gui, parent, ARROW_TEXTURE, arrow.rotation, L[arrow.name], L['One pixel, with Shift ten.'], function()
        local step = IsShiftKeyDown() and 10 or 1
        Anchors:Nudge(arrow.dx * step, arrow.dy * step)
    end, size, imageSize)
end

---Down the side of a box in the outer thirds, across everywhere else.
---@param popup NRSKNUI.AnchorsWindow
---@param vertical boolean
local function LayoutStrip(popup, vertical)
    if popup.vertical == vertical then return end
    popup.vertical = vertical

    -- rows of { widget, width } cells; false is a wider gap between groups
    local arrows = popup.arrows
    local half = (FIELD_WIDTH - ICON_GAP) / 2
    local rows
    if vertical then
        rows = {
            { { popup.xBox, FIELD_WIDTH } },
            { { popup.yBox, FIELD_WIDTH } },
            false,
            { { arrows[1], half }, { arrows[4], half } },
            { { arrows[2], half }, { arrows[3], half } },
            false,
            { { popup.centerX, half }, { popup.centerY, half } },
            { { popup.points, half }, { popup.undo, half } },
        }
    else
        -- the vertical blocks turned on their side
        rows = {
            {
                { popup.xBox, FIELD_WIDTH }, false,
                { arrows[1], half }, { arrows[4], half }, false,
                { popup.centerX, half }, { popup.centerY, half },
            },
            {
                { popup.yBox, FIELD_WIDTH }, false,
                { arrows[2], half }, { arrows[3], half }, false,
                { popup.points, half }, { popup.undo, half },
            },
        }
    end

    -- pinned from the top left: centred in a strip of odd pixels they'd sit on half ones
    local width, y = 0, STRIP_PAD
    for _, row in ipairs(rows) do
        if row then
            local x = STRIP_PAD
            for _, cell in ipairs(row) do
                if cell then
                    cell[1]:ClearAllPoints()
                    cell[1]:NCSetPoint('TOPLEFT', popup, 'TOPLEFT', x, -y)
                    cell[1]:NCSetSize(cell[2], ICON_SIZE)
                    x = x + cell[2] + ICON_GAP
                else
                    x = x + GROUP_GAP
                end
            end
            width = math_max(width, x - ICON_GAP + STRIP_PAD)
            y = y + ICON_SIZE + ICON_GAP
        else
            y = y + GROUP_GAP
        end
    end
    popup:NCSetSize(width, y - ICON_GAP + STRIP_PAD)
end

---The session's settings as a ribbon: groups of controls, each named by a caption under it.
---@return NRSKNUI.AnchorsWindow
function Anchors:CreatePanel()
    if panel then
        return panel
    end

    local gui, settings, name = activeAddon.GUI, Core:GetAnchorsSettings(), activeAddon.shortName
    local theme = gui.theme
    local inset = theme.paddingMedium
    panel = NewStrip(gui)
    panel:SetFrameLevel(PANEL_LEVEL)

    panel:SetMovable(true)
    panel:RegisterForDrag('LeftButton')
    panel:SetScript('OnDragStart', panel.StartMoving)
    panel:SetScript('OnDragStop', function(frame)
        frame:StopMovingOrSizing()
        -- a drag leaves it between pixels
        local point, _, relPoint, x, y = frame:GetPoint(1)
        frame:ClearAllPoints()
        frame:NCSetGridPoint(point, UIParent, relPoint, x, y)
        settings.Panels[name] = { point, relPoint, x, y }
        Anchors:UpdateHelp()
    end)

    -- Groups --

    local view = CreateFrame('Frame', nil, panel)
    panel.grid = gui:CreateSlimCheckbox(view, L['Grid'], {
        value = settings.Grid,
        tooltip = L['Lines across the screen. While they show, dragging snaps to them too.'],
        callback = function(checked) Anchors:SetGrid(checked) end,
    })
    panel.snap = gui:CreateSlimCheckbox(view, L['Snap'], {
        value = settings.Snap,
        tooltip = L['Hold Shift while dragging to turn it off for a moment.'],
        callback = function(checked) settings.Snap = checked end,
    })
    panel.keys = gui:CreateSlimCheckbox(view, L['Arrow Keys'], {
        value = settings.ArrowKeys,
        tooltip = L['The arrow keys nudge the selected box. Off, they move you as usual.'],
        callback = function(checked) settings.ArrowKeys = checked end,
    })
    local gridWidth, snapWidth, keysWidth = panel.grid:GetFitWidth(), panel.snap:GetFitWidth(), panel.keys:GetFitWidth()
    panel.grid:NCSetWidth(gridWidth)
    panel.grid:NCSetPoint('LEFT', view, 'LEFT', 0, 0)
    panel.snap:NCSetWidth(snapWidth)
    panel.snap:NCSetPoint('LEFT', panel.grid, 'RIGHT', inset, 0)
    panel.keys:NCSetWidth(keysWidth)
    panel.keys:NCSetPoint('LEFT', panel.snap, 'RIGHT', inset, 0)
    view:NCSetWidth(gridWidth + inset + snapWidth + inset + keysWidth)

    -- named here, not at load: the chosen language isn't applied while Core loads
    local options = {}
    for index, group in ipairs(SHOW_GROUPS) do
        options[index] = { value = group[1], text = L[group[2]], tooltip = L[group[3]] }
    end
    local show = CreateFrame('Frame', nil, panel)
    panel.show = gui:CreateDropdown(show, nil, {
        options = options,
        value = settings.Show[name] or 'all',
        callback = function(value)
            settings.Show[name] = value
            if not Anchors.isActive then return end

            Anchors:Select(nil)
            -- previews first: a group's box is sized from them
            activeAddon.PreviewManager:Refresh()
            PlaceOverlays()
            Anchors:RefreshOverlayStates()
            C_Timer.After(LAYOUT_SETTLE_DELAY, function() Anchors:OnExternalPositionChange() end)
        end,
    })
    panel.show:NCSetWidth(SHOW_WIDTH)
    show:NCSetWidth(SHOW_WIDTH)

    local edit = CreateFrame('Frame', nil, panel)
    panel.undoAll = gui:CreateButton(edit, L['Undo All'], {
        width = REVERT_WIDTH,
        height = BUTTON_HEIGHT,
        tooltip = L['Put everything back where it was when anchors opened.'],
        callback = function()
            if Anchors.isActive then
                Anchors:RevertAll()
            end
        end,
    })
    panel.undoAll:NCSetPoint('TOPLEFT', edit, 'TOPLEFT', 0, 0)
    edit:NCSetWidth(REVERT_WIDTH)

    -- the window header's buttons, with their glow
    local helpGroup = CreateFrame('Frame', nil, panel)
    local helpIcon = Kaji.HeaderIcon('help')
    helpIcon.tooltip = L['Help']
    helpIcon.onClick = function()
        settings.Help = not settings.Help
        Anchors:UpdateHelp()
    end
    panel.helpButton = Kaji.CreateHeaderButton(gui, helpGroup, helpIcon)
    panel.helpButton:ClearAllPoints()
    panel.helpButton:NCSetPoint('TOPLEFT', helpGroup, 'TOPLEFT', 0, 0)
    helpGroup:NCSetWidth(panel.helpButton:GetWidth())

    local leave = CreateFrame('Frame', nil, panel)
    local closeIcon = Kaji.HeaderIcon('close')
    closeIcon.tooltip = L['Close']
    closeIcon.onClick = function() Anchors:Exit() end
    local close = Kaji.CreateHeaderButton(gui, leave, closeIcon)
    close:ClearAllPoints()
    close:NCSetPoint('TOPLEFT', leave, 'TOPLEFT', 0, 0)
    leave:NCSetWidth(close:GetWidth())

    -- side by side, a hairline between, each named underneath; joined ones get a gap instead
    local groups = {
        { view, L['View'] },
        { show, L['Show'] },
        { edit, L['Edit'] },
        { helpGroup, L['Help'] },
        { leave, L['Leave'], joined = true },
    }
    local captions, dividers = {}, {}
    local dotSize = GRIP_DOT * Pixel.GetMult()
    local x = inset + dotSize * (GRIP_COLUMNS * 2 - 1)

    local function AddDivider()
        local line = panel:CreateTexture(nil, 'ARTWORK')
        line:NCDisablePixelSnap()
        line:NCSetPoint('TOPLEFT', panel, 'TOPLEFT', x + GROUP_SPACE, -inset)
        line:NCSetPoint('BOTTOMLEFT', panel, 'BOTTOMLEFT', x + GROUP_SPACE, inset)
        line:NCSetWidth(theme.borderSize)
        dividers[#dividers + 1] = line
        x = x + GROUP_SPACE * 2 + theme.borderSize
    end

    AddDivider()
    for index, group in ipairs(groups) do
        local frame = group[1]
        local caption = panel:CreateFontString(nil, 'OVERLAY')
        gui:ApplyFont(caption, 'small')
        caption:SetJustifyH('CENTER')
        caption:SetText(group[2]:upper())
        captions[index] = caption
        -- as wide as its controls or its caption, the controls centred on a whole pixel
        local width = ToPixelGrid(math_max(frame:GetWidth(), caption:GetStringWidth()))
        frame:NCSetHeight(BUTTON_HEIGHT)
        frame:NCSetPoint('TOPLEFT', panel, 'TOPLEFT', x + ToPixelGrid((width - frame:GetWidth()) / 2), -inset)
        caption:NCSetPoint('TOPLEFT', panel, 'TOPLEFT', x, -(inset + BUTTON_HEIGHT + CAPTION_GAP))
        caption:NCSetWidth(width)
        x = x + width
        local nextGroup = groups[index + 1]
        if nextGroup and nextGroup.joined then
            x = x + GROUP_SPACE
        elseif nextGroup then
            AddDivider()
        end
    end
    local captionHeight = captions[1]:GetStringHeight()
    local contentHeight = BUTTON_HEIGHT + CAPTION_GAP + captionHeight
    panel:NCSetSize(x + inset, inset + contentHeight + inset)

    -- a grip, so it reads as draggable
    local dots = {}
    local gripTop = inset + ToPixelGrid((contentHeight - dotSize * (GRIP_ROWS * 2 - 1)) / 2)
    for row = 0, GRIP_ROWS - 1 do
        for column = 0, GRIP_COLUMNS - 1 do
            local dot = panel:CreateTexture(nil, 'ARTWORK')
            dot:NCDisablePixelSnap()
            dot:NCSetSize(dotSize, dotSize)
            dot:NCSetPoint('TOPLEFT', panel, 'TOPLEFT', inset + column * dotSize * 2, -(gripTop + row * dotSize * 2))
            dots[#dots + 1] = dot
        end
    end

    -- the keys card, rows of keycaps right-aligned against what they do
    local help = NewStrip(gui)
    help:SetFrameLevel(PANEL_LEVEL)
    panel.help = help
    local rows, labels = {}, {}
    local keyColumn, textWidth = 0, 0
    for index, row in ipairs(KEY_ROWS) do
        if type(row) == 'string' then
            local caption = help:CreateFontString(nil, 'OVERLAY')
            gui:ApplyFont(caption, 'small')
            caption:SetText(L[row]:upper())
            captions[#captions + 1] = caption
            rows[index] = { caption = caption }
        else
            local keys, width = {}, 0
            for _, key in ipairs(row.keys) do
                local arrow = ARROWS[key]
                -- a keycap, not a control: it never takes the mouse
                local keycap = gui:CreateButton(help, arrow and '' or L[key]:upper(), {
                    width = KEY_HEIGHT,
                    height = KEY_HEIGHT,
                    fontSize = 'small',
                    bgColor = theme.bgDark,
                    selectionStyle = 'text',
                    image = arrow and ARROW_TEXTURE or nil,
                    imageSize = KEY_HEIGHT - 6,
                    imageRotation = arrow and math_rad(arrow.rotation) or nil,
                    imageColor = theme.textPrimary,
                })
                keycap:EnableMouse(false)
                if not arrow then
                    keycap:NCSetWidth(math_max(KEY_HEIGHT, ToPixelGrid(keycap.text:GetStringWidth()) + KEY_PAD * 2))
                end
                keys[#keys + 1] = keycap
                width = width + keycap:GetWidth() + KEY_GAP
            end
            local label = help:CreateFontString(nil, 'OVERLAY')
            gui:ApplyFont(label, 'normal')
            label:SetText(L[row.text])
            labels[#labels + 1] = label
            rows[index] = { keys = keys, width = width - KEY_GAP, label = label }
            keyColumn = math_max(keyColumn, width - KEY_GAP)
            textWidth = math_max(textWidth, label:GetStringWidth())
        end
    end

    local y = inset
    for index, row in ipairs(rows) do
        if row.caption then
            if index > 1 then
                y = y + GAP
            end
            row.caption:NCSetPoint('TOPLEFT', help, 'TOPLEFT', inset, -y)
            y = y + captionHeight + GAP
        else
            local keyX = inset + keyColumn - row.width
            for _, keycap in ipairs(row.keys) do
                keycap:NCSetPoint('TOPLEFT', help, 'TOPLEFT', keyX, -y)
                keyX = keyX + keycap:GetWidth() + KEY_GAP
            end
            local labelY = y + ToPixelGrid((KEY_HEIGHT - row.label:GetStringHeight()) / 2)
            row.label:NCSetPoint('TOPLEFT', help, 'TOPLEFT', inset + keyColumn + GAP, -labelY)
            y = y + KEY_HEIGHT + GAP
        end
    end
    local mult = Pixel.GetMult()
    help:NCSetSize(inset + keyColumn + GAP + math_ceil(textWidth / mult) * mult + inset, y - GAP + inset)

    -- raised by the room it keeps for a label, measured once placed
    panel.show:NCSetPoint('TOPLEFT', show, 'TOPLEFT', 0, 0)
    local saved = settings.Panels[name]
    if saved then
        panel:NCSetGridPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
    else
        panel:NCSetGridPoint('TOP', UIParent, 'TOP', 0, -inset)
    end
    local showTop, fieldTop = panel.show:GetTop(), panel.show:GetField():GetTop()
    if showTop and fieldTop then
        panel.show:ClearAllPoints()
        panel.show:NCSetPoint('TOPLEFT', show, 'TOPLEFT', 0, ToPixelGrid(showTop - fieldTop))
    end

    local function Paint()
        local muted, line, text, accent = theme.textMuted, theme.widgetBorder, theme.textSecondary, theme.accent
        for _, caption in ipairs(captions) do
            caption:SetTextColor(muted[1], muted[2], muted[3], 1)
        end
        for _, divider in ipairs(dividers) do
            divider:SetColorTexture(line[1], line[2], line[3], 1)
        end
        for _, label in ipairs(labels) do
            label:SetTextColor(text[1], text[2], text[3], 1)
        end
        for _, dot in ipairs(dots) do
            dot:SetColorTexture(accent[1], accent[2], accent[3], GRIP_ALPHA)
        end
    end
    Paint()
    gui:OnThemeChanged(Paint)
    return panel
end

function Anchors:CreatePopup()
    if popup then return end

    local gui = activeAddon.GUI
    local strip = NewStrip(gui)
    popup = strip

    -- to the box they were filled for, a new selection's focus loss commits too
    local function CommitOffsets()
        local x, y = tonumber(strip.xBox:GetValue()), tonumber(strip.yBox:GetValue())
        local entry = strip.key and Anchors.registry[strip.key]
        if not (entry and not entry.locked and x and y) then
            Anchors:UpdatePopup()
            return
        end

        -- untouched, so nothing re-applies
        local oldX, oldY = Anchors:GetOffsets(strip.key)
        if x == ToTenths(oldX) and y == ToTenths(oldY) then return end

        Anchors:SetOffsets(strip.key, x, y)
    end

    strip.xBox = gui:CreateEditBox(strip, 'X', {
        inlineLabel = true,
        labelWidth = 16,
        tooltip = L['Its offset left to right. Type a number and press Enter.'],
        callback = CommitOffsets,
    })
    strip.yBox = gui:CreateEditBox(strip, 'Y', {
        inlineLabel = true,
        labelWidth = 16,
        tooltip = L['Its offset up and down. Type a number and press Enter.'],
        callback = CommitOffsets,
    })
    strip.arrows = {}
    for index, arrow in ipairs(ARROWS) do
        strip.arrows[index] = ArrowButton(gui, strip, arrow)
    end
    strip.centerX = IconButton(gui, strip, CENTER_X_TEXTURE, 0, L['Center Horizontally'],
        L['Moves it to the middle of the screen, on the horizontal axis.'], function() Anchors:CenterSelected(true) end)
    strip.centerY = IconButton(gui, strip, CENTER_Y_TEXTURE, 0, L['Center Vertically'],
        L['Moves it to the middle of the screen, on the vertical axis.'], function() Anchors:CenterSelected(false) end)
    strip.points = IconButton(gui, strip, ANCHOR_TEXTURE, 0, L['Anchor Points'],
        L['Choose which points it is anchored by or reset it to its default.'], function()
        Anchors.pointsOpen = not Anchors.pointsOpen
        Anchors:UpdatePopup()
    end)
    strip.undo = IconButton(gui, strip, UNDO_TEXTURE, 0, L['Undo'],
        L['Back to where it was when anchors opened.'], function() Anchors:RevertSelected() end)

    -- the anchor points and the way back to the default, one click away
    local flyout = NewStrip(gui)
    strip.flyout = flyout
    strip.from = gui:CreateAnchorPicker(flyout, L['Anchor From'], {
        callback = function(point) Anchors:SetAnchorPoints(point, nil) end,
    })
    strip.from:NCSetPoint('TOPLEFT', flyout, 'TOPLEFT', STRIP_PAD, -STRIP_PAD)
    strip.from:NCSetWidth(PICKER_WIDTH)
    strip.to = gui:CreateAnchorPicker(flyout, L["To Frame's"], {
        callback = function(point) Anchors:SetAnchorPoints(nil, point) end,
    })
    strip.to:NCSetPoint('TOPLEFT', strip.from, 'TOPRIGHT', GAP, 0)
    strip.to:NCSetWidth(PICKER_WIDTH)
    strip.reset = gui:CreateButton(flyout, L['Reset to Default'], {
        height = BUTTON_HEIGHT,
        callback = function() Anchors:ResetSelected() end,
    })
    strip.reset:NCSetPoint('TOPLEFT', strip.from, 'BOTTOMLEFT', 0, -GAP)
    strip.reset:NCSetPoint('TOPRIGHT', strip.to, 'BOTTOMRIGHT', 0, -GAP)
    flyout:NCSetSize(PICKER_WIDTH * 2 + GAP + STRIP_PAD * 2, strip.from:GetHeight() + GAP + BUTTON_HEIGHT + STRIP_PAD * 2)
end

---Up and down beside the box, left and right under it; greyed out on a box that can't move.
---@param overlay Frame?
---@param movable boolean
local function PlaceBoxArrows(overlay, movable)
    if not overlay then
        if boxArrows then
            boxArrows.column:Hide()
            boxArrows.row:Hide()
        end
        return
    end

    -- each pair clamped on its own, so a box at the screen's edge can still be nudged back
    if not boxArrows then
        local long = BOX_ARROW_SIZE * 2 + ICON_GAP
        boxArrows = { column = CreateFrame('Frame', nil, decorHost), row = CreateFrame('Frame', nil, decorHost), buttons = {} }
        boxArrows.column:NCSetSize(BOX_ARROW_SIZE, long)
        boxArrows.row:NCSetSize(long, BOX_ARROW_SIZE)
        for index, arrow in ipairs(ARROWS) do
            local pair = boxArrows[arrow.pair] --[[@as Frame]]
            pair:SetClampedToScreen(true)
            local button = ArrowButton(activeAddon.GUI, pair, arrow, BOX_ARROW_SIZE, BOX_ARROW_IMAGE)
            button:NCSetPoint(arrow.point, pair, arrow.point, 0, 0)
            boxArrows.buttons[index] = button
        end
    end
    for _, button in ipairs(boxArrows.buttons) do
        button:SetEnabled(movable)
    end
    boxArrows.column:ClearAllPoints()
    boxArrows.column:NCSetGridPoint('LEFT', overlay, 'RIGHT', GAP, 0)
    boxArrows.column:Show()
    boxArrows.row:ClearAllPoints()
    boxArrows.row:NCSetGridPoint('TOP', overlay, 'BOTTOM', 0, -GAP)
    boxArrows.row:Show()
end

---Fills the strip and puts it beside the box, towards the centre; or the box's arrows.
function Anchors:UpdatePopup()
    local key = Anchors.selectedKey
    local entry = key and Anchors.registry[key]
    local frame = entry and GetEntryFrame(entry)
    local overlay = key and Anchors.overlays[key]
    -- the box can still be fading out when the session closed a frame ago
    local live = Anchors.isActive and frame and overlay and overlay:IsShown()
    PlaceBoxArrows(live and Anchors.boxKey and overlay or nil, entry ~= nil and not entry.locked)
    local shown = live and NumPoints(frame) == 1
    if not popup then return end

    if not shown or Anchors.boxKey then
        popup.fader(0)
        popup.flyout.fader(0)
        return
    end

    -- read first: clearing the focus commits and can come back in here
    local previousKey = popup.key
    popup.xBox.editBox:ClearFocus()
    popup.yBox.editBox:ClearFocus()
    popup.key = key
    local movable = not entry.locked
    local posTable = GetTables(entry)
    local _, relTo = frame:GetPoint(1)
    for _, widget in ipairs({ popup.xBox, popup.yBox, popup.centerX, popup.centerY, popup.points }) do
        widget:SetEnabled(movable)
    end
    for _, arrow in ipairs(popup.arrows) do
        arrow:SetEnabled(movable)
    end
    popup.undo:SetEnabled(movable and MovedSinceOpen(key))

    -- a dynamic group hangs from the point it grows from
    local pickable = movable and posTable ~= nil and posTable[entry.fromKey] ~= nil
    popup.from:SetEnabled(pickable and not frame.UpdateGroupPosition)
    popup.to:SetEnabled(pickable)
    popup.reset:SetEnabled(movable and DefaultPosition(entry) ~= nil)

    local x, y = self:GetOffsets(key)
    popup.xBox:SetValue(movable and FormatOffset(x) or '--')
    popup.yBox:SetValue(movable and FormatOffset(y) or '--')
    popup.from:SetValue(posTable and posTable[entry.fromKey] or 'CENTER')
    popup.to:SetValue(posTable and posTable[entry.toKey] or 'CENTER')
    popup.to.label:SetText((relTo or UIParent) == UIParent and L["To Screen's"] or L["To Frame's"])

    -- beside a box in the outer thirds, above or below one in the middle
    local centerX, centerY = scrubsecretvalues(overlay:GetCenter())
    local width, height = UIParent:GetSize()
    local side = 'below'
    if centerX and centerX <= width / 3 then
        side = 'right'
    elseif centerX and centerX >= width * 2 / 3 then
        side = 'left'
    elseif centerY and centerY < height / 2 then
        side = 'above'
    end
    LayoutStrip(popup, side == 'left' or side == 'right')

    popup:ClearAllPoints()
    local placement = STRIP_SIDES[side]
    popup:NCSetGridPoint(placement.point, overlay, placement.relPoint, placement.x * GAP, placement.y * GAP)
    popup.fader(1)

    -- the flyout opens away from the box
    local open = Anchors.pointsOpen and movable
    popup.points:SetSelected(open)
    local flyout = popup.flyout
    flyout:ClearAllPoints()
    placement = FLYOUT_SIDES[side]
    flyout:NCSetGridPoint(placement.point, popup, placement.relPoint, placement.x * GAP, placement.y * GAP)
    -- a new selection shuts it at once, a fade would play out beside the next box
    if open or key == previousKey then
        flyout.fader(open and 1 or 0)
    else
        flyout:Hide()
    end
end

---The grid on or off, for anchors mode and the box alike.
---@param shown boolean
function Anchors:SetGrid(shown)
    Core:GetAnchorsSettings().Grid = shown
    if not Anchors.isActive then return end

    if shown then
        ShowGrid()
    else
        HideGrid()
    end
end

-- Popup actions --

---Keeps the box where it is on screen.
---@param from string? nil keeps the current one
---@param to string?
function Anchors:SetAnchorPoints(from, to)
    local key = Anchors.selectedKey
    local entry = key and Anchors.registry[key]
    local frame = entry and GetEntryFrame(entry)
    local posTable = entry and GetTables(entry)
    if not (frame and posTable and NumPoints(frame) == 1) then return end

    local point, relTo, relPoint = frame:GetPoint(1)
    relTo = relTo or UIParent
    from, to = from or point, to or relPoint
    local _, _, oldLeft, oldBottom, step = Pixel.GetAnchorBase(frame, point, relTo --[[@as Frame]], relPoint)
    local _, _, newLeft, newBottom = Pixel.GetAnchorBase(frame, from, relTo --[[@as Frame]], to)
    if not (oldLeft and oldBottom and newLeft and newBottom) then return end

    -- each anchor's spot snaps on its own, so moving the snapped difference keeps the pixel
    -- and switching back gives the same offsets
    local x, y = self:GetOffsets(key)
    x = ToPixelGrid(x, step) + oldLeft - newLeft
    y = ToPixelGrid(y, step) + oldBottom - newBottom
    posTable[entry.fromKey], posTable[entry.toKey] = from, to
    self:SetOffsets(key, x, y)
end

---@param across boolean
function Anchors:CenterSelected(across)
    local key = Anchors.selectedKey
    local entry = key and Anchors.registry[key]
    local frame = entry and GetEntryFrame(entry)
    local overlay = key and Anchors.overlays[key]
    if not (frame and overlay) then return end

    local centerX, centerY = scrubsecretvalues(overlay:GetCenter())
    if not (centerX and centerY) then return end

    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x, y = self:GetOffsets(key)
    if across then
        x = x + (gridCenterX - centerX) / ratio
    else
        y = y + (gridCenterY - centerY) / ratio
    end
    self:SetOffsets(key, x, y)
end

function Anchors:ResetSelected()
    local key = Anchors.selectedKey
    local entry = key and Anchors.registry[key]
    local defaults = entry and not entry.locked and DefaultPosition(entry)
    local posTable = defaults and GetTables(entry)
    if not posTable then return end

    for _, field in ipairs(entry.fields) do
        for _, source in ipairs(defaults) do
            if source[field] ~= nil then
                posTable[field] = source[field]
                break
            end
        end
    end
    Reapply(key)
end

function Anchors:RevertAll()
    for key in pairs(Anchors.snapshot or {}) do
        RevertKey(key)
    end
end

function Anchors:RevertSelected()
    if Anchors.selectedKey then
        RevertKey(Anchors.selectedKey)
    end
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
    StackOverlays()
    self:UpdatePopup()
end

---Re-themes live overlays and the panel after a theme change.
function Anchors:RefreshTheme()
    if not Anchors.isActive then return end

    -- the fill and border animate to the new colours with the state
    self:RefreshOverlayStates()
end

---An addon's own handle on the anchor system. What it registers is its own and it opens on its own theme.
---@param addon table needs GUI, Theme, Print, OpenOptions and PreviewManager
---@return NRSKNUI.Anchors
function Core:NewAnchors(addon)
    addons[#addons + 1] = addon
    return setmetatable({ addon = addon }, { __index = Anchors })
end
