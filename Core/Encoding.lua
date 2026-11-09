---@class NRSKNUI
local Private = select(2, ...)

local pcall = pcall
local type = type

local SerializeCBOR = C_EncodingUtil.SerializeCBOR
local DeserializeCBOR = C_EncodingUtil.DeserializeCBOR
local CompressString = C_EncodingUtil.CompressString
local DecompressString = C_EncodingUtil.DecompressString
local EncodeBase64 = C_EncodingUtil.EncodeBase64
local DecodeBase64 = C_EncodingUtil.DecodeBase64

local DEFLATE = Enum.CompressionMethod.Deflate
local OPTIMIZE_SIZE = Enum.CompressionLevel.OptimizeForSize

-- the format of every Norsken export string and of Blizzard's Cooldown Manager layouts: CBOR, Deflate, Base64

---@param data table
---@return string? encoded nil when the data can't be packed
function Private:EncodeTable(data)
    local ok, encoded = pcall(function()
        return EncodeBase64(CompressString(SerializeCBOR(data), DEFLATE, OPTIMIZE_SIZE))
    end)
    if not ok then return nil end

    return encoded
end

---@param text string without any prefix
---@return table? data nil when the text isn't a packed table
function Private:DecodeTable(text)
    -- untrusted pasted text and these natives raise rather than return nil
    local ok, data = pcall(function()
        local compressed = DecodeBase64(text)
        local serialized = compressed and DecompressString(compressed, DEFLATE)
        return serialized and DeserializeCBOR(serialized)
    end)

    -- a crafted string can deserialize cleanly into a scalar
    if not ok or type(data) ~= 'table' then return nil end

    return data
end
