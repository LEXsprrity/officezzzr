-- A pack seed's flower, end to end as the live game runs it (owner bug 2026-10-15: "six Legendaries from the
-- Lotus Wyrm packs, all the same flower"): a PackSpirit10 receipt -> the HUD Inventory's Plant button (the key
-- its card sends: the smallest bag key of the label, HUD.client bagEntries) -> RequestUseItem "Seed:<key>"
-- -> PlaceSeed (the key Planting.client keeps) -> PlantSeed with that key -> the seedling's sprouting ends
-- (the payout loop's popSprout) -> the flower model, then a save and a rejoin. Every seed's flower must be the
-- one its own gene picks (CreatureModels.variantOf), so the flowers spread over the rarity's models.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local H = require("./harness")

local Config = H.shared("Config")
local SeedPacks = H.shared("SeedPacks")
local Planting = H.shared("Planting")

-- The server's Roblox side, mocked (the same tables as the other specs when they ran first)
local function signal(): any
	return { Connect = function(self, fn)
		self.fn = fn
	end }
end
H.services.MarketplaceService = H.services.MarketplaceService or {
	UserOwnsGamePassAsync = function()
		return false
	end,
	PromptGamePassPurchase = function() end,
	PromptProductPurchase = function() end,
	PromptGamePassPurchaseFinished = signal(),
}
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

local ProfileStore = H.server("ProfileStore")
local Sessions = H.server("Sessions")
local SpeedLogic = H.server("SpeedLogic")
local Shop = H.server("Shop")
local CreatureModels = H.server("CreatureModels")
local Seedling = H.server("Seedling")
local PlantGhosts = H.server("PlantGhosts")
local TreadmillBoard = H.server("TreadmillBoard")
local WorldBuilder = H.server("WorldBuilder")
local PlotService = H.server("PlotService")
local ShopService = H.server("ShopService")

-- The HUD's Inventory list (HUD.client bagEntries, which a test can't require): seeds listed by label, each
-- card's Plant button planting the smallest key of its label. Checked against the HUD's source below.
local function inventoryKeys(seedBag: { [string]: number }): { [string]: string }
	local byLabel = {}
	for key in seedBag do
		local label = SeedPacks.labelKey(key)
		if SeedPacks.parseBagKey(key) and (byLabel[label] == nil or key < byLabel[label]) then
			byLabel[label] = key
		end
	end
	return byLabel
end

