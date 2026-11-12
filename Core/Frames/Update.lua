---@class NRSKNUI
local Core = select(2, ...)

-- Throttled --

---Run callback at most once per `throttle` seconds; no arguments clears OnUpdate.
---@param frame Frame
---@param throttle? number
---@param callback? fun(frame: Frame)
local function ApplyOnUpdate(frame, throttle, callback)
    if not (throttle and callback) then
        frame:SetScript('OnUpdate', nil)
        return
    end

    local total = 0
    frame:SetScript('OnUpdate', function(_, elapsed)
        total = total + elapsed
        if total > throttle then
            total = 0
            callback(frame)
        end
    end)
end

-- Coalesced one-shot --

-- Blizzard's dirty pattern: arms before the next frame run the handler once, then it disarms
local RunOnce = Enum.OnUpdateMode.RunOnce
local RunWhenVisibleOnce = Enum.OnUpdateMode.RunWhenVisibleOnce
local OnUpdateDisabled = Enum.OnUpdateMode.Disabled

local function RunScheduledUpdate(frame)
    local callback = frame._scheduledUpdate
    if callback then
        callback(frame)
    end
end

---A one-shot handler for ScheduleUpdate to arm. Replaces the frame's OnUpdate script.
---@param frame Frame
---@param callback fun(frame: Frame)
---@param whenVisible? boolean only run while the frame is shown
local function SetScheduledUpdate(frame, callback, whenVisible)
    frame._scheduledUpdate = callback
    frame._scheduledMode = whenVisible and RunWhenVisibleOnce or RunOnce
    frame:SetScript('OnUpdate', RunScheduledUpdate)
    frame:SetOnUpdateMode(OnUpdateDisabled)
end

---Run the SetScheduledUpdate handler once next frame; repeated calls coalesce.
---@param frame Frame
local function ScheduleUpdate(frame)
    if frame._scheduledMode then
        frame:SetOnUpdateMode(frame._scheduledMode)
    end
end

local methods = Core.FrameMethods
methods.NCApplyOnUpdate = ApplyOnUpdate
methods.NCSetScheduledUpdate = SetScheduledUpdate
methods.NCScheduleUpdate = ScheduleUpdate
