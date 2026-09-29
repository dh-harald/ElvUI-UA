-- ElvUI.ProfileCodec: the "!E2!" profile export string of current ElvUI
-- (retail Distributor.lua, `D:GetProfileExport` / `D:Decode`):
--
--   "!E2!" .. Base64( Deflate( CBOR(data) .. "::" .. type [.. "::" .. key] ) )
--
-- `type` is profile / private / global / filters; only `profile` carries a
-- key (the profile name). Retail builds it with the client's
-- C_EncodingUtil (SerializeCBOR, CompressString with the Deflate method,
-- EncodeBase64). Neither 1.12.1 nor Unreal Azeroth has that API, so the
-- three layers are pure Lua here: Base64 and CBOR in this file, DEFLATE from
-- LibDeflate (Ace3v port).
--
-- It also reads ElvUI-vanilla's "text" export (see the last section).
--
-- No WoW API is used, so the file also loads in a plain Lua 5.0 interpreter
-- for offline tests; it needs only ElvUI.Compat and, for the compression
-- step, LibStub("LibDeflate") (for the vanilla format, "AceSerializer-3.0").

ElvUI = ElvUI or {}
ElvUI.ProfileCodec = ElvUI.ProfileCodec or {}

local Codec = ElvUI.ProfileCodec
local Compat = ElvUI.Compat

local mod = Compat.mod
local floor, frexp, ldexp = math.floor, math.frexp, math.ldexp
local strbyte, strchar, strsub, strlen, strfind = string.byte, string.char, string.sub, string.len, string.find
local tconcat, tsort = table.concat, table.sort

Codec.PREFIX = "!E2!"
Codec.OLD_PREFIX = "!E1!"

Codec.TYPES = { profile = true, private = true, global = true, filters = true }

-- Powers of two as literals: `^` goes through the math library on Lua 5.0.
local TWO_20 = 1048576
local TWO_23 = 8388608
local TWO_31 = 2147483648
local TWO_32 = 4294967296
local TWO_52 = 4503599627370496
local TWO_53 = 9007199254740992

local INF = 1 / 0

-- One-character strings for every byte value, so hot loops index a table
-- instead of calling string.char.
local BYTE = {}
do
	local i
	for i = 0, 255 do BYTE[i] = strchar(i) end
end

-- ---------------------------------------------------------------------
-- Base64 (RFC 4648)
-- ---------------------------------------------------------------------

local B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_CHAR = {}
local B64_VALUE = {}
do
	local i
	for i = 0, 63 do
		local c = strsub(B64_ALPHABET, i + 1, i + 1)
		B64_CHAR[i] = c
		B64_VALUE[strbyte(c)] = i
	end
	-- The URL-safe alphabet decodes too.
	B64_VALUE[strbyte("-")] = 62
	B64_VALUE[strbyte("_")] = 63
end

-- Bytes skipped by the decoder: line breaks and spaces a paste may add.
local B64_SKIP = { [9] = true, [10] = true, [13] = true, [32] = true }

-- Standard alphabet with "=" padding.
function Codec.EncodeBase64(data)
	local len = strlen(data)
	local parts, n = {}, 0
	local i = 1
	while i + 2 <= len do
		local v = strbyte(data, i) * 65536 + strbyte(data, i + 1) * 256 + strbyte(data, i + 2)
		n = n + 1
		parts[n] = B64_CHAR[floor(v / 262144)] .. B64_CHAR[mod(floor(v / 4096), 64)]
			.. B64_CHAR[mod(floor(v / 64), 64)] .. B64_CHAR[mod(v, 64)]
		i = i + 3
	end
	local rest = len - i + 1
	if rest == 1 then
		local v = strbyte(data, i) * 65536
		n = n + 1
		parts[n] = B64_CHAR[floor(v / 262144)] .. B64_CHAR[mod(floor(v / 4096), 64)] .. "=="
	elseif rest == 2 then
		local v = strbyte(data, i) * 65536 + strbyte(data, i + 1) * 256
		n = n + 1
		parts[n] = B64_CHAR[floor(v / 262144)] .. B64_CHAR[mod(floor(v / 4096), 64)]
			.. B64_CHAR[mod(floor(v / 64), 64)] .. "="
	end
	return tconcat(parts)
