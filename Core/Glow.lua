---@class NRSKNUI
local Core = select(2, ...)

local LCG = LibStub('LibCustomGlow-1.0')

-- the runtime half of Kaji's GlowSettingsCard: its settings table in, a LibCustomGlow glow out

local procOptions = {}

---Start a glow from a GlowSettingsCard table, replacing whatever glow type the frame had under this key.
---@param frame Frame
---@param db table GlowType/GlowColor/GlowLines/GlowFrequency/GlowLength/GlowThickness/GlowBorder/GlowScale/GlowStartAnim/GlowDuration
---@param key? string
function Core:StartGlow(frame, db, key)
    Core:StopGlow(frame, key)

    local glowType = db.GlowType
    if glowType == 'autocast' then
        LCG.AutoCastGlow_Start(frame, db.GlowColor, db.GlowLines, db.GlowFrequency, db.GlowScale, 0, 0, key)
    elseif glowType == 'button' then
        LCG.ButtonGlow_Start(frame, db.GlowColor, db.GlowFrequency)
    elseif glowType == 'proc' then
        procOptions.color = db.GlowColor
        procOptions.startAnim = db.GlowStartAnim
        procOptions.duration = db.GlowDuration
        procOptions.key = key
        LCG.ProcGlow_Start(frame, procOptions)
    else
        LCG.PixelGlow_Start(frame, db.GlowColor, db.GlowLines, db.GlowFrequency, db.GlowLength, db.GlowThickness, 0, 0, db.GlowBorder, key)
    end
end

---Stop every glow type StartGlow can put on the frame under this key.
---@param frame Frame
---@param key? string
function Core:StopGlow(frame, key)
    LCG.PixelGlow_Stop(frame, key)
    LCG.AutoCastGlow_Stop(frame, key)
    LCG.ButtonGlow_Stop(frame)
    LCG.ProcGlow_Stop(frame, key)
end
