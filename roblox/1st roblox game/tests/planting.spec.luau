-- Free planting (Shared/Planting): players plant anywhere on their own plot's dirt beds. The placement
-- rules the server checks (on a bed of your own plot, spacing by full-grown size, reach, the slot limit),
-- old saves' fixed slots moved onto the beds, auto-placing, and selling/removing by plant id. Runs on the
-- generated map (world.spec builds it) and on the committed map/World.rbxm.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local H = require("./harness")
local MapTool = require("../tools/map_tool")

local Config = H.shared("Config")
local Planting = H.shared("Planting")
local ProfileStore = H.server("ProfileStore")
local Selling = H.server("Selling")
local WorldBuilder = H.server("WorldBuilder")
local Vector3 = H.Vector3

local function plots(): { any }
	local world = H.workspace:FindFirstChild("World")
	local list = WorldBuilder.adopt(world)
	assert(list, "the generated map adopts")
	return list
end

-- A world point on `plot`'s bed `b`, at (x, z) in the plot's space, on the bed's top.
local function onBed(plot: any, x: number, z: number): Vector3
	local p = Planting.toWorld(plot.origin, x, z)
	return Vector3.new(p.X, plot.beds[1].CFrame.Position.Y + plot.beds[1].Size.Y / 2, p.Z)
end

local function query(plot: any, pos: Vector3, extra: { [string]: any }?): any
	local q = { beds = plot.beds, origin = plot.origin, plants = {}, pos = pos, rarity = 1, root = pos + Vector3.new(0, 3, 4), limit = 5 }
	for k, v in extra or {} do
		q[k] = v
	end
	return q
end

H.test("planting: anywhere on your own dirt beds; not on the path, the grass, the fence line or the edge", function()
	local plot = plots()[1]
	for _, spot in { { 13, 0 }, { -13, 30 }, { 37.5, -37.5 }, { -25, -10 }, { 20.3, 4.7 } } do
		local ok, why = Planting.check(query(plot, onBed(plot, spot[1], spot[2])))
		H.ok(ok, `({spot[1]}, {spot[2]}) on a bed: {why}`)
	end
	-- the middle path, outside the plot, the beds' edges (a plant's centre keeps PLANT_BED_MARGIN of dirt)
	for _, spot in { { 0, 0 }, { 5, 20 }, { 8.9, 0 }, { 50, 0 }, { 13, 60 }, { 40.4, 0 }, { 13, 40.4 } } do
		local ok, why = Planting.check(query(plot, onBed(plot, spot[1], spot[2])))
		H.eq(ok, false, `({spot[1]}, {spot[2]}) refused`)
		H.eq(why, "bed")
	end
	-- way above or below a bed doesn't count either
	H.eq(select(2, Planting.check(query(plot, onBed(plot, 13, 0) + Vector3.new(0, 20, 0)))), "bed")
end)

H.test("planting: only YOUR plot's beds (a spot on another plot is refused)", function()
	local all = plots()
	local mine, theirs = all[1], all[3]
	local ok = Planting.check(query(mine, onBed(theirs, 13, 0), { root = onBed(theirs, 13, 0) }))
	H.eq(ok, false, "planting on plot 3's dirt with plot 1's beds")
	local _, why = Planting.check(query(mine, onBed(theirs, 13, 0), { root = onBed(theirs, 13, 0) }))
	H.eq(why, "bed")
	-- the server only ever checks against the planter's own plot (plotOf(player))
	local source = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(source, "beds = state.info.beds, -- only this player's own plot", 1, true) ~= nil, "PlotService passes the player's own beds")
	H.ok(string.find(source, "local state = plotOf(player)", 1, true) ~= nil, "...of the plot the player owns")
end)