end

-- Accepts both alphabets, ignores whitespace, and does not require the
-- padding. Returns nil on any other character or on a dangling sextet.
function Codec.DecodeBase64(text)
	local len = strlen(text)
	local parts, n = {}, 0
	local acc, count = 0, 0
	local i
	for i = 1, len do
		local b = strbyte(text, i)
		if b == 61 then -- "=": padding ends the data
			break
		end
		if not B64_SKIP[b] then
			local v = B64_VALUE[b]
			if not v then return nil end
			acc = acc * 64 + v
			count = count + 1
			if count == 4 then
				n = n + 1
				parts[n] = BYTE[floor(acc / 65536)] .. BYTE[mod(floor(acc / 256), 256)] .. BYTE[mod(acc, 256)]
				acc, count = 0, 0
			end
		end
	end
	if count == 1 then
		return nil
	elseif count == 2 then
		n = n + 1
		parts[n] = BYTE[floor(acc / 16)]
	elseif count == 3 then
		n = n + 1
		parts[n] = BYTE[floor(acc / 1024)] .. BYTE[mod(floor(acc / 4), 256)]
	end
	return tconcat(parts)
end

-- ---------------------------------------------------------------------
-- CBOR (RFC 8949)
-- ---------------------------------------------------------------------
--
-- Encoder: a table whose keys are exactly 1..n becomes an array, any other
-- table a map with its keys sorted (numbers first, then strings), so the
-- same data always encodes to the same bytes. Integral numbers within
-- +-2^53 become integers, every other number a float64. Strings are text
-- strings. Values of other types (functions, userdata) are left out.
--
-- Decoder: every major type, definite and indefinite lengths, tags (the
-- tagged item is returned untagged), half/single/double floats. null,
-- undefined and other simple values decode to nil, so a map entry holding
-- one is dropped. A map key that is not a string, number or boolean drops
-- the entry.

local MAX_DEPTH = 100

-- Big-endian bytes of an unsigned integer below 2^32.
local function UInt32(v)
	return BYTE[floor(v / 16777216)] .. BYTE[mod(floor(v / 65536), 256)]
		.. BYTE[mod(floor(v / 256), 256)] .. BYTE[mod(v, 256)]
end

-- Initial byte plus argument, in the shortest form (RFC 8949 4.2.1).
local function Head(major, value)
	local mt = major * 32
	if value < 24 then
		return BYTE[mt + value]
	elseif value < 256 then
		return BYTE[mt + 24] .. BYTE[value]
	elseif value < 65536 then
		return BYTE[mt + 25] .. BYTE[floor(value / 256)] .. BYTE[mod(value, 256)]
	elseif value < TWO_32 then
		return BYTE[mt + 26] .. UInt32(value)
	end
	local hi = floor(value / TWO_32)
	return BYTE[mt + 27] .. UInt32(hi) .. UInt32(value - hi * TWO_32)
end

-- IEEE 754 binary64, built from math.frexp (no string.pack on Lua 5.0/5.1).
local function Float64(v)
	if v ~= v then
		return "\251\127\248\000\000\000\000\000\000"
	end
	local sign = 0
	if v < 0 or (v == 0 and 1 / v < 0) then
		sign = TWO_31
		v = -v
	end
	local exponent, fraction
	if v == INF then
		exponent, fraction = 2047, 0
	elseif v == 0 then
		exponent, fraction = 0, 0
	else
		local m, e = frexp(v) -- v = m * 2^e, 0.5 <= m < 1
		exponent = e + 1022
		if exponent <= 0 then
			-- Subnormal: the fraction counts units of 2^-1074.
			exponent, fraction = 0, ldexp(v, 1074)
		else
			fraction = ldexp(m * 2 - 1, 52)
		end
	end
	local fracHi = floor(fraction / TWO_32)
	return "\251" .. UInt32(sign + exponent * TWO_20 + fracHi) .. UInt32(fraction - fracHi * TWO_32)
