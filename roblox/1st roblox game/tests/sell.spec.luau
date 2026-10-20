-- The SELL stall (TODO 9): the price math and the SellPlants request check (Selling, pure), the stall in
-- the generated map and in the committed map/World.rbxm. PlotService.sellPlants is a thin wrapper
-- (distance to WorldBuilder.sellPoints, models, pushes) that can't run under Lune (no prompt events).
local H = require("./harness")
local MapTool = require("../tools/map_tool")
local Config = H.shared("Config")
local Selling = H.server("Selling")
local ProfileStore = H.server("ProfileStore")
local WorldBuilder = H.server("WorldBuilder")
local Vector3 = H.Vector3
local Enum = require("@lune/roblox").Enum

local NOW = 1_800_000_000
local NEAR = 5 -- studs from the stall: close enough

local function plant(slot: number, zone: number, rarity: number, age: number, mutation: string?): ProfileStore.Plant
	return { slot = slot, zone = zone, rarity = rarity, mutation = mutation, plantedAt = NOW - age }
end

-- The base $/s PlotService.plantStats gives a plant (what refreshIncome sums up).
local function income(p: ProfileStore.Plant): number
	local weight = Config.plantWeight(p.zone, p.rarity, NOW - p.plantedAt, Config.plantVariance(p.plantedAt, p.slot))
	return Config.plantIncome(p.zone, p.rarity, weight, p.mutation)
end

local function profileWith(plants: { ProfileStore.Plant }): ProfileStore.Profile
	local profile = ProfileStore.defaultProfile()
	profile.money = 1000
	profile.plants = plants
	return profile
end

local function totalIncome(profile: ProfileStore.Profile): number
	local sum = 0
	for _, p in profile.plants do
		sum += income(p)
	end
	return sum
end

H.test("sell: the stall pays SELL_STALL_SECONDS of the plant's income x the money multiplier", function()
	H.ok(Config.SELL_STALL_SECONDS <= 10 * 60, "only minutes of what the plant earns by staying")
	local mult = Config.moneyMult(7, true) -- plot level 7 and the 2x Money pass
	for zone = 1, #Config.ZONES do
		for rarity = 1, #Config.RARITIES do
			for _, mutation in { nil, "Gold" } :: { string? } do
				for _, age in { 0, 600, 3 * 3600 } do
					local p = plant(3, zone, rarity, age, mutation)
					local want = income(p) * Config.SELL_STALL_SECONDS * mult
					H.near(Selling.price(p, NOW, mult), want, want * 1e-9, `zone {zone} rarity {rarity} {mutation or "-"} age {age}`)
				end
			end
		end
	end
	-- Grown plants sell for more than sprouts, rarer for more than commoner, and the multiplier scales it.
	local sprout, grown = plant(1, 4, 2, 0), plant(1, 4, 2, 3 * 3600)
	H.ok(Selling.price(grown, NOW, 1) > Selling.price(sprout, NOW, 1), "grown > sprout")
	H.ok(Selling.price(plant(1, 4, 3, 0), NOW, 1) > Selling.price(plant(1, 4, 2, 0), NOW, 1), "Rare > Uncommon")
	H.near(Selling.price(grown, NOW, 2.5), Selling.price(grown, NOW, 1) * 2.5, 1e-6, "x the money multiplier")
end)

