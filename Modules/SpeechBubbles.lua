-- Speech bubbles: the text an NPC says (gossip, quest greeting, quest text,
-- progress) as a bubble over its head while the dialog is open. Without a
-- nameplate to hang it on, it sits at the top of the screen. Only reads the
-- texts the game provides; the dialogs themselves stay as they are.
local _, ns = ...
local L = ns.L

local SpeechBubbles = ns:NewModule("SpeechBubbles", {
	title = L.SPEECH_TITLE,
	order = 5.5,
	defaults = {
		enabled = true,
		gossip = true,
		quests = true,
		fallback = true,
	},
})

local BUBBLE_WIDTH = 350
local BUBBLE_MAX_HEIGHT = 200
local PADDING = 12
local FALLBACK_Y = -120
local TEXTURE = [[Interface\Tooltips\UI-Tooltip-Background]]

local bubbles = {}      -- nameplate -> bubble
local fallbackBubble
local current           -- the bubble on show
local lastNameplate     -- nameplate of the NPC, remembered before the dialog opens

local function CreateBubble(parent, withTail)
	local bubble = CreateFrame("Frame", nil, parent)
	bubble:SetSize(BUBBLE_WIDTH, 60)
	bubble:SetFrameStrata("HIGH")
	local back = bubble:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetTexture(TEXTURE)
	back:SetVertexColor(0.08, 0.08, 0.1, 0.92)
	bubble.Text = bubble:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	bubble.Text:SetPoint("TOPLEFT", PADDING, -PADDING)
	bubble.Text:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
	bubble.Text:SetJustifyH("LEFT")
	bubble.Text:SetJustifyV("TOP")
	bubble.Text:SetTextColor(1, 1, 1)
	if withTail then
		local tail = bubble:CreateTexture(nil, "OVERLAY")
		tail:SetSize(22, 24)
		tail:SetPoint("TOP", bubble, "BOTTOM", -10, -17)
		tail:SetTexture(TEXTURE)
		tail:SetVertexColor(0.08, 0.08, 0.1, 0.92)
	end
	bubble:Hide()
	return bubble
end

local function NameplateBubble(nameplate)
	local bubble = bubbles[nameplate]
	if not bubble then
		bubble = CreateBubble(nameplate, true)
		bubble:SetPoint("BOTTOM", nameplate, "TOP", 0, 15)
		bubbles[nameplate] = bubble
	end
	return bubble
end

local function FallbackBubble()
	if not fallbackBubble then
		fallbackBubble = CreateBubble(UIParent, false)
		fallbackBubble:SetPoint("TOP", UIParent, "TOP", 0, FALLBACK_Y)
	end
	return fallbackBubble
end

-- Puts the text in the bubble, cut at a word boundary when it would not fit.
local function SetText(bubble, text)
	bubble.Text:SetWidth(BUBBLE_WIDTH - PADDING * 2)
	bubble.Text:SetText(text)
	local limit = BUBBLE_MAX_HEIGHT - PADDING * 2
	local cut = false
	while bubble.Text:GetStringHeight() > limit and #text > 20 do
		text = text:sub(1, math.floor(#text * 0.85)):gsub("%s+%S*$", "")
		bubble.Text:SetText(text .. "…")
		cut = true
	end
	if not cut then
		bubble.Text:SetText(text)
	end
	bubble:SetSize(BUBBLE_WIDTH, bubble.Text:GetStringHeight() + PADDING * 2)
end

local function Readable(text)
	return type(text) == "string" and text ~= "" and not (issecretvalue and issecretvalue(text)) and text or nil
end

local function GossipText()
	return C_GossipInfo and C_GossipInfo.GetText and Readable(C_GossipInfo.GetText())
end

local function QuestText(event)
	local getter = ({ QUEST_GREETING = GetGreetingText, QUEST_DETAIL = GetQuestText, QUEST_PROGRESS = GetProgressText })[event]
	return getter and Readable(getter())
end

local function NpcNameplate()
	if UnitExists("npc") then
		local nameplate = C_NamePlate.GetNamePlateForUnit("npc")
		if nameplate and not nameplate:IsForbidden() then
			return nameplate
		end
	end
end

local function Hide()
	if current then
		current:Hide()
		current = nil
	end
end

local function Show(text)
	local nameplate = NpcNameplate() or lastNameplate
	if nameplate and nameplate:IsForbidden() then
		nameplate = nil
	end
	local bubble
	if nameplate then
		bubble = NameplateBubble(nameplate)
	elseif SpeechBubbles.db.fallback then
		bubble = FallbackBubble()
	end
	Hide()
	if bubble then
		SetText(bubble, text)
		bubble:Show()
		current = bubble
	end
end

local function OnGossip()
	if SpeechBubbles.db.gossip then
		local text = GossipText()
		if text then
			Show(text)
		end
	end
end

local function OnQuestText(_, event)
	if SpeechBubbles.db.quests then
		local text = QuestText(event)
		if text then
			Show(text)
		end
	end
end

local function RememberNameplate()
	lastNameplate = NpcNameplate() or lastNameplate
end

SpeechBubbles.Show = Show
SpeechBubbles.Hide = Hide

function SpeechBubbles:Apply()
	local on = self.db.enabled
	self:ToggleEvent("GOSSIP_SHOW", on, OnGossip)
	for _, event in ipairs({ "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS" }) do
		self:ToggleEvent(event, on, OnQuestText)
	end
	for _, event in ipairs({ "GOSSIP_CLOSED", "QUEST_FINISHED", "QUEST_COMPLETE" }) do
		self:ToggleEvent(event, on, Hide)
	end
	self:ToggleEvent("PLAYER_TARGET_CHANGED", on, RememberNameplate)
	self:ToggleEvent("NAME_PLATE_UNIT_ADDED", on, RememberNameplate)
	if not on then
		Hide()
	end
end

function SpeechBubbles:OnLogin()
	self:Apply()
end

function SpeechBubbles:OnOptionChanged()
	self:Apply()
end

SpeechBubbles.options = {
	{ key = "enabled", type = "toggle", name = L.SPEECH_ENABLE, desc = L.SPEECH_ENABLE_DESC },
	{ key = "gossip", type = "toggle", name = L.SPEECH_GOSSIP, desc = L.SPEECH_GOSSIP_DESC, parent = "enabled" },
	{ key = "quests", type = "toggle", name = L.SPEECH_QUESTS, desc = L.SPEECH_QUESTS_DESC, parent = "enabled" },
	{ key = "fallback", type = "toggle", name = L.SPEECH_FALLBACK, desc = L.SPEECH_FALLBACK_DESC, parent = "enabled" },
}
