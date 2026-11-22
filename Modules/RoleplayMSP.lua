local _, ns = ...
local MSP = { prefix = "MSP2" }
ns.RoleplayMSP = MSP

local SEPARATOR = "`"
local MAX_PAYLOAD, MAX_PARTS = 240, 128
local session = math.random(0, 4095)
local tooltipFields = { "VP", "VA", "NA", "NH", "NI", "NT", "RA", "CU", "FR", "FC", "RC", "PX" }
local inTooltip = {}
for _, field in ipairs(tooltipFields) do inTooltip[field] = true end

-- MSP2 uses Chomp's in-game string framing and its logged text codec.
local escape = { ["~"] = "~7E", ["|"] = "~7C", ["\\"] = "~5C", ["\n"] = "~0A" }
local unescape = { ["7E"] = "~", ["7C"] = "|", ["5C"] = "\\", ["0A"] = "\n" }
local function Send(address, payload, logged, reserve, canContinue)
	local send = logged and C_ChatInfo.SendAddonMessageLogged or not logged and C_ChatInfo.SendAddonMessage
	if type(send) ~= "function" then return false end
	local parts = {}
	if logged then
		payload = payload:gsub("[~|\\\n]", escape)
	end
	local first = 1
	while first <= #payload do
		local last = math.min(first + MAX_PAYLOAD - 1, #payload)
		if last < #payload then
			while payload:byte(last + 1) >= 128 and payload:byte(last + 1) <= 191 do last = last - 1 end
			if logged then
				local start = payload:sub(last - 1, last):find("~", 1, true)
				if start then last = last - (3 - start) end
			end
		end
		parts[#parts + 1] = payload:sub(first, last)
		first = last + 1
	end
	if #parts == 0 or not reserve(#parts) then return false end
	session = (session + 1) % 4096
	local id, index = session, 1
	local deadline = canContinue and GetTime() + 10
	local function SendParts()
		if canContinue and (not canContinue() or GetTime() >= deadline) then return false end
		local status = Enum.SendAddonMessageResult
		while index <= #parts do
			local packet = ("00A%03X%03X%03X%s"):format(id, index, #parts, parts[index])
			local ok, result = pcall(send, MSP.prefix, packet, "WHISPER", address)
			if not ok or ns.Secret(result) then return false end
			if canContinue and status.AddonMessageThrottle and result == status.AddonMessageThrottle then
				ns.After("Roleplay: retry MSP reply", 1, SendParts)
				return true
			end
			if result ~= status.Success then return false end
			index = index + 1
		end
		return true
	end
	return SendParts()
end

function MSP.Request(address, fields, reserve)
	return Send(address, fields, false, reserve)
end

local crcTable
local function Checksum(text)
	if not crcTable then
		crcTable = {}
		for byte = 0, 255 do
			local value = byte
			for _ = 1, 8 do
				local lowBit = bit.band(value, 1)
				value = bit.rshift(value, 1)
				if lowBit == 1 then value = bit.bxor(value, 0x82F63B78) end
			end
			crcTable[byte] = value
		end
	end
	local crc = 0xFFFFFFFF
	for index = 1, #text do
		local byte = bit.band(bit.bxor(crc, text:byte(index)), 255)
		crc = bit.bxor(bit.rshift(crc, 8), crcTable[byte])
	end
	return ("%X"):format(bit.bxor(crc, 0xFFFFFFFF) % 0x100000000)
end

function MSP.Reply(address, requests, fields, reserve, canContinue)
	local result, seen = {}, {}
	for field in pairs(requests) do
		if inTooltip[field] then field = "TT" end
		if not seen[field] then
			seen[field] = true
			if field == "TT" then
				local tooltip = {}
				for _, key in ipairs(tooltipFields) do
					local value = fields[key]
					tooltip[#tooltip + 1] = value and key .. ":" .. value or key
				end
				local body = table.concat(tooltip, SEPARATOR)
				result[#result + 1] = body .. SEPARATOR .. "TT" .. Checksum(body)
			elseif fields[field] then
				result[#result + 1] = field .. Checksum(fields[field]) .. ":" .. fields[field]
			else
				result[#result + 1] = field
			end
		end
	end
	return Send(address, table.concat(result, SEPARATOR), true, reserve, canContinue)
end

function MSP.Packet(message, logged, fragments)
	if type(message) ~= "string" or #message > 255 then return end
	local flags, id, index, count, part = message:match("^(%x%x%x)(%x%x%x)(%x%x%x)(%x%x%x)(.+)$")
	if flags ~= "00A" and flags ~= "008" then return end
	index, count = tonumber(index, 16), tonumber(count, 16)
	if index == 0 or index > count or count > MAX_PARTS then return end
	if count == 1 then return part end
	if not (fragments and logged) then return end
	local group = fragments[id]
	if not group then
		-- A peer can answer a tooltip and a profile request at the same time.
		if (fragments.count or 0) >= 2 then return end
		group = { count = count, received = 0, parts = {} }
		fragments[id] = group
		fragments.count = (fragments.count or 0) + 1
	end
	if group.parts[index] then return end
	group.count = math.max(group.count, count)
	group.parts[index] = part
	group.received = group.received + 1
	if group.received == group.count then
		fragments[id] = nil
		fragments.count = fragments.count - 1
		return table.concat(group.parts)
	end
end

function MSP.Commands(payload, logged)
	local requests, fields = {}, {}
	for command in payload:gmatch("[^`]+") do
		local key = command:match("^%?(%u%u)%x*$")
		if key then
			requests[key] = true
		elseif logged then
			local field, value = command:match("^(%u%u)%x*:(.*)$")
			if value then
				fields[field] = value:gsub("~(%x%x)", function(code) return unescape[code:upper()] end)
			else
				field = command:match("^(%u%u)%x*$")
				if field then fields[field] = "" end
			end
		end
	end
	return requests, fields
end
