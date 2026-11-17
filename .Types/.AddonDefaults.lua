---@meta

---What NorskenCoreDB holds, read with GetSharedSettings
---@class NorskenCore.SharedSettings
---@field Adopted boolean?
---@field Language string 'auto' or a locale from NRSKNUI.LANGUAGES
---@field Colors NorskenCore.Colors
---@field globalMedia NorskenCore.GlobalMedia

---@class NorskenCore.Colors
---@field [string] any
---@field Class NorskenCore.Colors.Class
---@field Dispel NorskenCore.Colors.Dispel
---@field Power NorskenCore.Colors.Power
---@field Reaction NorskenCore.Colors.Reaction
---@field Runes NorskenCore.Colors.Runes
---@field Stagger NorskenCore.Colors.Stagger
---@field Status NorskenCore.Colors.Status

---@class NorskenCore.Colors.Class
---@field [string] any
---@field DEATHKNIGHT table
---@field DEMONHUNTER table
---@field DRUID table
---@field EVOKER table
---@field HUNTER table
---@field MAGE table
---@field MONK table
---@field PALADIN table
---@field PRIEST table
---@field ROGUE table
---@field SHAMAN table
---@field WARLOCK table
---@field WARRIOR table

---@class NorskenCore.Colors.Dispel
---@field [string] any
---@field Bleed table
---@field Curse table
---@field Disease table
---@field Enrage table
---@field Magic table
---@field None table
---@field Poison table

---@class NorskenCore.Colors.Power
---@field [string] any
---@field [number] any

---@class NorskenCore.Colors.Reaction
---@field [string] any
---@field [number] any

---@class NorskenCore.Colors.Runes
---@field [string] any
---@field [number] any

---@class NorskenCore.Colors.Stagger
---@field [string] any
---@field [number] any

---@class NorskenCore.Colors.Status
---@field [string] any
---@field Dead table
---@field Disconnected table
---@field Tapped table

---@class NorskenCore.GlobalMedia
---@field [string] any
---@field Enabled boolean
---@field blizzardFonts NorskenCore.GlobalMedia.blizzardFonts
---@field durationBreakpointColors boolean
---@field durationCurveColors boolean
---@field durationSingleColor boolean
---@field durationSingleColorValue table
---@field profileBar NorskenCore.GlobalMedia.profileBar
---@field profileBorder NorskenCore.GlobalMedia.profileBorder
---@field profileBreakPoints NorskenCore.GlobalMedia.profileBreakPoints
---@field profileColorBreakPoint NorskenCore.GlobalMedia.profileColorBreakPoint
---@field profileColorCurve NorskenCore.GlobalMedia.profileColorCurve
---@field profileFont NorskenCore.GlobalMedia.profileFont
---@field profileSpark NorskenCore.GlobalMedia.profileSpark

---@class NorskenCore.GlobalMedia.blizzardFonts
---@field [string] any
---@field Enabled boolean
---@field Families NorskenCore.GlobalMedia.blizzardFonts.Families
---@field HideShadow boolean
---@field Outline string
---@field Overrides NorskenCore.GlobalMedia.blizzardFonts.Overrides
---@field Slug boolean
---@field Specials NorskenCore.GlobalMedia.blizzardFonts.Specials

---@class NorskenCore.GlobalMedia.blizzardFonts.Families
---@field [string] any

---@class NorskenCore.GlobalMedia.blizzardFonts.Overrides
---@field [string] any

---@class NorskenCore.GlobalMedia.blizzardFonts.Specials
---@field [string] any
---@field ActionStatus NorskenCore.GlobalMedia.blizzardFonts.Specials.ActionStatus
---@field ChatBubbles NorskenCore.GlobalMedia.blizzardFonts.Specials.ChatBubbles
---@field CombatFont NorskenCore.GlobalMedia.blizzardFonts.Specials.CombatFont
---@field CombatText NorskenCore.GlobalMedia.blizzardFonts.Specials.CombatText
---@field ErrorText NorskenCore.GlobalMedia.blizzardFonts.Specials.ErrorText
---@field NameFont NorskenCore.GlobalMedia.blizzardFonts.Specials.NameFont
---@field Nameplates NorskenCore.GlobalMedia.blizzardFonts.Specials.Nameplates
---@field PvPZoneText NorskenCore.GlobalMedia.blizzardFonts.Specials.PvPZoneText
---@field SubZoneText NorskenCore.GlobalMedia.blizzardFonts.Specials.SubZoneText
---@field ZoneText NorskenCore.GlobalMedia.blizzardFonts.Specials.ZoneText

---@class NorskenCore.GlobalMedia.blizzardFonts.Specials.ActionStatus
---@field [string] any
---@field Enabled boolean
---@field Hide boolean
---@field Position NorskenCore.GlobalMedia.blizzardFonts.Specials.ActionStatus.Position
---@field Size number

