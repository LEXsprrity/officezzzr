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

H.test("sell: the stall pays SELL_STALL_SECONDS of the plant's income x the money multiplier, more than the R refund", function()
	H.ok(Config.SELL_STALL_SECONDS > Config.SELL_SECONDS, "walking to the stall is worth it")
	H.ok(Config.SELL_STALL_SECONDS <= 10 * 60, "but it is only minutes of what the plant earns by staying")
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
	H.near(Selling.price(grown, NOW, 1) / (income(grown) * Config.SELL_SECONDS), Config.SELL_STALL_SECONDS / Config.SELL_SECONDS, 1e-9,
		"stall vs refund ratio")
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
