-- Security and validation: an exploiter owns their client (any remote with any arguments at any rate, a
-- teleported or flying character, prompts fired from anywhere, spoofed purchase reports). These are the
-- regression tests of the security audit: every remote shrugs off junk, positions the server checks are
-- ones it saw the character walk to, money can't be made twice, Robux and pass grants only follow what
-- Roblox confirms, and a profile is never written by two servers.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local H = require("./harness")
local Vector3 = H.Vector3
local Enum = roblox.Enum

local Config = H.shared("Config")
local SeedPacks = H.shared("SeedPacks")
local Planting = H.shared("Planting")
local ProfileStore = H.server("ProfileStore")
local SpeedLogic = H.server("SpeedLogic")
local Selling = H.server("Selling")
local Inventory = H.server("Inventory")
local Shop = H.server("Shop")
local Rewards = H.server("Rewards")
local PlantGhosts = H.server("PlantGhosts")

local NAN, INF = 0 / 0, math.huge
local NOW = 1_800_000_000

----------------------------------------------------------------------------------------------------
-- The server's Roblox side, mocked (shared with passes.spec when it ran first: the same tables)
----------------------------------------------------------------------------------------------------
local function signal(): any
	return { Connect = function(self, fn)
		self.fn = fn
	end }
end
local Marketplace = H.services.MarketplaceService
if not Marketplace then
	Marketplace = {
		UserOwnsGamePassAsync = function()
			return false
		end,
		PromptGamePassPurchase = function() end,
		PromptProductPurchase = function() end,
		PromptGamePassPurchaseFinished = signal(),
	}
	H.services.MarketplaceService = Marketplace
end
local Players = H.services.Players or {}
H.services.Players = Players
Players.GetPlayerByUserId = Players.GetPlayerByUserId or function()
	return nil
end
Players.PlayerRemoving = Players.PlayerRemoving or signal()
H.services.DataStoreService = H.services.DataStoreService or { GetOrderedDataStore = function()
	error("no DataStore in tests")
end }
H.services.GroupService = H.services.GroupService or { GetGroupsAsync = function()
	return {}
end }
local Net = H.stubServer("Net", { StatsUpdate = { FireClient = function() end }, LootEvent = { FireClient = function() end }, toast = function() end })
for _, name in { "RequestBuy", "RequestUseItem", "SellPlants", "PlantSeed", "RemovePlant", "ClaimReward" } do
	Net[name] = Net[name] or { OnServerEvent = signal() }
end
Net.IncomePopup = Net.IncomePopup or { FireClient = function() end }
Net.announce = Net.announce or function() end

