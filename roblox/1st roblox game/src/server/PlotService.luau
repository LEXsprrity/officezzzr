-- Plots: assignment, planting (server ProximityPrompt on the plot's pad), plant-creature models,
-- and income. Weight is a closed-form function of plantedAt: one payout loop, no per-plant ticking.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local SeedPacks = require(Shared:WaitForChild("SeedPacks"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))
local SeedService = require(script.Parent:WaitForChild("SeedService"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))

local PlotService = {}

type PlotState = {
	info: WorldBuilder.PlotInfo,
	owner: Player?,
	models: { [number]: Model }, -- by slot
	scales: { [number]: number },
}

local plots: { PlotState } = {}

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

----------------------------------------------------------------------------------------------------
-- Models
----------------------------------------------------------------------------------------------------
local function plantScale(plant: ProfileStore.Plant, weight: number): number
	-- Grows up to ~1.7x as weight approaches GROW_MAX_FACTOR x sprout weight.
	local ratio = weight / Config.sproutWeight(plant.zone, plant.rarity)
	return math.clamp(ratio ^ (1 / 3), 0.8, 2) * (0.9 + 0.1 * plant.rarity)
end

local function labelsFor(model: Model): (TextLabel?, TextLabel?)
	local gui = model:FindFirstChild("Info", true)
	if not gui then
		return nil, nil
	end
	return gui:FindFirstChild("Weight") :: TextLabel?, gui:FindFirstChild("Income") :: TextLabel?
end

local function buildPlantModel(state: PlotState, plant: ProfileStore.Plant, weight: number, income: number): Model
	local zone = Config.ZONES[plant.zone]
	local rarity = Config.RARITIES[plant.rarity]
	local mut = Config.mutationById(plant.mutation)
	local cf = state.info.slotCFrames[plant.slot]
	local model = Instance.new("Model")
	model.Name = "Plant_" .. plant.slot

	local function add(name: string, shape: Enum.PartType, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.CFrame = cf * offset
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.Parent = model
		return p
	end

	local bodyColor = if mut then mut.color else zone.seedColor
	local body = add("Body", Enum.PartType.Ball, Vector3.one * 3.4, CFrame.new(0, 2.2, 0), bodyColor, if mut then Enum.Material.Neon else Enum.Material.SmoothPlastic)
	model.PrimaryPart = body
	add("Pot", Enum.PartType.Block, Vector3.new(3, 1.2, 3), CFrame.new(0, 0.6, 0), Color3.fromRGB(190, 100, 60))
	for _, x in { -0.6, 0.6 } do
		add("Eye", Enum.PartType.Ball, Vector3.one * 0.8, CFrame.new(x, 2.7, -1.35), Color3.new(1, 1, 1))
		add("Pupil", Enum.PartType.Ball, Vector3.one * 0.4, CFrame.new(x, 2.7, -1.7), Color3.new(0, 0, 0))
	end
	for i = 0, 2 do
		local a = i * 2 * math.pi / 3
		add("Leaf", Enum.PartType.Block, Vector3.new(0.3, 1.8, 1.1),
			CFrame.new(math.cos(a) * 0.5, 4.2, math.sin(a) * 0.5) * CFrame.Angles(0, a, math.rad(25)),
			rarity.color, if plant.rarity >= 3 then Enum.Material.Neon else Enum.Material.Grass)
	end
	if plant.rarity >= 3 or mut then
		local light = Instance.new("PointLight")
		light.Color = if mut then mut.color else rarity.color
		light.Range = 8 + plant.rarity * 2
		light.Brightness = 2
		light.Parent = body
	end
	if mut then
		model:SetAttribute("Mutation", mut.id)
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(mut.color)
		sparkles.Rate = 6
		sparkles.Lifetime = NumberRange.new(0.6, 1.2)
		sparkles.Speed = NumberRange.new(1, 3)
		sparkles.Size = NumberSequence.new(0.5)
		sparkles.Parent = body
	end

	-- Info billboard (text refreshed by the payout loop)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromOffset(170, 66)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
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
	end
	line("Name", SeedService.seedName(plant.zone, plant.rarity, plant.mutation), if mut then mut.color else rarity.color, 1)
	line("Weight", Format.weight(weight), Color3.new(1, 1, 1), 2)
	line("Income", Format.money(income) .. "/s", Color3.fromRGB(120, 255, 120), 3)

	-- Owner-only "remove" prompt (the client hides other players' prompts; the server re-checks).
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Remove"
	prompt.ObjectText = SeedService.seedName(plant.zone, plant.rarity, plant.mutation)
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt:SetAttribute("OwnerUserId", if state.owner then state.owner.UserId else 0)
	prompt.Parent = body
	prompt.Triggered:Connect(function(player: Player)
		PlotService.removePlant(player, plant.slot)
	end)

	model.WorldPivot = cf -- scale from the ground, not the body's centre
	model.Parent = state.info.plants
	return model
end

local function renderSoil(state: PlotState, count: number)
	state.info.soil:ClearAllChildren()
	for i = 1, count do
		local p = Instance.new("Part")
		p.Name = "Soil" .. i
		p.Anchored = true
		p.Size = Vector3.new(6, 0.4, 6)
		p.CanCollide = false
		p.CFrame = state.info.slotCFrames[i] * CFrame.new(0, 0.2, 0) -- slot CFrames sit on the floor's top surface
		p.Color = Color3.fromRGB(120, 80, 50)
		p.Material = Enum.Material.Ground
		p.Parent = state.info.soil
	end
end

local function spawnPlant(state: PlotState, plant: ProfileStore.Plant, now: number)
	local weight, income = PlotService.plantStats(plant, now)
	local model = buildPlantModel(state, plant, weight, income)
	state.models[plant.slot] = model
	state.scales[plant.slot] = 1
	local scale = plantScale(plant, weight)
	model:ScaleTo(scale)
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
	local view = {}
	for _, plant in s.profile.plants do
		local weight, income = PlotService.plantStats(plant, now)
		table.insert(view, { slot = plant.slot, zone = plant.zone, rarity = plant.rarity, mutation = plant.mutation, weight = weight, income = income * mult })
	end
	Sessions.push(s.player, { plants = view, slots = Sessions.maxSlots(s) })
end

local function refreshIncome(s: Sessions.Session, now: number)
	s.income = PlotService.incomeOf(s.profile, now)
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
	Net.toast(player, "Your plot is full! Remove a plant or buy more slots.", "red")
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
	if not root or not model or not model.PrimaryPart or (root.Position - model.PrimaryPart.Position).Magnitude > 14 then
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
			s.profile.money += refund
			refreshIncome(s, now)
			pushPlants(s, now)
			Sessions.pushCore(s)
			Net.LootEvent:FireClient(player, "Sold", { amount = refund })
			return
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Assignment
----------------------------------------------------------------------------------------------------
function PlotService.init(infos: { WorldBuilder.PlotInfo })
	for i, info in infos do
		local state: PlotState = { info = info, owner = nil, models = {}, scales = {} }
		plots[i] = state
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
			state.info.signLabel.Text = `🏠 {s.player.DisplayName}'s Plot`
			local padPrompt = state.info.pad:FindFirstChildOfClass("ProximityPrompt")
			if padPrompt then
				padPrompt:SetAttribute("OwnerUserId", s.player.UserId)
			end
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
	state.info.signLabel.Text = "🏠 Empty Plot"
	state.info.model:SetAttribute("OwnerUserId", nil)
	local padPrompt = state.info.pad:FindFirstChildOfClass("ProximityPrompt")
	if padPrompt then
		padPrompt:SetAttribute("OwnerUserId", 0)
	end
end

-- After buying slots or a slots gamepass.
function PlotService.refreshSlots(s: Sessions.Session)
	local state = plotOf(s.player)
	if state then
		renderSoil(state, Sessions.maxSlots(s))
		pushPlants(s, os.time())
	end
end

-- Offline earnings (capped): income of the plants as they are now, times time away.
function PlotService.grantOffline(s: Sessions.Session): number
	local last = s.profile.lastSeen
	if last <= 0 then
		return 0
	end
	local now = os.time()
	local away = math.clamp(now - last, 0, Config.OFFLINE_CAP_SECONDS)
	local amount = PlotService.incomeOf(s.profile, now) * away * (if s.passes.DoubleMoney then 2 else 1)
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
	local total = 0
	for _, plant in s.profile.plants do
		local weight, income = PlotService.plantStats(plant, now)
		local earned = income * mult * Config.PAYOUT_INTERVAL
		total += earned
		local model = state.models[plant.slot]
		if model and model.PrimaryPart then
			local weightLabel, incomeLabel = labelsFor(model)
			if weightLabel then
				weightLabel.Text = Format.weight(weight)
			end
			if incomeLabel then
				incomeLabel.Text = Format.money(income * mult) .. "/s"
			end
			local scale = plantScale(plant, weight)
			if math.abs(scale - (state.scales[plant.slot] or 1)) > 0.03 then
				model:ScaleTo(scale)
				state.scales[plant.slot] = scale
			end
			Net.IncomePopup:FireClient(s.player, earned, model.PrimaryPart.Position + Vector3.new(0, 3, 0))
		end
	end
	s.profile.money += total
	s.income = total / (mult * Config.PAYOUT_INTERVAL)
	Sessions.pushCore(s)
	pushPlants(s, now)
end

function PlotService.start()
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
