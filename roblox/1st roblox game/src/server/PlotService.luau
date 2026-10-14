-- Plots: assignment, planting (server ProximityPrompt on the plot's pad), plant-creature models,
-- and income. Weight is a closed-form function of plantedAt: one payout loop, no per-plant ticking.
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local SeedPacks = require(Shared:WaitForChild("SeedPacks"))
local Icons = require(Shared:WaitForChild("Icons"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))
local SeedService = require(script.Parent:WaitForChild("SeedService"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))
local CreatureModels = require(script.Parent:WaitForChild("CreatureModels"))
local Shop = require(script.Parent:WaitForChild("Shop"))
local Selling = require(script.Parent:WaitForChild("Selling"))

local PlotService = {}

type PlotState = {
	info: WorldBuilder.PlotInfo,
	owner: Player?,
	models: { [number]: Model }, -- by slot
	scales: { [number]: number },
}

local plots: { PlotState } = {}
local sellStalls: { BasePart } = {} -- the SELL stalls' prompt parts (WorldBuilder.sellPoints)

----------------------------------------------------------------------------------------------------
-- Pure-ish helpers (also used for offline income)
----------------------------------------------------------------------------------------------------
function PlotService.plantStats(plant: ProfileStore.Plant, now: number): (number, number)
	local variance = Config.plantVariance(plant.plantedAt, plant.slot)
	local weight = Config.plantWeight(plant.zone, plant.rarity, now - plant.plantedAt, variance)
	return weight, Config.plantIncome(plant.zone, plant.rarity, weight, plant.mutation)
end

-- Base $/s of all plants (before money multipliers).
function PlotService.incomeOf(profile: ProfileStore.Profile, now: number): number
	local total = 0
	for _, plant in profile.plants do
		local _, income = PlotService.plantStats(plant, now)
		total += income
	end
	return total
end

-- $/s of all plants right now: base income times each plant's day/night multiplier (before money multipliers).
function PlotService.liveIncomeOf(profile: ProfileStore.Profile, now: number): number
	local isNight = Config.dayPhase(now)
	local total = 0
	for _, plant in profile.plants do
		local _, income = PlotService.plantStats(plant, now)
		total += income * Config.timeMult(plant.zone, isNight)
	end
	return total
end

-- Offline $/s: base income times the day/night multiplier averaged over a full cycle.
function PlotService.offlineIncomeOf(profile: ProfileStore.Profile, now: number): number
	local total = 0
	for _, plant in profile.plants do
		local _, income = PlotService.plantStats(plant, now)
		total += income * Config.averageTimeMult(plant.zone)
	end
	return total
end

----------------------------------------------------------------------------------------------------
-- Models
----------------------------------------------------------------------------------------------------
local function plantScale(plant: ProfileStore.Plant, weight: number): number
	return CreatureModels.scaleFor(plant.zone, plant.rarity, weight)
end

local function labelsFor(model: Model): (TextLabel?, TextLabel?)
	local gui = model:FindFirstChild("Info", true)
	if not gui then
		return nil, nil
	end
	return gui:FindFirstChild("Weight") :: TextLabel?, gui:FindFirstChild("Income") :: TextLabel?
end

-- "☀️ $12/s 1.5x!" in gold while the plant's phase is on, "🌙 $8/s" in green otherwise.
local INCOME_GREEN = Color3.fromRGB(120, 255, 120)
local INCOME_GOLD = Color3.fromRGB(255, 215, 60)
local function setIncomeLabel(label: TextLabel, zone: number, perSecond: number, isNight: boolean)
	local active = Config.isActiveTime(zone, isNight)
	local icon = Config.ACTIVE_ICONS[Config.ZONES[zone].active]
	label.Text = `{icon} {Format.money(perSecond)}/s{if active then string.format(" %gx!", Config.ACTIVE_TIME_MULT) else ""}`
	label.TextColor3 = if active then INCOME_GOLD else INCOME_GREEN
end

local function buildPlantModel(state: PlotState, plant: ProfileStore.Plant, weight: number, income: number, scale: number): Model
	local rarity = Config.RARITIES[plant.rarity]
	local mut = Config.mutationById(plant.mutation)
	-- The creature (with its rarity/mutation flair and "Mutation" attribute) comes from CreatureModels,
	-- built at the origin; it is pivoted onto the slot below.
	local model = CreatureModels.build(plant.zone, plant.rarity, plant.mutation)
	model.Name = "Plant_" .. plant.slot
	local body = model.PrimaryPart :: BasePart

	-- Info billboard (text refreshed by the payout loop). It hangs on an attachment at the creature's top,
	-- which ScaleTo moves as the creature grows; SizeOffset puts the billboard's bottom edge there.
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromOffset(170, 66)
	gui.Adornee = body:FindFirstChild("InfoAnchor") :: Attachment
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Parent = body
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = gui
	local function line(name: string, text: string, color: Color3, order: number)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 1 / 3, 0)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = text
		label.TextColor3 = color
		label.LayoutOrder = order
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = label
		label.Parent = gui
		return label
	end
	line("Name", SeedService.seedName(plant.zone, plant.rarity, plant.mutation), if mut then mut.color else rarity.color, 1)
	line("Weight", Format.weight(weight), Color3.new(1, 1, 1), 2)
	local isNight = Config.dayPhase(os.time())
	setIncomeLabel(line("Income", "", INCOME_GREEN, 3), plant.zone, income * Config.timeMult(plant.zone, isNight), isNight)

	-- Owner-only "remove" prompt (the client hides other players' prompts; the server re-checks).
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Remove"
	prompt.ObjectText = SeedService.seedName(plant.zone, plant.rarity, plant.mutation)
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt:SetAttribute("OwnerUserId", if state.owner then state.owner.UserId else 0)
	prompt.Parent = body:FindFirstChild("PromptAnchor") -- low on the creature, so it stays reachable when huge
	prompt.Triggered:Connect(function(player: Player)
		PlotService.removePlant(player, plant.slot)
	end)

	-- Stand on the soil facing the gate (slot CFrames look into the plot). The pivot is on the soil, so
	-- ScaleTo grows the creature from the ground up. Scale before parenting: one replication, not two.
	local rest = state.info.slotCFrames[plant.slot] * CFrame.new(0, Config.SOIL_HEIGHT, 0) * CFrame.Angles(0, math.pi, 0)
	model:PivotTo(rest)
	CreatureModels.applyScale(model, scale)
	model:SetAttribute("RestPivot", rest) -- the client's idle sway (Effects.client) animates around this
	model.Parent = state.info.plants
	return model
end

local function renderSoil(state: PlotState, count: number)
	state.info.soil:ClearAllChildren()
	for i = 1, count do
		local p = Instance.new("Part")
		p.Name = "Soil" .. i
		p.Anchored = true
		p.Size = Vector3.new(6, Config.SOIL_HEIGHT, 6)
		p.CanCollide = false
		p.CFrame = state.info.slotCFrames[i] * CFrame.new(0, Config.SOIL_HEIGHT / 2, 0) -- slot CFrames sit on the floor's top surface
		p.Color = Color3.fromRGB(120, 80, 50)
		p.Material = Enum.Material.Ground
		p.Parent = state.info.soil
	end
end

local function spawnPlant(state: PlotState, plant: ProfileStore.Plant, now: number)
	local weight, income = PlotService.plantStats(plant, now)
	local scale = plantScale(plant, weight)
	state.models[plant.slot] = buildPlantModel(state, plant, weight, income, scale)
	state.scales[plant.slot] = scale
end

local function clearPlants(state: PlotState)
	for _, m in state.models do
		m:Destroy()
	end
	state.models = {}
	state.scales = {}
end

----------------------------------------------------------------------------------------------------
-- Plants view for the client's Plants menu
----------------------------------------------------------------------------------------------------
local function pushPlants(s: Sessions.Session, now: number)
	local mult = Sessions.moneyMult(s)
	local isNight = Config.dayPhase(now)
	local view = {}
	for _, plant in s.profile.plants do
		local weight, income = PlotService.plantStats(plant, now)
		income *= mult * Config.timeMult(plant.zone, isNight)
		-- `sell`: what the SELL stall pays for it right now (Selling.price)
		table.insert(view, {
			slot = plant.slot, zone = plant.zone, rarity = plant.rarity, mutation = plant.mutation, weight = weight, income = income,
			sell = Selling.price(plant, now, mult),
		})
	end
	Sessions.push(s.player, { plants = view, slots = Sessions.maxSlots(s) })
end

local function refreshIncome(s: Sessions.Session, now: number)
	s.income = PlotService.liveIncomeOf(s.profile, now)
end

----------------------------------------------------------------------------------------------------
-- Planting and removing
----------------------------------------------------------------------------------------------------
local function plotOf(player: Player): PlotState?
	for _, state in plots do
		if state.owner == player then
			return state
		end
	end
	return nil
end

-- The first free slot if `player` stands at their own pad with room left, else nil (toasting why;
-- being too far is silent unless `farMessage` is given).
local function freeSlotAtPad(player: Player, s: Sessions.Session, state: PlotState, farMessage: string?): number?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - state.info.pad.Position).Magnitude > Config.PLANT_DISTANCE then
		if farMessage then
			Net.toast(player, farMessage, "red")
		end
		return nil
	end
	local used = {}
	for _, plant in s.profile.plants do
		used[plant.slot] = true
	end
	for i = 1, Sessions.maxSlots(s) do
		if not used[i] then
			return i
		end
	end
	Net.toast(player, "Your plot is full! Remove a plant or upgrade your plot (board at your plot's entrance).", "red")
	return nil