---@class NorskenCore.GlobalMedia.blizzardFonts.Specials.ActionStatus.Position
---@field [string] any
---@field Anchor string
---@field X number
---@field Y number

---@class NorskenCore.GlobalMedia.blizzardFonts.Specials.ChatBubbles
---@field [string] any
---@field Enabled boolean
---@field Size number

---@class NorskenCore.GlobalMedia.blizzardFonts.Specials.CombatFont
---@field [string] any
---@field Enabled boolean

---@class NorskenCore.GlobalMedia.blizzardFonts.Specials.CombatText
---@field [string] any
---@field Enabled boolean

---@class NorskenCore.GlobalMedia.blizzardFonts.Specials.ErrorText
---@field [string] any
---@field Enabled boolean
---@field Hide boolean
---@field Position NorskenCore.GlobalMedia.blizzardFonts.Specials.ErrorText.Position
---@field Size number

---@class NorskenCore.GlobalMedia.blizzardFonts.Specials.ErrorText.Position
---@field [string] any
---@field Anchor string
---@field X number
---@field Y number

---@class NorskenCore.GlobalMedia.blizzardFonts.Specials.NameFont
---@field [string] any
---@field Enabled boolean

---@class NorskenCore.GlobalMedia.blizzardFonts.Specials.Nameplates
---@field [string] any
---@field Enabled boolean

---@class NorskenCore.GlobalMedia.blizzardFonts.Specials.PvPZoneText
---@field [string] any
---@field Enabled boolean
---@field Size number

---@class NorskenCore.GlobalMedia.blizzardFonts.Specials.SubZoneText
---@field [string] any
---@field Enabled boolean
---@field Size number

---@class NorskenCore.GlobalMedia.blizzardFonts.Specials.ZoneText
---@field [string] any
---@field Enabled boolean
---@field Hide boolean
---@field Position NorskenCore.GlobalMedia.blizzardFonts.Specials.ZoneText.Position
---@field Size number

---@class NorskenCore.GlobalMedia.blizzardFonts.Specials.ZoneText.Position
---@field [string] any
---@field Anchor string
---@field X number
---@field Y number

---@class NorskenCore.GlobalMedia.profileBar
---@field [string] any
---@field statusBar string

---@class NorskenCore.GlobalMedia.profileBorder
---@field [string] any
---@field BackdropColor table
---@field BorderColor table

---@class NorskenCore.GlobalMedia.profileBreakPoints
---@field [string] any
---@field pointFive NorskenCore.GlobalMedia.profileBreakPoints.pointFive
---@field pointFour NorskenCore.GlobalMedia.profileBreakPoints.pointFour
---@field pointOne NorskenCore.GlobalMedia.profileBreakPoints.pointOne
---@field pointSix NorskenCore.GlobalMedia.profileBreakPoints.pointSix
---@field pointThree NorskenCore.GlobalMedia.profileBreakPoints.pointThree
---@field pointTwo NorskenCore.GlobalMedia.profileBreakPoints.pointTwo

---@class NorskenCore.GlobalMedia.profileBreakPoints.pointFive
---@field [string] any
---@field format string
---@field threshold number

---@class NorskenCore.GlobalMedia.profileBreakPoints.pointFour
---@field [string] any
---@field format string
---@field threshold number

---@class NorskenCore.GlobalMedia.profileBreakPoints.pointOne
---@field [string] any
---@field format string
---@field step number
---@field threshold number

---@class NorskenCore.GlobalMedia.profileBreakPoints.pointSix
---@field [string] any
---@field format string
---@field threshold number

---@class NorskenCore.GlobalMedia.profileBreakPoints.pointThree
---@field [string] any
---@field format string
---@field threshold number

---@class NorskenCore.GlobalMedia.profileBreakPoints.pointTwo
---@field [string] any
---@field format string
---@field step number
---@field threshold number

---@class NorskenCore.GlobalMedia.profileColorBreakPoint
---@field [string] any
---@field colorFive table
---@field colorFour table
---@field colorOne table
---@field colorSix table
---@field colorThree table
---@field colorTwo table

---@class NorskenCore.GlobalMedia.profileColorCurve
---@field [string] any
---@field colorFive table
---@field colorFour table
---@field colorOne table
---@field colorSix table
---@field colorThree table
---@field colorTwo table

---@class NorskenCore.GlobalMedia.profileFont
---@field [string] any
---@field Enabled boolean
---@field FontFace string

---@class NorskenCore.GlobalMedia.profileSpark
---@field [string] any
---@field Scale number
---@field Width number
---@field color table
---@field sparkTexture string
