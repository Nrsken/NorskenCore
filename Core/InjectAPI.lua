---@class NRSKNUI
local Core = select(2, ...)

local pairs = pairs
local type = type
local getmetatable = getmetatable
local CreateFrame = CreateFrame
local EnumerateFrames = EnumerateFrames

---Add methods to an object's widget type via its metatable; names it has are kept.
---@param object table any widget of the type
---@param methods table<string, function>
function Core:InjectAPI(object, methods)
    if not object or type(methods) ~= 'table' then return end

    local mt = getmetatable(object)
    local index = mt and mt.__index
    if type(index) ~= 'table' then return end

    for name, fn in pairs(methods) do
        if index[name] == nil then
            index[name] = fn
        end
    end
end

-- Inject --

-- onto every widget type with an instance by now
do
    local methods = Core.FrameMethods
    local object = CreateFrame('Frame')
    Core:InjectAPI(object, methods)
    Core:InjectAPI(object:CreateTexture(), methods)
    Core:InjectAPI(object:CreateMaskTexture(), methods)
    Core:InjectAPI(object:CreateLine(), methods)
    Core:InjectAPI(object:CreateFontString(), methods)

    local injected = { Frame = true }
    object = EnumerateFrames()
    while object do
        local objectType = object:GetObjectType()
        if not object:IsForbidden() and not injected[objectType] then
            Core:InjectAPI(object, methods)
            injected[objectType] = true
        end
        object = EnumerateFrames(object)
    end

    -- no ScrollFrame exists this early
    Core:InjectAPI(CreateFrame('ScrollFrame'), methods)
end