end

-- Plants a seed (carried or from the seed bag) into `slot`: model, Index, income and client updates.
local function plantSeed(player: Player, s: Sessions.Session, state: PlotState, slot: number, zone: number, rarity: number, mutation: string?)
	local now = os.time()
	local plant: ProfileStore.Plant = { slot = slot, zone = zone, rarity = rarity, mutation = mutation, plantedAt = now }
	table.insert(s.profile.plants, plant)
	spawnPlant(state, plant, now)

	-- Index (collection book)
	local newEntries = {}
	local keys = { `{zone}:{rarity}` }
	if mutation then
		table.insert(keys, `{zone}:{mutation}`)
	end
	for _, key in keys do
		if not s.profile.index[key] then
			s.profile.index[key] = true
			table.insert(newEntries, key)
		end
	end

	refreshIncome(s, now)
	pushPlants(s, now)
	Sessions.pushFull(s)
	local weight = PlotService.plantStats(plant, now)
	Net.LootEvent:FireClient(player, "Planted", {
		name = SeedService.seedName(zone, rarity, mutation),
		weight = weight,
		rarity = rarity,
		newIndex = newEntries,
	})
end

local function tryPlant(player: Player, state: PlotState)
	local s = Sessions.get(player)
	if not s or state.owner ~= player then
		return
	end
	if not s.carry then
		local hasBag = SeedPacks.bagCount(s.profile.seedBag) > 0
		Net.toast(player, if hasBag then "Steal a seed, or plant one from your 🌱 Seeds bag!" else "Steal a seed from the corridor first!", "red")
		return
	end
	local slot = freeSlotAtPad(player, s, state, nil)
	if not slot then
		return
	end
	local carry = SeedService.consumeCarry(player)
	if not carry then
		return
	end
	plantSeed(player, s, state, slot, carry.zone, carry.rarity, carry.mutation)
	if Config.announcesLegendary(carry.zone, carry.rarity, false) then
		Net.announce(Config.legendaryAnnouncement(player.DisplayName, carry.zone, carry.mutation), "gold")
	end
