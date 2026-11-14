-- Talent plan summary: adds up the effects of the talent descriptions (at the
-- planned rank) per kind, e.g. "+5 % critical strike chance, +3 % movement
-- speed". The descriptions are the game's own texts, German or English; a
-- sentence counts for the first kind whose cue it contains and takes its first
-- number. Sentences without a known kind are only counted.
local _, ns = ...

local Summary = {}
ns.TalentSummary = Summary

-- key, German label, English label, cues (lower case), flat numbers count too
local KINDS = {
	{ "critdamage", "Kritischer Schaden", "Critical strike damage", { "kritischen schaden", "kritische schaden", "critical strike damage", "critical damage", "crit damage" } },
	{ "crit", "Kritische Trefferchance", "Critical strike chance", { "kritische", "critical strike", "critical hit", "crit chance" } },
	{ "hit", "Trefferchance", "Hit chance", { "trefferchance", "treffen", "chance to hit", "hit chance", "trefferwertung" } },
	{ "attackspeed", "Angriffsgeschwindigkeit", "Attack speed", { "angriffsgeschwindigkeit", "attack speed", "swing speed" } },
	{ "castspeed", "Zaubergeschwindigkeit", "Casting speed", { "zaubertempo", "zaubergeschwindigkeit", "wirkzeit", "casting speed", "cast time", "haste" } },
	{ "movement", "Bewegungsgeschwindigkeit", "Movement speed", { "bewegungsgeschwindigkeit", "laufgeschwindigkeit", "movement speed", "run speed" } },
	{ "dodge", "Ausweichchance", "Dodge chance", { "ausweich", "dodge" } },
	{ "parry", "Parierchance", "Parry chance", { "parier", "parry" } },
	{ "block", "Blockchance", "Block chance", { "blockchance", "blocken", "chance to block", "block chance" } },
	{ "manacost", "Manakosten", "Mana cost", { "manakosten", "mana cost" } },
	{ "manaregen", "Manaregeneration", "Mana regeneration", { "manaregeneration", "mana regeneration", "mana pro", "mana per", "regeneriert" } },
	{ "mana", "Mana", "Mana", { "mana" }, true },
	{ "health", "Gesundheit", "Health", { "gesundheit", "health" }, true },
	{ "armor", "Rüstung", "Armor", { "rüstung", "armor" }, true },
	{ "resist", "Widerstand", "Resistance", { "widerstand", "resistance" }, true },
	{ "attackpower", "Angriffskraft", "Attack power", { "angriffskraft", "attack power" }, true },
	{ "threat", "Bedrohung", "Threat", { "bedrohung", "threat" } },
	{ "healing", "Heilung", "Healing", { "heilung", "healing" } },
	{ "damage", "Schaden", "Damage", { "schaden", "damage" } },
	{ "strength", "Stärke", "Strength", { "stärke", "strength" }, true },
	{ "agility", "Beweglichkeit", "Agility", { "beweglichkeit", "agility" }, true },
	{ "stamina", "Ausdauer", "Stamina", { "ausdauer", "stamina" }, true },
	{ "intellect", "Intelligenz", "Intellect", { "intelligenz", "intellect" }, true },
	{ "spirit", "Willenskraft", "Spirit", { "willenskraft", "spirit" }, true },
}

local NEGATIVE = { "verringert", "reduziert", "senkt", "vermindert", "verlangsamt", "reduces", "decreases", "lowers", "slows" }

local function Contains(text, list)
	for _, word in ipairs(list) do
		if text:find(word, 1, true) then
			return true
		end
	end
	return false
end

local function Number(text)
	return tonumber((text:gsub(",", ".")))
end

-- One sentence: kind key, signed value, whether it was a percentage; nil without a kind or number.
function Summary.Sentence(sentence)
	local lower = sentence:lower()
	-- Durations and cooldowns are no stats.
	if lower:find("sek", 1, true) or lower:find("sec", 1, true) or lower:find("abklingzeit", 1, true) or lower:find("cooldown", 1, true) then
		return nil
	end
	local percent = lower:match("(%d+[%.,]?%d*)%s*%%")
	local flat = not percent and lower:match("(%d+)")
	if not percent and not flat then
		return nil
	end
	for _, kind in ipairs(KINDS) do
		if Contains(lower, kind[4]) and (percent or kind[5]) then
			local value = Number(percent or flat)
			if Contains(lower, NEGATIVE) then
				value = -value
			end
			return kind[1], value, percent ~= nil
		end
	end
	return nil
end

local function Label(key, german)
	for _, kind in ipairs(KINDS) do
		if kind[1] == key then
			return german and kind[2] or kind[3]
		end
	end
	return key
end