H.test("planting: spacing by full-grown size (bigger rarities need more room)", function()
	local plot = plots()[2]
	local planted = { { x = 20, z = 0, rarity = 1, slot = 1 } }
	local need = Planting.minDistance(1, 1)
	H.ok(Planting.check(query(plot, onBed(plot, 20, need + 0.01), { plants = planted })), "just far enough")
	local ok, why = Planting.check(query(plot, onBed(plot, 20, need - 0.1), { plants = planted }))
	H.eq(ok, false)
	H.eq(why, "close")
	-- a Legendary next to it needs more room than a Common
	H.ok(Planting.minDistance(1, 5) > Planting.minDistance(1, 1), "Legendary reach is bigger")
	H.eq(select(2, Planting.check(query(plot, onBed(plot, 20, need + 0.01), { plants = planted, rarity = 5 }))), "close")
	-- spacing is flat (x/z in the plot's space), whatever the height
	H.eq(select(2, Planting.check(query(plot, onBed(plot, 20, 1) + Vector3.new(0, 1, 0), { plants = planted }))), "close")
	-- re-placing a plant ignores itself
	H.ok(Planting.check(query(plot, onBed(plot, 20, 0.5), { plants = planted, ignore = 1 })), "ignore")
end)

H.test("planting: the slot limit (plot level + pass) and the planter's reach", function()
	local plot = plots()[1]
	local five = {}
	for i = 1, 5 do
		local x, z = Planting.legacySpot(i)
		table.insert(five, { x = x, z = z, rarity = 1, slot = i })
	end
	local pos = onBed(plot, 13, 30)
	H.eq(select(2, Planting.check(query(plot, pos, { plants = five, limit = 5 }))), "full")
	H.ok(Planting.check(query(plot, pos, { plants = five, limit = 6 })), "a level up gives room")
	-- reach: flat distance from where the planter stands
	H.ok(Planting.check(query(plot, pos, { root = pos + Vector3.new(Config.PLANT_REACH - 0.5, 4, 0) })), "at reach")
	H.eq(select(2, Planting.check(query(plot, pos, { root = pos + Vector3.new(Config.PLANT_REACH + 1, 0, 0) }))), "far")
	H.eq(select(2, Planting.check(query(plot, pos, { root = pos + Vector3.new(0, 0, 200) }))), "far", "from the corridor")
	-- every refusal has a message for the toast and the client's hint
	for _, reason in { "full", "bed", "close", "far" } do
		H.ok(type(Planting.MESSAGES[reason]) == "string", reason)
	end
end)

H.test("planting: ids are the smallest free number (the SELL stall, the remove prompt and the Plants menu use them)", function()
	H.eq(Planting.newId({}), 1)
	H.eq(Planting.newId({ { x = 0, z = 0, rarity = 1, slot = 1 }, { x = 0, z = 0, rarity = 1, slot = 3 } }), 2)
	H.eq(Planting.newId({ { x = 0, z = 0, rarity = 1, slot = 2 }, { x = 0, z = 0, rarity = 1, slot = 1 } }), 3)
	-- never above the most slots a plot can have, so ids always fit the save's bound
	local list = {}
	for i = 1, Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS - 1 do
		table.insert(list, { x = 0, z = 0, rarity = 1, slot = i })
	end
	H.eq(Planting.newId(list), Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS)
end)

H.test("planting: every old slot lands on a bed, spaced, keeping the old arrangement; auto-placing fills the beds", function()
	-- the old grid was budgeted for the base footprint (Common..Rare); the bigger Epics and Legendaries need more
	-- room, so an old save of those is spread out by settle
	local RARE = 3
	for _, plot in plots() do
		local placed = {}
		for slot = 1, Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS do
			local x, z = Planting.legacySpot(slot)
			local pos = Planting.toWorld(plot.origin, x, z)
			local ok, why = Planting.check({ beds = plot.beds, origin = plot.origin, plants = placed, pos = pos, rarity = RARE })
			H.ok(ok, `plot {plot.index} old slot {slot} at ({x}, {z}): {why}`)
			table.insert(placed, { x = x, z = z, rarity = RARE, slot = slot })
		end
	end
	-- the old grid's halves are pushed out onto the beds, rows unchanged
	local x1, z1 = Planting.legacySpot(1)
	local x8 = Planting.legacySpot(8)
	local _, z9 = Planting.legacySpot(9)
	H.ok(x1 < -Config.PLOT_PATH_WIDTH / 2 and x8 > Config.PLOT_PATH_WIDTH / 2, "left and right beds")
	H.eq(z1 - z9, Config.SLOT_SPACING, "rows SLOT_SPACING apart, as before")
	-- auto-placing keeps going until the beds are full: more room than any plot can use
	local plot = plots()[1]
	local placed = {}
	for i = 1, Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS + 20 do
		local x, z = Planting.autoPlace(plot.beds, plot.origin, placed, RARE)
		H.ok(x ~= nil, `auto-place {i}`)
		table.insert(placed, { x = x, z = z, rarity = RARE, slot = i })
	end
end)

H.test("planting: Legendaries (the big plants) stand further inside the bed and take more room", function()
	local plot = plots()[1]
	local L = #Config.RARITIES
	local edge = Config.PLOT_SIZE / 2 - Config.BED_FENCE_GAP - Config.PLANT_BED_MARGIN
	H.ok(Planting.check(query(plot, onBed(plot, edge - 0.1, 0))), "a Common by the fence")
	H.eq(select(2, Planting.check(query(plot, onBed(plot, edge - 0.1, 0), { rarity = L }))), "bed", "a Legendary by the fence")
	local inside = Config.PLOT_SIZE / 2 - Config.BED_FENCE_GAP - Planting.bedMargin(L)
	H.ok(Planting.check(query(plot, onBed(plot, inside - 0.1, 0), { rarity = L })), "a Legendary further in")
	-- even auto-placing on the old grid (settle) still fits a good number of them on one plot
	local placed = {}
	while #placed < 100 do
		local x, z = Planting.autoPlace(plot.beds, plot.origin, placed, L)
		if not x then
			break
		end
		table.insert(placed, { x = x, z = z, rarity = L, slot = #placed + 1 })
	end
	print(`        a plot's beds fit {#placed} full-grown Legendaries on the old grid`)
	H.ok(#placed >= 10, `{#placed} Legendaries`)
end)

H.test("planting: settle moves only the plants that don't fit (off a bed, overlapping), oldest id first", function()
	local plot = plots()[1]
	local plants = {
		{ slot = 1, x = 13, z = 0, rarity = 1 },
		{ slot = 2, x = 13.5, z = 0.5, rarity = 1 }, -- on top of plant 1
		{ slot = 3, x = 0, z = 0, rarity = 1 }, -- on the path
		{ slot = 4, x = -30, z = 20, rarity = 3 }, -- fine
	}
	H.eq(Planting.settle(plot.beds, plot.origin, plants), 2)
	H.eq(plants[1].x, 13, "the first one stays")
	H.eq(plants[4].x, -30, "a fine one stays")
	for i, p in plants do
		H.ok(Planting.bedAt(plot.beds, Planting.toWorld(plot.origin, p.x, p.z)) ~= nil, `plant {i} on a bed`)
		for j, q in plants do
			if i < j then
				local d = math.sqrt((p.x - q.x) ^ 2 + (p.z - q.z) ^ 2)
				H.ok(d >= Planting.minDistance(p.rarity, q.rarity) - 1e-6, `plants {i} and {j} apart`)
			end
		end
	end
	H.eq(Planting.settle(plot.beds, plot.origin, plants), 0, "settled plants stay put")
end)

H.test("planting saves: v5 slot plants get their old slot's spot; v6 round-trips spots; bad spots fall back", function()
	H.ok(ProfileStore.VERSION >= 6)
	local v5 = {
		v = 5, money = 1, speed = 2, plotLevel = 3, trails = { "Grey" }, trail = "Grey", treadmillTier = 1,
		plants = { { s = 1, z = 1, r = 1, t = 100 }, { s = 7, z = 2, r = 3, m = "Gold", t = 200 }, { s = 40, z = 7, r = 5, t = 300 } },
	}
	local p = ProfileStore.deserialize(serde.decode("json", serde.encode("json", v5)))
	H.eq(#p.plants, 3)
	for _, plant in p.plants do
		local x, z = Planting.legacySpot(plant.slot)
		H.eq(plant.x, x, `slot {plant.slot} x`)
		H.eq(plant.z, z, `slot {plant.slot} z`)
	end
	H.eq(p.plants[2].slot, 7, "the slot number stays as the id (its weight variance doesn't change)")
	H.eq(p.plants[2].mutation, "Gold")
	-- saved again (v6+), the spots come back exactly (no second migration)
	local data = ProfileStore.serialize(p)
	H.eq(data.v, ProfileStore.VERSION)
	H.eq(data.plants[1].px, p.plants[1].x)
	p.plants[1].x, p.plants[1].z = -21.25, 30.5 -- a freely placed plant
	local back = ProfileStore.deserialize(serde.decode("json", serde.encode("json", ProfileStore.serialize(p))))
	H.eq(back.plants[1].x, -21.25)
	H.eq(back.plants[1].z, 30.5)
	H.eq(back.plants[3].x, (Planting.legacySpot(40)))
	-- a v6 plant with a missing, absurd or NaN spot gets its id's old spot (PlotService settles it later)
	for _, bad in { { px = "x", pz = 1 }, { px = 1e9, pz = 0 }, { pz = 2 }, { px = 0 / 0, pz = 0 } } do
		local raw = { s = 2, z = 1, r = 1, t = 5, px = bad.px, pz = bad.pz }
		local loaded = ProfileStore.deserialize({ v = 6, plants = { raw } })
		local x, z = Planting.legacySpot(2)
		H.eq(loaded.plants[1].x, x)
		H.eq(loaded.plants[1].z, z)
	end
	-- a v5 save with spots in it (can't happen, but) is still migrated from its slots
	local odd = ProfileStore.deserialize({ v = 5, plants = { { s = 3, z = 1, r = 1, t = 5, px = 30, pz = 30 } } })
	H.eq(odd.plants[1].x, (Planting.legacySpot(3)))
end)

H.test("planting: selling and removing still go by plant id, and keep the other plants' spots", function()
	local profile = ProfileStore.defaultProfile()
	profile.plants = {
		{ slot = 1, zone = 1, rarity = 1, plantedAt = 1_799_999_000, x = 13, z = 0 },
		{ slot = 4, zone = 2, rarity = 2, plantedAt = 1_799_999_000, x = -21, z = 12 },
		{ slot = 2, zone = 1, rarity = 3, plantedAt = 1_799_999_000, x = 29, z = -20 },
	}
	local sale = Selling.sell(profile, { 4 }, 2, 1_800_000_000, 1)
	H.ok(sale ~= nil and sale.total > 0, "sold plant 4")
	H.eq(#profile.plants, 2)
	for _, p in profile.plants do
		H.ok(p.slot ~= 4, "plant 4 is gone")
		if p.slot == 2 then
			H.eq(p.x, 29)
			H.eq(p.z, -20)
		end
	end
	-- the freed id is reused by the next plant
	H.eq(Planting.newId(profile.plants :: any), 3)
	-- PlotService removes a plant's creature and its dug-soil patch by id (remove prompt and SELL stall)
	local source = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(source, "local function removePlantModel(state: PlotState, slot: number)", 1, true) ~= nil, "one helper")
	local _, uses = string.gsub(source, "removePlantModel%(state, slot%)", "")
	H.eq(uses, 2, "used by the R-key remove and the SELL stall")
end)

H.test("planting: the server checks every request; the client only previews and sends a spot", function()
	local plot = fs.readFile("src/server/PlotService.luau")
	for _, needle in {
		"function PlotService.plantAt(player: Player, pos: any, bagKey: any)",
		"typeof(pos) ~= \"Vector3\" or not finite(pos)",
		"root = root.Position,",
		"limit = Sessions.maxSlots(s),",
		"Planting.settle(state.info.beds, state.info.origin, s.profile.plants :: any)",
		"Net.LootEvent:FireClient(player, \"PlaceSeed\"",
	} do
		H.ok(string.find(plot, needle, 1, true) ~= nil, needle)
	end
	H.ok(string.find(plot, "PlantPad", 1, true) == nil and string.find(plot, "slotCFrames", 1, true) == nil, "no pad, no fixed slots")
	local shop = fs.readFile("src/server/ShopService.luau")
	H.ok(string.find(shop, "Net.PlantSeed.OnServerEvent:Connect(onPlant)", 1, true) ~= nil, "the remote is wired")
	H.ok(string.find(shop, "Sessions.allowRequest(s, PLANTS_PER_SECOND)", 1, true) ~= nil, "and rate-limited")
	local client = fs.readFile("src/client/Planting.client.luau")
	for _, needle in { "PlantSeed:FireServer(pos,", "TouchTapInWorld", "MouseButton1", "ButtonR2", "Planting.check(", "FilterType = Enum.RaycastFilterType.Include" } do
		H.ok(string.find(client, needle, 1, true) ~= nil, `client: {needle}`)
	end
end)

H.test("planting: the committed map/World.rbxm has two beds and an origin per plot", function()
	local world = MapTool.load(MapTool.PATH)
	local list = WorldBuilder.adopt(world)
	H.ok(list ~= nil, "validates")
	for i, plot in list do
		H.eq(#plot.beds, 2, `plot {i} beds`)
		local x, z = Planting.legacySpot(1)
		H.ok(Planting.bedAt(plot.beds, Planting.toWorld(plot.origin, x, z)) ~= nil, `plot {i}: old slot 1 lands on a bed`)
	end
end)

return nil