end

-- Plants one seed of kind `key` from the player's seed bag (seeds bought in packs), from the Seeds
-- menu. Same rules as the pad prompt: own plot, standing at the pad, a free slot.
function PlotService.plantFromBag(player: Player, key: string)
	local s = Sessions.get(player)
	local state = plotOf(player)
	local zone, rarity, mutation = SeedPacks.parseBagKey(key)
	if not s or not state or not zone or not rarity or (s.profile.seedBag[key] or 0) <= 0 then
		return
	end
	local slot = freeSlotAtPad(player, s, state, "Stand on your plot's planting pad to plant seeds from your bag.")
	if not slot or not SeedPacks.takeFromBag(s.profile.seedBag, key) then
		return
	end
	plantSeed(player, s, state, slot, zone, rarity, mutation)
end

function PlotService.removePlant(player: Player, slot: number)
	local s = Sessions.get(player)
	local state = plotOf(player)
	if not s or not state or type(slot) ~= "number" then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local model = state.models[slot]
	-- Measure from the prompt's anchor, not the body: a big creature's body can be 10+ studs up.
	local anchor = model and model.PrimaryPart and model.PrimaryPart:FindFirstChild("PromptAnchor")
	if not root or not anchor or not anchor:IsA("Attachment") or (root.Position - anchor.WorldPosition).Magnitude > 14 then
		return
	end
	for i, plant in s.profile.plants do
		if plant.slot == slot then
			local now = os.time()
			local _, income = PlotService.plantStats(plant, now)
			local refund = income * Config.SELL_SECONDS * Sessions.moneyMult(s)
			table.remove(s.profile.plants, i)
			model:Destroy()
			state.models[slot] = nil
			state.scales[slot] = nil
			s.profile.money += refund
			refreshIncome(s, now)
			pushPlants(s, now)
			Sessions.pushCore(s)
			Net.LootEvent:FireClient(player, "Sold", { amount = refund })
			return
		end
	end
