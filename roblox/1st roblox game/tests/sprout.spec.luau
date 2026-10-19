-- Sprouting (a fresh seed stands as a seedling, earning nothing, for Config.sproutTime before it becomes its
-- flower), "Grow now" for Robux (GrowNow10 / GrowNow30), and the SELL stall's seeds and quick sells.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("./harness")
local Vector3 = H.Vector3

local Config = H.shared("Config")
local SeedPacks = H.shared("SeedPacks")
local SellPick = H.shared("SellPick")
local ProfileStore = H.server("ProfileStore")
local Inventory = H.server("Inventory")
local Selling = H.server("Selling")
local Shop = H.server("Shop")

local NOW = 1_800_000_000

-- The server's Roblox side, mocked (the same tables as the other specs when they ran first)
local function signal(): any
	return { Connect = function(self, fn)
		self.fn = fn
	end }
end
local Marketplace = H.services.MarketplaceService or {
	UserOwnsGamePassAsync = function()
		return false
	end,
	PromptGamePassPurchase = function() end,
	PromptProductPurchase = function() end,
	PromptGamePassPurchaseFinished = signal(),
}
H.services.MarketplaceService = Marketplace
local Players = H.services.Players or {}
H.services.Players = Players
Players.GetPlayerByUserId = Players.GetPlayerByUserId or function()
	return nil
end
Players.PlayerRemoving = Players.PlayerRemoving or signal()
local Net = H.stubServer("Net", { StatsUpdate = { FireClient = function() end }, LootEvent = { FireClient = function() end }, toast = function() end })
for _, name in { "RequestBuy", "RequestUseItem", "SellPlants", "PlantSeed", "RemovePlant", "ClaimReward" } do
	Net[name] = Net[name] or { OnServerEvent = signal() }
end
Net.IncomePopup = Net.IncomePopup or { FireClient = function() end }
Net.announce = Net.announce or function() end
local toasts: { string } = {}
local realToast = Net.toast
Net.toast = function(player: any, text: string, ...)
	table.insert(toasts, text)
	return realToast(player, text, ...)
end

local Sessions = H.server("Sessions")
local SpeedLogic = H.server("SpeedLogic")
local PlotService = H.server("PlotService")
local ShopService = H.server("ShopService")
ShopService.init()

-- Sets fields for the length of fn, then puts them back.
local function with(fields: { { any } }, fn: () -> ())
	local old = {}
	for i, f in fields do
		old[i] = f[1][f[2]]
		f[1][f[2]] = f[3]
	end
	local ok, err = pcall(fn)
	for i, f in fields do
		f[1][f[2]] = old[i]
	end
	if not ok then
		error(err, 0)
	end
end

local nextId = 61000
local function player(): any
	nextId += 1
	local attributes = {}
	local p = { Name = `G{nextId}`, DisplayName = `G{nextId}`, UserId = nextId, Parent = true, Character = nil :: any }
	function p.SetAttribute(_, k: string, v: any)
		attributes[k] = v
	end
	function p.GetAttribute(_, k: string): any
		return attributes[k]
	end
	function p.FindFirstChild()
		return nil
	end
	return p
end

local function session(): any
	return Sessions.create(player(), ProfileStore.defaultProfile(), false)
end

-- A seedling planted at `at` (sprouting until at + sproutTime), as PlotService plants a fresh seed.
local function seedling(slot: number, zone: number, rarity: number, at: number, mutation: string?): any
	local untilAt = at + Config.sproutTime(zone, rarity)
	return { slot = slot, zone = zone, rarity = rarity, mutation = mutation, plantedAt = untilAt, sproutUntil = untilAt, x = 0, z = 0, variance = 1 }
end

