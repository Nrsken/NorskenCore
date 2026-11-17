---@class NorskenCore
local Core = select(2, ...)

local min, max, ceil, floor = math.min, math.max, math.ceil, math.floor

-- each other Grow as the first letter of a Grid Fill, so one parser reads them all
local GROW_FILL = { RIGHT = 'R', LEFT = 'L', HORIZONTAL = 'R', DOWN = 'D', UP = 'U', VERTICAL = 'D' }

---The flow layout a dynamic group's Layout asks for, so an aura group grows like one.
---@param layout table a dynamic group's Layout: Grow, Align, Spacing, RowSpacing, GridType, GridWidth
---@param width number one button's width
---@param height number one button's height
---@return table flow the container config's layout keys
function Core:ResolveAuraFlow(layout, width, height)
    local grow = layout.Grow
    local grid = grow == 'GRID'
    local fill = layout.GridType
    if not grid then
        local first = GROW_FILL[grow] or 'D' -- a dynamic group's default
        if first == 'R' or first == 'L' then
            fill = first .. (layout.Align == 'BOTTOM' and 'U' or 'D')
        else
            fill = first .. (layout.Align == 'RIGHT' and 'L' or 'R')
        end
    end
    local rowFirst, xSign, ySign, corner = Core:ParseGridType(fill)

    -- the container sizes itself to its auras, so a centre anchor keeps them centred
    local centred = grow == 'HORIZONTAL' or grow == 'VERTICAL'
    local alignCentre = not grid and (layout.Align or 'CENTER') == 'CENTER'
    local centreV = rowFirst and alignCentre or not rowFirst and centred
    local centreH = rowFirst and centred or not rowFirst and alignCentre
    local pointV = centreV and '' or (ySign > 0 and 'BOTTOM' or 'TOP')
    local pointH = centreH and '' or (xSign > 0 and 'LEFT' or 'RIGHT')
    local containerPoint = pointV .. pointH

    local spacing = layout.Spacing or 1
    local maximumLineSize
    if grid then
        maximumLineSize = (layout.GridWidth or 5) * ((rowFirst and width or height) + spacing)
    end

    return {
        layoutAxis = rowFirst and AnchorUtil.FlowLayoutAxis.Horizontal or AnchorUtil.FlowLayoutAxis.Vertical,
        anchorPoint = corner,
        containerPoint = containerPoint ~= '' and containerPoint or 'CENTER',
        horizontalGrowthDirection = xSign > 0 and 'RIGHT' or 'LEFT',
        verticalGrowthDirection = ySign > 0 and 'UP' or 'DOWN',
        elementSpacing = spacing,
        lineSpacing = grid and layout.RowSpacing or spacing,
        maximumLineSize = maximumLineSize,
    }
end

---How a count of buttons falls into lines, the way the native flow layout wraps them.
---@param config table a container config: size or width/height, elementSpacing, lineSpacing, maximumLineSize, layoutAxis
---@param count number most buttons that can be placed
---@return number width
---@return number height
---@return number perLine
---@return number lines
function Core:GetAuraGridSize(config, count)
    count = max(1, count)
    local width = config.width or config.size or 24
    local height = config.height or config.size or 24
    local spacing, lineSpacing = config.elementSpacing or 0, config.lineSpacing or 0
    local vertical = config.layoutAxis == AnchorUtil.FlowLayoutAxis.Vertical
    local primary, cross = width, height
    if vertical then
        primary, cross = height, width
    end

    local perLine = count
    if config.maximumLineSize then
        perLine = max(1, floor((config.maximumLineSize + spacing) / (primary + spacing)))
    end
    local lines = ceil(count / perLine)
    local along = min(perLine, count)

    local primarySize = along * primary + (along - 1) * spacing
    local crossSize = lines * cross + (lines - 1) * lineSpacing
    if vertical then
        return crossSize, primarySize, perLine, lines
    end
    return primarySize, crossSize, perLine, lines
end

---An aura group's container config; it grows like a dynamic group with the same Layout.
---@param db table
---@param style table read through its template
---@return table
function Core:GetAuraGroupConfig(db, style)
    local config = Core:ResolveAuraFlow(db.Layout, style.Width, style.Height)
    config.width, config.height = style.Width, style.Height
    -- else the layout reads each button's size, which a restyle changes after it ran
    config.elementWidth, config.elementHeight = style.Width, style.Height
    config.maxFrameCount = db.maxFrameCount
    config.sortMethod = AuraContainerSortMethod[db.sortMethod]
    config.sortDirection = AuraContainerSortDirection[db.sortDirection]
    return config
end

---Most auras an aura group can put on screen, one group per trigger.
---@param db table
---@return number
function Core:GetAuraPreviewCount(db)
    return min(db.maxFrameCount * Core:CountTriggerBranches(db.Trigger), db.previewLimit)
end
