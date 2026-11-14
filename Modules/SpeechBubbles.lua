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

local BUBBLE_WIDTH = 330
local BUBBLE_MAX_HEIGHT = 200
local PADDING = 12   -- used by the plain fallback look only
local INSET = 16     -- the border art lies this far around the text
local FALLBACK_Y = -120
local TEXTURE = [[Interface\Tooltips\UI-Tooltip-Background]]

local speechBubble, active
local npcGuid, anchorUnit, anchorPlate
local removedPlates = {}

-- Like the players' chat bubbles: dark rounded box with a light border and a
-- tail, the text centred in white. Without that art a plain dark pane.
local function CreateBubble()
	local bubble = CreateFrame("Frame", nil, UIParent)
	bubble:SetSize(BUBBLE_WIDTH, 30)
	bubble:SetFrameStrata("HIGH")
	bubble.Art, bubble.Tail = ns.CreateBubbleArt(bubble, INSET, -10)
	if not bubble.Art then
		local back = bubble:CreateTexture(nil, "BACKGROUND")
		back:SetPoint("TOPLEFT", -PADDING, PADDING)
		back:SetPoint("BOTTOMRIGHT", PADDING, -PADDING)
		back:SetTexture(TEXTURE)
		back:SetVertexColor(0.08, 0.08, 0.1, 0.92)
	end
	bubble.Text = bubble:CreateFontString(nil, "OVERLAY")
	bubble.Text:SetFontObject(_G.ChatBubbleFont and "ChatBubbleFont" or "GameFontNormal")
	bubble.Text:SetPoint("CENTER", 0, 0)
	bubble.Text:SetJustifyH("CENTER")
	bubble.Text:SetJustifyV("MIDDLE")
	bubble.Text:SetNonSpaceWrap(true)
	bubble.Text:SetTextColor(1, 1, 1)
	bubble:Hide()
	return bubble
end

-- Puts the text in the bubble: as wide as the text needs (up to the maximum),
-- cut at a word boundary when it would not fit the height.
local function SetText(bubble, text)
	bubble.Text:SetWidth(0)
	bubble.Text:SetText(text)
	local width = math.min(BUBBLE_WIDTH, math.max(40, bubble.Text:GetStringWidth() + 2))
	bubble.Text:SetWidth(width)
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
	bubble:SetSize(width, math.max(bubble.Text:GetStringHeight(), 14))
end

local function Readable(text)
	return type(text) == "string" and text ~= "" and not ns.Secret(text) and text or nil
end

local function GossipText()
	return C_GossipInfo and C_GossipInfo.GetText and Readable(C_GossipInfo.GetText())
end

local function QuestText(event)
	local getter = ({ QUEST_GREETING = GetGreetingText, QUEST_DETAIL = GetQuestText, QUEST_PROGRESS = GetProgressText })[event]
	return getter and Readable(getter())
end

local function NpcNameplate()
	local plate
	plate, anchorUnit = ns.NpcBubbleNameplate(npcGuid, anchorUnit, removedPlates)
	return plate
end

local function Hide()
	if speechBubble then
		speechBubble:Hide()
	end
	active, npcGuid, anchorUnit, anchorPlate = nil, nil, nil, nil
	wipe(removedPlates)
	ns.ShowFriendlyPlates(false, "speech")
end

local function Place(nameplate)
	anchorPlate = nameplate
	speechBubble:ClearAllPoints()
	if speechBubble.Tail then
		speechBubble.Tail:SetShown(nameplate ~= nil)
	end
	if nameplate then
		speechBubble:SetPoint("BOTTOM", nameplate, "TOP", 0, 15 + INSET + 16)
		speechBubble:Show()
	elseif SpeechBubbles.db.fallback then
		speechBubble:SetPoint("TOP", UIParent, "TOP", 0, FALLBACK_Y)
		speechBubble:Show()
	else
		speechBubble:Hide()
	end
end

local function RefreshNameplate()
	if not active then
		return
	end
	local nameplate = NpcNameplate()
	if nameplate ~= anchorPlate then
		Place(nameplate)
	end
end

local function Show(text)
	if not speechBubble then
		speechBubble = CreateBubble()
		ns.SetUpdate(speechBubble, "SpeechBubbles: plate watch", RefreshNameplate)
	end
	npcGuid = ns.NpcBubbleGUID() or npcGuid
	ns.ShowFriendlyPlates(SpeechBubbles.db.fallback and npcGuid ~= nil, "speech")
	active = true
	SetText(speechBubble, text)
	Place(NpcNameplate())
end

local function OnGossip()
	if SpeechBubbles.db.gossip and not ns.dialogBubbles then
		local text = GossipText()
		if text then
			Show(text)
		end
	end
end

local function OnQuestText(_, event)
	if SpeechBubbles.db.quests and not ns.dialogBubbles then
		local text = QuestText(event)
		if text then
			Show(text)
		end
	end
end

local function OnPlateAdded(_, _, unit)
	removedPlates[unit] = nil
	RefreshNameplate()
end

local function OnPlateRemoved(_, _, unit)
	if active then
		removedPlates[unit] = true
		RefreshNameplate()
	end
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
	self:ToggleEvent("NAME_PLATE_UNIT_ADDED", on, OnPlateAdded)
	self:ToggleEvent("NAME_PLATE_UNIT_REMOVED", on, OnPlateRemoved)
	if not on then
		Hide()
	elseif active then
		ns.ShowFriendlyPlates(self.db.fallback and npcGuid ~= nil, "speech")
		Place(NpcNameplate())
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
