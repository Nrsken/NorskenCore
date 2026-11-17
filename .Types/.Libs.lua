---@meta

---@class NorskenCore.Libraries
---@field LSM LibSharedMedia-3.0
---@field LS LibSpecialization

-- LibCustomGlow-1.0 --

---@alias NorskenCore.GlowColor number[]|{ GetRGBA: fun(self: table): number, number, number, number }

---@class NorskenCore.LibCustomGlowProcOptions
---@field frameLevel? integer
---@field color? NorskenCore.GlowColor
---@field startAnim? boolean
---@field xOffset? number
---@field yOffset? number
---@field duration? number
---@field key? string

---@class LibCustomGlow-1.0
---@field glowList string[]
---@field startList table<string, fun(frame: Frame, ...: any)>
---@field stopList table<string, fun(frame: Frame, ...: any)>
---@field GlowTexPool table
---@field GlowFramePool table
---@field ButtonGlowPool table
---@field ProcGlowPool table
---@field RegisterTextures fun(texture: string, id: string)
---@field PixelGlow_Start fun(frame: Frame, color?: NorskenCore.GlowColor, N?: integer, frequency?: number, length?: number, th?: number, xOffset?: number, yOffset?: number, border?: boolean, key?: string, frameLevel?: integer)
---@field PixelGlow_Stop fun(frame: Frame, key?: string): boolean|nil
---@field AutoCastGlow_Start fun(frame: Frame, color?: NorskenCore.GlowColor, N?: integer, frequency?: number, scale?: number, xOffset?: number, yOffset?: number, key?: string, frameLevel?: integer)
---@field AutoCastGlow_Stop fun(frame: Frame, key?: string): boolean|nil
---@field ButtonGlow_Start fun(frame: Frame, color?: NorskenCore.GlowColor, frequency?: number, frameLevel?: integer)
---@field ButtonGlow_Stop fun(frame: Frame)
---@field ProcGlow_Start fun(frame: Frame, options?: NorskenCore.LibCustomGlowProcOptions)
---@field ProcGlow_Stop fun(frame: Frame, key?: string)

-- LibSpecialization --

---@alias LibSpecializationRole "TANK"|"HEALER"|"DAMAGER"
---@alias LibSpecializationPosition "MELEE"|"RANGED"
---@alias LibSpecializationCallback fun(specId: integer, role: LibSpecializationRole, position: LibSpecializationPosition, playerName: string, talents: string|nil)

---@class LibSpecialization
---@field callbackMapGroup table<table, LibSpecializationCallback>
---@field callbackMapGuild table<table, LibSpecializationCallback>
---@field callbackMapPlayerSpecChange table<table, fun()>
---@field frame Frame
---@field RegisterGroup fun(addon: table, callback: LibSpecializationCallback)
---@field UnregisterGroup fun(addon: table)
---@field RegisterGuild fun(addon: table, callback: LibSpecializationCallback)
---@field UnregisterGuild fun(addon: table)
---@field RegisterPlayerSpecChange fun(addon: table, callback: fun())
---@field UnregisterPlayerSpecChange fun(addon: table)
---@field MySpecialization fun(): integer|nil, LibSpecializationRole|nil, LibSpecializationPosition|nil, string|nil
---@field RequestGroupSpecialization fun()
---@field RequestGuildSpecialization fun()
