-- Runs the test suite: the parts in suite/ in order, in one shared environment.
-- Top-level locals that later parts use live in that environment (SHARED); every other
-- global read or write goes to _G as before. Call: cd tests && lua5.1 run.lua ..
local SHARED = {}
for _, name in ipairs({
	"BagComparisonState", "ITEMS", "IsJunkItemFn", "NewFont", "NewFrame", "compare", "frameMeta", "getW",
	"items", "itemsMod", "link", "ns", "realPopup", "root", "setuv", "trees", "upvalue", "uv", "xp",
}) do SHARED[name] = true end
local env = setmetatable({}, {
	__index = function(_, k) if SHARED[k] then return nil end return _G[k] end,
	__newindex = function(t, k, v) if SHARED[k] then rawset(t, k, v) else _G[k] = v end end,
})
for _, part in ipairs({
	"01_setup.lua",
	"02_data_capture.lua",
	"03_quests.lua",
	"04_tooltip.lua",
	"05_tooltip.lua",
	"06_dialog.lua",
	"07_dialog.lua",
	"08_dialog.lua",
	"09_solo_party.lua",
	"10_world_map.lua",
	"11_visuals.lua",
	"12_auction.lua",
	"13_observations.lua",
	"14_profession_plan.lua",
	"15_visuals.lua",
	"16_tooltip.lua",
	"17_visuals.lua",
	"18_camera.lua",
	"19_info.lua",
	"20_auction.lua",
	"21_world_reactions.lua",
	"22_auction.lua",
	"23_waypoint.lua",
}) do
	local chunk = assert(loadfile("suite/" .. part))
	setfenv(chunk, env)
	chunk(...)
end
