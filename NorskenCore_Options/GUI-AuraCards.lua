---@class NorskenCore
local Core = _G.NorskenCore
---@class NorskenCore.GUIAuraCards
local AuraCards = {}
Core.GUIAuraCards = AuraCards
local L = Core.L
local Theme = Core.Kaji.DEFAULT_THEME
local rowH = Theme.rowHeight
local rowHL = Theme.rowHeightLast
local Apply = Core.Enum.Apply

local ipairs = ipairs

Core.AnchorOptions = {
    { value = 'TOPLEFT',     text = L['Top Left'] },
    { value = 'TOP',         text = L['Top'] },
    { value = 'TOPRIGHT',    text = L['Top Right'] },
    { value = 'LEFT',        text = L['Left'] },
    { value = 'CENTER',      text = L['Center'] },
    { value = 'RIGHT',       text = L['Right'] },
    { value = 'BOTTOMLEFT',  text = L['Bottom Left'] },
    { value = 'BOTTOM',      text = L['Bottom'] },
    { value = 'BOTTOMRIGHT', text = L['Bottom Right'] },
}

AuraCards.SortMethods = {
    { value = 'ExpirationOnly',     text = L['Expiration Only'] },
    { value = 'Expiration',         text = L['Expiration'] },
    { value = 'Default',            text = L['Default'] },
    { value = 'ImportantOnly',      text = L['Important Only'] },
    { value = 'BigDefensive',       text = L['Big Defensive'] },
    { value = 'UnitFrameDebuff',    text = L['Unit Frame Debuff'] },
    { value = 'Name',               text = L['Name'] },
    { value = 'NameOnly',           text = L['Name Only'] },
    { value = 'AuraInstanceIDOnly', text = L['Aura Instance ID'] },
}

AuraCards.SortDirections = {
    { value = 'Normal',  text = L['Normal'] },
    { value = 'Reverse', text = L['Reverse'] },
}

---Anchor and offsets for a button's strings, one row each.
---@param page KajiGUIPage
---@param db table
---@param ctx table { Apply: fun(part: NorskenCore.Apply), slots: table[] } `{ key, anchor, x, y }` per string: its db key and labels
---@return KajiGUIFluentCard
function AuraCards:TextPosition(page, db, ctx)
    local Update = ctx.Apply
    local slots = ctx.slots

    local card = page:Card(L['Text Position'], 'all')
    for index, slot in ipairs(slots) do
        local last = index == #slots
        local position = db[slot.key].Position
        local row = card:Row(last and rowHL or rowH, last and 0 or nil)

        row:Dropdown(slot.anchor, {
            width = 0.4,
            options = Core.AnchorOptions,
            value = position.AnchorFrom,
            callback = function(key)
                position.AnchorFrom = key
                Update(Apply.Position)
            end,
        })
        row:Slider(slot.x, {
            width = 0.3,
            min = -40,
            max = 40,
            step = 1,
            value = position.XOffset,
            callback = function(val)
                position.XOffset = val
                Update(Apply.Position)
            end,
        })
        row:Slider(slot.y, {
            width = 0.3,
            min = -40,
            max = 40,
            step = 1,
            value = position.YOffset,
            callback = function(val)
                position.YOffset = val
                Update(Apply.Position)
            end,
        })
    end

    return card
end