end

-- The SELL stall (the HUD's Sell window, remote SellPlants): sells the plants in `slots` for
-- SELL_STALL_SECONDS of their income each (Selling). The player must stand within SELL_STALL_DISTANCE of
-- a SELL stall. Like removePlant: frees the slots, refreshes income and the plants view (saved by the
-- autosave).
function PlotService.sellPlants(player: Player, slots: any)
	local s = Sessions.get(player)
	local state = plotOf(player)
	if not s or not state then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local distance: number?, stall: BasePart? = nil, nil -- to the nearest stall
	for _, part in sellStalls do
		local d = if root and part.Parent then (root.Position - part.Position).Magnitude else nil
		if d and (distance == nil or d < distance) then
			distance, stall = d, part
		end
	end
	local now = os.time()
	local sale, why = Selling.sell(s.profile, slots, distance, now, Sessions.moneyMult(s))
	if not sale then
		if why == "far" then
			Net.toast(player, "Walk up to the SELL stall in the shop plaza to sell plants.", "red")
		elseif why == "none" then
			pushPlants(s, now) -- the window was showing plants that are gone: redraw it
		end
		return
	end
	for _, slot in sale.slots do
		local model = state.models[slot]
		if model then
			model:Destroy()
		end
		state.models[slot] = nil
		state.scales[slot] = nil
	end
	refreshIncome(s, now)
	pushPlants(s, now)
	Sessions.pushCore(s)
	local count = #sale.slots
	Net.LootEvent:FireClient(player, "SoldPlants", { amount = sale.total, count = count })
	if stall then
		Net.IncomePopup:FireClient(player, sale.total, stall.Position + Vector3.new(0, 6, 0))
	end
end

----------------------------------------------------------------------------------------------------
-- Plot upgrades: the board at each plot's gate (money or Robux), and the Shop's "PlotUpgrade" (money)
----------------------------------------------------------------------------------------------------
local UPGRADE_PROMPT_DISTANCE = 9

-- The board's two owner-only prompts (money and Robux).
local function upgradePrompts(state: PlotState): { ProximityPrompt }
	local list = {}
	for _, d in state.info.upgradeBoard:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			table.insert(list, d)
		end
	end
	return list
end

-- The purple button's price: the tier's placeholder until its product has an id, then the Dashboard
-- price. GetProductInfo works on the server too, and the price is the same for everyone who reads the
-- board, so the server fetches it once per id (cached, pcall'd) and redraws the boards when it arrives.
local robuxPrices: { [number]: number } = {}
local priceFetching: { [number]: boolean } = {}
local renderAllBoards: () -> ()
local function boardRobuxPrice(product: Config.DevProduct): number
	if product.id == 0 then
		return product.robux
	end
	local cached = robuxPrices[product.id]
	if cached then
		return cached
	end
	if not priceFetching[product.id] then
		priceFetching[product.id] = true
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, product.id, Enum.InfoType.Product)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				robuxPrices[product.id] = info.PriceInRobux
				renderAllBoards()
			else
				task.delay(60, function() -- let a later render try again
					priceFetching[product.id] = nil
				end)
			end
		end)
	end
	return product.robux
end

