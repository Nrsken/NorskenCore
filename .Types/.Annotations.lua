---@meta

-- LibStub keeps its registries on the table itself, which the bundled stub leaves out.
---@class LibStub
---@field libs table<string, table>
---@field minors table<string, number>

-- Dynamic groups (see Core/DynamicGroup.lua; methods are documented at their definitions)

---A grow-type entry for NRSKNUI:RegisterDynamicGroupGrower. The factory closes over a
---config and returns the layout closure; the layout fills positions[record] = { x, y }
---(raw offsets from the resolved anchor point) for the first numVisible records and
---returns the content extents totalW, totalH.
---@class NorskenCore.DynamicGroupGrower
---@field point string|fun(config: NorskenCore.DynamicGroupConfig): string anchor point used for every control point
---@field factory fun(config: NorskenCore.DynamicGroupConfig): fun(positions: table<NorskenCore.DynamicGroupChildRecord, number[]>, active: NorskenCore.DynamicGroupChildRecord[], numVisible: number): number, number

---@class NorskenCore.DynamicGroupConfig
---@field Grow? string "LEFT"|"RIGHT"|"UP"|"DOWN"|"HORIZONTAL"|"VERTICAL"|"GRID" (default "DOWN")
---@field Align? string cross-axis alignment: vertical grows "LEFT"|"CENTER"|"RIGHT", horizontal grows "TOP"|"CENTER"|"BOTTOM" (default "CENTER")
---@field Spacing? number main-axis gap (default 1)
---@field RowSpacing? number GRID cross-axis gap (defaults to Spacing)
---@field GridType? string GRID fill: "RD","RU","LD","LU","DR","DL","UR","UL" (default "RD")
---@field GridWidth? number children per run before wrapping (default 5)
---@field UseLimit? boolean cap the number of visible children
---@field Limit? number max visible when UseLimit (default 5)
---@field MinWidth? number container minimum width (default 1)
---@field MinHeight? number container minimum height (default 1)
---@field Comparator? fun(a: NorskenCore.DynamicGroupChildRecord, b: NorskenCore.DynamicGroupChildRecord): boolean? custom sort, ties fall through to order/index

---@class NorskenCore.DynamicGroupChildRecord
---@field child Frame
---@field key string|false
---@field order number sort priority (default = attach sequence)
---@field index number attach sequence, stable tiebreak
---@field width number declared width
---@field height number declared height
---@field controlPoint Frame
---@field active boolean

---@class NorskenCore.DynamicGroup : Frame
---@field _config NorskenCore.DynamicGroupConfig
---@field _growFunc fun(positions: table<NorskenCore.DynamicGroupChildRecord, number[]>, active: NorskenCore.DynamicGroupChildRecord[], numVisible: number): number, number
---@field _growPoint string
---@field _children NorskenCore.DynamicGroupChildRecord[]
---@field _byKey table<string, NorskenCore.DynamicGroupChildRecord>
---@field _byChild table<Frame, NorskenCore.DynamicGroupChildRecord>
---@field _active NorskenCore.DynamicGroupChildRecord[]
---@field _positions table
---@field _pool ObjectPool
---@field _comparator? fun(a: NorskenCore.DynamicGroupChildRecord, b: NorskenCore.DynamicGroupChildRecord): boolean
---@field _suspend number
---@field _counter number
---@field _needSort boolean
---@field _needPosition boolean
---@field _contentW number
---@field _contentH number

---@class NorskenCore.AnchorOverlay : Frame
---@field entry table the registry entry this overlay tracks
---@field text FontString
---@field isHovered boolean
---@field didDrag boolean
---@field animateBorder fun(r: number, g: number, b: number, a?: number)
---@field fadeTo fun(alpha: number)
