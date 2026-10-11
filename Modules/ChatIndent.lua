-- Chat with hanging indent: a message that wraps puts its next lines under the text, not under the
-- timestamp. The game's own indented wrapping only indents a little, so the message is wrapped here
-- (measured with the font of the chat window) and the continuation lines start with blanks of the width
-- of the timestamp. Done after the message was added, with the chat window's own TransformMessages;
-- Blizzard's functions stay untouched. The saved chat log keeps the unwrapped text.
local _, ns = ...
local L = ns.L

local Indent = ns:NewModule("ChatIndent", {
	title = L.CHATINDENT_TITLE,
	order = 5.95,
	defaults = {
		enabled = false,
	},
})

local MARGIN = 6          -- pixels kept free at the right edge (measuring is not exact)
local FALLBACK_BLANKS = 2 -- indentation without a timestamp
local MAX_REMEMBERED = 400

local meter
local widths = {}         -- token -> width for the current font
local meterKey
local spaceWidth = 4
local originals = {}     -- wrapped text -> original text
local remembered = 0
local hooked = {}

-- Width of a text in the font of the chat window; replaceable for tests.
function Indent.measure(text)
	meter:SetText(text)
	local width = meter.GetUnboundedStringWidth and meter:GetUnboundedStringWidth() or meter:GetStringWidth()
	return ns.Number(width, 0)
end

local function PrepareMeter(frame)
	if not meter then
		meter = ns.hider:CreateFontString(nil, "ARTWORK")
	end
	local object = frame:GetFontObject()
	if object then
		meter:SetFontObject(object)
	end
	local file, size, flags = meter:GetFont()
	local key = ("%s|%s|%s"):format(tostring(file), tostring(size), tostring(flags))
	if key ~= meterKey then
		meterKey = key
		wipe(widths)
		spaceWidth = math.max(1, Indent.measure("a a") - Indent.measure("aa"))
	end
end

local function TokenWidth(token)
	local width = widths[token]
	if not width then
		width = Indent.measure(token)
		widths[token] = width
	end
	return width
end

-- Words, split at blanks outside of links; nil for texts that already have line breaks or escapes
-- that cannot be measured.
local function Tokens(text)
	local list, start, state, i, last = {}, 1, 0, 1, #text
	while i <= last do
		local byte = text:byte(i)
		if byte == 124 then -- |
			local code = text:sub(i + 1, i + 1)
			if code == "n" or code == "K" then
				return nil
			elseif code == "H" then
				state = 1
			elseif code == "h" then
				state = state == 1 and 2 or 0
			end
			i = i + 2
		elseif byte == 10 then
			return nil
		elseif byte == 32 and state == 0 then
			list[#list + 1] = text:sub(start, i - 1)
			start = i + 1
			i = i + 1
		else
			i = i + 1
		end
	end
	list[#list + 1] = text:sub(start)
	return list
end

-- Length of the timestamp at the start of the message (0 without).
local function PrefixLength(message)
	local format = ChatFrameUtil and ChatFrameUtil.GetTimestampFormat and ChatFrameUtil.GetTimestampFormat()
	if not format or not TimeUtil or not TimeUtil.BetterDate then
		return 0
	end
	local sample = TimeUtil.BetterDate(format, time())
	if type(sample) ~= "string" or sample == "" then
		return 0
	end
	local shape = (sample:gsub("%d", "#"))
	if (message:sub(1, #sample):gsub("%d", "#")) == shape then
		return #sample
	end
	return 0
end

-- The message with line breaks and blanks in front of the continuation lines; nil when it fits or
-- cannot be wrapped.
function Indent.Wrap(frame, message)
	if type(message) ~= "string" or (issecretvalue and issecretvalue(message)) or not message:find(" ", 1, true) then
		return nil
	end
	local width = ns.Number(frame:GetWidth(), 0)
	if width < 50 then
		return nil
	end
	local available = width - MARGIN
	PrepareMeter(frame)
	if Indent.measure(message) <= available then
		return nil
	end
	local tokens = Tokens(message)
	if not tokens or #tokens < 2 then
		return nil
	end
	local prefix = PrefixLength(message)
	local indent = prefix > 0 and Indent.measure(message:sub(1, prefix)) or spaceWidth * FALLBACK_BLANKS
	local blanks = math.max(1, math.floor(indent / spaceWidth + 0.5))
	local pad = (" "):rep(blanks)
	local padWidth = blanks * spaceWidth
	-- The timestamp is part of the first word; the first line is measured as it is.
	local lines, line, lineWidth = {}, nil, 0
	for _, token in ipairs(tokens) do
		local tokenWidth = TokenWidth(token)
		if not line then
			line, lineWidth = token, tokenWidth
		elseif lineWidth + spaceWidth + tokenWidth <= available then
			line, lineWidth = line .. " " .. token, lineWidth + spaceWidth + tokenWidth
		else
			lines[#lines + 1] = (#lines > 0 and pad or "") .. line
			line, lineWidth = token, padWidth + tokenWidth
		end
	end
	lines[#lines + 1] = (#lines > 0 and pad or "") .. line
	if #lines < 2 then
		return nil
	end
	return table.concat(lines, "\n")
end

local function Remember(wrapped, original)
	if remembered >= MAX_REMEMBERED then
		wipe(originals)
		remembered = 0
	end
	originals[wrapped] = original
	remembered = remembered + 1
end

local function OnAddMessage(frame, message)
	if not Indent.db.enabled or type(message) ~= "string" or (issecretvalue and issecretvalue(message)) then
		return
	end
	local wrapped = Indent.Wrap(frame, message)
	if not wrapped then
		return
	end
	Remember(wrapped, message)
	frame:TransformMessages(function(text)
		return not (issecretvalue and issecretvalue(text)) and text == message
	end, function(_, ...)
		return wrapped, ...
	end)
end

-- Wraps the lines again (after a resize) or gives them back unwrapped (rewrap false).
local function Redo(frame, rewrap)
	frame:TransformMessages(function(text)
		return not (issecretvalue and issecretvalue(text)) and originals[text] ~= nil
	end, function(text, ...)
		local original = originals[text]
		local wrapped = rewrap and Indent.Wrap(frame, original)
		if wrapped then
			Remember(wrapped, original)
			return wrapped, ...
		end
		return original, ...
	end)
end

local pending = {}

local function OnSizeChanged(frame)
	if pending[frame] or not Indent.db.enabled then
		return
	end
	pending[frame] = true
	C_Timer.After(0.4, function()
		pending[frame] = nil
		if Indent.db.enabled then
			Redo(frame, true)
		end
	end)
end

local function Hook(frame)
	if hooked[frame] or not frame.TransformMessages then
		return
	end
	hooked[frame] = true
	hooksecurefunc(frame, "AddMessage", ns.Measured("Chat: indented wrap", OnAddMessage))
	frame:HookScript("OnSizeChanged", OnSizeChanged)
end

function Indent:Apply()
	for _, name in ipairs(CHAT_FRAMES) do
		local frame = _G[name]
		-- The combat log is far too busy.
		if frame and frame ~= COMBATLOG then
			Hook(frame)
			if not self.db.enabled then
				Redo(frame, false)
			end
		end
	end
	if not self.db.enabled then
		wipe(originals)
		remembered = 0
	end
end

function Indent:OnLogin()
	self:Apply()
end

function Indent:OnOptionChanged()
	self:Apply()
end

Indent.options = {
	{ key = "enabled", type = "toggle", name = L.CHATINDENT, desc = L.CHATINDENT_DESC, new = true },
}