----------------------------------------------------------------------------------------------------
-- Treadmill upgrades: two owner-only prompts on each plot's belt (money or Robux, one tier at a time),
-- and the Shop's "TreadmillUpgrade" (money). They are added at runtime to whatever belt the map has.
----------------------------------------------------------------------------------------------------
-- The belt's two prompts (money and Robux).
local function treadmillPrompts(state: PlotState): { ProximityPrompt }
	local list = {}
	for _, d in state.info.belt:GetDescendants() do
		if d:IsA("ProximityPrompt") and string.sub(d.Name, 1, 9) == "Treadmill" then
			table.insert(list, d)
		end
	end
	return list
end

-- How close the owner must be to the belt's centre to see its prompts: anywhere on the belt, plus a bit
-- (the belt's size comes from the map, so a resized treadmill still works).
local function treadmillPromptDistance(belt: BasePart): number
	return math.max(10, math.max(belt.Size.X, belt.Size.Z) / 2 + 4)
end

-- The treadmill sign shows its owner's tier, what standing on it pays right now (WalkSpeed x Speed per
-- stud x the tier's multiplier, per second, like the HUD's "+X Speed/step") and the next tier's prices.
-- Refreshed with every payout. The prompts say what they buy; at the last tier they switch off.
local function renderTreadmillSign(state: PlotState)
	local s = state.owner and Sessions.get(state.owner)
	if not s then
		Icons.set(state.info.treadmillLabel, "Treadmill", "🏃 TREADMILL")
		return
	end
	local tier = s.profile.treadmillTier
	local mult = Sessions.treadmillMult(s)
	local perSecond = math.min(s.walkSpeed, Config.GAIN_CAP_STUDS_PER_TICK / Config.TICK) * Sessions.speedPerStud(s) * mult
	local price = Config.priceOf("TreadmillUpgrade", s.profile)
	local _, product = Config.treadmillUpgradeProduct(tier)
	local robux = if product then Format.robux(boardRobuxPrice(product)) else nil
	local nextLine = if price and robux then `\nNext x{Config.treadmillMult(tier + 1)}: {Format.money(price)} or {robux}` else "\nMAX TIER"
	Icons.set(state.info.treadmillLabel, "Treadmill",
		`🏃 TREADMILL x{mult} ({tier}/{Config.TREADMILL_MAX})\n+{Format.short(perSecond)} Speed/s{nextLine}`)
	for _, prompt in treadmillPrompts(state) do
		prompt.ActionText = if price then `Upgrade to x{Config.treadmillMult(tier + 1)}` else "Maxed"
		prompt.ObjectText = if prompt.Name == "TreadmillCash" then (if price then Format.money(price) else "")
			else (robux or "")
		prompt.MaxActivationDistance = if price then treadmillPromptDistance(state.info.belt) else 0
	end
end

-- Buys the next treadmill tier for money (from the belt's E prompt or the Shop).
function PlotService.upgradeTreadmill(player: Player)
	local s = Sessions.get(player)
	local state = plotOf(player)
	if not s or not state then
		return
	end
	local ok, msg = Shop.buy(s.profile, "TreadmillUpgrade")
	if not ok then
		Net.toast(player, if msg == "Maxed" then "Your treadmill is fully upgraded!" else msg, "red")
		return
	end
	renderTreadmillSign(state)
	Sessions.pushFull(s)
	Net.LootEvent:FireClient(player, "Bought", {
		itemId = "TreadmillUpgrade",
		label = `{msg}! Your treadmill pays x{Sessions.treadmillMult(s)} the walking Speed`,
	})
end

-- The belt's F prompt: opens the Robux prompt for the product of the treadmill's price tier (a product
-- without an id says "coming soon"). ProcessReceipt (ShopService) grants the tier.
function PlotService.promptRobuxTreadmill(player: Player)
	local s = Sessions.get(player)
	if not s then
		return
	end
	local name = Config.treadmillUpgradeProduct(s.profile.treadmillTier)
	if not name then
		Net.toast(player, "Your treadmill is fully upgraded!", "red")
		return
	end
	local product, why = Shop.canPrompt(s.profile, name)
	if not product then
		Net.toast(player, why or "Unknown product", "red")
		return
	end
	MarketplaceService:PromptProductPurchase(player, product.id)
end

-- After a treadmill tier from a Robux receipt: the sign and the prompts' prices.
function PlotService.refreshTreadmill(s: Sessions.Session)
	local state = plotOf(s.player)
	if state then
		renderTreadmillSign(state)
	end
end

-- The belt's prompts, either side of its middle: E buys with money, F with Robux (different keys, so
-- both show at once, like the Upgrade board). The client hides them from everyone but the owner; the
-- server re-checks the owner and the distance.
local TREADMILL_PROMPTS = {
	{ name = "TreadmillCash", side = 1, hold = 0.3, key = Enum.KeyCode.E, pad = Enum.KeyCode.ButtonX, buy = function(player: Player)
		PlotService.upgradeTreadmill(player)
	end },
	{ name = "TreadmillRobux", side = -1, hold = 0, key = Enum.KeyCode.F, pad = Enum.KeyCode.ButtonY, buy = function(player: Player)
		PlotService.promptRobuxTreadmill(player)
	end },
}