----------------------------------------------------------------------------------------------------
-- The formula
----------------------------------------------------------------------------------------------------
H.test("sprout: time = base by rarity (30 s .. 20 min) x a zone factor rising to x2.5, rounded to 5 s; Fast Grow halves it", function()
	H.deepEq(Config.SPROUT_BASE, { 30, 60, 180, 480, 1200 })
	H.eq(Config.sproutZoneFactor(1), 1, "Meadow x1")
	H.eq(Config.sproutZoneFactor(#Config.ZONES), 2.5, "Spirit Garden x2.5")
	local rows = {}
	for k, zone in Config.ZONES do
		local cells = {}
		for r in Config.RARITIES do
			local t = Config.sproutTime(k, r)
			H.eq(t % Config.SPROUT_ROUND, 0, "whole 5 s")
			H.near(t, Config.SPROUT_BASE[r] * Config.sproutZoneFactor(k), Config.SPROUT_ROUND / 2, `{zone.id} {r}`)
			if r > 1 then
				H.ok(t > Config.sproutTime(k, r - 1), "rarer waits longer")
			end
			if k > 1 then
				H.ok(t >= Config.sproutTime(k - 1, r), "deeper waits longer")
			end
			H.near(Config.sproutTime(k, r, 2), t / 2, Config.SPROUT_ROUND / 2 + 0.01, "Fast Grow: half")
			table.insert(cells, tostring(t))
		end
		table.insert(rows, `{zone.id} {table.concat(cells, "/")}`)
	end
	print("        sprout seconds: " .. table.concat(rows, ", "))
	H.eq(Config.sproutTime(1, 1), 30)
	H.eq(Config.sproutTime(7, 5), 3000, "a Spirit Garden Legendary: 50 min")
	H.eq(Config.SPROUT_MAX, 3000)
	H.eq(Config.sproutTime(1, 1, 1000), Config.SPROUT_ROUND, "never 0")
	-- left / is sprouting
	local p = seedling(1, 2, 3, NOW)
	H.eq(Config.sproutLeft(p, NOW), Config.sproutTime(2, 3))
	H.ok(Config.isSprouting(p, NOW + 1))
	H.eq(Config.sproutLeft(p, NOW + 1e6), 0)
	H.eq(Config.sproutLeft({ sproutUntil = nil }, NOW), 0, "an old plant: sprouted")
end)

----------------------------------------------------------------------------------------------------
-- No income while sprouting; growth starts after; offline goes on
----------------------------------------------------------------------------------------------------
H.test("sprout: a seedling earns nothing; it earns from the moment it sprouts, its growth starting there", function()
	local p = seedling(1, 3, 2, NOW)
	local done = p.sproutUntil
	local w0, income = PlotService.plantStats(p, NOW)
	H.eq(income, 0, "no income while sprouting")
	H.near(w0, Config.plantWeight(3, 2, 0, 1), 1e-9, "its sprout weight")
	local _, later = PlotService.plantStats(p, done)
	H.near(later, Config.plantIncome(3, 2, Config.plantWeight(3, 2, 0, 1), nil), 1e-9, "at the end: the fresh plant's income")
	local w1 = PlotService.plantStats(p, done + 600)
	H.near(w1, Config.plantWeight(3, 2, 600, 1), 1e-9, "the growth curve starts when it sprouted")
	local profile = ProfileStore.defaultProfile()
	profile.plants = { p, { slot = 2, zone = 3, rarity = 2, plantedAt = NOW - 100, x = 0, z = 0, variance = 1 } }
	local _, grown = PlotService.plantStats(profile.plants[2], NOW)
	H.near(PlotService.incomeOf(profile, NOW), grown, 1e-9, "the plot's income leaves the seedling out")
	H.near(PlotService.liveIncomeOf(profile, NOW), grown * Config.timeMult(3, (Config.dayPhase(NOW))), 1e-9)
end)

H.test("sprout: sprouting goes on offline, and offline pay counts only the time after it sprouted", function()
	local s = session()
	local now = os.time()
	local away = 1200
	s.profile.lastSeen = now - away
	local p = seedling(1, 2, 4, now - away) -- an Epic from the Desert: 600 s
	local sprout = Config.sproutTime(2, 4)
	H.eq(sprout, 600)
	s.profile.plants = { p }
	H.eq(Config.sproutLeft(p, now), 0, "done while they were away")
	local amount = PlotService.grantOffline(s)
	local _, income = PlotService.plantStats(p, now)
	H.near(amount, income * Config.averageTimeMult(2) * Config.OFFLINE_MULT * (away - sprout) * Sessions.moneyMult(s), amount * 1e-9, "paid for the last 600 s only, at the offline share")
	-- still sprouting when they come back: nothing
	local s2 = session()
	s2.profile.lastSeen = now - 100
	s2.profile.plants = { seedling(1, 7, 5, now - 200) }
	H.eq(PlotService.grantOffline(s2), 0, "a seedling earns nothing offline")
	-- old plants are unaffected: the whole time away
	local s3 = session()
	s3.profile.lastSeen = now - 500
	s3.profile.plants = { { slot = 1, zone = 1, rarity = 1, plantedAt = now - 1000, x = 0, z = 0, variance = 1 } }
	H.near(PlotService.grantOffline(s3), PlotService.offlineIncomeOf(s3.profile, now) * 500 * Sessions.moneyMult(s3), 1e-6)
end)

H.test("sprout: a seedling taken to the inventory keeps what it had left, and sprouts on when planted again", function()
	local profile = ProfileStore.defaultProfile()
	local p = seedling(4, 5, 3, NOW) -- 360 s
	profile.plants = { p }
	local entry = Inventory.take(profile, 4, NOW + 100) :: any
	H.ok(entry ~= nil, "taken")
	H.eq(entry.sprout, Config.sproutTime(5, 3) - 100, "260 s left")
	H.eq(entry.age, 0, "no growth yet")
	-- days later: still 260 s left (it waits in the inventory)
	local later = NOW + 86400
	local back = Inventory.toPlant(entry, 9, later, 1, 2)
	H.eq(back.sproutUntil, later + 260)
	H.eq(back.plantedAt, back.sproutUntil, "growth starts when it is done")
	H.eq(Config.sproutLeft(back, later), 260)
	H.eq((PlotService.plantStats(back, later)), Config.plantWeight(5, 3, 0, 1))
	-- a grown plant has nothing to keep
	profile.plants = { { slot = 5, zone = 1, rarity = 1, plantedAt = NOW - 50, x = 0, z = 0, variance = 1 } }
	local grown = Inventory.take(profile, 5, NOW) :: any
	H.eq(grown.sprout, nil)
	H.eq(Inventory.toPlant(grown, 6, NOW, 0, 0).sproutUntil, nil)
end)

----------------------------------------------------------------------------------------------------
-- Save
----------------------------------------------------------------------------------------------------
H.test("sprout: save v12 keeps sproutUntil and the inventory's sprout; older saves' plants are fully grown", function()
	H.ok(ProfileStore.VERSION >= 12)
	local p = ProfileStore.defaultProfile()
	p.plants = { seedling(1, 2, 2, NOW), { slot = 2, zone = 1, rarity = 1, plantedAt = NOW - 10, x = 0, z = 0, variance = 1 } }
	p.inventory = { { id = 1, zone = 3, rarity = 4, age = 0, variance = 1, sprout = 123 }, { id = 2, zone = 1, rarity = 1, age = 30, variance = 1 } }
	local back = ProfileStore.deserialize(ProfileStore.serialize(p))
	H.eq(back.plants[1].sproutUntil, p.plants[1].sproutUntil)
	H.eq(back.plants[1].plantedAt, p.plants[1].plantedAt)
	H.eq(back.plants[2].sproutUntil, nil)
	H.eq(back.inventory[1].sprout, 123)
	H.eq(back.inventory[2].sprout, nil)
	-- a v11 save (no sprouting then): even a stray su is ignored, the plant is grown
	local old = ProfileStore.serialize(p)
	old.v = 11
	local migrated = ProfileStore.deserialize(old)
	for _, plant in migrated.plants do
		H.eq(plant.sproutUntil, nil, "an old plant is fully grown")
		H.eq(Config.isSprouting(plant, NOW), false)
	end
	H.eq(migrated.inventory[1].sprout, nil)
	-- junk is dropped or clamped
	local junk = ProfileStore.serialize(p)
	junk.plants[1].su = "soon"
	junk.inv[1].sp = 1e9
	local cleaned = ProfileStore.deserialize(junk)
	H.eq(cleaned.plants[1].sproutUntil, nil, "not a number: grown")
	H.eq(cleaned.inventory[1].sprout, Config.SPROUT_MAX, "clamped to the longest sprout")
	junk.plants[1].su = 0 / 0
	H.eq(ProfileStore.deserialize(junk).plants[1].sproutUntil, nil, "NaN: grown")
end)

----------------------------------------------------------------------------------------------------
-- Grow now
----------------------------------------------------------------------------------------------------
H.test("grow now: two products, picked by the time left (up to 10 min 9 R$, longer 29 R$, which finishes any)", function()
	H.eq(Config.DEVELOPER_PRODUCTS.GrowNow10.robux, 9)
	H.eq(Config.DEVELOPER_PRODUCTS.GrowNow30.robux, 19) -- owner 2026-10-16: 29 -> 19, named Skip (1) / Skip (2)
	H.eq(Config.DEVELOPER_PRODUCTS.GrowNow10.label, "Skip (1)")
	H.eq(Config.DEVELOPER_PRODUCTS.GrowNow30.label, "Skip (2)")
	H.eq(Config.DEVELOPER_PRODUCTS.GrowNow1, nil)
	H.eq(Config.DEVELOPER_PRODUCTS.GrowNow5, nil)
	H.eq(#Config.products("GrowNow"), 2)
	for _, case in { { 1, "GrowNow10" }, { 59, "GrowNow10" }, { 600, "GrowNow10" }, { 601, "GrowNow30" }, { 1800, "GrowNow30" }, { 3000, "GrowNow30" }, { 1e6, "GrowNow30" } } do
		H.eq((Config.growNowProduct(case[1])), case[2], `{case[1]} s left`)
	end
	H.eq((Config.growNowProduct(0)), nil, "grown: nothing to sell")
	H.eq((Config.growNowProduct(-5)), nil)
	H.eq((Config.growNowProduct(0 / 0)), nil)
end)

H.test("grow now: the prompt only for your own seedling, with the product its time left calls for", function()
	local p = ProfileStore.defaultProfile()
	p.plants = { seedling(1, 1, 1, NOW), seedling(2, 7, 5, NOW), { slot = 3, zone = 1, rarity = 1, plantedAt = NOW - 5, x = 0, z = 0, variance = 1 } }
	with({ { Config.DEVELOPER_PRODUCTS.GrowNow10, "id", 5001 }, { Config.DEVELOPER_PRODUCTS.GrowNow30, "id", 5002 } }, function()
		H.ok(Shop.canPrompt(p, "GrowNow10", { slot = 1, now = NOW }) ~= nil, "30 s left: GrowNow10")
		H.ok(Shop.canPrompt(p, "GrowNow30", { slot = 2, now = NOW }) ~= nil, "50 min left: GrowNow30")
		local function refused(name: string, target: any, why: string)
			local product, msg = Shop.canPrompt(p, name, target)
			H.eq(product, nil, why)
			H.ok(type(msg) == "string", why)
		end
		refused("GrowNow30", { slot = 1, now = NOW }, "the dearer tier for a short wait")
		refused("GrowNow10", { slot = 2, now = NOW }, "the cheap tier for a long wait")
		refused("GrowNow10", nil, "no plant picked (Product:GrowNow10)")
		refused("GrowNow10", { slot = 3, now = NOW }, "already grown")
		refused("GrowNow10", { slot = 99, now = NOW }, "not one of yours")
		for _, junk in { "1", 1.5, 0 / 0, math.huge, {}, -1 } do
			refused("GrowNow10", { slot = junk, now = NOW }, `junk id {tostring(junk)}`)
		end
	end)
	-- id 0: "coming soon", never prompted
	local product, why = Shop.canPrompt(p, "GrowNow10", { slot = 1, now = NOW })
	H.eq(product, nil)
	H.ok(string.find(why or "", "coming soon", 1, true) ~= nil)
end)

H.test("grow now: a receipt finishes that seedling once per PurchaseId; gone, it goes to another seedling", function()
	local p = ProfileStore.defaultProfile()
	p.plants = { seedling(1, 2, 3, NOW), seedling(2, 6, 4, NOW), { slot = 3, zone = 1, rarity = 1, plantedAt = NOW - 5, x = 0, z = 0, variance = 1 } }
	local function rng(): number
		return 0.5
	end
	local status, grant = Shop.grantProduct(p, "GrowNow10", "gn-1", 0, rng, { slot = 1, now = NOW + 10 })
	H.eq(status, "granted")
	H.eq(p.plants[1].sproutUntil, nil, "sprouted")
	H.eq(p.plants[1].plantedAt, NOW + 10, "its growth starts now")
	H.deepEq((grant :: any).grown, { 1 })
	local before = Config.sproutLeft(p.plants[2], NOW + 10)
	H.eq((Shop.grantProduct(p, "GrowNow10", "gn-1", 0, rng, { slot = 2, now = NOW + 10 })), "duplicate", "the same receipt again")
	H.eq(Config.sproutLeft(p.plants[2], NOW + 10), before, "...grows nothing more")
	-- the target already grew (or was sold): the seedling with the most time left gets the skip
	p.plants[4] = seedling(4, 1, 1, NOW)
	local _, g2 = Shop.grantProduct(p, "GrowNow10", "gn-2", 0, rng, { slot = 1, now = NOW + 10 })
	H.deepEq((g2 :: any).grown, { 2 }, "the longest seedling")
	H.eq(Config.sproutLeft(p.plants[2], NOW + 10), before - 600, "GrowNow10 skips up to 10 min of it")
	H.eq(p.plants[2].plantedAt, p.plants[2].sproutUntil, "its growth still starts when it is done")
	Shop.grantProduct(p, "GrowNow30", "gn-3", 0, rng, { slot = 3, now = NOW + 10 })
	H.eq(p.plants[2].sproutUntil, nil, "GrowNow30 finishes any seedling")
	-- no target known (the prompt was in another server): the longest seedling too
	Shop.grantProduct(p, "GrowNow30", "gn-4", 0, rng, nil)
	H.eq(Config.isSprouting(p.plants[4], NOW + 10), false)
	-- nothing on the plot: a seedling in the inventory
	p.inventory = { { id = 1, zone = 1, rarity = 1, age = 0, variance = 1, sprout = 1000 } }
	local _, g5 = Shop.grantProduct(p, "GrowNow10", "gn-5", 0, rng, { slot = 1, now = NOW + 10 })
	H.eq(p.inventory[1].sprout, 400, "10 min off the inventory seedling")
	H.ok(not (g5 :: any).wasted)
	Shop.grantProduct(p, "GrowNow30", "gn-6", 0, rng, nil)
	H.eq(p.inventory[1].sprout, nil)
	-- nothing sprouting anywhere: confirmed (paid) but nothing to do, and flagged for the log
	local status7, g7 = Shop.grantProduct(p, "GrowNow10", "gn-7", 0, rng, nil)
	H.eq(status7, "granted")
	H.eq((g7 :: any).wasted, true)
	H.eq(#p.receipts, 7, "every receipt remembered")
end)

H.test("grow now: through the remotes (RequestBuy \"GrowNow:<id>\" then ProcessReceipt), owner only", function()
	local buy = Net.RequestBuy.OnServerEvent.fn
	local process = Marketplace.ProcessReceipt
	H.ok(type(buy) == "function" and type(process) == "function", "wired")
	local owner, stranger = session(), session()
	local now = os.time()
	owner.profile.plants = { seedling(7, 3, 2, now) } -- 90 s: GrowNow10
	stranger.profile.plants = {}
	local prompted: { { any } } = {}
	with({
		{ Config.DEVELOPER_PRODUCTS.GrowNow10, "id", 5101 },
		{ Config.DEVELOPER_PRODUCTS.GrowNow30, "id", 5102 },
		{ Marketplace, "PromptProductPurchase", function(_, who: any, id: number)
			table.insert(prompted, { who, id })
		end },
		{ ShopService, "save", function(): boolean
			return true
		end },
		{ Players, "GetPlayerByUserId", function(_, id: number): any
			return if id == owner.player.UserId then owner.player elseif id == stranger.player.UserId then stranger.player else nil
		end },
	}, function()
		-- someone else's seedling, junk ids: no prompt
		for _, itemId in { "GrowNow:7", "GrowNow:", "GrowNow:-7", "GrowNow:7.5", "GrowNow:abc", "GrowNow:99999999999" } do
			stranger.requests = {}
			buy(stranger.player, itemId)
		end
		H.eq(#prompted, 0, "a stranger can't grow your plant")
		buy(owner.player, "Product:GrowNow10")
		H.eq(#prompted, 0, "never without its plant")
		owner.requests = {}
		buy(owner.player, "GrowNow:7")
		H.eq(#prompted, 1)
		H.eq(prompted[1][1], owner.player)
		H.eq(prompted[1][2], 5101, "the tier for 90 s")
		H.eq(owner.growNow.GrowNow10, 7, "remembered for the receipt")
		local GRANTED = roblox.Enum.ProductPurchaseDecision.PurchaseGranted
		local info = { PlayerId = owner.player.UserId, ProductId = 5101, PurchaseId = "grow-e2e" }
		H.eq(process(info), GRANTED)
		H.eq(owner.profile.plants[1].sproutUntil, nil, "it grew")
		H.eq(owner.growNow.GrowNow10, nil, "used")
		H.eq(process(info), GRANTED, "a repeat is confirmed...")
		H.eq(#owner.profile.receipts, 1, "...and granted once")
		-- grown now: no more prompts for it
		owner.requests = {}
		buy(owner.player, "GrowNow:7")
		H.eq(#prompted, 1)
	end)
	-- rate limit: the shop's 8 a second
	local spam = session()
	spam.profile.plants = { seedling(1, 1, 1, os.time()) }
	local count = 0
	with({ { Config.DEVELOPER_PRODUCTS.GrowNow10, "id", 5101 }, { Marketplace, "PromptProductPurchase", function()
		count += 1
	end } }, function()
		for _ = 1, 30 do
			buy(spam.player, "GrowNow:1")
		end
	end)
	H.ok(count <= 8, `rate-limited ({count} prompts)`)
end)

H.test("grow now: the seedling model, its countdown and the Grow now button (source)", function()
	local plot = fs.readFile("src/server/PlotService.luau")
	for _, needle in {
		"Seedling.build(plant.zone, plant.rarity, plant.mutation)",
		"model:SetAttribute(\"SproutUntil\", plant.sproutUntil)",
		"plant.sproutUntil = now + Config.sproutTime(zone, rarity, Sessions.growMult(s))",
		"continue -- a seedling earns nothing",
		"PlotService.popSprout(s, state, plant, now)",
	} do
		H.ok(string.find(plot, needle, 1, true) ~= nil, needle)
	end
	local client = fs.readFile("src/client/Sprouts.client.luau")
	for _, needle in { "GrowNowUi.button(gui, slot,", "model:GetAttribute(\"OwnerUserId\") == player.UserId", "UiFx.relief(count, 3, 3)",
		"(info and info.Enabled) or entry.over", "kind ~= \"Sprouted\"" } do
		H.ok(string.find(client, needle, 1, true) ~= nil, needle)
	end
	local hud = fs.readFile("src/client/HUD.client.luau")
	H.ok(string.find(hud, "GrowNowUi.button(f, slot, UDim2.fromOffset(236, 44))", 1, true) ~= nil, "the Plants card's Grow now")
	H.ok(string.find(hud, "income.Text = `Sprouting {Format.clock(math.ceil(left))}`", 1, true) ~= nil, "the Plants card's countdown")
	local ui = fs.readFile("src/shared/GrowNowUi.luau")
	H.ok(string.find(ui, "FireServer(`GrowNow:{slot}`)", 1, true) ~= nil, "asks the server, which picks the product")
	-- the seedling builds (studded blocks, an InfoAnchor up top, pivot on the ground)
	local Seedling = H.server("Seedling")
	local m = Seedling.build(2, 5, "Gold")
	H.ok(m.PrimaryPart ~= nil and m.PrimaryPart:FindFirstChild("InfoAnchor") ~= nil)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			H.eq(d.TopSurface, roblox.Enum.SurfaceType.Studs, `{d.Name} studded`)
			H.ok(not d.CanCollide and d.Anchored, `{d.Name} decoration`)
		end
	end
	H.eq((m:FindFirstChild("Bud") :: any).Color, Config.mutationById("Gold").color, "the bud in its mutation's colour")
	local body = m.PrimaryPart :: any
	H.ok(math.abs((body.CFrame * body.PivotOffset).Position.Y) < 1e-6, "pivot on the ground")
end)

----------------------------------------------------------------------------------------------------
-- The SELL stall: 10x $/s, seeds, quick sells
----------------------------------------------------------------------------------------------------
H.test("sell: a plant sells for 10x its $/s; a seed for 5 s of its sprout-weight income, always less than its plant", function()
	H.eq(Config.SELL_STALL_SECONDS, 10)
	local plant = { slot = 1, zone = 4, rarity = 3, mutation = "Gold", plantedAt = NOW - 300, x = 0, z = 0, variance = 1 }
	local _, income = PlotService.plantStats(plant :: any, NOW)
	H.near(Selling.price(plant :: any, NOW, 1.5), income * 10 * 1.5, 1e-6, "10x its $/s, x the money multiplier")
	for k in Config.ZONES do
		for r in Config.RARITIES do
			for _, m in { nil, "Gold", "Rainbow", "Celestial" } do
				local seed = Config.seedSellPrice(k, r, m, 1.3)
				local want = math.max(1, Config.plantIncome(k, r, Config.sproutWeight(k, r), m) * Config.SEED_SELL_SECONDS * 1.3)
				H.near(seed, want, want * 1e-12)
				-- planted, with the lowest variance (0.8), right as it sprouts: still worth more
				local low = { slot = 1, zone = k, rarity = r, mutation = m, plantedAt = NOW, x = 0, z = 0, variance = 0.8 }
				H.ok(seed <= Selling.price(low :: any, NOW, 1.3) or seed == 1, `zone {k} rarity {r} {m}: the seed is worth less than its plant`)
			end
		end
	end
	H.eq(Config.seedSellPrice(1, 1, nil, 0), 1, "at least $1")
end)

H.test("sell: seeds from the bag sell at the stall; only what you hold, never more; junk refused", function()
	local p = ProfileStore.defaultProfile()
	SeedPacks.addToBag(p.seedBag, 2, 1, nil, 11)
	SeedPacks.addToBag(p.seedBag, 2, 1, nil, 12)
	SeedPacks.addToBag(p.seedBag, 2, 1, nil, 12)
	SeedPacks.addToBag(p.seedBag, 3, 2, "Gold", 13)
	local unit = Config.seedSellPrice(2, 1, nil, 2)
	local sale = Selling.sell(p, {}, 1, NOW, 2, nil, nil, { ["2:1"] = 2 }) :: any
	H.ok(sale ~= nil, "sold")
	H.eq(sale.seedCount, 2)
	H.near(sale.total, unit * 2, 1e-9)
	H.eq(SeedPacks.bagCount(p.seedBag), 2, "two left")
	H.near(p.money, unit * 2, 1e-9)
	-- asking for more than held sells what there is
	local more = Selling.sell(p, {}, 1, NOW, 2, nil, nil, { ["2:1"] = 50 }) :: any
	H.eq(more.seedCount, 1, "only the one left")
	H.eq(Selling.seedsHeld(p.seedBag, "2:1"), 0)
	-- none of that seed: nothing to sell
	local none, why = Selling.sell(p, {}, 1, NOW, 2, nil, nil, { ["2:1"] = 1 })
	H.eq(none, nil)
	H.eq(why, "none")
	-- junk: refused whole, nothing changes
	local money = p.money
	for _, junk in { "2:1", 5, { ["2:1"] = 0 }, { ["2:1"] = -1 }, { ["2:1"] = 1.5 }, { ["2:1"] = 0 / 0 }, { ["3:2:Gold#13"] = 1 }, { ["9:1"] = 1 },
		{ ["3:2:Hacked"] = 1 }, { [1] = 1 }, { ["3:2:Gold"] = 1e9 } } do
		local s2, w2 = Selling.sell(p, {}, 1, NOW, 2, nil, nil, junk)
		H.eq(s2, nil, `junk {tostring(junk)}`)
		H.eq(w2, "bad")
	end
	H.eq(p.money, money)
	H.eq(Selling.seedsHeld(p.seedBag, "3:2:Gold"), 1, "still there")
	-- far from the stall: nothing
	H.eq(select(2, Selling.sell(p, {}, 99, NOW, 2, nil, nil, { ["3:2:Gold"] = 1 })), "far")
	-- plants and seeds together
	p.plants = { { slot = 1, zone = 1, rarity = 1, plantedAt = NOW - 5, x = 0, z = 0, variance = 1 } }
	local both = Selling.sell(p, { 1 }, 1, NOW, 1, nil, nil, { ["3:2:Gold"] = 1 }) :: any
	H.eq(#both.slots, 1)
	H.eq(both.seedCount, 1)
	H.eq(#p.plants, 0)
	H.eq(SeedPacks.bagCount(p.seedBag), 0)
end)

H.test("sell: quick sells per rarity and Sell all count plants, inventory plants and seeds; Legendary and (unless on) mutated kept", function()
	local stats = {
		plotLevel = 1, passes = {},
		plants = {
			{ slot = 1, zone = 1, rarity = 1, sell = 10 }, { slot = 2, zone = 1, rarity = 2, mutation = "Gold", sell = 50 },
			{ slot = 3, zone = 1, rarity = 5, sell = 999 }, { slot = 4, zone = 2, rarity = 3, sell = 70 },
		},
		inventory = { { id = 1, zone = 1, rarity = 1, sell = 7 }, { id = 2, zone = 1, rarity = 4, sell = 40 } },
		seedBag = { ["1:1#5"] = 2, ["1:1#9"] = 1, ["2:2:Gold#3"] = 1, ["1:5#2"] = 1 },
	}
	local items = SellPick.items(stats)
	local seedCommon = SellPick.seedPrice(stats, 1, 1, nil)
	local common = SellPick.sale(items, { group = "Common" })
	H.deepEq(common.slots, { 1 })
	H.deepEq(common.ids, { 1 }, "the inventory plant counts")
	H.deepEq(common.seeds, { ["1:1"] = 3 }, "seeds of one label sell as one, every gene")
	H.eq(common.count, 5)
	H.near(common.total, 10 + 7 + 3 * seedCommon, 1e-9)
	H.eq(SellPick.sale(items, { group = "Uncommon" }).count, 0, "the Gold Uncommons are kept...")
	local mutated = SellPick.sale(items, { group = "Uncommon", mutated = true })
	H.eq(mutated.count, 2, "...unless mutated are included")
	H.deepEq(mutated.seeds, { ["2:2:Gold"] = 1 })
	local all = SellPick.sale(items, { group = "All" })
	H.eq(all.count, 1 + 1 + 3 + 1 + 1, "every non-mutated, non-Legendary thing")
	for _, slot in all.slots do
		H.ok(slot ~= 3, "Legendary never quick-sold")
	end
	H.eq(all.seeds["1:5"], nil, "a Legendary seed neither")
	H.eq(SellPick.sale(items, { group = "All", mutated = true }).count, all.count + 2)
	H.eq(#SellPick.GROUPS, 5)
	H.eq(SellPick.GROUPS[5].id, "All")
	-- one seed card's Sell 1 / Sell all
	H.deepEq(SellPick.sale(items, { key = "s1:1", count = 1 }).seeds, { ["1:1"] = 1 })
	H.deepEq(SellPick.sale(items, { key = "s1:1" }).seeds, { ["1:1"] = 3 })
	H.deepEq(SellPick.sale(items, { key = "s1:1", count = 99 }).seeds, { ["1:1"] = 3 }, "never more than held")
	H.eq(SellPick.sale(items, { key = "p3" }).count, 1, "a Legendary sells from its own card")
end)

H.test("sell: a quick sell goes through the remote and sells (a player at the stall, plants, inventory and seeds)", function()
	local WorldBuilder = H.server("WorldBuilder")
	WorldBuilder.build()
	local world = H.workspace:FindFirstChild("World")
	local stalls = WorldBuilder.sellPoints(world)
	H.ok(#stalls > 0, "the map has a SELL stall")
	-- (the stalls only: the plots' boards need a real engine; Lune parts have no .Position, so stand-ins)
	local stall = { Position = stalls[1].CFrame.Position, Parent = world }
	PlotService.init({}, { stall :: any })
	local s = session()
	local p = s.profile
	p.plants = { { slot = 1, zone = 1, rarity = 1, plantedAt = os.time() - 60, x = 0, z = 0, variance = 1 },
		{ slot = 2, zone = 1, rarity = 2, mutation = "Gold", plantedAt = os.time() - 60, x = 8, z = 0, variance = 1 } }
	p.inventory = { { id = 1, zone = 2, rarity = 1, age = 30, variance = 1 } }
	SeedPacks.addToBag(p.seedBag, 1, 1, nil, 3)
	SeedPacks.addToBag(p.seedBag, 1, 1, nil, 4)
	-- standing at the stall, as the movement check saw it
	local at = stall.Position + Vector3.new(2, 0, 0)
	local root = { Name = "HumanoidRootPart", Position = at, CFrame = roblox.CFrame.new(at) }
	local hum = { Health = 100 }
	s.player.Character = {
		FindFirstChild = function(_, name: string): any
			return if name == "HumanoidRootPart" then root else nil
		end,
		FindFirstChildOfClass = function(_, class: string): any
			return if class == "Humanoid" then hum else nil
		end,
	}
	SpeedLogic.teleported(s.tracker, at)
	s.tracker.at = os.clock()
	-- what the client's Sell window sends for "Sell Common" (Shared/SellPick over the stats it was pushed)
	local now = os.time()
	local stats = { plotLevel = p.plotLevel, passes = {}, seedBag = table.clone(p.seedBag), plants = {}, inventory = {} }
	for _, plant in p.plants do
		table.insert(stats.plants, { slot = plant.slot, zone = plant.zone, rarity = plant.rarity, mutation = plant.mutation, sell = Selling.price(plant, now, 1) })
	end
	for _, e in p.inventory do
		table.insert(stats.inventory, { id = e.id, zone = e.zone, rarity = e.rarity, mutation = e.mutation, sell = Selling.price(Inventory.asPlant(e, now), now, 1) })
	end
	local sale = SellPick.sale(SellPick.items(stats), { group = "Common" })
	H.eq(sale.count, 4, "1 plant + 1 inventory plant + 2 seeds")
	s.requests = {}
	Net.SellPlants.OnServerEvent.fn(s.player, sale.slots, sale.ids, sale.seeds)
	H.eq(#p.plants, 1, "the Common sold, the Gold Uncommon kept")
	H.eq(p.plants[1].slot, 2)
	H.eq(#p.inventory, 0)
	H.eq(SeedPacks.bagCount(p.seedBag), 0)
	H.near(p.money, sale.total, sale.total * 1e-6, "paid what the window said")
end)


H.test("offline: time away pays 0.2x of playing, and the welcome-back plate gets the amount", function()
	H.eq(Config.OFFLINE_MULT, 0.2, "owner 2026-10-16")
	local s = session()
	local now = os.time()
	s.profile.lastSeen = now - 600
	s.profile.plants = { { slot = 1, zone = 2, rarity = 3, plantedAt = now - 5000, x = 0, z = 0, variance = 1 } }
	local _, income = PlotService.plantStats(s.profile.plants[1], now)
	local amount = PlotService.grantOffline(s)
	H.near(amount, income * Config.averageTimeMult(2) * 0.2 * 600 * Sessions.moneyMult(s), amount * 1e-9, "a fifth of the in-game pay")
	H.near(s.player:GetAttribute("OfflineEarned"), amount, 1e-9, "the HUD reads it on join")
	H.eq(s.player:GetAttribute("OfflineSeconds"), 600)
end)
return nil