H.test("pack seeds: Inventory Plant -> PlantSeed -> sprouted -> rejoin: each flower is its own gene's (Lotus Wyrm x10)", function()
	local hud = fs.readFile("src/client/HUD.client.luau")
	H.ok(string.find(hud, "entry.key = if key < entry.key then key else entry.key", 1, true) ~= nil, "the HUD card plants the smallest key of its label")
	H.ok(string.find(hud, "RequestUseItem:FireServer(\"Seed:\" .. key)", 1, true) ~= nil, "its Plant button asks for that seed")
	local client = fs.readFile("src/client/Planting.client.luau")
	H.ok(string.find(client, "key = data.key, rarity = data.rarity", 1, true) ~= nil, "Planting.client keeps PlaceSeed's key")
	H.ok(string.find(client, "PlantSeed:FireServer(pos, if bag then bag.key else nil, yaw)", 1, true) ~= nil, "...and plants that key")

	-- A plot, as Main sets it up. Lune has no ProximityPrompt events, so PlotService.init stops at the board
	-- buttons, after the plot is registered (the treadmill board is built on the real belt).
	local info = table.clone(WorldBuilder.build()[1])
	local belt = info.belt
	info.belt = setmetatable({ GetPropertyChangedSignal = function()
		return signal()
	end }, { __index = function(_, k)
		return (belt :: any)[k]
	end }) :: any
	local realBoard = TreadmillBoard.build
	TreadmillBoard.build = function(model, _, center)
		return realBoard(model, belt, center)
	end
	pcall(PlotService.init, { info })
	TreadmillBoard.build = realBoard
	ShopService.init()
	PlantGhosts.publish(roblox.Instance.new("Folder"))

	-- Lune models have no PivotTo/ScaleTo/GetBoundingBox: the plot gets stand-ins that remember what was built
	-- (`pick`: the flower CreatureModels.build was asked for); the real build of that pick is checked below.
	local built: { any } = {}
	local function standIn(kind: string, pick: number?): any
		local body = roblox.Instance.new("Part")
		local anchor = roblox.Instance.new("Attachment")
		anchor.Name = "InfoAnchor"
		anchor.Parent = body
		local attrs = {}
		local m = { kind = kind, pick = pick, PrimaryPart = body, Name = "" }
		function m.SetAttribute(_, k, v)
			attrs[k] = v
		end
		function m.GetAttribute(_, k)
			return attrs[k]
		end
		function m.GetDescendants()
			return {}
		end
		function m.PivotTo() end
		function m.GetBoundingBox()
			return roblox.CFrame.new(), roblox.Vector3.new(1, 1, 1)
		end
		function m.Destroy()
			m.Parent = nil
		end
		table.insert(built, m)
		return m
	end
	local realBuild, realScale, realSeedling = CreatureModels.build, CreatureModels.applyScale, Seedling.build
	local placed: any = nil
	local realFire = Net.LootEvent.FireClient
	local ok, err = pcall(function()
		CreatureModels.build = function(_, _, _, pick)
			return standIn("flower", pick)
		end
		CreatureModels.applyScale = function() end
		Seedling.build = function()
			return standIn("seedling")
		end
		Net.LootEvent.FireClient = function(_, _, kind, data)
			if kind == "PlaceSeed" then
				placed = data
			end
		end

		local player = { Name = "Planter", DisplayName = "Planter", UserId = 87001, Parent = true, Character = nil :: any }
		function player.SetAttribute() end
		function player.GetAttribute(): any
			return nil
		end
		function player.FindFirstChild(): any
			return nil
		end
		local s = Sessions.create(player :: any, ProfileStore.defaultProfile(), false)
		local p = s.profile
		p.plotLevel = Config.PLOT_LEVEL_MAX
		assert(PlotService.assign(s), "a plot")

		-- Two x10 receipts. The rng is a fixed sequence; each seed's rarity draw (the first of its three:
		-- rarity, mutation, gene) is pushed to Legendary, so all twenty are Legendary with real genes.
		local rng = H.Random.new(20261015)
		local draw = 0
		local function roll(): number
			draw += 1
			local u = rng:NextNumber()
			return if draw % 3 == 1 then 0.99 + u * 0.0099 else u
		end
		for i = 1, 2 do
			local status = Shop.grantProduct(p, "PackSpirit10", `test-{i}`, 0, roll)
			H.eq(status, "granted")
		end
		H.eq(SeedPacks.bagCount(p.seedBag), 20)
		local genes: { [string]: number } = {}
		for key in p.seedBag do
			local zone, rarity, _, gene = SeedPacks.parseBagKey(key)
			H.eq(zone, 7, "a Lotus Wyrm seed")
			H.eq(rarity, Config.LEGENDARY)
			H.ok(gene ~= nil, `{key} has a gene`)
			genes[key] = gene :: number
		end

		local root = { Name = "HumanoidRootPart", CFrame = roblox.CFrame.new() }
		local hum = { Health = 100 }
		player.Character = {
			FindFirstChild = function(_, name: string): any
				return if name == "HumanoidRootPart" then root else nil
			end,
			FindFirstChildOfClass = function(_, class: string): any
				return if class == "Humanoid" then hum else nil
			end,
		}
		local expected: { [number]: string } = {} -- plant id -> the flower its seed's gene picks
		for _ = 1, Config.SLOTS_MAX do
			local keys = inventoryKeys(p.seedBag)
			local label, key = next(keys)
			if not key then
				break
			end
			-- the Plant button of the label's card (any label: each is planted the same way)
			placed = nil
			s.requests = {}
			Net.RequestUseItem.OnServerEvent.fn(player, "Seed:" .. key)
			H.ok(placed ~= nil, `{label}: PlaceSeed`)
			H.eq(placed.key, key, "the preview is for the card's seed")
			H.eq(placed.ghost, PlantGhosts.indexOf(7, Config.LEGENDARY, genes[key]), "its ghost is its gene's flower")
			-- standing on a free spot of the plot, clicking it (the server saw the character walk there)
			local x, z = Planting.autoPlace(info.beds, info.origin, p.plants :: any, Config.LEGENDARY)
			if not x then
				break
			end
			local pos = Planting.toWorld(info.origin, x, z :: number)
			root.CFrame = roblox.CFrame.new(pos)
			SpeedLogic.teleported(s.tracker, pos)
			s.tracker.at = os.clock()
			s.requests = {}
			local before = #p.plants
			Net.PlantSeed.OnServerEvent.fn(player, pos, placed.key, 0)
			H.eq(#p.plants, before + 1, `{key}: planted`)
			H.eq(p.seedBag[key], nil, "that very seed left the bag")
			local plant = p.plants[#p.plants]
			H.ok(plant.sproutUntil ~= nil, "a seedling first")
			expected[plant.slot] = CreatureModels.variantOf(7, Config.LEGENDARY, genes[key]) :: string
			H.eq(plant.variant, expected[plant.slot], `{key}: the flower its gene picks`)
		end
		local planted = 0
		for _ in expected do
			planted += 1
		end
		H.ok(planted >= 8, `planted {planted} seeds`)

		-- The sprouting ends (Grow Now / the payout loop: popSprout): each seedling becomes its own flower.
		local function flowersBuilt(): { [number]: string }
			local out = {}
			for _, m in built do
				local slot = tonumber(string.match(m.Name, "^Plant_(%d+)$"))
				if m.Parent ~= nil and m.kind == "flower" and slot then
					out[slot] = CreatureModels.variantOf(7, Config.LEGENDARY, m.pick) :: string
				end
			end
			return out
		end
		for _, plant in p.plants do
			plant.sproutUntil = os.time() - 1
			plant.plantedAt = os.time() - 1
		end
		PlotService.refreshSprouts(s)
		local flowers = flowersBuilt()
		local kinds = {}
		for slot, want in expected do
			H.eq(flowers[slot], want, `plant {slot}: grew into its own flower`)
			kinds[want] = true
		end
		local distinct = 0
		for _ in kinds do
			distinct += 1
		end
		H.ok(distinct >= 3, `{planted} Legendary seeds grew into {distinct} different flowers`)

		-- Saved and loaded again (a rejoin): the same flowers.
		local loaded = ProfileStore.deserialize(ProfileStore.serialize(p))
		PlotService.release(player :: any)
		local s2 = Sessions.create(player :: any, loaded, false)
		table.clear(built)
		assert(PlotService.assign(s2), "the plot again")
		flowers = flowersBuilt()
		for slot, want in expected do
			H.eq(flowers[slot], want, `plant {slot}: the same flower after a rejoin`)
		end
		PlotService.release(player :: any)
		Sessions.remove(player :: any)
	end)
	CreatureModels.build, CreatureModels.applyScale, Seedling.build = realBuild, realScale, realSeedling
	Net.LootEvent.FireClient = realFire
	if not ok then
		error(err, 0)
	end

	-- ...and the real build of each pick is that flower's model.
	for i, name in CreatureModels.variants(7, Config.LEGENDARY) do
		H.eq(CreatureModels.build(7, Config.LEGENDARY, nil, i):GetAttribute("Asset"), name, `pick {i} builds {name}`)
		H.eq(CreatureModels.build(7, Config.LEGENDARY, "Gold", i):GetAttribute("Asset"), name, `a Gold pick {i} too`)
	end
end)

return nil