end

local function KeyLess(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then
		if ta == "number" then return true end
		if tb == "number" then return false end
		return ta < tb
	end
	if ta == "number" or ta == "string" then
		return a < b
	end
	return tostring(a) < tostring(b)
end

local ENCODABLE = { number = true, string = true, boolean = true, table = true }

local EncodeValue

local function EncodeTable(t, parts, depth)
	if depth > MAX_DEPTH then
		error("CBOR: table nesting too deep")
	end

	local keys, count = {}, 0
	local isArray = true
	local k, v
	for k, v in pairs(t) do
		if ENCODABLE[type(v)] and ENCODABLE[type(k)] and type(k) ~= "table" then
			count = count + 1
			keys[count] = k
			if type(k) ~= "number" or k < 1 or k ~= floor(k) then
				isArray = false
			end
		else
			isArray = false
		end
	end
	if isArray then
		local i
		for i = 1, count do
			if t[i] == nil then
				isArray = false
				break
			end
		end
	end

	if isArray and count > 0 then
		parts.n = parts.n + 1
		parts[parts.n] = Head(4, count)
		local i
		for i = 1, count do
			EncodeValue(t[i], parts, depth + 1)
		end
		return
	end

	tsort(keys, KeyLess)
	parts.n = parts.n + 1
	parts[parts.n] = Head(5, count)
	local i
	for i = 1, count do
		EncodeValue(keys[i], parts, depth + 1)
		EncodeValue(t[keys[i]], parts, depth + 1)
	end
end

EncodeValue = function(v, parts, depth)
	local tv = type(v)
	if tv == "table" then
		EncodeTable(v, parts, depth)
		return
	end

	local out
	if tv == "string" then
		out = Head(3, strlen(v)) .. v
	elseif tv == "boolean" then
		out = v and "\245" or "\244"
	elseif tv == "number" then
		-- -0 is integral but has no integer form; it goes out as a float.
		if v == floor(v) and v < TWO_53 and v > -TWO_53 and not (v == 0 and 1 / v < 0) then
			if v >= 0 then
				out = Head(0, v)
			else
				out = Head(1, -1 - v)
			end
		else
			out = Float64(v)
		end
	else
		error("CBOR: cannot encode a " .. tv)
	end
	parts.n = parts.n + 1
	parts[parts.n] = out
end

-- Returns the CBOR encoding of `value` (a table, string, number or boolean).
function Codec.EncodeCBOR(value)
	local parts = { n = 0 }
	EncodeValue(value, parts, 0)
	parts.n = nil
	return tconcat(parts)
end

-- Decoder state lives in upvalues for the duration of one DecodeCBOR call.
local src, srcLen

local function Need(pos, count)
	if pos + count - 1 > srcLen then
		error("CBOR: truncated data")
	end
end

local function ReadUInt(pos, size)
	Need(pos, size)
	local v, i = 0, 0
	for i = 0, size - 1 do
		v = v * 256 + strbyte(src, pos + i)
	end
	return v, pos + size
end

local function Half(bits)
	local sign = bits >= 32768 and -1 or 1
	local exponent = mod(floor(bits / 1024), 32)
	local fraction = mod(bits, 1024)
	if exponent == 0 then
		return sign * ldexp(fraction, -24)
	elseif exponent == 31 then
		if fraction == 0 then return sign * INF end
		return 0 / 0
	end
	return sign * ldexp(fraction + 1024, exponent - 25)
end

local function Single(bits)
	local sign = bits >= TWO_31 and -1 or 1
	local exponent = mod(floor(bits / TWO_23), 256)
	local fraction = mod(bits, TWO_23)
	if exponent == 0 then
		return sign * ldexp(fraction, -149)
	elseif exponent == 255 then
		if fraction == 0 then return sign * INF end
		return 0 / 0
	end
	return sign * ldexp(fraction + TWO_23, exponent - 150)
end

local function Double(hi, lo)
	local sign = hi >= TWO_31 and -1 or 1
	local exponent = mod(floor(hi / TWO_20), 2048)
	local fraction = mod(hi, TWO_20) * TWO_32 + lo
	if exponent == 0 then
		return sign * ldexp(fraction, -1074)
	elseif exponent == 2047 then
		if fraction == 0 then return sign * INF end
		return 0 / 0
	end
	return sign * ldexp(fraction + TWO_52, exponent - 1075)
end

local BREAK = {}

local DecodeItem

-- The argument of an initial byte: its value, or nil for an indefinite
-- length (additional info 31).
local function Argument(info, pos)
	if info < 24 then
		return info, pos
	elseif info == 24 then
		return ReadUInt(pos, 1)
	elseif info == 25 then
		return ReadUInt(pos, 2)
	elseif info == 26 then
		return ReadUInt(pos, 4)
	elseif info == 27 then
		local hi, lo
		hi, pos = ReadUInt(pos, 4)
		lo, pos = ReadUInt(pos, 4)
		return hi * TWO_32 + lo, pos
	elseif info == 31 then
		return nil, pos
	end
	error("CBOR: reserved additional info " .. info)
end

local function DecodeString(major, value, pos, depth)
	if value then
		Need(pos, value)
		return strsub(src, pos, pos + value - 1), pos + value
	end
	local chunks, n = {}, 0
	while true do
		local chunk
		chunk, pos = DecodeItem(pos, depth + 1, true)
		if chunk == BREAK then break end
		if type(chunk) ~= "string" then
			error("CBOR: bad chunk in an indefinite-length string")
		end
		n = n + 1
		chunks[n] = chunk
	end
	return tconcat(chunks), pos
end

local function DecodeArray(value, pos, depth)
	local t = {}
	if value then
		-- Every item takes at least one byte.
		Need(pos, value)
		local i
		for i = 1, value do
			t[i], pos = DecodeItem(pos, depth + 1)
		end
		return t, pos
	end
	local i = 0
	while true do
		local item
		item, pos = DecodeItem(pos, depth + 1, true)
		if item == BREAK then break end
		i = i + 1
		t[i] = item
	end
	return t, pos
end

local function StoreEntry(t, key, item)
	local tk = type(key)
	if item ~= nil and (tk == "string" or tk == "boolean" or (tk == "number" and key == key)) then
		t[key] = item
	end
end

local function DecodeMap(value, pos, depth)
	local t = {}
	if value then
		Need(pos, value * 2)
		local i
		for i = 1, value do
			local key, item
			key, pos = DecodeItem(pos, depth + 1)
			item, pos = DecodeItem(pos, depth + 1)
			StoreEntry(t, key, item)
		end
		return t, pos
	end
	while true do
		local key, item
		key, pos = DecodeItem(pos, depth + 1, true)
		if key == BREAK then break end
		item, pos = DecodeItem(pos, depth + 1)
		StoreEntry(t, key, item)
	end
	return t, pos
end

local function DecodeSimple(info, pos)
	if info == 20 then
		return false, pos
	elseif info == 21 then
		return true, pos
	elseif info == 25 then
		local bits
		bits, pos = ReadUInt(pos, 2)
		return Half(bits), pos
	elseif info == 26 then
		local bits
		bits, pos = ReadUInt(pos, 4)
		return Single(bits), pos
	elseif info == 27 then
		local hi, lo
		hi, pos = ReadUInt(pos, 4)
		lo, pos = ReadUInt(pos, 4)
		return Double(hi, lo), pos
	elseif info == 24 then
		Need(pos, 1)
		return nil, pos + 1
	elseif info < 24 then
		-- null, undefined, unassigned simple values
		return nil, pos
	end
	error("CBOR: reserved simple value " .. info)
end

DecodeItem = function(pos, depth, allowBreak)
	if depth > MAX_DEPTH then
		error("CBOR: nesting too deep")
	end
	Need(pos, 1)
	local ib = strbyte(src, pos)
	pos = pos + 1
	local major, info = floor(ib / 32), mod(ib, 32)

	if ib == 255 then
		if not allowBreak then error("CBOR: unexpected break") end
		return BREAK, pos
	end
	if major == 7 then
		return DecodeSimple(info, pos)
	end

	local value
	value, pos = Argument(info, pos)
	if major == 0 then
		if not value then error("CBOR: indefinite integer") end
		return value, pos
	elseif major == 1 then
		if not value then error("CBOR: indefinite integer") end
		return -1 - value, pos
	elseif major == 2 or major == 3 then
		return DecodeString(major, value, pos, depth)
	elseif major == 4 then
		return DecodeArray(value, pos, depth)
	elseif major == 5 then
		return DecodeMap(value, pos, depth)
	end
	-- major 6: a tag, followed by the tagged item
	if not value then error("CBOR: indefinite tag") end
	return DecodeItem(pos, depth + 1)
end

-- Decodes ONE CBOR item starting at `pos` (default 1). Returns the value and
-- the position after it, or nil and an error message. Trailing bytes are
-- left to the caller: the export string carries its "::type::key" suffix
-- right behind the CBOR item.
function Codec.DecodeCBOR(data, pos)
	src, srcLen = data, strlen(data)
	local ok, value, nextPos = pcall(DecodeItem, pos or 1, 0)
	src = nil
	if not ok then
		return nil, value
	end
	return value, nextPos
end

-- ---------------------------------------------------------------------
-- The "!E2!" string
-- ---------------------------------------------------------------------

local function Deflate()
	return LibStub and LibStub("LibDeflate", true)
end

-- Builds the export string. `key` is used (and required) only for the
-- "profile" type, like retail's `D:CreateProfileExport`.
function Codec.Encode(dataType, key, data)
	local LibDeflate = Deflate()
	if not LibDeflate or not Codec.TYPES[dataType] or type(data) ~= "table" then
		return nil
	end
	if dataType == "profile" and (type(key) ~= "string" or key == "") then
		return nil
	end

	local payload = Codec.EncodeCBOR(data) .. "::" .. dataType
	if dataType == "profile" then
		payload = payload .. "::" .. key
	end
	return Codec.PREFIX .. Codec.EncodeBase64(LibDeflate:CompressDeflate(payload))
end

-- The DEFLATE flavour of retail's Enum.CompressionMethod.Deflate is not
-- documented, so a zlib stream (RFC 1950 header: CM 8, header checksum
-- divisible by 31) is accepted as well as raw deflate.
local function Inflate(LibDeflate, data)
	local b1, b2 = strbyte(data, 1), strbyte(data, 2)
	local zlibHeader = b1 and b2 and mod(b1, 16) == 8 and mod(b1 * 256 + b2, 31) == 0
	local out
	if zlibHeader then
		out = LibDeflate:DecompressZlib(data)
		if out then return out end
	end
	out = LibDeflate:DecompressDeflate(data)
	if out then return out end
	if not zlibHeader then
		out = LibDeflate:DecompressZlib(data)
	end
	return out
end

-- Returns dataType, key, data on success (key is nil for types other than
-- "profile"), or nil and an error code:
--   "old"       an "!E1!" string (older ElvUI; retail no longer reads it)
--   "prefix"    not an "!E2!" string at all
--   "library"   LibDeflate is not loaded
--   "base64", "inflate", "cbor", "suffix", "type"   the layer that failed
function Codec.Decode(text)
	if type(text) ~= "string" then return nil, "prefix" end
	local _, _, body = strfind(text, "^%s*(.-)%s*$")

	if strsub(body, 1, 4) == Codec.OLD_PREFIX then return nil, "old" end
	if strsub(body, 1, 4) ~= Codec.PREFIX then return nil, "prefix" end

	local LibDeflate = Deflate()
	if not LibDeflate then return nil, "library" end

	local compressed = Codec.DecodeBase64(strsub(body, 5))
	if not compressed or compressed == "" then return nil, "base64" end

	local payload = Inflate(LibDeflate, compressed)
	if not payload then return nil, "inflate" end

	-- The CBOR item is self-delimiting, so the suffix starts exactly where
	-- the item ends. Retail finds it with a pattern from the end of the
	-- string instead; both agree on every string retail itself produces.
	local data, nextPos = Codec.DecodeCBOR(payload, 1)
	if type(data) ~= "table" then return nil, "cbor" end

	local suffix = strsub(payload, nextPos)
	local _, _, dataType, key = strfind(suffix, "^::([^:]*)::(.*)$")
	if not dataType then
		_, _, dataType = strfind(suffix, "^::([^:]*)$")
	end
	if not dataType then return nil, "suffix" end
	if not Codec.TYPES[dataType] then return nil, "type" end
	if dataType == "profile" then
		if not key or key == "" then return nil, "suffix" end
	else
		key = nil
	end

	return dataType, key, data
end

-- ---------------------------------------------------------------------
-- ElvUI-vanilla "text" export
-- ---------------------------------------------------------------------
--
-- ElvUI-vanilla (distributor.lua `GetProfileExport`, format "text"), no
-- prefix:
--
--   LibBase64( LibCompress:Compress( AceSerializer(data) .. "::" .. type [.. "::" .. key] ) )
--
-- LibCompress keeps the smallest result of its codecs, named by the first
-- byte: 1 stored, 2 LZW, 3 Huffman. Only decompression is implemented here,
-- on LibCompress's exact byte format, with arithmetic in place of the `bit`
-- library, which neither client guarantees.

local POW2 = {}
do
	local i, v = 0, 1
	for i = 0, 32 do
		POW2[i] = v
		v = v * 2
	end
end

-- LibCompress's variable-length integer (its local `decode`): one byte below
-- 250, or the byte 256 - n followed by n little-endian base-255 digits,
-- each stored plus one. Returns the value and the number of bytes read.
local function LZWNumber(data, i)
	local a = strbyte(data, i)
	if not a then error("LZW: truncated data") end
	if a < 250 then
		return a, 1
	end
	local count = 256 - a
	local r = 0
	local n
	for n = i + count, i + 1, -1 do
		local b = strbyte(data, n)
		if not b then error("LZW: truncated data") end
		r = r * 255 + b - 1
	end
	return r, count + 1
end

local function DecompressLZW(data)
	local dict, dictSize = {}, 256
	local i
	for i = 0, 255 do dict[i] = BYTE[i] end

	local len = strlen(data)
	local pos = 2
	local k, delta = LZWNumber(data, pos)
	pos = pos + delta
	local w = dict[k]
	if not w then error("LZW: bad code") end
	local parts, n = { w }, 1
	while pos <= len do
		k, delta = LZWNumber(data, pos)
		pos = pos + delta
		local entry = dict[k]
		if not entry then
			-- Only the code being defined right now may be unknown.
			if k ~= dictSize then error("LZW: bad code") end
			entry = w .. strsub(w, 1, 1)
		end
		n = n + 1
		parts[n] = entry
		dict[dictSize] = w .. strsub(entry, 1, 1)
		dictSize = dictSize + 1
		w = entry
	end
	return tconcat(parts)
end

-- LSB-first bit reader for the Huffman stream; state lives in upvalues for
-- the duration of one DecompressHuffman call.
local hData, hPos, hByte, hBit

local function ReadBit()
	if hBit == 8 then
		hByte = strbyte(hData, hPos)
		if not hByte then error("Huffman: truncated data") end
		hPos = hPos + 1
		hBit = 0
	end
	local bit = mod(hByte, 2)
	hByte = floor(hByte / 2)
	hBit = hBit + 1
	return bit
end

-- Header: 3, symbol count - 1, original size (3 bytes, little-endian). Then,
-- per symbol, 8 bits of symbol and its code "escaped" (a 0 bit as "0", a 1
-- bit as "1 0", first code bit first) closed by "1 1"; then the codes of the
-- data. Bits are packed LSB-first; a code's first bit is its value's bit 0.
local function DecompressHuffman(data)
	if strlen(data) < 5 then error("Huffman: truncated header") end
	local numSymbols = strbyte(data, 2) + 1
	local origSize = strbyte(data, 3) + strbyte(data, 4) * 256 + strbyte(data, 5) * 65536
	if origSize == 0 then return "" end

	hData, hPos, hBit = data, 6, 8

	local codes = {}
	local minLen, maxLen = 1000, 0
	local s
	for s = 1, numSymbols do
		local symbol, b = 0, 0
		for b = 0, 7 do
			symbol = symbol + ReadBit() * POW2[b]
		end
		local value, length = 0, 0
		while true do
			if ReadBit() == 1 then
				if ReadBit() == 1 then break end
				value = value + POW2[length]
			end
			length = length + 1
			if length > 32 then error("Huffman: code too long") end
		end
		codes[length] = codes[length] or {}
		codes[length][value] = BYTE[symbol]
		if length < minLen then minLen = length end
		if length > maxLen then maxLen = length end
	end

	local out, n = {}, 0
	local symbol
	while n < origSize do
		local value, length = 0, 0
		symbol = nil
		repeat
			value = value + ReadBit() * POW2[length]
			length = length + 1
			if length >= minLen and codes[length] then
				symbol = codes[length][value]
			end
			if not symbol and length >= maxLen then
				error("Huffman: bad code")
			end
		until symbol
		n = n + 1
		out[n] = symbol
	end
	return tconcat(out)
end

-- Returns the decompressed string, or nil and an error message.
function Codec.DecompressLibCompress(data)
	local method = strbyte(data, 1)
	local ok, result
	if method == 1 then
		return strsub(data, 2)
	elseif method == 2 then
		ok, result = pcall(DecompressLZW, data)
	elseif method == 3 then
		ok, result = pcall(DecompressHuffman, data)
	else
		return nil, "unknown compression method " .. tostring(method)
	end
	hData = nil
	if not ok then return nil, result end
	return result
end

-- Returns dataType, key, data (key only for "profile"), or nil and an error
-- code: "base64", "decompress", "suffix", "library" (AceSerializer-3.0 is
-- not loaded), "deserialize". The type is returned as found (vanilla also
-- exports "styleFilters"); the caller decides what it accepts.
function Codec.DecodeVanilla(text)
	if type(text) ~= "string" then return nil, "base64" end
	local _, _, body = strfind(text, "^%s*(.-)%s*$")

	local packed = Codec.DecodeBase64(body)
	if not packed or packed == "" then return nil, "base64" end

	local payload = Codec.DecompressLibCompress(packed)
	if not payload then return nil, "decompress" end

	-- AceSerializer ends its data with "^^" and escapes every "^" inside
	-- it, so the first "^^::" is where the data ends.
	local split = strfind(payload, "^^::", 1, true)
	if not split then return nil, "suffix" end
	local serialized = strsub(payload, 1, split + 1)
	local info = strsub(payload, split + 4)

	local _, _, dataType, key = strfind(info, "^([^:]*)::(.*)$")
	if not dataType then dataType = info end
	if dataType == "" then return nil, "suffix" end
	if dataType == "profile" then
		if not key or key == "" then return nil, "suffix" end
	else
		key = nil
	end

	local AceSerializer = LibStub and LibStub("AceSerializer-3.0", true)
	if not AceSerializer then return nil, "library" end
	local ok, data = AceSerializer:Deserialize(serialized)
	if not ok or type(data) ~= "table" then return nil, "deserialize" end

	return dataType, key, data
end
