-- Gamepasses: 2x Speed, 2x Luck, VIP and Fast Grow next to 2x Money and +10 Slots. Each pass's effect
-- applies only to its owner; ownership is decided only on the server (UserOwnsGamePassAsync at join, and
-- after PromptGamePassPurchaseFinished reports a purchase); the Shop's PASSES cards show it.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("./harness")
local Vector3 = H.Vector3

local Config = H.shared("Config")
local Treadmill = H.shared("Treadmill")
local PassCards = H.shared("PassCards")
local ProfileStore = H.server("ProfileStore")
local SpeedLogic = H.server("SpeedLogic")
local Selling = H.server("Selling")
local Inventory = H.server("Inventory")

local NOW = 1_800_000_000

-- The server's Roblox side, mocked: the marketplace answers ownership from `owned` (pass id -> true) and
-- records prompts; remotes record their handler.
local function signal(): any
	return { Connect = function(self, fn)
		self.fn = fn
	end }
end
local owned: { [number]: boolean } = {}
local prompted: { number } = {}
local toasts: { string } = {}
local Marketplace = {
	UserOwnsGamePassAsync = function(_, _userId: number, id: number): boolean
		return owned[id] == true
	end,
	PromptGamePassPurchase = function(_, _player: any, id: number)
		table.insert(prompted, id)
	end,
	PromptProductPurchase = function() end,
	PromptGamePassPurchaseFinished = signal(),
}
H.services.MarketplaceService = Marketplace
H.services.Players = H.services.Players or { GetPlayerByUserId = function() return nil end }
local Net = H.stubServer("Net", { StatsUpdate = { FireClient = function() end }, LootEvent = { FireClient = function() end }, toast = function() end })
for _, name in { "RequestBuy", "RequestUseItem", "SellPlants", "PlantSeed" } do
	Net[name] = Net[name] or { OnServerEvent = signal() }
end
local realToast = Net.toast
Net.toast = function(_player: any, text: string, ...)
	table.insert(toasts, text)
	return realToast(_player, text, ...)
end
local Sessions = H.server("Sessions")
local SpeedService = H.server("SpeedService")
local SeedService = H.server("SeedService")
local PlotService = H.server("PlotService")
local ShopService = H.server("ShopService")
local VipService = H.server("VipService")

-- A player the server can tag: attributes, a character with a Head.
local nextId = 7000
local function player(): any
	nextId += 1
	local attributes = {}
	local p = { Name = `P{nextId}`, DisplayName = `P{nextId}`, UserId = nextId, Parent = true, Character = nil :: any }
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

local function session(passes: { [string]: boolean }?): any
	local s = Sessions.create(player(), ProfileStore.defaultProfile(), false)
	for name, v in passes or {} do
		s.passes[name] = v
	end
	return s
end

-- Runs fn with some pass ids set (as if pasted from the Creator Dashboard), then puts the stubs back.
local function withPassIds(ids: { [string]: number }, fn: () -> ())
	local old = {}
	for name, id in ids do
		old[name] = Config.GAMEPASSES[name].id
		Config.GAMEPASSES[name].id = id
	end
	local ok, err = pcall(fn)
	for name, id in old do
		Config.GAMEPASSES[name].id = id
	end
	if not ok then
		error(err, 0)
	end
end