local Sessions = H.server("Sessions")
local SpeedService = H.server("SpeedService")
local SeedService = H.server("SeedService")
local PlotService = H.server("PlotService")
local ShopService = H.server("ShopService")
local RewardService = H.server("RewardService")
ShopService.init() -- (the remotes' handlers, ProcessReceipt and the pass purchase signal, into the mocks)
RewardService.init(nil) -- (no gift box or money board in this mock world)

-- A player: attributes and a character with a Head (no root: PlotService and the pods aren't reached).
local nextId = 91000
local function player(): any
	nextId += 1
	local attributes = {}
	local p = { Name = `S{nextId}`, DisplayName = `S{nextId}`, UserId = nextId, Parent = true, Character = nil :: any }
	function p.SetAttribute(_, k: string, v: any)
		attributes[k] = v
	end
	function p.GetAttribute(_, k: string): any
		return attributes[k]
	end
	function p.FindFirstChild()
		return nil
	end
	local char = roblox.Instance.new("Model")
	local head = roblox.Instance.new("Part")
	head.Name = "Head"
	head.Parent = char
	p.Character = char
	return p
end

local function session(): any
	return Sessions.create(player(), ProfileStore.defaultProfile(), false)
end

-- Something to lose: money, Speed, plants, the inventory, seeds in the bag, a trail.
local function richSession(): any
	local s = session()
	local p = s.profile
	p.money, p.speed = 1e6, 1e6
	p.trails.Green = true
	p.plants = {
		{ slot = 1, zone = 2, rarity = 3, plantedAt = os.time() - 100, x = -20, z = 10, variance = 1 },
		{ slot = 2, zone = 1, rarity = 1, mutation = "Gold", plantedAt = os.time() - 50, x = 20, z = -10, variance = 1.1 },
	}
	p.inventory = { { id = 1, zone = 3, rarity = 2, age = 60, variance = 1 } }
	SeedPacks.addToBag(p.seedBag, 1, 1, nil, 5)
	SeedPacks.addToBag(p.seedBag, 1, 1, nil, 5)
	return s
end

local function snapshot(s: any): any
	return ProfileStore.serialize(s.profile)
end

-- Runs fn with Config / mock fields swapped, then puts them back, even if fn fails.
local function with(swaps: { { any } }, fn: () -> ())
	local old = {}
	for i, swap in swaps do
		old[i] = swap[1][swap[2]]
		swap[1][swap[2]] = swap[3]
	end
	local ok, err = pcall(fn)
	for i, swap in swaps do
		swap[1][swap[2]] = old[i]
	end
	if not ok then
		error(err, 0)
	end
end

-- What a remote may be sent: every Luau type a client can serialize, broken numbers, long, malformed and
-- look-alike strings, Vector3s off in the void, and tables that are empty, sparse, mixed, huge or deep.
local function junkList(): any
	local deep = {}
	local cur = deep
	for _ = 1, 200 do
		cur.x = {}
		cur = cur.x
	end
	return table.pack(
		nil, true, false, 0, -1, 1.5, NAN, INF, -INF, 1e308, -1e308, 2 ^ 53, 1e9 + 1,
		"", "x", string.rep("A", 5000), "\0", "Trail:", "Trail:Hacked", "Trail:green", "Trail:Green ", "Product:", "Product:Nope",
		"Product:../Speed25K", "Pass:", "Pass:Nope", "Pass:__index", "Seed:", "Seed:inv:", "Seed:inv:999999999999", "Seed:inv:-1",
		"Seed:1:1", "Seed:99:1", "Seed:1:1:Hacked", "Seed:1:1#0", "Seed:01:1#5", "Equip:", "Equip:Rainbow", "Equip:hacked",
		"PlotUpgrade ", "Bat\0", "Gift ", "gift", "inv:1", "inv:-1", "1:1#5",
		{}, { 1 }, { 2, 2, 2 }, { NAN }, { INF }, { -1 }, { 1.5 }, { "1" }, { [1.5] = 1 }, { [-1] = 1 }, { [0] = 1 }, { a = 1 },
		{ 1, 2, 3, a = "b", [10] = 5 }, table.create(10000, 1), deep, { { { 1 } } },
		Vector3.new(NAN, 0, 0), Vector3.new(0, INF, 0), Vector3.new(1e30, 0, 0), Vector3.zero,
		roblox.CFrame.new(), roblox.Instance.new("Part"), roblox.Color3.new(1, 0, 0)
	)
end
local JUNK = junkList()

local function describe(v: any): string
	local text = tostring(v)
	return `{typeof(v)} {if #text > 24 then string.sub(text, 1, 24) .. ".." else text}`
end

----------------------------------------------------------------------------------------------------
-- Remotes: junk, rates, ownership
----------------------------------------------------------------------------------------------------
H.test("security: every remote shrugs off junk (bad types, NaN/inf, huge and deep tables): no error, nothing changes", function()
	local handlers = {
		RequestBuy = Net.RequestBuy.OnServerEvent.fn,
		RequestUseItem = Net.RequestUseItem.OnServerEvent.fn,
		SellPlants = Net.SellPlants.OnServerEvent.fn,
		PlantSeed = Net.PlantSeed.OnServerEvent.fn,
		RemovePlant = PlotService.removePlant, -- (what PlotService.init connects to Net.RemovePlant)
		ClaimReward = Net.ClaimReward.OnServerEvent.fn,
	}
	local s = richSession()
	local before = snapshot(s)
	local ghost = { UserId = 1, Name = "Ghost" } -- no session: left, or still loading
	for name, fn in handlers do
		H.ok(type(fn) == "function", `{name} is wired`)
		for i = 1, JUNK.n do
			for j = 1, JUNK.n, 5 do -- with a second argument too (SellPlants' ids, PlantSeed's bag key)
				s.requests = {} -- (under the rate limit, so every call is really checked)
				local ok, err = pcall(fn, s.player, JUNK[i], JUNK[j])
				H.ok(ok, `{name}({describe(JUNK[i])}, {describe(JUNK[j])}): {err}`)
			end
			local ok, err = pcall(fn, ghost, JUNK[i])
			H.ok(ok, `{name} from a player without a session: {err}`)
		end
		local same, why = H.deepEq(snapshot(s), before)
		H.ok(same, `{name} changed the profile: {why}`)
		H.eq(s.carry, nil, `{name}: no carry`)
		H.eq(next(s.passes), nil, `{name}: no pass`)
	end
end)

H.test("security: a remote spammed past its budget is dropped (8 a second for the shop, 4 for planting and removing)", function()
	local s = session()
	local allowed = 0
	for _ = 1, 100 do
		allowed += if Sessions.allowRequest(s, 8) then 1 else 0
	end
	H.eq(allowed, 8, "8 in a second")
	-- every client -> server handler spends from the budget before it does anything
	local shop = fs.readFile("src/server/ShopService.luau")
	local function section(source: string, from: string, to: string): string
		local a = string.find(source, from, 1, true)
		local b = a and string.find(source, to, a + #from, true)
		H.ok(a ~= nil and b ~= nil, `found {from}`)
		return string.sub(source, a :: number, b :: number)
	end
	for _, handler in { "local function onBuy(", "local function onUse(", "local function onSell(", "local function onPlant(" } do
		H.ok(string.find(section(shop, handler, "\nend"), "Sessions.allowRequest(s, ", 1, true) ~= nil, `{handler} is rate-limited`)
	end
	local plot = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(section(plot, "function PlotService.removePlant(", "\nend"), "Sessions.allowRequest(s, REMOVES_PER_SECOND)", 1, true) ~= nil,
		"RemovePlant is rate-limited")
	local reward = fs.readFile("src/server/RewardService.luau")
	H.ok(string.find(section(reward, "Net.ClaimReward.OnServerEvent:Connect(", "\tend)"), "Sessions.allowRequest(s, REQUESTS_PER_SECOND)", 1, true) ~= nil,
		"ClaimReward is rate-limited")
	-- the server -> client remotes drop whatever a client fires at them
	local net = fs.readFile("src/server/Net.luau")
	H.ok(string.find(net, "for _, r in { Net.StatsUpdate, Net.LootEvent, Net.IncomePopup } do", 1, true) ~= nil
		and string.find(net, "r.OnServerEvent:Connect(function() end)", 1, true) ~= nil, "server -> client remotes have a sink")
end)

H.test("security: shop rules take only valid ids, never charge twice, never go negative", function()
	local p = ProfileStore.defaultProfile()
	p.money = Config.TRAILS[2].price -- exactly the Green trail
	for i = 1, JUNK.n do
		local id = JUNK[i]
		if type(id) == "string" then
			local before = p.money
			Shop.buy(p, id)
			H.eq(p.money, before, `Shop.buy({describe(id)})`)
			Shop.equipTrail(p, id)
			H.eq(p.equippedTrail, Config.DEFAULT_TRAIL, `equipTrail({describe(id)}) equips nothing`)
			Shop.canPrompt(p, id)
		end
	end
	H.ok(Shop.buy(p, "Trail:Green"), "the real one")
	H.eq(p.money, 0, "paid exactly once")
	local ok, why = Shop.buy(p, "Trail:Green")
	H.ok(not ok and p.money == 0, `bought again: refused ({why}), money unchanged`)
	ok = Shop.buy(p, "PlotUpgrade")
	H.ok(not ok and p.money == 0 and p.plotLevel == 1, "no money: no level, and money never below 0")
end)

----------------------------------------------------------------------------------------------------
-- Economy: selling, removing, inventory ids
----------------------------------------------------------------------------------------------------
local function plant(slot: number): ProfileStore.Plant
	return { slot = slot, zone = 2, rarity = 2, plantedAt = NOW - 300, x = 0, z = 0, variance = 1 }
end

H.test("security: a plant is sold once: named twice in a request, sold twice, or sold and removed", function()
	local p = ProfileStore.defaultProfile()
	p.plants = { plant(1), plant(2) }
	p.inventory = { { id = 7, zone = 1, rarity = 1, age = 30, variance = 1 } }
	local one = Selling.price(plant(1), NOW, 1)
	local sale = Selling.sell(p, { 1, 1, 1, 1 }, 1, NOW, 1, { 7, 7, 7 })
	H.ok(sale ~= nil, "sold")
	H.eq(#sale.slots, 1, "slot 1 once")
	H.eq(#sale.ids, 1, "id 7 once")
	local stored = Selling.price(Inventory.asPlant({ id = 7, zone = 1, rarity = 1, age = 30, variance = 1 }, NOW), NOW, 1)
	H.near(p.money, one + stored, 1e-6, "paid once each")
	local money = p.money
	local again, why = Selling.sell(p, { 1 }, 1, NOW, 1, { 7 })
	H.ok(again == nil and why == "none" and p.money == money, "sold again: nothing")
	-- removed into the inventory, then sold by its old slot: nothing (it is under its new id now)
	local entry = Inventory.take(p, 2, NOW)
	H.ok(entry ~= nil)
	again = Selling.sell(p, { 2 }, 1, NOW, 1)
	H.ok(again == nil and p.money == money, "a removed plant can't be sold by its slot")
	H.eq(Inventory.take(p, 2, NOW), nil, "nor removed twice")
	-- sold from the inventory, then planted from it (or sold) again: gone
	H.ok(Selling.sell(p, nil, 1, NOW, 1, { entry.id }) == nil, "slots must be a list")
	H.ok(Selling.sell(p, {}, 1, NOW, 1, { entry.id }) ~= nil, "sold from the inventory")
	H.eq(Inventory.find(p, entry.id), nil, "gone from the inventory")
	H.eq(Inventory.remove(p, entry.id), nil, "can't be planted from it")
	H.eq(#p.plants, 0)
	-- an id taken again after a sale is a new plant: nothing is made twice
	p.plants = { plant(3) }
	local reused = Inventory.take(p, 3, NOW)
	H.ok(reused ~= nil and #p.inventory == 1, "one plant, one entry")
end)

H.test("security: selling refuses junk lists, a far or broken distance, and changes nothing then", function()
	local p = ProfileStore.defaultProfile()
	p.plants = { plant(1), plant(2) }
	p.inventory = { { id = 1, zone = 1, rarity = 1, age = 30, variance = 1 } }
	local before = ProfileStore.serialize(p)
	for i = 1, JUNK.n do
		for j = 1, JUNK.n, 3 do
			local ok, err = pcall(Selling.sell, p, JUNK[i], 1, NOW, 1, JUNK[j])
			H.ok(ok, `Selling.sell({describe(JUNK[i])}, {describe(JUNK[j])}): {err}`)
			if p.money ~= 0 then
				-- (a valid list of a slot or id it has sells it: put everything back and go on)
				p.money = 0
				p.plants = { plant(1), plant(2) }
				p.inventory = { { id = 1, zone = 1, rarity = 1, age = 30, variance = 1 } }
			end
		end
	end
	for _, distance in { NAN, INF, Config.SELL_STALL_DISTANCE + 0.01, "1", nil } :: { any } do
		local sale, why = Selling.sell(p, { 1, 2 }, distance, NOW, 1, { 1 })
		H.ok(sale == nil and why == "far", `distance {distance}: refused`)
	end
	local same, why = H.deepEq(ProfileStore.serialize(p), before)
	H.ok(same, why)
end)

H.test("security: removing, the inventory and the seed bag take only what the profile has", function()
	local p = ProfileStore.defaultProfile()
	p.plants = { plant(1) }
	p.inventory = { { id = 4, zone = 1, rarity = 1, age = 30, variance = 1 } }
	SeedPacks.addToBag(p.seedBag, 2, 3, "Gold", 77)
	local before = ProfileStore.serialize(p)
	for i = 1, JUNK.n do
		local v = JUNK[i]
		if not (type(v) == "number" and (v == 1 or v == 4)) then
			H.eq(Inventory.take(p, v, NOW), nil, `take({describe(v)})`)
			H.eq(Inventory.find(p, v), nil, `find({describe(v)})`)
			H.eq(Inventory.remove(p, v), nil, `remove({describe(v)})`)
		end
		local ok, err = pcall(PlantGhosts.bagPreview, p.seedBag, v, math.random)
		H.ok(ok, `bagPreview({describe(v)}): {err}`)
		local parsed = SeedPacks.parseBagKey(v)
		H.ok(parsed == nil or type(v) == "string", `parseBagKey({describe(v)})`)
	end
	local same, why = H.deepEq(ProfileStore.serialize(p), before)
	H.ok(same, why)
	-- a planting spot off in the void, or NaN, is refused without error
	local beds = {}
	for _, b in Planting.defaultBeds() do
		table.insert(beds, { CFrame = roblox.CFrame.new(b.center), Size = b.size })
	end
	for _, pos in { Vector3.new(NAN, 0, 0), Vector3.new(INF, 0, INF), Vector3.new(1e30, 0, 0) } do
		local ok = Planting.check({ beds = beds, origin = roblox.CFrame.new(), plants = {}, pos = pos, rarity = 1, root = Vector3.zero, limit = 5 })
		H.eq(ok, false, `spot {pos}`)
	end
end)

----------------------------------------------------------------------------------------------------
-- Robux: receipts and gamepasses
----------------------------------------------------------------------------------------------------
H.test("security: ProcessReceipt grants once per PurchaseId, only to the buyer, and only once it is saved", function()
	local process = Marketplace.ProcessReceipt
	H.ok(type(process) == "function", "wired")
	local buyer, other = session(), session()
	local saves, saveOk = 0, true
	local GRANTED, LATER = Enum.ProductPurchaseDecision.PurchaseGranted, Enum.ProductPurchaseDecision.NotProcessedYet
	with({
		{ Config.DEVELOPER_PRODUCTS.Speed25K, "id", 424242 },
		{ ShopService, "save", function(_s: any): boolean
			saves += 1
			return saveOk
		end },
		{ Players, "GetPlayerByUserId", function(_, id: number): any
			return if id == buyer.player.UserId then buyer.player elseif id == other.player.UserId then other.player else nil
		end },
	}, function()
		local info = { PlayerId = buyer.player.UserId, ProductId = 424242, PurchaseId = "receipt-1" }
		H.eq(process(info), GRANTED)
		H.eq(buyer.profile.speed, 25e3, "granted")
		H.eq(saves, 1, "saved before confirming")
		H.eq(process(info), GRANTED, "delivered again: confirmed again...")
		H.eq(buyer.profile.speed, 25e3, "...but granted once")
		H.eq(other.profile.speed, 0, "nobody else gets it")
		-- the save fails: not confirmed; Roblox's retry confirms without granting twice
		saveOk = false
		local retry = { PlayerId = buyer.player.UserId, ProductId = 424242, PurchaseId = "receipt-2" }
		H.eq(process(retry), LATER, "not saved: not confirmed")
		H.eq(buyer.profile.speed, 50e3)
		saveOk = true
		H.eq(process(retry), GRANTED)
		H.eq(buyer.profile.speed, 50e3, "the retry grants nothing more")
		-- a buyer who isn't in this server, or a product this game doesn't sell: never confirmed here
		H.eq(process({ PlayerId = 123, ProductId = 424242, PurchaseId = "receipt-3" }), LATER)
		H.eq(process({ PlayerId = buyer.player.UserId, ProductId = 99, PurchaseId = "receipt-4" }), LATER)
		H.eq(buyer.profile.speed, 50e3)
		H.eq(other.profile.speed, 0)
	end)
end)

H.test("security: a gamepass is granted only when Roblox confirms the player owns it (a spoofed purchase report gives nothing)", function()
	local finished = Marketplace.PromptGamePassPurchaseFinished.fn
	H.ok(type(finished) == "function", "wired")
	local s = session()
	-- every pass is a stub (id 0): a fake "purchased" for id 0 matched all six
	with({ { Marketplace, "UserOwnsGamePassAsync", function()
		return true
	end } }, function()
		finished(s.player, 0, true)
		for i = 1, JUNK.n do
			finished(s.player, JUNK[i], true)
			finished(s.player, 0, JUNK[i])
		end
	end)
	H.eq(next(s.passes), nil, "no pass from id 0 or junk")
	local owns = false
	with({
		{ Config.GAMEPASSES.DoubleMoney, "id", 777 },
		{ Marketplace, "UserOwnsGamePassAsync", function(_, _userId: number, id: number): boolean
			return owns and id == 777
		end },
	}, function()
		finished(s.player, 777, true)
		H.eq(s.passes.DoubleMoney, nil, "reported but not owned: nothing")
		H.eq(Sessions.moneyMult(s), Config.plotMoneyMult(1), "no 2x Money")
		owns = true
		finished(s.player, 777, false)
		H.eq(s.passes.DoubleMoney, nil, "not purchased: nothing")
		finished(s.player, 777, true)
		H.eq(s.passes.DoubleMoney, true, "owned: granted")
	end)
	local source = fs.readFile("src/server/ShopService.luau")
	H.ok(string.find(source, "MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchased)", 1, true) ~= nil, "the handler")
end)

----------------------------------------------------------------------------------------------------
-- Free Gift: once per account, even when clicks race the community check
----------------------------------------------------------------------------------------------------
H.test("security: the Free Gift can't be claimed twice by clicking while the community check waits", function()
	-- the rule: a claim that lands while another waits on Roblox's web API makes the waiting one "claimed"
	local p = ProfileStore.defaultProfile()
	local depth = 0
	local function claim(): string
		return Rewards.claimGift(p, 4242, function(): boolean?
			if depth == 0 then
				depth += 1
				claim() -- a second click, answered first
			end
			return true
		end)
	end
	H.eq(claim(), "claimed")
	H.eq(p.speed, Config.FREE_GIFT_SPEED, "granted once")

	-- through the remote: the second click is turned away while the first check runs
	local remote = Net.ClaimReward.OnServerEvent.fn
	local s = session()
	local checks, heldOff = 0, true
	s.player.IsInGroupAsync = function(_, _groupId: number): boolean
		checks += 1
		-- Roblox takes longer than the 2 s between claims to answer: clicks keep arriving meanwhile
		heldOff = heldOff and s.cooldowns.Gift == math.huge
		for _ = 1, 3 do
			s.requests = {}
			remote(s.player, "Gift")
		end
		return true
	end
	with({ { Config, "COMMUNITY_GROUP_ID", 4242 } }, function()
		remote(s.player, "Gift")
		H.eq(checks, 1, "one check at a time")
		H.ok(heldOff, "...however long it takes (not just for the 2 s between claims)")
		H.eq(s.profile.speed, Config.FREE_GIFT_SPEED, "granted once")
		H.ok(s.profile.freeGift)
		s.cooldowns.Gift = 0
		s.requests = {}
		remote(s.player, "Gift")
		H.eq(s.profile.speed, Config.FREE_GIFT_SPEED, "and never again")
	end)
	H.ok(Rewards.autoOpenGift(s.profile, 4242) == false, "the window doesn't reopen for a claimed gift")
end)

----------------------------------------------------------------------------------------------------
-- Movement: teleports, NaN, flying, a deleted Humanoid
----------------------------------------------------------------------------------------------------
local DT = Config.TICK
local function opts(walk: number): any
	return { walkSpeed = walk, onTreadmill = false, mult = 1, treadmillTier = 1, trailMult = 1 }
end

H.test("security: a NaN or infinite position never gets into the movement check (it would never rubber-band again)", function()
	local st = SpeedLogic.newState()
	H.eq(select(2, SpeedLogic.step(st, Vector3.new(NAN, 0, 0), DT, opts(16))), "ignored", "nothing seen yet: ignored")
	H.eq(st.lastPos, nil, "and not kept")
	for _ = 1, 5 do
		SpeedLogic.step(st, Vector3.zero, DT, opts(16))
	end
	for _, bad in { Vector3.new(NAN, 0, 0), Vector3.new(0, NAN, 0), Vector3.new(INF, 0, 0), Vector3.new(0, 0, -INF), Vector3.new(2e6, 0, 0) } do
		local gain, verdict, back = SpeedLogic.step(st, bad, DT, opts(16))
		H.eq(verdict, "rubberband", `{bad}`)
		H.eq(gain, 0)
		H.ok(back == Vector3.zero, "back where it was")
		H.ok(st.bucket == st.bucket and st.lastPos == Vector3.zero, "the state stays sane")
	end
	H.eq(select(2, SpeedLogic.step(st, Vector3.new(500, 0, 0), DT, opts(16))), "rubberband", "a teleport right after is still caught")
	H.ok(SpeedLogic.finite(Vector3.new(1, 2, 3)) and not SpeedLogic.finite(Vector3.new(NAN, 0, 0)))
end)

H.test("security: plausible = the next tick wouldn't rubber-band; a teleport, or ignoring the rubber-band, isn't", function()
	local walk = 50
	local st = SpeedLogic.newState()
	H.ok(not SpeedLogic.plausible(st, Vector3.zero, DT, walk), "never seen: not trusted")
	for _ = 1, 5 do
		SpeedLogic.step(st, Vector3.zero, DT, opts(walk))
	end
	H.ok(SpeedLogic.plausible(st, Vector3.new(walk * DT, 0, 0), DT, walk), "a walking step")
	H.ok(SpeedLogic.plausible(st, Vector3.new(0, 300, 0), DT, walk), "straight up doesn't count (the checks are flat)")
	H.ok(not SpeedLogic.plausible(st, Vector3.new(400, 0, 0), DT, walk), "a teleport")
	H.ok(not SpeedLogic.plausible(st, Vector3.new(400, 0, 0), 60, walk), "...however long ago the last tick was (the budget is capped)")
	H.ok(not SpeedLogic.plausible(st, Vector3.new(NAN, 0, 0), DT, walk), "NaN")
	-- a client that ignores the rubber-band stays where it went: still not trusted on the next ticks
	local gone = Vector3.new(400, 0, 0)
	for _ = 1, 4 do
		H.eq(select(2, SpeedLogic.step(st, gone, DT, opts(walk))), "rubberband")
		H.ok(not SpeedLogic.plausible(st, gone, DT, walk), "still not trusted")
	end
	-- and the plausible budget is exactly the rubber-band's
	local at = Vector3.new(SpeedLogic.allowedPerTick(walk, DT) - 0.01, 0, 0)
	H.ok(SpeedLogic.plausible(st, at, DT, walk))
	H.eq(select(2, SpeedLogic.step(st, at, DT, opts(walk))), "ok")
end)

-- A character the server sees: a table root (Lune parts have no Position) and a Humanoid.
local function body(at: Vector3, withHumanoid: boolean?): (any, any, any)
	local root = { CFrame = roblox.CFrame.new(at), Position = at }
	function root.move(self: any, pos: Vector3)
		self.CFrame = roblox.CFrame.new(pos)
		self.Position = pos
	end
	local hum = if withHumanoid == false then nil else roblox.Instance.new("Humanoid")
	if hum then
		hum.Health = 100
	end
	local char = {
		Parent = true,
		FindFirstChild = function(_, name: string)
			return if name == "HumanoidRootPart" then root else nil
		end,
		FindFirstChildOfClass = function(_, class: string)
			return if class == "Humanoid" then hum else nil
		end,
		PivotTo = function(_, cf: any)
			root:move(cf.Position)
		end,
	}
	return char, root, hum
end

local function seen(s: any, at: Vector3)
	SpeedLogic.teleported(s.tracker, at)
	s.tracker.at = os.clock()
end

H.test("security: SpeedService.trustedRoot: only alive, and only where the movement check saw the character get to", function()
	local s = session()
	local char, root, hum = body(Vector3.new(0, 3, 0))
	s.player.Character = char
	H.eq(SpeedService.trustedRoot(s.player), nil, "before the first tick")
	seen(s, Vector3.new(0, 3, 0))
	H.eq(SpeedService.trustedRoot(s.player), root, "where it was seen")
	root:move(Vector3.new(2000, 3, 0))
	H.eq(SpeedService.trustedRoot(s.player), nil, "teleported: not trusted")
	SpeedService.tickPlayer(s, DT, os.clock())
	H.ok(root.Position == Vector3.new(0, 3, 0), "rubber-banded back")
	root:move(Vector3.new(2000, 3, 0)) -- the client puts itself back there anyway
	H.eq(SpeedService.trustedRoot(s.player), nil, "still not trusted")
	root:move(Vector3.new(0, 3, 0))
	H.eq(SpeedService.trustedRoot(s.player), root, "back where it was seen")
	hum.Health = 0
	H.eq(SpeedService.trustedRoot(s.player), nil, "dead")
	H.eq(SpeedService.trustedRoot({ UserId = 5 } :: any), nil, "no session")
end)

H.test("security: the guards chase where the server saw the thief get to, so a teleport home doesn't shake them off", function()
	local s = session()
	local start = Vector3.new(400, 3, -40)
	local char, root = body(start)
	s.player.Character = char
	H.eq(SpeedService.seenPosition(s.player), nil, "never seen")
	seen(s, start)
	H.ok(SpeedService.seenPosition(s.player) == start)
	root:move(Vector3.new(Config.CORRIDOR_START_X - 30, 3, 0)) -- teleported into the base, rubber-band ignored
	local pos = SpeedService.seenPosition(s.player)
	H.ok(pos == start and pos.X >= Config.CORRIDOR_START_X, "for the guard they are still in the corridor")
	root:move(start + Vector3.new(1, 0, 0))
	H.ok(SpeedService.seenPosition(s.player) == start + Vector3.new(1, 0, 0), "a real step is followed")
	local guard = fs.readFile("src/server/GuardService.luau")
	H.ok(string.find(guard, "local pos = SpeedService.seenPosition(player)", 1, true) ~= nil
		and string.find(guard, "safe = pos.X < Config.CORRIDOR_START_X", 1, true) ~= nil, "GuardService chases that position")
end)

H.test("security: a character whose Humanoid was deleted (to dodge the checks and the guards) is respawned", function()
	local s = session()
	local char = body(Vector3.new(0, 3, 0), false)
	local respawns = 0
	s.player.Character = char
	s.player.LoadCharacter = function()
		respawns += 1
	end
	seen(s, Vector3.new(0, 3, 0))
	H.eq(SpeedService.trustedRoot(s.player), nil, "never trusted without a Humanoid")
	SpeedService.tickPlayer(s, DT, os.clock())
	H.eq(respawns, 0, "one tick could be a hiccup")
	SpeedService.tickPlayer(s, DT, os.clock())
	H.eq(respawns, 1, "two in a row: respawned")
	-- a dead character (its Humanoid is there) is left to Roblox's own respawn
	local dead = session()
	local deadChar, _, deadHum = body(Vector3.zero)
	deadHum.Health = 0
	dead.player.Character = deadChar
	dead.player.LoadCharacter = function()
		respawns += 100
	end
	for _ = 1, 3 do
		SpeedService.tickPlayer(dead, DT, os.clock())
	end
	H.eq(respawns, 1, "not respawned by us")
	local project = serde.decode("json", fs.readFile("default.project.json"))
	H.eq(project.tree.Workspace["$properties"].RejectCharacterDeletions, "Enabled", "and clients can't delete parts of their character")
end)

-- Pods and thieves (Lune parts, so a seed can be put on their back)
local function nestInfos(): { any }
	PlantGhosts.publish(roblox.Instance.new("Folder")) -- (a stolen seed's ghost is built into it)
	local infos = {}
	for k in Config.ZONES do
		local model = roblox.Instance.new("Model")
		model.Name = "SecurityNest_" .. k
		model.Parent = H.workspace
		local pods = {}
		for i = 1, Config.PODS_PER_NEST do
			pods[i] = roblox.CFrame.new(Config.nestCenter(k) + Config.podOffset(k, i))
		end
		infos[k] = { zone = k, model = model, center = Config.nestCenter(k), podCFrames = pods, guardHome = Config.nestCenter(k) }
	end
	return infos
end

local function thief(at: Vector3): any
	local s = session()
	local char = roblox.Instance.new("Model")
	for _, name in { "HumanoidRootPart", "UpperTorso" } do
		local part = roblox.Instance.new("Part")
		part.Name = name
		part.Size = Vector3.new(2, 2, 1)
		part.CFrame = roblox.CFrame.new(at)
		part.Parent = char
	end
	local hum = roblox.Instance.new("Humanoid")
	hum.Health = 100
	hum.Parent = char
	s.player.Character = char
	seen(s, at)
	return s
end

-- The client moves its character (what the server sees next), without the movement check having seen it.
local function jump(s: any, to: Vector3)
	s.player.Character:FindFirstChild("HumanoidRootPart").CFrame = roblox.CFrame.new(to)
end

H.test("security: a seed can't be stolen from far away or by teleporting to it, nor taken home by teleporting", function()
	SeedService.buildPods(nestInfos())
	local zone, index = 3, 2
	local pod = SeedService.pods(zone)[index]
	local at = pod.part.CFrame.Position + Vector3.new(2, 0, 0)
	local home = Vector3.new(Config.CORRIDOR_START_X - 10, 3, 0)

	-- the prompt fired from the base (exploits fire prompts from anywhere)
	local s = thief(home)
	SeedService.steal(s.player, zone, index)
	H.ok(s.carry == nil and pod.available, "from far away: nothing")
	-- teleported next to the pod
	jump(s, at)
	SeedService.steal(s.player, zone, index)
	H.ok(s.carry == nil and pod.available, "teleported to it: nothing")
	-- walked there: stolen
	seen(s, at)
	SeedService.steal(s.player, zone, index)
	H.ok(s.carry ~= nil and not pod.available, "walked to it: stolen")
	-- teleported home: it stays on their back (the guard is still after them)
	jump(s, home)
	H.eq(SeedService.storeCarried(s.player), false, "teleported home: not stored")
	H.ok(s.carry ~= nil, "still carried")
	seen(s, home)
	H.eq(SeedService.storeCarried(s.player), true, "walked home: stored")
	H.eq(s.carry, nil)
	-- a dead thief can't steal
	local dead = thief(at)
	dead.player.Character:FindFirstChildOfClass("Humanoid").Health = 0
	H.runDelayed() -- (the pod regrows)
	SeedService.steal(dead.player, zone, index)
	H.eq(dead.carry, nil, "dead: nothing")
end)

H.test("security: a thief out over the corridor's walls (flying, clipping) loses the seed back to its pod", function()
	SeedService.buildPods(nestInfos())
	local zone, index = 2, 1
	local pod = SeedService.pods(zone)[index]
	local at = pod.part.CFrame.Position + Vector3.new(2, 0, 0)
	local half = Config.CORRIDOR_WIDTH / 2
	for _, out in { Vector3.new(at.X, 3, -(half + 20)), Vector3.new(at.X, 60, half + Inventory.OFF_COURSE_MARGIN + 1), Vector3.new(Config.END_X + 30, 3, 0) } do
		local s = thief(at)
		SeedService.steal(s.player, zone, index)
		H.ok(s.carry ~= nil, "stolen")
		local rarity, gene = pod.rarity, pod.gene
		jump(s, out)
		H.eq(SeedService.storeCarried(s.player), false)
		H.eq(s.carry, nil, `at {out}: the seed is gone from their back`)
		H.ok(pod.available and pod.rarity == rarity and pod.gene == gene, "back in its pod, as it was")
	end
	H.ok(not Inventory.offCourse(Vector3.new(Config.CORRIDOR_START_X - 1, 3, 140)), "the base is wider than the corridor")
	H.ok(not Inventory.offCourse(Vector3.new(at.X, 200, half - 1)), "high up inside the walls (the catch is flat)")
	H.ok(not Inventory.offCourse(Vector3.new(Config.END_X - 1, 3, 0)), "by the back wall")
	H.ok(not Inventory.offCourse(Vector3.new(NAN, 0, 0)), "NaN (trustedRoot refuses it)")
end)

H.test("security: every position check between ticks goes through trustedRoot (pods, home, SELL stall, planting, boards, bat)", function()
	local function count(file: string, needle: string): number
		local n = 0
		for _ in string.gmatch(fs.readFile(file), (needle:gsub("%p", "%%%0"))) do
			n += 1
		end
		return n
	end
	H.eq(count("src/server/SeedService.luau", "SpeedService.trustedRoot(player)"), 2, "steal and storeCarried")
	H.eq(count("src/server/PlotService.luau", "SpeedService.trustedRoot(player)"), 4, "plantAt, sellPlants and both Upgrade boards")
	H.eq(count("src/server/GuardService.luau", "SpeedService.trustedRoot(player)"), 1, "the bat")
	H.eq(count("src/server/PlotService.luau", "FindFirstChild(\"HumanoidRootPart\")"), 0, "no raw root read left in PlotService")
end)

----------------------------------------------------------------------------------------------------
-- Data: malformed saves, the session lock
----------------------------------------------------------------------------------------------------
-- A DataStore that stores JSON; `held` (when set) keeps the next write's transform for a test to land later.
local function mockStore(): any
	local ds = { data = {} :: { [string]: string }, calls = 0, hold = false, held = nil :: any }
	function ds.UpdateAsync(self, key: string, transform: (any) -> any)
		self.calls += 1
		if self.hold then
			self.hold = false
			self.held = { key = key, transform = transform }
			return nil -- (a save in flight: it lands when the test says)
		end
		local old = if self.data[key] then serde.decode("json", self.data[key]) else nil
		local new = transform(old)
		if new ~= nil then
			self.data[key] = serde.encode("json", new)
		end
		return new
	end
	function ds.land(self)
		local h = self.held
		self.held = nil
		local old = if self.data[h.key] then serde.decode("json", self.data[h.key]) else nil
		local new = h.transform(old)
		if new ~= nil then
			self.data[h.key] = serde.encode("json", new)
		end
	end
	function ds.stored(self, userId: number): any
		local raw = self.data["Player_" .. userId]
		return raw and serde.decode("json", raw)
	end
	return ds
end

H.test("security: malformed or hostile saves load without error, clamped (no NaN, no infinite money, no junk lock)", function()
	local deep = {}
	local cur = deep
	for _ = 1, 100 do
		cur.v = {}
		cur = cur.v
	end
	local cases = {
		"junk", 5, true, deep, { v = "x" }, { v = NAN }, { money = INF, speed = -INF }, { money = NAN, speed = "1" },
		{ v = 10, plants = { { s = 1, z = 1, r = 1, t = NAN }, { s = 2, z = 1, r = 1, t = INF }, { s = 3, z = 1, r = 1, t = NOW } } },
		{ v = 10, inv = { { i = NAN, z = 1, r = 1, va = 1 }, { i = 1, z = 1, r = 1, a = NAN, va = 1 }, { i = 2, z = 1, r = 1, va = NAN } } },
		{ v = 10, bag = { ["1:1"] = INF, ["1:1#0"] = 3, [5] = 2, ["99:1"] = 1, ["1:1:Hacked"] = 1 } },
		{ v = 10, receipts = { string.rep("r", 100), 5, "ok" }, items = { [1] = 2 }, trails = "Rainbow", trail = { "Rainbow" } },
		{ v = 10, lock = "mine" }, { v = 10, lock = { id = 5, t = "x" } }, { v = 10, index = deep },
	}
	for i, data in cases do
		local ok, p = pcall(ProfileStore.deserialize, data)
		H.ok(ok, `case {i}: {p}`)
		if ok then
			H.ok(p.money == p.money and p.money >= 0 and p.money <= ProfileStore.MAX_AMOUNT, `case {i}: money {p.money}`)
			H.ok(p.speed == p.speed and p.speed >= 0 and p.speed <= ProfileStore.MAX_AMOUNT, `case {i}: speed {p.speed}`)
			for _, pl in p.plants do
				H.ok(pl.plantedAt == pl.plantedAt and math.abs(pl.plantedAt) < 1e12, `case {i}: plant {pl.slot} plantedAt`)
			end
			for _, e in p.inventory do
				H.ok(e.age == e.age and e.variance == e.variance and e.id == e.id, `case {i}: inventory`)
			end
			H.ok(SeedPacks.bagCount(p.seedBag) <= Config.SEED_BAG_HARD_MAX, `case {i}: bag`)
			H.eq((p :: any).lock, nil, `case {i}: the lock isn't part of the profile`)
		end
	end
	H.eq(#ProfileStore.deserialize(cases[9]).plants, 1, "only the plant with a real time")
	-- through a store: the save round-trips and the junk lock is replaced by a real one
	local ds = mockStore()
	ds.data.Player_5 = serde.encode("json", { v = 10, money = 7, lock = "junk" })
	local p, ok = ProfileStore.new(ds, 1, 0, "server"):load(5)
	H.ok(ok and p.money == 7)
	H.eq(type(ds:stored(5).lock), "table", "claimed")
end)

H.test("security: a profile is written by one server at a time (session lock: hops, crashes, late saves)", function()
	local ds = mockStore()
	local A = ProfileStore.new(ds, 1, 0, "server-A")
	local B = ProfileStore.new(ds, 1, 0, "server-B")
	local T = NOW
	A.now = function()
		return T
	end
	B.now = A.now

	-- A loads and plays
	local pa = A:load(42)
	pa.money = 100
	H.ok(A:save(42, pa), "A's autosave")
	-- B loads while A still holds it (A crashed): B waits LOCK_TRIES loads, then takes it over
	ds.calls = 0
	local pb, okB = B:load(42)
	H.ok(okB and pb.money == 100, "B has A's last save")
	H.eq(ds.calls, ProfileStore.LOCK_TRIES, "after waiting for A")
	pb.money = 500
	H.ok(B:save(42, pb))
	-- A's late save (its session lives on) is refused: B's progress stays
	pa.money = 1e9
	local saved, why = A:save(42, pa)
	H.ok(saved == false and why == "locked", "A can't write any more")
	H.eq(ds:stored(42).money, 500, "B's progress kept")
	H.eq(select(2, A:save(42, pa, true)), "locked", "nor release B's lock")

	-- B lets it go when the player leaves: the next server loads at once
	H.ok(B:save(42, pb, true))
	H.eq(ds:stored(42).lock.done, true, "released")
	H.eq(select(2, B:save(42, pb)), "locked", "and B's session writes nothing more")
	ds.calls = 0
	local pc = A:load(42)
	H.eq(ds.calls, 1, "no wait")
	H.eq(pc.money, 500)

	-- a lock from a server dead for longer than LOCK_STALE is taken at once
	T += ProfileStore.LOCK_STALE + 1
	ds.calls = 0
	local pd = B:load(42)
	H.eq(ds.calls, 1, "stale: taken at once")

	-- a save that lands after a newer one (a retried autosave) is refused, so it can't undo the newer one
	pd.money = 1
	ds.hold = true
	B:save(42, pd) -- in flight...
	pd.money = 2
	H.ok(B:save(42, pd), "a newer save lands first")
	ds:land()
	H.eq(ds:stored(42).money, 2, "the older one landing late changes nothing")
	-- ...and an autosave landing after the player's last save can't take the lock back
	pd.money = 3
	ds.hold = true
	B:save(42, pd)
	pd.money = 4
	H.ok(B:save(42, pd, true), "the last save, released")
	ds:land()
	local final = ds:stored(42)
	H.ok(final.money == 4 and final.lock.done == true, "still released, with the last save's money")

	-- a server from before locks (an update rolling out) writes the profile with no lock at all: the session
	-- keeps saving and claims it again
	local pg = A:load(44)
	ds.data.Player_44 = serde.encode("json", { v = ProfileStore.VERSION, money = 7 })
	pg.money = 6
	H.ok(A:save(44, pg), "saved")
	H.ok(ds:stored(44).money == 6 and type(ds:stored(44).lock.id) == "string", "and locked again")

	-- a rejoin on the same server while the leave save is still in flight loads that save, not an older one
	local pe = A:load(43)
	pe.money = 10
	H.ok(A:save(43, pe))
	pe.money = 20
	ds.hold = true
	A:save(43, pe, true) -- the player left; the save is in flight
	local tries = 0
	local base = ds.UpdateAsync
	ds.UpdateAsync = function(self, key, transform)
		tries += 1
		if tries == 2 and self.held then
			self:land() -- (it lands while the new session waits)
		end
		return base(self, key, transform)
	end
	local pf = A:load(43)
	ds.UpdateAsync = base
	H.eq(tries, 2, "the new session waited for it...")
	H.eq(pf.money, 20, "...and has the leave save's money, not the older autosave's")
end)

H.test("security: Main saves with the session lock, releases it, and stops saving a profile another server took", function()
	local main = fs.readFile("src/server/Main.server.luau")
	for _, needle in {
		"store = ProfileStore.new(ds, nil, nil, game.JobId)", -- each server's sessions are its own
		"local ok, why = store:save(s.player.UserId, s.profile, release)",
		"if why == \"locked\" then",
		"s.canSave = false -- another server has this profile now",
		"store:save(player.UserId, profile, true) -- left while loading", -- the claimed lock goes back
		"if not player.Parent or Sessions.get(player) ~= s then", -- left during the pass check: no plot leak
	} do
		H.ok(string.find(main, needle, 1, true) ~= nil, needle)
	end
	local full = string.find(main, "This server is full", 1, true)
	H.ok(full ~= nil and string.find(string.sub(main, full, full + 120), "save(s, true)", 1, true) ~= nil, "a full server lets the profile go")
	local a = string.find(main, "game:BindToClose", 1, true)
	H.ok(a ~= nil and string.find(main, "save(s, true)", a, true) ~= nil, "shutdown releases every profile")
	local leaving = string.find(main, "local function onPlayerRemoving", 1, true)
	H.ok(leaving ~= nil and string.find(string.sub(main, leaving, leaving + 300), "save(s, true)", 1, true) ~= nil, "a player leaving releases theirs")
end)

----------------------------------------------------------------------------------------------------
-- General
----------------------------------------------------------------------------------------------------
H.test("security: no loadstring, no fenv, no require by asset id, no HTTP; InsertService only for Config's own ids", function()
	local files: { string } = {}
	local function collect(dir: string)
		for _, entry in fs.readDir(dir) do
			if string.match(entry, "%.luau$") then
				table.insert(files, dir .. "/" .. entry)
			elseif fs.isDir(dir .. "/" .. entry) then
				collect(dir .. "/" .. entry)
			end
		end
	end
	for _, dir in { "src/client", "src/server", "src/shared" } do
		collect(dir)
	end
	H.ok(#files > 30, `{#files} scripts`)
	for _, file in files do
		local source = fs.readFile(file)
		for _, banned in { "loadstring", "getfenv", "setfenv", "HttpService", "RequestAsync", "PostAsync", "MessagingService" } do
			if banned == "MessagingService" and file == "src/server/LiveEventService.luau" then
				continue -- (the live events' cross-server sync: it only publishes on and listens to LiveEvents.TOPIC)
			end
			H.ok(not string.find(source, banned, 1, true), `{file}: {banned}`)
		end
		H.ok(not string.match(source, "require%s*%(%s*%d"), `{file}: require by asset id`)
		if string.find(source, "GetService(\"InsertService\")", 1, true) then
			-- CreatureModels: Config.CREATURE_ASSETS; CandyService: the owner's candy corn (one fixed id, scripts removed)
			H.ok(file == "src/server/CreatureModels.luau" or file == "src/server/CandyService.luau", `{file}: InsertService only for Config's own ids`)
			if file == "src/server/CandyService.luau" then
				H.ok(string.find(source, "LoadAsset, InsertService, Halloween.CANDY_ASSET)", 1, true) ~= nil, "only the candy corn")
				H.ok(string.find(source, "d:IsA(\"BaseScript\")", 1, true) ~= nil, "its scripts removed")
			end
		end
	end
end)

----------------------------------------------------------------------------------------------------
-- Sell spammed (owner bug report 2026-10-15): the real SellPlants handler (ShopService's onSell ->
-- PlotService.sellPlants -> Selling.sell), 10 times in a row for the same thing, pays it once.
----------------------------------------------------------------------------------------------------
H.test("security: Sell spammed 10 times in a row (the real SellPlants handler) pays once; the seed bag never goes negative", function()
	local onSell = Net.SellPlants.OnServerEvent.fn
	H.ok(type(onSell) == "function", "SellPlants is wired")
	local stallAt = Vector3.new(500, 3, 500)
	PlotService.init({}, { { Position = stallAt, Parent = true } } :: any) -- one SELL stall, no plots
	local ok, err = pcall(function()
		-- A rich player standing at the stall, seen there by the movement check
		local function atStall(): any
			local s = richSession()
			local char = body(stallAt + Vector3.new(3, 0, 0))
			s.player.Character = char
			seen(s, stallAt + Vector3.new(3, 0, 0))
			return s
		end
		local sold = 0 -- SoldPlants events (one per sale that paid)
		local function spam(s: any, paced: boolean, slots: any, ids: any, seeds: any): { number }
			local paid = {}
			for _ = 1, 10 do
				if paced then
					s.requests = {} -- (each one under the rate limit, so every one reaches PlotService.sellPlants)
				end
				local before = s.profile.money
				onSell(s.player, slots, ids, seeds)
				table.insert(paid, s.profile.money - before)
				for _, count in s.profile.seedBag do
					H.ok(count > 0, "no empty or negative seed-bag entry")
				end
			end
			return paid
		end
		local function onlyFirst(paid: { number }, what: string)
			H.ok(paid[1] > 0, `{what}: the first sale pays`)
			for i = 2, #paid do
				H.eq(paid[i], 0, `{what}: request {i} pays nothing`)
			end
		end
		with({ { Net.LootEvent, "FireClient", function(_, _, kind: string)
			if kind == "SoldPlants" then
				sold += 1
			end
		end } }, function()
			for _, paced in { false, true } do
				local how = if paced then "paced under the rate limit" else "back to back"
				-- one planted plant
				local s = atStall()
				local want = Selling.price(s.profile.plants[1], os.time(), Sessions.moneyMult(s), Sessions.growMult(s))
				sold = 0
				local paid = spam(s, paced, { 1 }, nil, nil)
				onlyFirst(paid, `plant ({how})`)
				H.near(paid[1], want, want * 0.01, "its price")
				H.eq(sold, 1, "one SoldPlants")
				H.eq(#s.profile.plants, 1, "only that plant went")
				-- one inventory plant
				s = atStall()
				sold = 0
				onlyFirst(spam(s, paced, {}, { 1 }, nil), `inventory plant ({how})`)
				H.eq(#s.profile.inventory, 0)
				H.eq(sold, 1)
				-- all the seeds of a label (the bag holds 2 of "1:1")
				s = atStall()
				local label, held = nil, 0
				for key, count in s.profile.seedBag do
					label = SeedPacks.labelKey(key)
					held += count
				end
				H.eq(held, 2, "(two seeds)")
				local seedPrice = Config.seedSellPrice(1, 1, nil, Sessions.moneyMult(s))
				sold = 0
				paid = spam(s, paced, {}, nil, { [label :: string] = held })
				onlyFirst(paid, `seeds ({how})`)
				H.near(paid[1], held * seedPrice, 1e-6, "both seeds, once")
				H.eq(SeedPacks.bagCount(s.profile.seedBag), 0, "the bag is empty, not negative")
				H.eq(sold, 1)
				-- "Sell 1" spammed: each request sells one more seed, only while there is one: never more than held
				s = atStall()
				local start = s.profile.money
				paid = spam(s, paced, {}, nil, { [label :: string] = 1 })
				local total = 0
				for _, p in paid do
					total += p
				end
				H.near(total, held * seedPrice, 1e-6, `Sell 1 x10 ({how}): paid for the 2 seeds there were, no more`)
				H.near(s.profile.money - start, total, 1e-6)
				H.eq(SeedPacks.bagCount(s.profile.seedBag), 0)
				-- everything at once, ten times
				s = atStall()
				sold = 0
				paid = spam(s, paced, { 1, 2 }, { 1 }, { [label :: string] = 99 })
				onlyFirst(paid, `everything ({how})`)
				H.eq(#s.profile.plants + #s.profile.inventory + SeedPacks.bagCount(s.profile.seedBag), 0, "all sold")
				H.eq(sold, 1, "one sale")
			end
		end)
	end)
	PlotService.init({}, nil) -- (no stall again, as before)
	if not ok then
		error(err, 0)
	end
end)

return nil
