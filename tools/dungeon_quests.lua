-- Export the instance quest relationships from a pinned AllTheThings checkout (MIT).
local att = assert(arg[1], "ATT checkout")
local here = arg[0]:match("^(.*)/[^/]*$") or "."
local loader = dofile(here .. "/att_loader.lua")

-- ATT's instance IDs for older dungeons are journal IDs, not World Map IDs.
local worldMaps = {
	[63] = 36, [64] = 33, [226] = 389, [227] = 48, [228] = 230, [229] = 229,
	[230] = 429, [231] = 90, [232] = 349, [233] = 129, [234] = 47, [236] = 329,
	[237] = 109, [238] = 34, [239] = 70, [240] = 43, [241] = 209, [246] = 289,
	[316] = 189, [760] = 249,
}

local function Walk(node, mapID)
	if type(node) ~= "table" or type(node.t) ~= "table" or node.t.u then
		return
	end
	if node.kind == "CreateInstance" then
		mapID = worldMaps[node.id] or (node.id >= 2700 and node.id < 4000 and node.id) or nil
	elseif mapID and node.kind == "CreateQuest" and type(node.id) == "number" and node.id > 0 then
		local t = node.t
		local faction = t.r == 1 and "H" or t.r == 2 and "A" or "-"
		local classes = type(t.c) == "table" and table.concat(t.c, ",") or "-"
		local level = type(t.lvl) == "number" and t.lvl or 0
		print(mapID, node.id, faction, level, classes)
	end
	for _, child in ipairs(loader.children(node)) do
		Walk(child, mapID)
	end
end

for _, root in ipairs(loader.load(att, { "Instances" })) do
	Walk(root)
end