H.test("sell: selling removes the plants, pays their price, frees the slots and lowers the income", function()
	local plants = { plant(1, 1, 1, 100), plant(2, 2, 3, 5000, "Gold"), plant(4, 3, 2, 50), plant(5, 1, 1, 9000) }
	local profile = profileWith(plants)
	local mult = Config.moneyMult(3, false)
	local want = Selling.price(plants[1], NOW, mult) + Selling.price(plants[3], NOW, mult)
	local incomeBefore = totalIncome(profile)
	local soldIncome = income(plants[1]) + income(plants[3])

	local sale = Selling.sell(profile, { 4, 1 }, NEAR, NOW, mult)
	H.ok(sale, "sold")
	H.eq(#sale.slots, 2)
	H.eq(sale.slots[1], 4, "in request order")
	H.eq(sale.slots[2], 1)
	H.near(sale.total, want, 1e-6, "total")
	H.near(profile.money, 1000 + want, 1e-6, "paid")
	H.eq(#profile.plants, 2, "two plants left")
	for _, p in profile.plants do
		H.ok(p.slot == 2 or p.slot == 5, `slot {p.slot} kept`)
	end
	H.near(totalIncome(profile), incomeBefore - soldIncome, 1e-9, "the income the payout loop sees drops by the sold plants")
	-- The freed slots are free again, and selling them again does nothing.
	local again, why = Selling.sell(profile, { 1, 4 }, NEAR, NOW, mult)
	H.eq(again, nil)
	H.eq(why, "none")
	H.near(profile.money, 1000 + want, 1e-6, "nothing paid twice")
end)

H.test("sell: a slot named twice in one request is sold once", function()
	local plants = { plant(1, 5, 4, 2000), plant(2, 5, 1, 2000) }
	local profile = profileWith(plants)
	local price = Selling.price(plants[1], NOW, 1)
	local sale = Selling.sell(profile, { 1, 1, 1, 1 }, NEAR, NOW, 1)
	H.ok(sale, "sold")
	H.eq(#sale.slots, 1)
	H.near(sale.total, price, 1e-6, "paid once")
	H.near(profile.money, 1000 + price, 1e-6)
	H.eq(#profile.plants, 1)
	H.eq(profile.plants[1].slot, 2)
end)

H.test("sell: only your own plants, real slots and a plain list; nothing changes on a refused request", function()
	local function fresh()
		return profileWith({ plant(1, 2, 2, 100), plant(3, 2, 1, 100) })
	end
	local cases: { { any } } = {
		{ "not a table", 3, "bad" },
		{ "string slots", { "1" }, "bad" },
		{ "fractional slot", { 1.5 }, "bad" },
		{ "NaN slot", { 0 / 0 }, "bad" },
		{ "a map, not a list", { a = 1 }, "bad" },
		{ "holes", { [1] = 1, [3] = 3 }, "bad" },
		{ "too many", table.create(Selling.MAX_SLOTS + 1, 1), "bad" },
		{ "empty", {}, "none" },
		{ "slots with no plant (another player's, or sold)", { 2, 7, 40, -1, math.huge }, "none" },
	}
	for _, case in cases do
		local profile = fresh()
		local sale, why = Selling.sell(profile, case[2], NEAR, NOW, 1)
		H.eq(sale, nil, case[1])
		H.eq(why, case[3], case[1])
		H.eq(profile.money, 1000, case[1] .. ": no money")
		H.eq(#profile.plants, 2, case[1] .. ": no plant removed")
	end
	-- Unknown slots mixed with real ones: only the real ones sell.
	local profile = fresh()
	local sale = Selling.sell(profile, { 9, 3, 2 }, NEAR, NOW, 1)
	H.ok(sale and #sale.slots == 1 and sale.slots[1] == 3, "only slot 3")
	H.eq(#profile.plants, 1)
	-- A full plot with the ExtraSlots pass fits in one request.
	local all, slots = {}, {}
	for s = 1, Selling.MAX_SLOTS do
		table.insert(all, plant(s, 1, 1, 10))
		table.insert(slots, s)
	end
	profile = profileWith(all)
	H.ok(Selling.sell(profile, slots, NEAR, NOW, 1), "every slot at once")
	H.eq(#profile.plants, 0)
end)

H.test("remove (RemovePlant, the Plants panel): only one of your own plants, by a whole slot number; into the inventory, never money", function()
	local Inventory = H.server("Inventory")
	local mine = profileWith({ plant(1, 2, 3, 600), plant(2, 4, 1, 3600, "Gold") })
	local theirs = profileWith({ plant(5, 1, 1, 60) })
	-- refused: nothing changes
	for _, bad in { "1", 1.5, 0 / 0, math.huge, {}, true } :: { any } do
		local entry, why = Inventory.take(mine, bad, NOW)
		H.eq(entry, nil, `slot {tostring(bad)}`)
		H.eq(why, "bad", `slot {tostring(bad)}`)
	end
	local entry, why = Inventory.take(mine, 5, NOW) -- another player's plant (not in your profile)
	H.eq(entry, nil)
	H.eq(why, "none")
	H.eq(#mine.plants, 2, "nothing removed")
	H.eq(#theirs.plants, 1, "theirs untouched")
	-- your plant: off the plot, into your inventory, no money
	H.ok(Inventory.take(mine, 2, NOW) ~= nil)
	H.eq(#mine.plants, 1)
	H.eq(mine.plants[1].slot, 1)
	H.eq(#mine.inventory, 1)
	H.eq(mine.money, 1000, "Remove never pays")
	H.eq(select(2, Inventory.take(mine, 2, NOW)), "none", "gone: a second click removes nothing")
	-- the remote: its own RemoteEvent, rate-limited, through Inventory.take; no Remove prompt on the plants
	local fs = require("@lune/fs")
	local net = fs.readFile("src/server/Net.luau")
	local plot = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(net, "RemovePlant = remote(\"RemovePlant\")", 1, true) ~= nil, "Net.RemovePlant")
	H.ok(string.find(plot, "Net.RemovePlant.OnServerEvent:Connect(PlotService.removePlant)", 1, true) ~= nil, "PlotService handles it")
	H.ok(string.find(plot, "not Sessions.allowRequest(s, REMOVES_PER_SECOND)", 1, true) ~= nil, "rate-limited")
	H.ok(string.find(plot, "Inventory.take(s.profile, slot, now, Sessions.growMult(s))", 1, true) ~= nil, "checked against your own profile")

	local a = string.find(plot, "local function buildPlantModel", 1, true)
	local b = string.find(plot, "local function removePlantModel", 1, true)
	local build = a and b and string.sub(plot, a, b) or ""
	H.ok(build ~= "" and not string.find(build, "ProximityPrompt", 1, true) and not string.find(build, "\"Remove\"", 1, true), "no Remove prompt on plants")
	H.ok(not string.find(plot, "KeyCode.R\n", 1, true) and not string.find(plot, "KeyCode.R\r", 1, true), "no R key")
end)

H.test("sell: only at the SELL stall (within SELL_STALL_DISTANCE of its prompt part)", function()
	for _, case in { { nil, "no stall in the map" }, { Config.SELL_STALL_DISTANCE + 0.5, "too far" }, { math.huge, "no character" }, { 0 / 0, "NaN" } } do
		local profile = profileWith({ plant(1, 1, 1, 10) })
		local sale, why = Selling.sell(profile, { 1 }, case[1], NOW, 1)
		H.eq(sale, nil, case[2])
		H.eq(why, "far", case[2])
		H.eq(#profile.plants, 1, case[2])
	end
	H.ok(Selling.check(profileWith({ plant(1, 1, 1, 10) }), { 1 }, Config.SELL_STALL_DISTANCE), "right at the limit is fine")
end)

-- The generated map's SELL stall
local function sellStall(world: any): (any?, any?)
	local plaza = world:FindFirstChild("ShopPlaza")
	for _, d in plaza:GetDescendants() do
		if d:IsA("ProximityPrompt") and d:GetAttribute("OpensShop") == "Sell" then
			return d, plaza
		end
	end
	return nil, plaza
end

H.test("sell: the shop plaza has a SELL stall: asset slot, prompt, green circle in front, big red SELL text", function()
	WorldBuilder.build()
	local world = H.workspace:FindFirstChild("World")
	local prompt, plaza = sellStall(world)
	H.ok(prompt, "a prompt with OpensShop = Sell")
	H.eq(prompt.HoldDuration, 0)
	H.ok(prompt.MaxActivationDistance <= Config.SELL_STALL_DISTANCE, "the prompt opens where selling works")
	local host = prompt.Parent
	local points = WorldBuilder.sellPoints(world)
	H.eq(#points, 1, "one SELL stall")
	H.eq(points[1], host, "sellPoints finds its prompt part")

	local stall = plaza:FindFirstChild("ShopStall_Sell")
	H.ok(stall and stall:IsA("Model") and stall:GetAttribute("AssetSlot") == "ShopStall_Sell", "the ShopStall_Sell asset slot")
	local red, white = 0, 0
	for _, d in stall:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Awning" then
			if d.Color.R > 0.8 and d.Color.G < 0.3 then
				red += 1
			elseif d.Color.R > 0.9 and d.Color.G > 0.9 and d.Color.B > 0.9 then
				white += 1
			end
		end
	end
	H.ok(red >= 3 and white >= 3, `red-and-white striped awning ({red} red, {white} white)`)

	-- The glowing circle: on the floor, in front of the counter (toward the walkway), close enough to sell from.
	local circle = plaza:FindFirstChild("SellCircle")
	H.ok(circle and circle.Material == Enum.Material.Neon and circle.CanCollide == false, "a non-colliding Neon circle")
	H.ok(circle.Color.G > 0.9 and circle.Color.R < 0.5, "green")
	H.ok(math.abs(circle.CFrame.Position.Y - Config.GROUND_Y) < 1, "on the floor")
	H.ok(math.abs(circle.CFrame.Position.Z) < math.abs(host.CFrame.Position.Z), "in front of the counter")
	H.ok((circle.CFrame.Position - host.CFrame.Position).Magnitude + circle.Size.Y / 2 <= Config.SELL_STALL_DISTANCE, "all of it is within selling range")

	local sign
	for _, d in plaza:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "SELL" then
			sign = d
		end
	end
	H.ok(sign, "a SELL label")
	H.ok(sign.TextColor3.R > 0.8 and sign.TextColor3.G < 0.3, "in red")
	H.ok(sign:FindFirstChildOfClass("UIStroke").Thickness >= 4, "with a thick outline")
	H.ok(sign.Parent:IsA("BillboardGui") and sign.Parent.Adornee.CFrame.Position.Y > host.CFrame.Position.Y + 10, "floating above the stall")

	-- Standing in the circle sells; standing at the next stall (the Index) doesn't.
	local profile = profileWith({ plant(1, 1, 1, 10) })
	H.ok(Selling.check(profile, { 1 }, (circle.CFrame.Position + Vector3.new(0, 3, 0) - host.CFrame.Position).Magnitude), "from the circle")
	local index
	for _, d in plaza:GetDescendants() do
		if d:IsA("ProximityPrompt") and d:GetAttribute("OpensShop") == "Index" then
			index = d.Parent
		end
	end
	H.eq(Selling.check(profile, { 1 }, (index.CFrame.Position - host.CFrame.Position).Magnitude), nil, "not from the Index stall")
end)

H.test("sell: the four stalls fit the plaza side by side", function()
	local world = H.workspace:FindFirstChild("World")
	local plaza = world:FindFirstChild("ShopPlaza")
	local floor = plaza:FindFirstChild("Plaza")
	local spans = {}
	for _, name in { "ShopStall_Shop", "ShopStall_Trails", "ShopStall_Index", "ShopStall_Sell" } do
		local stall = plaza:FindFirstChild(name)
		H.ok(stall, name)
		local lo, hi = math.huge, -math.huge
		for _, d in stall:GetDescendants() do
			if d:IsA("BasePart") then
				lo = math.min(lo, d.CFrame.Position.X - d.Size.X / 2)
				hi = math.max(hi, d.CFrame.Position.X + d.Size.X / 2)
			end
		end
		H.ok(lo >= floor.CFrame.Position.X - floor.Size.X / 2 - 0.5 and hi <= floor.CFrame.Position.X + floor.Size.X / 2 + 0.5, `{name} inside the plaza`)
		table.insert(spans, { lo, hi, name })
	end
	table.sort(spans, function(a, b)
		return a[1] < b[1]
	end)
	for i = 2, #spans do
		H.ok(spans[i][1] > spans[i - 1][2], `{spans[i - 1][3]} and {spans[i][3]} don't overlap`)
	end
end)

H.test("sell: the committed map/World.rbxm has the SELL stall", function()
	local world = MapTool.load(MapTool.PATH)
	local points = WorldBuilder.sellPoints(world)
	H.eq(#points, 1, "one SELL stall in map/World.rbxm")
	local plots = WorldBuilder.adopt(world)
	H.ok(plots, "and the map still validates")
	H.ok(world.ShopPlaza:FindFirstChild("SellCircle"), "with its circle")
	H.ok(world.ShopPlaza:FindFirstChild("ShopStall_Sell"), "and its stall")
end)

----------------------------------------------------------------------------------------------------
-- Spamming Sell (owner bug report 2026-10-15: "spam Sell too fast and you sell the same plant/seed several
-- times till it disappears"): the server pays once (security.spec drives the real handler), and the window
-- drops what it has asked to sell at once (SellPick's pending), instead of showing it until the next push.
----------------------------------------------------------------------------------------------------
local SellPick = H.shared("SellPick")
local fs = require("@lune/fs")

local function sellStats(): any
	return {
		plotLevel = 1, passes = {},
		plants = { { slot = 1, zone = 1, rarity = 1, sell = 10 }, { slot = 2, zone = 1, rarity = 2, sell = 20 } },
		inventory = { { id = 7, zone = 1, rarity = 1, sell = 5 } },
		seedBag = { ["1:1#5"] = 2, ["1:1#9"] = 1, ["2:2#3"] = 1 },
	}
end

local function find(items: { any }, key: string): any
	for _, it in items do
		if it.key == key then
			return it
		end
	end
	return nil
end

H.test("sell spam: what was asked to sell drops out of the window at once; a repeat click sells nothing", function()
	local stats = sellStats()
	local pending = SellPick.newPending()
	local T = 100
	-- what HUD's sellNow does: sale of the unsold items, mark it, fire
	local fired = {}
	local function click(pick: any)
		local items = SellPick.items(stats)
		local sale = SellPick.sale(SellPick.unsold(items, pending), pick)
		if sale.count > 0 then
			SellPick.markSold(pending, items, sale, T)
			table.insert(fired, sale)
		end
		return sale
	end
	-- a plant: ten fast clicks, one request
	for _ = 1, 10 do
		click({ key = "p1" })
	end
	H.eq(#fired, 1, "the plant is asked for once")
	H.deepEq(fired[1].slots, { 1 })
	H.eq(find(SellPick.unsold(SellPick.items(stats), pending), "p1"), nil, "its card is gone at once")
	-- an inventory plant
	for _ = 1, 10 do
		click({ key = "i7" })
	end
	H.eq(#fired, 2, "the inventory plant once")
	H.eq(find(SellPick.unsold(SellPick.items(stats), pending), "i7"), nil)
	-- seeds: Sell 1 three times sells the three there are, then nothing; the card counts down and goes
	click({ key = "s1:1", count = 1 })
	H.eq(find(SellPick.unsold(SellPick.items(stats), pending), "s1:1").count, 2, "x3 -> x2 at once")
	click({ key = "s1:1", count = 1 })
	click({ key = "s1:1", count = 1 })
	H.eq(find(SellPick.unsold(SellPick.items(stats), pending), "s1:1"), nil, "all three asked: the card is gone")
	for _ = 1, 10 do
		click({ key = "s1:1", count = 1 })
		click({ key = "s1:1" })
	end
	H.eq(#fired, 5, "never more seeds asked than the bag holds")
	local asked = 0
	for _, sale in fired do
		asked += sale.seeds["1:1"] or 0
	end
	H.eq(asked, 3)
	-- quick sells count from the pending-adjusted list
	local quick = SellPick.sale(SellPick.unsold(SellPick.items(stats), pending), { group = "All" })
	H.deepEq(quick.slots, {}, "the quick sell never takes a planted plant")
	H.deepEq(quick.ids, {}, "and the pending inventory plant")
	H.deepEq(quick.seeds, { ["2:2"] = 1 }, "and the pending seeds")
	H.eq(quick.count, 1)
	-- the server's push confirms part of it: the seeds still outstanding stay hidden
	stats.seedBag = { ["1:1#9"] = 1, ["2:2#3"] = 1 } -- two of the three sold so far
	stats.plants = { { slot = 2, zone = 1, rarity = 2, sell = 20 } } -- the plant is gone
	SellPick.settle(pending, SellPick.items(stats), T + 0.5)
	H.eq(pending.slots[1], nil, "the plant's sale is confirmed")
	H.ok(pending.ids[7] ~= nil, "the inventory plant still pending (the push still has it)")
	H.eq(find(SellPick.unsold(SellPick.items(stats), pending), "i7"), nil, "so still hidden")
	H.ok(pending.seeds["1:1"] ~= nil, "one seed still outstanding")
	H.eq(find(SellPick.unsold(SellPick.items(stats), pending), "s1:1"), nil, "the last seed stays hidden")
	stats.seedBag = { ["2:2#3"] = 1 }
	stats.inventory = {}
	H.ok(SellPick.settle(pending, SellPick.items(stats), T + 1), "everything confirmed")
	H.eq(next(pending.slots), nil)
	H.eq(next(pending.ids), nil)
	H.eq(next(pending.seeds), nil)
	-- a new seed of that kind later shows and sells normally
	stats.seedBag["1:1#4"] = 1
	H.eq(find(SellPick.unsold(SellPick.items(stats), pending), "s1:1").count, 1, "a new seed shows")
end)

H.test("sell spam: what the server never confirms (refused: too far) shows again after a few seconds; a new seed mid-sale counts", function()
	local stats = sellStats()
	local pending = SellPick.newPending()
	local items = SellPick.items(stats)
	SellPick.markSold(pending, items, SellPick.sale(items, { key = "p2" }), 10)
	SellPick.markSold(pending, items, SellPick.sale(items, { key = "s2:2" }), 10)
	H.ok(not SellPick.settle(pending, SellPick.items(stats), 10 + SellPick.PENDING_SECONDS - 0.5), "waiting for the push")
	H.eq(find(SellPick.unsold(SellPick.items(stats), pending), "p2"), nil)
	H.ok(SellPick.settle(pending, SellPick.items(stats), 10 + SellPick.PENDING_SECONDS), "not confirmed in time")
	H.ok(find(SellPick.unsold(SellPick.items(stats), pending), "p2") ~= nil, "the plant shows again")
	H.ok(find(SellPick.unsold(SellPick.items(stats), pending), "s2:2") ~= nil, "the seed too")
	H.ok(SellPick.PENDING_SECONDS >= 3 and SellPick.PENDING_SECONDS <= 10, "a few seconds")
	-- selling 2 of 3 seeds while a pack adds one: the count is right throughout, then confirmed
	stats = sellStats()
	pending = SellPick.newPending()
	items = SellPick.items(stats)
	SellPick.markSold(pending, items, SellPick.sale(items, { key = "s1:1", count = 2 }), 20)
	stats.seedBag["1:1#5"] = 3 -- a pack's seed arrives before the sale lands: 4 held
	SellPick.settle(pending, SellPick.items(stats), 20.2) -- (the push)
	H.eq(find(SellPick.unsold(SellPick.items(stats), pending), "s1:1").count, 2, "4 held, 2 being sold")
	stats.seedBag["1:1#5"] = 1 -- the sale lands: 2 held
	H.ok(SellPick.settle(pending, SellPick.items(stats), 20.5), "confirmed")
	H.eq(find(SellPick.unsold(SellPick.items(stats), pending), "s1:1").count, 2, "2 left")
	H.eq(next(pending.seeds), nil)
end)

H.test("sell spam: the HUD's Sell window lists, sells and counts its quick sells from the pending-adjusted items", function()
	local hud = string.gsub(fs.readFile("src/client/HUD.client.luau"), "\r", "")
	local a = string.find(hud, "-- SELL window (TODO 9", 1, true)
	local b = string.find(hud, "end of SELL", 1, true)
	local block = string.sub(hud, a :: number, b :: number)
	H.ok(string.find(block, "local sellSold = SellPick.newPending()", 1, true) ~= nil, "a pending list")
	H.ok(string.find(block, "return SellPick.unsold(SellPick.items(stats), sellSold)", 1, true) ~= nil, "sellItems: without what is pending")
	local sellNow = string.match(block, "local function sellNow%(pick: any%).-\n\tend\n") or ""
	H.ok(string.find(sellNow, "local sale = SellPick.sale(SellPick.unsold(items, sellSold), pick)", 1, true) ~= nil, "a repeat click on a pending item sells nothing")
	local mark = string.find(sellNow, "SellPick.markSold(sellSold, items, sale, os.clock())", 1, true)
	local fire = string.find(sellNow, "SellPlants:FireServer(sale.slots, sale.ids, sale.seeds)", 1, true)
	H.ok(mark and fire and mark < fire, "marked pending as it is sent")
	H.ok(string.find(sellNow, "task.delay(SellPick.PENDING_SECONDS + 0.1, function()", 1, true) ~= nil, "unconfirmed: shown again")
	H.ok(string.find(block, "local list = sellItems() -- (the quick sells count from it too)", 1, true) ~= nil, "the window lists the unsold items")
	H.ok(string.find(block, "quickButton(row, group, list)", 1, true) ~= nil, "quick sells from that list")
	H.ok(string.find(block, "local sale = SellPick.sale(sellItems(), pending)", 1, true) ~= nil, "the confirm bar too")
	H.ok(string.find(block, "SellPick.settle(sellSold, SellPick.items(stats), os.clock()) -- (what the push confirms is sold)", 1, true) ~= nil,
		"each push settles what it confirms")
	-- nothing in the window reads the raw items except through sellItems / settle / sellNow
	local _, raw = string.gsub(block, "SellPick%.items%(stats%)", "")
	H.eq(raw, 4, "sellItems, sellNow, its timeout and the push's settle")
end)