local function addTreadmillPrompts(state: PlotState)
	local belt = state.info.belt
	for _, spec in TREADMILL_PROMPTS do
		local anchor = Instance.new("Attachment")
		anchor.Name = spec.name .. "PromptAnchor"
		anchor.Position = Vector3.new(spec.side * belt.Size.X * 0.3, belt.Size.Y / 2 + 3, 0)
		anchor.Parent = belt
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = spec.name
		prompt.ActionText = "Upgrade"
		prompt.ObjectText = "Treadmill"
		prompt.HoldDuration = spec.hold
		prompt.MaxActivationDistance = treadmillPromptDistance(belt)
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = spec.key
		prompt.GamepadKeyCode = spec.pad
		prompt:SetAttribute("OwnerUserId", 0)
		prompt.Parent = anchor
		prompt.Triggered:Connect(function(player: Player)
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if state.owner == player and root and (root.Position - belt.Position).Magnitude <= treadmillPromptDistance(belt) + 6 then
				spec.buy(player)
			end
		end)
	end
end

-- Writes the owner's level and both prices on the board ("MAX LEVEL" and no buttons at the last level).
-- The prompts only work while there is a level to buy (Enabled is owned by the client-side owner filter).
local function renderUpgradeSign(state: PlotState)
	local s = state.owner and Sessions.get(state.owner)
	local level = if s then s.profile.plotLevel else nil
	local _, product = Config.plotUpgradeProduct(level or Config.PLOT_LEVEL_MAX)
	WorldBuilder.setUpgradeBoard(state.info.upgradeLabels, level, if product then boardRobuxPrice(product) else nil)
	for _, prompt in upgradePrompts(state) do
		prompt.MaxActivationDistance = if product then UPGRADE_PROMPT_DISTANCE else 0
	end
end

renderAllBoards = function()
	for _, state in plots do
		renderUpgradeSign(state)
		renderTreadmillSign(state)
	end
end