-- Splits the text of a description into sentences without colour codes.
local function Sentences(description)
	local text = description:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "\n")
	local list = {}
	for part in text:gmatch("[^\n]+") do
		for sentence in (part .. " "):gmatch("(.-%.)%s") do
			list[#list + 1] = sentence
		end
		-- a last piece without a final full stop
		local rest = part:match("[^%.]+$")
		if rest and not part:match("%.%s*$") then
			list[#list + 1] = rest
		end
	end
	return list
end

-- descriptions: list of texts. Returns lines { key, text } in the order of KINDS, and the number of
-- sentences without a kind.
function Summary.Build(descriptions, german)
	local percent, flat, other = {}, {}, 0
	for _, description in ipairs(descriptions) do
		for _, sentence in ipairs(Sentences(description)) do
			local key, value, isPercent = Summary.Sentence(sentence)
			if key then
				local into = isPercent and percent or flat
				into[key] = (into[key] or 0) + value
			elseif sentence:find("%d") then
				other = other + 1
			end
		end
	end
	local lines = {}
	for _, kind in ipairs(KINDS) do
		local key = kind[1]
		for _, entry in ipairs({ { percent[key], "%+g %%" }, { flat[key], "%+g" } }) do
			local total = entry[1]
			if total and total ~= 0 then
				lines[#lines + 1] = { key = key, text = ("%s %s"):format(entry[2]:format(math.floor(total * 100 + 0.5) / 100), Label(key, german)) }
			end
		end
	end
	return lines, other
end

-- Match whole, single-effect descriptions. A conditional bonus or an effect on a specific
-- ability needs a model of the fight before it can be compared with a bonus from equipment.
local STAT_PHRASES = {
	[false] = {
		strength = "STR", agility = "AGI", stamina = "STA", intellect = "INT", spirit = "SPI",
		armor = "ARMOR", ["defense skill"] = "DEF", ["attack power"] = "AP", ["ranged attack power"] = "RAP",
		["spell power"] = "SP", ["healing power"] = "HEAL",
		["melee attack speed"] = "HASTE", ["spell haste"] = "SHASTE", ["spell casting speed"] = "SHASTE",
		["spell critical strike chance"] = "SCRIT",
		["chance to dodge"] = "DODGE", ["chance to parry"] = "PARRY", ["chance to block"] = "BLOCK",
		["dodge chance"] = "DODGE", ["parry chance"] = "PARRY", ["block chance"] = "BLOCK",
		["chance to hit"] = "HIT", ["chance to hit with all spells"] = "SHIT",
		["chance to hit with all spells and attacks"] = "HIT", ["chance to hit with all attacks and spells"] = "HIT",
		["critical strike chance with all spells and attacks"] = "CRIT",
		["chance to get a critical strike with all spells and attacks"] = "CRIT",
	},
	[true] = {
		["stärke"] = "STR", beweglichkeit = "AGI", ausdauer = "STA", intelligenz = "INT", willenskraft = "SPI",
		["rüstung"] = "ARMOR", verteidigung = "DEF", verteidigungsfertigkeit = "DEF", verteidigungswert = "DEF",
		angriffskraft = "AP", fernkampfangriffskraft = "RAP",
		zaubermacht = "SP", heilzaubermacht = "HEAL", nahkampfangriffstempo = "HASTE",
		zaubertempo = "SHASTE", zaubergeschwindigkeit = "SHASTE", zauberkritchance = "SCRIT",
		ausweichchance = "DODGE", parierchance = "PARRY", blockchance = "BLOCK",
		["chance, einem angriff auszuweichen,"] = "DODGE", ["chance, einen angriff zu parieren,"] = "PARRY",
		["chance, einen angriff zu blocken,"] = "BLOCK", ["trefferchance mit allen zaubern"] = "SHIT",
		trefferchance = "HIT", ["trefferchance mit allen angriffen und zaubern"] = "HIT",
		["trefferchance mit allen zaubern und angriffen"] = "HIT",
		["kritische trefferchance mit allen angriffen und zaubern"] = "CRIT",
		["kritische trefferchance mit allen zaubern und angriffen"] = "CRIT",
	},
}
local PERCENTAGE_POINTS = {
	DODGE = true, PARRY = true, BLOCK = true, HIT = true, SHIT = true, CRIT = true, SCRIT = true, HASTE = true, SHASTE = true,
}

local function DirectBonus(description, german)
	local text = description:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
	local verb, stat, value
	if german then
		verb, stat, value = text:match("^(%S+) (.-) um (.+)$")
		if verb ~= "erhöht" and verb ~= "verbessert" then
			return nil
		end
		stat = stat:gsub("^eure[nms]? ", ""):gsub("^euer ", ""):gsub("^die ", ""):gsub("^den ", "")
		stat = stat:gsub("^deine?[nms]? ", ""):gsub("^gesamte[nms]? ", "")
		value = value:gsub("^zusätzlich ", "")
	else
		verb, stat, value = text:match("^(%S+) (.-) by (.+)$")
		if verb ~= "increases" and verb ~= "improves" then
			return nil
		end
		stat = stat:gsub("^your ", ""):gsub("^the ", "")
		stat = stat:gsub("^total ", "")
		value = value:gsub("^an additional ", "")
	end
	local key = STAT_PHRASES[german][stat]
	local amount, percent = value:match("^(%d+[.,]?%d*)%s*(%%?)%.?$")
	if key and amount then
		return key, Number(amount), percent == "%"
	end
end

-- Score only what changes with one point. Percent bonuses to primary stats are estimated
-- using the current character stats. Chances are already in the scorer's percentage-point units.
function Summary.RankGain(previous, description, weights, stats, german)
	local key, amount, percent = DirectBonus(description, german)
	if not amount then
		return nil
	end
	local old = 0
	if previous then
		local previousKey, previousAmount, previousPercent = DirectBonus(previous, german)
		if key ~= previousKey or percent ~= previousPercent then
			return nil
		end
		old = previousAmount
	end
	local gain = amount - old
	if gain <= 0 or (PERCENTAGE_POINTS[key] and not percent) then
		return nil
	end
	if percent and not PERCENTAGE_POINTS[key] then
		gain = gain * (stats[key] or 0) / 100
	end
	local weight = key == "HASTE" and (weights.HASTE or 0) or ns.SharedStatWeight(weights, key)
	return gain > 0 and gain * weight or nil
end