----------------------------------------------------------------------------------------------------
-- Config: every pass listed, priced and described; the multipliers
----------------------------------------------------------------------------------------------------
H.test("passes: six gamepasses, each with an id stub, a label, a price, a benefit line and a place in the Shop", function()
	local prices = { DoubleSpeed = 299, DoubleLuck = 249, VIP = 399, FastGrow = 149 }
	local names = Config.passNames()
	H.eq(#names, 6)
	H.deepEq(names, { "DoubleMoney", "DoubleSpeed", "DoubleLuck", "VIP", "FastGrow", "ExtraSlots" })
	for _, name in names do
		local pass = Config.GAMEPASSES[name]
		H.eq(pass.id, 0, `{name}: id 0 until the owner creates it`)
		H.ok(type(pass.label) == "string" and pass.label ~= "" and type(pass.about) == "string" and #pass.about <= 34, `{name}: label and a short line`)
		H.ok(type(pass.robux) == "number", name)
		if prices[name] then
			H.eq(pass.robux, prices[name], `{name}'s price`)
		end
	end
	local readme = fs.readFile("README.md")
	for _, name in names do
		H.ok(string.find(readme, "`" .. name .. "`", 1, true) ~= nil, `README lists {name}`)
	end
end)

H.test("passes: the multipliers apply only to what you own, and stack (VIP x 2x)", function()
	H.eq(Config.passSpeedMult(nil), 1)
	H.eq(Config.passSpeedMult({}), 1)
	H.eq(Config.passSpeedMult({ DoubleSpeed = true }), 2)
	H.eq(Config.passSpeedMult({ VIP = true }), 1.25)
	H.eq(Config.passSpeedMult({ DoubleSpeed = true, VIP = true }), 2.5)
	H.eq(Config.passSpeedMult({ DoubleMoney = true, DoubleLuck = true, FastGrow = true, ExtraSlots = true }), 1, "other passes: no Speed")
	H.eq(Config.passMoneyMult({ DoubleMoney = true }), 2)
	H.eq(Config.passMoneyMult({ VIP = true }), 1.25)
	H.eq(Config.passMoneyMult({ DoubleMoney = true, VIP = true }), 2.5)
	H.eq(Config.passMoneyMult({ DoubleSpeed = true, FastGrow = true }), 1, "other passes: no money")
	H.eq(Config.passLuckMult({ DoubleLuck = true }), 2)
	H.eq(Config.passLuckMult({ VIP = true }), 1)
	H.eq(Config.passGrowMult({ FastGrow = true }), 2)
	H.eq(Config.passGrowMult({ VIP = true, DoubleSpeed = true }), 1)
	-- money: plot level x passes; the old boolean form still means 2x Money
	H.near(Config.moneyMult(7, { DoubleMoney = true, VIP = true }), Config.plotMoneyMult(7) * 2.5, 1e-9)
	H.near(Config.moneyMult(7, true), Config.plotMoneyMult(7) * 2, 1e-9)
	H.near(Config.moneyMult(7, false), Config.plotMoneyMult(7), 1e-9)
	H.near(Config.moneyMult(7, nil), Config.plotMoneyMult(7), 1e-9)
	-- the session reads the server's own passes
	local s = session({ DoubleMoney = true, VIP = true })
	H.near(Sessions.moneyMult(s), Config.plotMoneyMult(1) * 2.5, 1e-9, "VIP x 2x Money")
	H.eq(Sessions.moneyMult(session()), Config.plotMoneyMult(1), "no pass: plot level only")
end)

----------------------------------------------------------------------------------------------------
-- 2x Speed (and VIP's x1.25): walking and the treadmill, and every number that shows it
----------------------------------------------------------------------------------------------------
-- A character for SpeedService.tickPlayer: a table root (Lune's parts have no Position).
local function runner(s: any, at: Vector3): any
	local root = {}
	function root.move(self: any, pos: Vector3)
		self.CFrame = roblox.CFrame.new(pos)
		self.Position = pos
	end
	root:move(at)
	local hum = roblox.Instance.new("Humanoid")
	hum.Health = 100
	s.player.Character = {
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
	return root
end

-- What `s` gains in the server's ticks: walking `steps` normal steps (no plot), or standing on its belt.
local function gained(s: any, onBelt: boolean): number
	local belt = roblox.Instance.new("Part")
	belt.Size = Vector3.new(6, 1, 12)
	belt.CFrame = roblox.CFrame.new(0, 0, 0)
	s.plot = if onBelt then { belt = belt } else nil
	local root = runner(s, Vector3.new(0, 3, 0))
	for i = 1, 6 do -- warm the tracker up standing still (fills the movement budget)
		SpeedService.tickPlayer(s, Config.TICK, i)
	end
	local before = s.profile.speed
	local pos = Vector3.new(0, 3, 0)
	for i = 1, 10 do
		if not onBelt then
			pos += Vector3.new(16 * Config.TICK * 0.8, 0, 0) -- (the same steps for both, whatever their WalkSpeed)
			root:move(pos)
		end
		SpeedService.tickPlayer(s, Config.TICK, 10 + i)
	end
	return s.profile.speed - before
end

H.test("2x Speed: owners gain double Speed walking and on the treadmill (server ticks); others don't", function()
	for _, case in { { passes = { DoubleSpeed = true }, mult = 2 }, { passes = { VIP = true }, mult = 1.25 }, { passes = { DoubleSpeed = true, VIP = true }, mult = 2.5 } } do
		for _, onBelt in { false, true } do
			local plain, owner = session(), session(case.passes)
			local a, b = gained(plain, onBelt), gained(owner, onBelt)
			H.ok(a > 0, "the plain player gains")
			H.near(b / a, case.mult, 1e-6, `{if onBelt then "treadmill" else "walking"}: x{case.mult}`)
		end
	end
	-- the treadmill pays the same number its sign, the popups and the Shop show
	local s = session({ DoubleSpeed = true })
	s.profile.treadmillTier = 3
	local perSecond = Treadmill.perSecond(3, s.profile.equippedTrail, Config.passSpeedMult(s.passes))
	H.near(perSecond, Config.treadmillRate(3) * 2, 1e-9, "the shown rate is doubled")
	H.near(Sessions.treadmillPerSecond(s), perSecond, 1e-9)
	H.near(SpeedLogic.treadmillGain(1, 3, Sessions.speedMult(s)), perSecond, 1e-9, "the server's second")
	H.near(Config.speedPerStud(nil, 2), Config.BASE_SPEED_PER_STUD * 2, 1e-9, "+X/step doubled")
	H.eq(Treadmill.perSecond(3, nil), Config.treadmillRate(3), "no pass: unchanged")
	-- every place that shows it passes the owner's Speed passes
	local plot = fs.readFile("src/server/PlotService.luau")
	H.ok(string.find(plot, "Treadmill.perSecond(tier, s.profile.equippedTrail, Sessions.passSpeedMult(s))", 1, true) ~= nil, "the +X/s sign and board")
	local effects = fs.readFile("src/client/Effects.client.luau")
	H.ok(string.find(effects, "Config.passSpeedMult(stats.passes)", 1, true) ~= nil and string.find(effects, "stats.passes = partial.passes", 1, true) ~= nil,
		"the popups over the runner")
	local hud = fs.readFile("src/client/HUD.client.luau")
	H.ok(string.find(hud, "Treadmill.perSecond(t, stats.equippedTrail, Config.passSpeedMult(stats.passes))", 1, true) ~= nil, "the Shop's treadmill card")
	H.ok(string.find(hud, "Config.speedPerStud(stats.equippedTrail, Config.passSpeedMult(stats.passes))", 1, true) ~= nil, "the +X/step")
end)

----------------------------------------------------------------------------------------------------
-- 2x Luck: re-drawn for the thief, never below what the pod showed, exactly 2x-luck odds
----------------------------------------------------------------------------------------------------
H.test("2x Luck: the upgrade never lowers a rarity, and without the pass changes nothing", function()
	local rng = H.Random.new(5)
	for k in Config.ZONES do
		for _, luck in { 1, Config.NIGHT_LUCK } do
			for r = 1, Config.LEGENDARY do
				for _ = 1, 200 do
					local out = Config.luckUpgrade(k, r, luck, 2, function()
						return rng:NextNumber()
					end)
					H.ok(out >= r and out <= Config.LEGENDARY, `zone {k} rarity {r}: {out}`)
				end
				H.eq(Config.luckUpgrade(k, r, luck, 1, error :: any), r, "luck x1: the pod's own, no roll")
			end
		end
	end
end)

H.test("2x Luck: over many pods, the owner's rarities follow the double-luck odds (Legendary x2 too)", function()
	local rng = H.Random.new(11)
	local function u(): number
		return rng:NextNumber()
	end
	local N = 400000
	for _, k in { 1, 4, 7 } do
		for _, luck in { 1, Config.NIGHT_LUCK } do
			local counts = table.create(Config.LEGENDARY, 0)
			for _ = 1, N do
				local pod = Config.rollSeed(k, luck, false, u)
				local r = Config.luckUpgrade(k, pod, luck, 2, u)
				counts[r] += 1
			end
			local want = Config.rarityWeights(k, luck * 2)
			for r = 1, Config.LEGENDARY do
				local p = want[r]
				local sigma = math.sqrt(p * (1 - p) / N)
				H.ok(math.abs(counts[r] / N - p) < 5 * sigma + 1e-6, `zone {k} luck {luck} rarity {r}: {counts[r] / N} vs {p}`)
			end
			H.near(want[Config.LEGENDARY], Config.legendaryChance(k, luck) * 2, 1e-12, "Legendary chance x2")
		end
	end
end)

local function nestInfos(): { any }
	local infos = {}
	for k in Config.ZONES do
		local model = roblox.Instance.new("Model")
		model.Name = "PassNest_" .. k
		model.Parent = H.workspace
		local pods = {}
		for i = 1, Config.PODS_PER_NEST do
			pods[i] = roblox.CFrame.new(Config.nestCenter(k) + Config.podOffset(k, i))
		end
		infos[k] = { zone = k, model = model, center = Config.nestCenter(k), podCFrames = pods, guardHome = Config.nestCenter(k) }
	end
	return infos
end

-- A thief standing at the pod, with a torso to carry on.
local function thief(passes: { [string]: boolean }?, at: Vector3): any
	local s = session(passes)
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
	-- the server's movement check has seen them there (SpeedService.trustedRoot)
	SpeedLogic.teleported(s.tracker, at)
	s.tracker.at = os.clock()
	return s
end

H.test("2x Luck: at steal time the owner's seed is re-drawn (only up), others get the pod's; caught, it goes back as shown", function()
	SeedService.buildPods(nestInfos())
	local zone, index = 1, 1
	local pod = SeedService.pods(zone)[index]
	local at = pod.part.CFrame.Position + Vector3.new(1, 0, 0)
	local upgrades, plainUps = 0, 0
	local lucky = thief({ DoubleLuck = true }, at)
	for i = 1, 300 do
		pod.rarity, pod.gene, pod.luck = 1, i * 2399, 1 -- a Common, a fresh seed each time
		local s = if i % 2 == 0 then lucky else thief(nil, at)
		SeedService.steal(s.player, zone, index)
		H.ok(s.carry ~= nil, "stolen")
		H.ok(s.carry.rarity >= 1, "never lower")
		if s.passes.DoubleLuck then
			upgrades += if s.carry.rarity > 1 then 1 else 0
			-- stealing the same seed again gives the same rarity (the pass can't be farmed by getting caught)
			local first = s.carry.rarity
			SeedService.returnCarry(s.player)
			H.eq(pod.rarity, 1, "back in its pod as the pod showed it, not upgraded")
			H.ok(pod.available, "shown again")
			SeedService.steal(s.player, zone, index)
			H.eq(s.carry.rarity, first, "the same seed and thief: the same draw")
		else
			plainUps += if s.carry.rarity ~= 1 then 1 else 0
		end
		SeedService.returnCarry(s.player)
	end
	H.eq(plainUps, 0, "without the pass a Common stays Common")
	H.ok(upgrades > 0, `with it some Commons come out rarer ({upgrades}/150)`)
	-- the draw depends on the seed and the thief
	H.ok(SeedService.luckRoll(5, 1) ~= SeedService.luckRoll(6, 1) and SeedService.luckRoll(5, 1) ~= SeedService.luckRoll(5, 2))
	for _, g in { 1, 77, Config.SEED_GENES } do
		local x = SeedService.luckRoll(g, 123456789)
		H.ok(x >= 0 and x < 1, "in [0, 1)")
	end
end)

----------------------------------------------------------------------------------------------------
-- Fast Grow: plants age twice as fast, offline too; the inventory keeps the growth
----------------------------------------------------------------------------------------------------
H.test("Fast Grow: the owner's plants are full-grown in half GROW_TIME, offline included; others' aren't", function()
	local half = Config.GROW_TIME / 2
	H.eq(Config.plantAge(NOW - half, NOW, 2), Config.GROW_TIME)
	H.eq(Config.plantAge(NOW - half, NOW, nil), half)
	H.eq(Config.plantAge(NOW + 5, NOW, 2), 0, "never negative")
	local plant = { slot = 1, zone = 3, rarity = 2, plantedAt = NOW - half, x = 0, z = 0, variance = 1 }
	local full = Config.plantWeight(3, 2, Config.GROW_TIME, 1)
	H.near((PlotService.plantStats(plant, NOW, 2)), full, 1e-9, "owner: full-grown")
	H.ok((PlotService.plantStats(plant, NOW, 1)) < full - 1e-6, "others: still growing")
	H.near((PlotService.plantStats(plant, NOW)), (PlotService.plantStats(plant, NOW, 1)), 1e-12, "no pass = x1")

	-- offline: the owner's plants grew at 2x while away, so the offline pay is bigger
	local function offline(passes: { [string]: boolean }?): number
		local s = session(passes)
		local now = os.time()
		s.profile.lastSeen = now - half
		s.profile.plants = { { slot = 1, zone = 3, rarity = 2, plantedAt = now - half, x = 0, z = 0, variance = 1 } }
		local amount = PlotService.grantOffline(s)
		H.near(amount, PlotService.offlineIncomeOf(s.profile, now, Sessions.growMult(s)) * half * Sessions.moneyMult(s), amount * 1e-6)
		return amount
	end
	H.ok(offline({ FastGrow = true }) > offline(nil) * 1.05, "Fast Grow pays more offline (the plants grew faster)")

	-- selling and the inventory keep the owner's growth
	local profile = ProfileStore.defaultProfile()
	H.near(Selling.price(plant :: any, NOW, 1, 2), Config.plantIncome(3, 2, full, nil) * Config.SELL_STALL_SECONDS, 1e-6, "sold full-grown")
	profile.plants = { table.clone(plant) :: any }
	local entry = Inventory.take(profile, 1, NOW, 2)
	H.ok(entry ~= nil and entry.age == Config.GROW_TIME, "taken off the plot as grown as it was")
	local half2 = { slot = 2, zone = 3, rarity = 2, plantedAt = NOW - 100, x = 0, z = 0, variance = 1 }
	profile.plants = { half2 :: any }
	local e2 = Inventory.take(profile, 2, NOW, 2) :: any
	H.eq(e2.age, 200, "100 s at 2x = 200 s of growth")
	local back = Inventory.toPlant(e2, 3, NOW, 0, 0, 2)
	H.eq(Config.plantAge(back.plantedAt, NOW, 2), 200, "planted again by the owner: the same growth, going on at 2x")
	H.near(Selling.price(Inventory.asPlant(e2, NOW), NOW, 1), Selling.price(back, NOW, 1, 2), 1e-9, "an inventory plant sells as it stands")
end)

----------------------------------------------------------------------------------------------------
-- Ownership: only the server decides it
----------------------------------------------------------------------------------------------------
H.test("passes: ownership is checked on the server (join and purchase); the client's request only prompts", function()
	ShopService.init()
	local buy = Net.RequestBuy.OnServerEvent.fn
	H.ok(buy ~= nil and Marketplace.PromptGamePassPurchaseFinished.fn ~= nil, "wired")

	-- id 0: "coming soon", nothing granted
	local s = session()
	table.clear(toasts)
	buy(s.player, "Pass:VIP")
	H.ok(#toasts == 1 and string.find(toasts[1], "coming soon", 1, true) ~= nil, `says coming soon ({toasts[1]})`)
	H.eq(s.passes.VIP, nil, "asking never grants")

	withPassIds({ VIP = 9001, FastGrow = 9002, DoubleLuck = 9003, DoubleSpeed = 9004 }, function()
		-- join: UserOwnsGamePassAsync
		owned = { [9001] = true, [9002] = true }
		local joined = session()
		ShopService.checkPasses(joined)
		H.ok(joined.passes.VIP == true and joined.passes.FastGrow == true, "owned passes found at join")
		H.ok(joined.passes.DoubleLuck == nil and joined.passes.DoubleSpeed == nil, "the rest not")
		H.eq(joined.player:GetAttribute("VIP"), true, "VIP: the chat attribute, set by the server")
		local head = joined.player.Character:FindFirstChild("Head")
		local tag = head:FindFirstChild(VipService.TAG)
		H.ok(tag ~= nil and tag:IsA("BillboardGui"), "VIP: the tag over the head")
		local label = tag:FindFirstChild("Label")
		H.ok(label.Text == "VIP" and label.TextColor3 == VipService.GOLD and tag:FindFirstChild("Shadow") ~= nil
			and label:FindFirstChildOfClass("UIStroke") ~= nil, "gold relief text")
		owned = {}
		local nobody = session()
		ShopService.checkPasses(nobody)
		H.eq(next(nobody.passes), nil, "owns nothing")
		H.eq(nobody.player:GetAttribute("VIP"), nil, "no VIP attribute")
		H.eq(nobody.player.Character:FindFirstChild("Head"):FindFirstChild(VipService.TAG), nil, "no tag")

		-- a real id: the request prompts, and only Roblox's purchase signal grants
		table.clear(prompted)
		buy(nobody.player, "Pass:DoubleSpeed")
		H.deepEq(prompted, { 9004 })
		H.eq(nobody.passes.DoubleSpeed, nil, "prompted, not granted")
		Marketplace.PromptGamePassPurchaseFinished.fn(nobody.player, 9004, false)
		H.eq(nobody.passes.DoubleSpeed, nil, "cancelled: nothing")
		Marketplace.PromptGamePassPurchaseFinished.fn(nobody.player, 9004, true)
		H.eq(nobody.passes.DoubleSpeed, nil, "a purchase Roblox doesn't confirm (the client's report alone): nothing")
		owned[9004] = true -- Roblox has the purchase: UserOwnsGamePassAsync says so
		Marketplace.PromptGamePassPurchaseFinished.fn(nobody.player, 9004, true)
		H.eq(nobody.passes.DoubleSpeed, true, "bought: granted")
		H.eq(Sessions.passSpeedMult(nobody), 2, "and in effect at once")
		owned[9001] = true
		Marketplace.PromptGamePassPurchaseFinished.fn(nobody.player, 9001, true)
		H.eq(nobody.player:GetAttribute("VIP"), true, "VIP bought mid-game: the chat attribute")
		H.ok(nobody.player.Character:FindFirstChild("Head"):FindFirstChild(VipService.TAG) ~= nil, "...and the head tag")
		-- an owned pass isn't prompted again; junk names are ignored
		table.clear(prompted)
		buy(nobody.player, "Pass:DoubleSpeed")
		buy(nobody.player, "Pass:Nope")
		buy(nobody.player, "Pass:")
		H.eq(#prompted, 0)
	end)
	-- the chat tag reads only the server's attribute
	local chat = fs.readFile("src/client/VipChat.client.luau")
	H.ok(string.find(chat, "TextChatService.OnIncomingMessage", 1, true) ~= nil and string.find(chat, "GetAttribute(\"VIP\")", 1, true) ~= nil,
		"the [VIP] chat tag comes from the server's VIP attribute")
	local main = fs.readFile("src/server/Main.server.luau")
	H.ok(string.find(main, "VipService.dress(char, true)", 1, true) ~= nil, "a respawned VIP gets the tag again")
end)

----------------------------------------------------------------------------------------------------
-- The Shop's PASSES cards
----------------------------------------------------------------------------------------------------
H.test("Shop PASSES: a bright card per pass with its icon, name, benefit and green R$ button, or Owned", function()
	local grid = roblox.Instance.new("Frame")
	local bought = {}
	local deps = {
		card = function(g: any, order: number, view: any): any
			local c = roblox.Instance.new("Frame")
			c.LayoutOrder = order
			c.BackgroundColor3 = view.color
			c:SetAttribute("Title", view.title)
			c:SetAttribute("About", view.about)
			c:SetAttribute("Icon", view.icon or "VIP badge")
			c.Parent = g
			return c
		end,
		button = function(c: any, view: any, onClick: () -> ()): any
			local b = roblox.Instance.new("TextButton")
			b.Name = "Buy"
			b.Text = view.caption
			b.Parent = c
			c:SetAttribute("Owned", view.owned)
			return b
		end,
		price = function(pass: any): number
			return pass.robux
		end,
		buy = function(name: string)
			table.insert(bought, name)
		end,
	}
	local clicks = {}
	local realButton = deps.button
	deps.button = function(c: any, view: any, onClick: () -> ()): any
		clicks[view.name] = onClick
		return realButton(c, view, onClick)
	end
	local cards = PassCards.render(grid, { VIP = true }, deps)
	H.eq(#grid:GetChildren(), 6, "six cards")
	for i, name in Config.passNames() do
		local c = cards[name]
		H.ok(c ~= nil and c.Parent == grid and c.LayoutOrder == i and c.Name == "Pass_" .. name, name)
		H.eq(c:GetAttribute("Title"), string.upper(Config.GAMEPASSES[name].label))
		H.eq(c:GetAttribute("About"), Config.GAMEPASSES[name].about)
		H.ok(c.BackgroundColor3 == (PassCards.COLORS[name] or PassCards.DEFAULT_COLOR), `{name}: its own colour`)
	end
	H.eq(cards.VIP:FindFirstChild("Buy").Text, "Owned", "an owned pass says Owned")
	H.eq(cards.DoubleSpeed:FindFirstChild("Buy").Text, "R$ 299")
	H.eq(cards.FastGrow:FindFirstChild("Buy").Text, "R$ 149")
	H.eq(cards.DoubleLuck:FindFirstChild("Buy").Text, "R$ 249")
	H.eq(cards.DoubleSpeed:GetAttribute("Icon"), "Speed")
	H.eq(cards.VIP:GetAttribute("Icon"), "VIP badge", "VIP: the gold badge instead of an icon")
	clicks.VIP()
	clicks.DoubleLuck()
	H.deepEq(bought, { "DoubleLuck" }, "clicking an owned pass asks nothing")
	H.eq(PassCards.view("DoubleMoney", nil, 0).caption, "Buy", "no price known: Buy")
	H.eq(PassCards.view("DoubleMoney", nil, 1234).caption, "R$ 1,234", "the Dashboard's price once read")

	-- the HUD draws them with its Shop card style and asks GetProductInfo for gamepass prices
	local hud = fs.readFile("src/client/HUD.client.luau")
	for _, needle in {
		"PassCards.render(cardGrid(nextOrder(), WIDE_W, WIDE_H), stats.passes, {",
		"robuxPrice(pass, Enum.InfoType.GamePass)",
		"RequestBuy:FireServer(\"Pass:\" .. name)",
		"robuxColor(pass.id, ROBUX_GREEN)",
		"UiFx.relief(bold(badge, 5, {",
	} do
		H.ok(string.find(hud, needle, 1, true) ~= nil, needle)
	end
	H.ok(not string.find(hud, "{ \"DoubleMoney\", \"ExtraSlots\" }", 1, true), "every pass, not a fixed two")
end)

return nil