-- Buys the next plot level for money (from the board's red button or the Shop). The ExtraSlots pass
-- stacks on top of the level's slots.
function PlotService.upgrade(player: Player)
	local s = Sessions.get(player)
	local state = plotOf(player)
	if not s or not state then
		return
	end
	local ok, msg = Shop.buy(s.profile, "PlotUpgrade")
	if not ok then
		Net.toast(player, if msg == "Maxed" then "Your plot is fully upgraded!" else msg, "red")
		return
	end
	PlotService.refreshSlots(s)
	Sessions.pushFull(s)
	local level = s.profile.plotLevel
	Net.LootEvent:FireClient(player, "Bought", {
		itemId = "PlotUpgrade",
		label = `{msg}: {Config.plotSlots(level)} slots, cash x{Config.plotMoneyMult(level)}`,
	})
end

-- The board's purple button: opens the Robux prompt for the product of the plot's level tier (a product
-- without an id says "coming soon"). ProcessReceipt (ShopService) grants the level.
function PlotService.promptRobuxUpgrade(player: Player)
	local s = Sessions.get(player)
	if not s then
		return
	end
	local name = Config.plotUpgradeProduct(s.profile.plotLevel)
	if not name then
		Net.toast(player, "Your plot is fully upgraded!", "red")
		return
	end
	local product, why = Shop.canPrompt(s.profile, name)
	if not product then
		Net.toast(player, why or "Unknown product", "red")
		return
	end
	MarketplaceService:PromptProductPurchase(player, product.id)
end

-- The board's prompts, under its buttons (x: share of the board's width; seen from the front, the red
-- button is on the board's +X side).
local UPGRADE_PROMPTS = {
	{ name = "UpgradeCash", object = "Cash", x = 0.16, hold = 0.3, key = Enum.KeyCode.E, pad = Enum.KeyCode.ButtonX, buy = function(player: Player)
		PlotService.upgrade(player)
	end },
	{ name = "UpgradeRobux", object = "Robux", x = -0.23, hold = 0, key = Enum.KeyCode.F, pad = Enum.KeyCode.ButtonY, buy = function(player: Player)
		PlotService.promptRobuxUpgrade(player)
	end },
}

----------------------------------------------------------------------------------------------------
-- Assignment
----------------------------------------------------------------------------------------------------
-- `stalls`: the SELL stalls' prompt parts (WorldBuilder.sellPoints); none means plants can't be sold
-- at a stall (the R-key Remove still works).
function PlotService.init(infos: { WorldBuilder.PlotInfo }, stalls: { BasePart }?)
	sellStalls = stalls or {}
	for i, info in infos do
		local state: PlotState = { info = info, owner = nil, models = {}, scales = {} }
		plots[i] = state
		-- Two owner-only prompts on the gate's board (the client hides other players' prompts), one under
		-- each button: E buys with money, F with Robux. Different keys, so both show at once. The server
		-- re-checks the owner and the distance.
		local board = info.upgradeBoard
		for _, spec in UPGRADE_PROMPTS do
			local anchor = Instance.new("Attachment")
			anchor.Name = spec.name .. "PromptAnchor"
			anchor.Position = Vector3.new(spec.x * board.Size.X, -board.Size.Y / 2 - 0.6, 0)
			anchor.Parent = board
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = spec.name
			prompt.ActionText = "Upgrade"
			prompt.ObjectText = spec.object
			prompt.HoldDuration = spec.hold
			prompt.MaxActivationDistance = UPGRADE_PROMPT_DISTANCE
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = spec.key
			prompt.GamepadKeyCode = spec.pad
			prompt:SetAttribute("OwnerUserId", 0)
			prompt.Parent = anchor
			prompt.Triggered:Connect(function(player: Player)
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if state.owner == player and root and (root.Position - board.Position).Magnitude <= 14 then
					spec.buy(player)
				end
			end)
		end
		renderUpgradeSign(state)
		addTreadmillPrompts(state)
		renderTreadmillSign(state)

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Plant Seed"
		prompt.ObjectText = "Your plot"
		prompt.HoldDuration = 0.2
		prompt.MaxActivationDistance = Config.PLANT_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt:SetAttribute("OwnerUserId", 0)
		prompt.Parent = info.pad
		prompt.Triggered:Connect(function(player: Player)
			tryPlant(player, state)
		end)
	end
end

-- Returns the PlotInfo, or nil if all plots are taken.
function PlotService.assign(s: Sessions.Session): WorldBuilder.PlotInfo?
	for _, state in plots do
		if state.owner == nil then
			state.owner = s.player
			s.plot = state.info
			Icons.set(state.info.signLabel, "Home", `🏠 {s.player.DisplayName}'s Plot`)
			local padPrompt = state.info.pad:FindFirstChildOfClass("ProximityPrompt")
			if padPrompt then
				padPrompt:SetAttribute("OwnerUserId", s.player.UserId)
			end
			for _, boardPrompt in upgradePrompts(state) do
				boardPrompt:SetAttribute("OwnerUserId", s.player.UserId)
			end
			for _, beltPrompt in treadmillPrompts(state) do
				beltPrompt:SetAttribute("OwnerUserId", s.player.UserId)
			end
			renderTreadmillSign(state)
			renderUpgradeSign(state)
			state.info.model:SetAttribute("OwnerUserId", s.player.UserId)
			renderSoil(state, Sessions.maxSlots(s))
			local now = os.time()
			for _, plant in s.profile.plants do
				if plant.slot <= #state.info.slotCFrames then
					spawnPlant(state, plant, now)
				end
			end
			refreshIncome(s, now)
			pushPlants(s, now)
			return state.info
		end
	end
	return nil
