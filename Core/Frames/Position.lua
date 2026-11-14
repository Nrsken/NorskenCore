---@class NRSKNUI
local Core = select(2, ...)

local _G = _G

---Place a frame from a module's saved position: its anchor, parent and strata.
---@param self Frame
---@param Config table the module's settings, with `Position` and optionally `anchorFrameType`, `ParentFrame`, `Strata`
---@param setParent boolean? also reparent to the anchor frame
---@param extraX number? added to the saved offset, not stored
---@param extraY number?
local function ApplyPosition(self, Config, setParent, extraX, extraY)
    local position = Config and Config.Position
    if not position then return end

    local parent = Config.anchorFrameType == 'SELECTFRAME' and Config.ParentFrame and _G[Config.ParentFrame] or UIParent
    if setParent then
        self:SetParent(parent)
    end

    self:ClearAllPoints()
    -- an odd size centred on a point lands on half pixels
    self:NCSetGridPoint(position.AnchorFrom or 'CENTER', parent, position.AnchorTo or 'CENTER', (position.XOffset or 0) + (extraX or 0), (position.YOffset or 0) + (extraY or 0))
    self:SetFrameStrata(Config.Strata or 'MEDIUM')
end

Core.FrameMethods.NCApplyPosition = ApplyPosition
