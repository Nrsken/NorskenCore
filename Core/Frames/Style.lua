---@class NRSKNUI
local Core = select(2, ...)

local type = type
local select = select
local ipairs = ipairs

local _G = _G

-- Icons --

---Crop an icon's edges, by `Core.GlobalZoom` unless given a zoom.
---@param object Texture
---@param zoom number?
local function SetZoom(object, zoom)
    local crop = 0.25 * (zoom or Core.GlobalZoom)
    object:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
end

-- Buttons --

-- flat additive overlays for Blizzard's state art, re-appliable as templates re-drive it
local BUTTON_STATES = {
    { field = 'hover',   set = 'SetHighlightTexture', get = 'GetHighlightTexture', r = 1,   g = 1,   b = 1,   a = 0.3 },
    { field = 'pushed',  set = 'SetPushedTexture',    get = 'GetPushedTexture',    r = 0.4, g = 0.4, b = 0.4, a = 0.3 },
    { field = 'checked', set = 'SetCheckedTexture',   get = 'GetCheckedTexture',   r = 1,   g = 1,   b = 1,   a = 0.3 },
}

---@param button Button
---@param noHover boolean?
---@param noPushed boolean?
---@param noChecked boolean?
local function StyleButton(button, noHover, noPushed, noChecked)
    if not button.CreateTexture then return end

    local skip = { hover = noHover, pushed = noPushed, checked = noChecked }
    for _, state in ipairs(BUTTON_STATES) do
        if button[state.set] and not skip[state.field] then
            button[state.set](button, Core.ClearTexture)

            local texture = button[state.get](button)
            texture:NCSetInside()
            texture:SetBlendMode('ADD')
            texture:SetColorTexture(state.r, state.g, state.b, state.a)
            button[state.field] = texture
        end
    end
end

-- Font strings --

---Style every FontString in a frame's child frames, at a size the caller picks per string.
---@param frame Frame|string
---@param source table
---@param getSize fun(fontString: FontString, parent: Frame): number? nil uses `source.FontSize`
local function StyleChildFontStrings(frame, source, getSize, outline, shadow, skip, setOwner)
    if type(frame) == 'string' then
        frame = _G[frame]
    end

    for i = 1, frame:GetNumChildren() do
        local child = select(i, frame:GetChildren())
        for j = 1, child:GetNumRegions() do
            local region = select(j, child:GetRegions())
            if region:IsObjectType('FontString') then
                local size = getSize and getSize(region, child) or source.FontSize
                region:SetFontStyle(source, size, outline, shadow, skip, setOwner)
            end
        end
    end
end

local methods = Core.FrameMethods
methods.NCSetZoom = SetZoom
methods.NCStyleButton = StyleButton
methods.NCStyleChildFontStrings = StyleChildFontStrings