end

function PlotService.release(player: Player)
	local state = plotOf(player)
	if not state then
		return
	end
	clearPlants(state)
	state.info.soil:ClearAllChildren()
	state.owner = nil
	Icons.set(state.info.signLabel, "Home", "🏠 Empty Plot")
	state.info.model:SetAttribute("OwnerUserId", nil)
	local padPrompt = state.info.pad:FindFirstChildOfClass("ProximityPrompt")
	if padPrompt then
		padPrompt:SetAttribute("OwnerUserId", 0)
	end
	for _, boardPrompt in upgradePrompts(state) do
		boardPrompt:SetAttribute("OwnerUserId", 0)
	end
	for _, beltPrompt in treadmillPrompts(state) do
		beltPrompt:SetAttribute("OwnerUserId", 0)
	end
	renderUpgradeSign(state)
	renderTreadmillSign(state)
end

-- After a plot upgrade (money or a Robux receipt) or the slots gamepass: soil, plants and the board.
function PlotService.refreshSlots(s: Sessions.Session)
	local state = plotOf(s.player)
	if state then
		renderSoil(state, Sessions.maxSlots(s))
		pushPlants(s, os.time())
		renderUpgradeSign(state)
	end
end

-- Offline earnings (capped): income of the plants as they are now, with the day/night multiplier
-- averaged over a cycle and the plot level / 2x Money multiplier, times time away.
function PlotService.grantOffline(s: Sessions.Session): number
	local last = s.profile.lastSeen
	if last <= 0 then
		return 0
	end
	local now = os.time()
	local away = math.clamp(now - last, 0, Config.OFFLINE_CAP_SECONDS)
	local amount = PlotService.offlineIncomeOf(s.profile, now) * away * Sessions.moneyMult(s)
	if amount > 0 then
		s.profile.money += amount
		Net.LootEvent:FireClient(s.player, "Offline", { amount = amount, seconds = away })
	end
	return amount
end

----------------------------------------------------------------------------------------------------
-- Payout loop: one pass over players every PAYOUT_INTERVAL; weight comes from the formula.
----------------------------------------------------------------------------------------------------
local function payout(s: Sessions.Session, state: PlotState, now: number)
	local mult = Sessions.moneyMult(s)
	local isNight = Config.dayPhase(now)
	local total = 0
	for _, plant in s.profile.plants do
		local weight, income = PlotService.plantStats(plant, now)
		local perSecond = income * Config.timeMult(plant.zone, isNight) * mult
		local earned = perSecond * Config.PAYOUT_INTERVAL
		total += earned
		local model = state.models[plant.slot]
		if model and model.PrimaryPart then
			local weightLabel, incomeLabel = labelsFor(model)
			if weightLabel then
				weightLabel.Text = Format.weight(weight)
			end
			if incomeLabel then
				setIncomeLabel(incomeLabel, plant.zone, perSecond, isNight) -- also flips ☀️/🌙 "1.5x!" on a phase change
			end
			local scale = plantScale(plant, weight)
			if math.abs(scale - (state.scales[plant.slot] or 1)) > 0.03 then
				CreatureModels.applyScale(model, scale) -- its Scale attribute makes the client re-read the rest pose
				state.scales[plant.slot] = scale
			end
			Net.IncomePopup:FireClient(s.player, earned, model.PrimaryPart.Position + Vector3.new(0, 3, 0))
		end
	end
	s.profile.money += total
	s.income = total / (mult * Config.PAYOUT_INTERVAL)
	renderTreadmillSign(state)
	Sessions.pushCore(s)
	pushPlants(s, now)
end

function PlotService.start()
	task.spawn(CreatureModels.preload) -- uploaded creature models, if any are configured (yields)
	task.spawn(function()
		while true do
			task.wait(Config.PAYOUT_INTERVAL)
			local now = os.time()
			for _, state in plots do
				local owner = state.owner
				local s = owner and Sessions.get(owner)
				if s then
					local ok, err = pcall(payout, s, state, now)
					if not ok then
						warn("[PlotService]", err)
					end
				end
			end
		end
	end)
end

return PlotService
