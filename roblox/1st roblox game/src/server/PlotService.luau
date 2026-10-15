-- Plots: assignment, free planting (anywhere on your own dirt beds: the client sends a spot, the server checks
-- it with Shared/Planting), plant-creature models, and income. Weight is a closed-form function of
-- plantedAt: one payout loop, no per-plant ticking.
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local SeedPacks = require(Shared:WaitForChild("SeedPacks"))
local Icons = require(Shared:WaitForChild("Icons"))
local Treadmill = require(Shared:WaitForChild("Treadmill"))
local Planting = require(Shared:WaitForChild("Planting"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))
local SeedService = require(script.Parent:WaitForChild("SeedService"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))
local CreatureModels = require(script.Parent:WaitForChild("CreatureModels"))
local Shop = require(script.Parent:WaitForChild("Shop"))
local Selling = require(script.Parent:WaitForChild("Selling"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local PlantGhosts = require(script.Parent:WaitForChild("PlantGhosts"))
local Seedling = require(script.Parent:WaitForChild("Seedling"))
local SpeedService = require(script.Parent:WaitForChild("SpeedService"))

local TreadmillBoard = require(script.Parent:WaitForChild("TreadmillBoard"))

local PlotService = {}

type PlotState = {
	info: WorldBuilder.PlotInfo,
	treadmill: TreadmillBoard.Board, -- the treadmill's Upgrade board and "+X/s" text
	owner: Player?,
	models: { [number]: Model }, -- by plant id (`slot`)
	scales: { [number]: number },
	sprouting: { [number]: boolean }, -- by plant id: its model is the seedling (swapped for the flower when it is done)
	clicks: { ClickDetector }, -- the Upgrade boards' click/tap targets (both boards), owner-only
}

-- Where a plant stands: its saved spot (in the plot's space, Shared/Planting) on the top of the bed under
-- it, facing the way the player turned it (Planting.facing: `yaw` from facing the entrance; older plants
-- face the entrance). Off every bed (a hand-moved bed): on the floor.
local function restOf(info: WorldBuilder.PlotInfo, plant: ProfileStore.Plant): CFrame
	local pos = Planting.toWorld(info.origin, plant.x, plant.z)
	local bed = Planting.bedAt(info.beds, pos)
	if bed then
		pos = Planting.surface(bed, pos)
	end
	return CFrame.new(pos) * Planting.facing(info.origin, plant.yaw)
end

local plots: { PlotState } = {}
local sellStalls: { BasePart } = {} -- the SELL stalls' prompt parts (WorldBuilder.sellPoints)

----------------------------------------------------------------------------------------------------
-- Pure-ish helpers (also used for offline income)
----------------------------------------------------------------------------------------------------
-- `growMult`: the owner's Fast Grow (Sessions.growMult; 1 when nil), so their plants are as big as they
-- grew, offline time included. A seedling (Config.isSprouting) earns nothing yet.
function PlotService.plantStats(plant: ProfileStore.Plant, now: number, growMult: number?): (number, number)
	local variance = Config.varianceOf(plant)
	local weight = Config.plantWeight(plant.zone, plant.rarity, Config.plantAge(plant.plantedAt, now, growMult), variance)
	if Config.isSprouting(plant, now) then
		return weight, 0
	end
	return weight, Config.plantIncome(plant.zone, plant.rarity, weight, plant.mutation)
end

-- Base $/s of all plants (before money multipliers).
function PlotService.incomeOf(profile: ProfileStore.Profile, now: number, growMult: number?): number
	local total = 0
	for _, plant in profile.plants do
		local _, income = PlotService.plantStats(plant, now, growMult)
		total += income
	end
	return total
end

-- $/s of all plants right now: base income times each plant's day/night multiplier (before money multipliers).
function PlotService.liveIncomeOf(profile: ProfileStore.Profile, now: number, growMult: number?): number
	local isNight = Config.dayPhase(now)
	local total = 0
	for _, plant in profile.plants do
		local _, income = PlotService.plantStats(plant, now, growMult)
		total += income * Config.timeMult(plant.zone, isNight)
	end
	return total
end

-- Offline $/s: base income times the day/night multiplier averaged over a full cycle.
function PlotService.offlineIncomeOf(profile: ProfileStore.Profile, now: number, growMult: number?): number
	local total = 0
	for _, plant in profile.plants do
		local _, income = PlotService.plantStats(plant, now, growMult)
		total += income * Config.averageTimeMult(plant.zone)
	end
	return total
end

-- What the plants earned over the last `away` seconds before `now` (before money multipliers): each one
-- its offline $/s for the part of that time after it sprouted (sprouting goes on offline; a seedling
-- earns nothing until it is done).
function PlotService.offlineEarnings(profile: ProfileStore.Profile, now: number, away: number, growMult: number?): number
	local total = 0
	for _, plant in profile.plants do
		local earning = math.clamp(now - (plant.sproutUntil or -math.huge), 0, away)
		if earning > 0 then
			local _, income = PlotService.plantStats(plant, now, growMult)
			total += income * Config.averageTimeMult(plant.zone) * earning
		end
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

-- "$12/s" in green during the plant's phase (x1), "$8/s · Night x0.8" in a muted grey out of it.
local INCOME_GREEN = Color3.fromRGB(120, 255, 120)
local function setIncomeLabel(label: TextLabel, zone: number, perSecond: number, isNight: boolean)
	local bonus = Config.bonusLabel(zone, isNight)
	label.Text = `{Format.money(perSecond)}/s{if bonus then " · " .. bonus else ""}`
	label.TextColor3 = if bonus then Config.OFF_TIME_COLOR else INCOME_GREEN
end

-- What a plant is called: the flower model it grew into (its `variant`, drawn when it was planted; older
-- plants: CreatureModels.variantOf with its id, the same pick as its model), after its mutation: "Daisy",
-- "Gold Desert Wild Flower". Without plant models (the built-in creature) it goes by its zone's seed.
function PlotService.plantName(plant: ProfileStore.Plant): string
	local prefix = if plant.mutation then plant.mutation .. " " else ""
	local variant = CreatureModels.flowerOf(plant.zone, plant.rarity, plant.variant, plant.slot)
	if not variant then
		return `{prefix}{Config.RARITIES[plant.rarity].id} {Config.ZONES[plant.zone].seed}`
	end
	return `{prefix}{Format.plantName(variant)}`
end

local SPROUTING_INK = Color3.fromRGB(200, 240, 170)
local function buildPlantModel(state: PlotState, plant: ProfileStore.Plant, weight: number, income: number, scale: number): Model
	local rarity = Config.RARITIES[plant.rarity]
	local mut = Config.mutationById(plant.mutation)
	-- The creature (with its rarity/mutation flair and "Mutation" attribute) comes from CreatureModels,
	-- built at the origin; it is pivoted onto the slot below. While it sprouts: the seedling instead, with
	-- its end time and owner as attributes (Client/Sprouts shows the countdown and the owner's Grow now).
	local sprouting = Config.isSprouting(plant, os.time())
	local model = if sprouting then Seedling.build(plant.zone, plant.rarity, plant.mutation)
		else CreatureModels.build(plant.zone, plant.rarity, plant.mutation, CreatureModels.pickOf(plant.zone, plant.rarity, plant.variant, plant.slot))
	model.Name = "Plant_" .. plant.slot
	if sprouting then
		model:SetAttribute("SproutUntil", plant.sproutUntil)
		model:SetAttribute("OwnerUserId", if state.owner then state.owner.UserId else 0)
	end
	local body = model.PrimaryPart :: BasePart

	-- Info billboard (text refreshed by the payout loop). It hangs on an attachment at the creature's top,
	-- which ScaleTo moves as the creature grows; SizeOffset puts the billboard's bottom edge there.
	-- Hidden: the client shows it only while the mouse is over the plant or a finger tapped it (PlantHover.client).
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Enabled = false
	gui.Size = UDim2.fromOffset(170, 66)
	gui.Adornee = body:FindFirstChild("InfoAnchor") :: Attachment
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.MaxDistance = 60
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
	line("Name", PlotService.plantName(plant), if mut then mut.color else rarity.color, 1)
	local isNight = Config.dayPhase(os.time())
	local incomeLine = line("Income", "", INCOME_GREEN, 3)
	if sprouting then
		incomeLine.Name = "Sprouting" -- (the payout loop leaves it be; the countdown is the client's)
		incomeLine.Text = "Sprouting"
		incomeLine.TextColor3 = SPROUTING_INK
	else
		setIncomeLabel(incomeLine, plant.zone, income * Config.timeMult(plant.zone, isNight), isNight)
	end
	-- No prompt on the plant: it is removed from the HUD's Plants panel (remote RemovePlant).

	-- Stand on the dirt facing the entrance. The pivot is on the dirt, so ScaleTo grows the creature from
	-- the ground up. Scale before parenting: one replication, not two.
	local rest = restOf(state.info, plant)
	model:PivotTo(rest)
	if sprouting then
		model:SetAttribute("Scale", 1) -- (the seedling keeps its size)
	else
		CreatureModels.applyScale(model, scale)
	end
	model:SetAttribute("RestPivot", rest) -- the client's idle sway (Effects.client) animates around this
	model.Parent = state.info.plants
	return model
end

-- Plants stand straight on the bed: no dug-soil patch under them.
local function removePlantModel(state: PlotState, slot: number)
	local model = state.models[slot]
	if model then
		model:Destroy()
	end
	state.models[slot] = nil
	state.scales[slot] = nil
	state.sprouting[slot] = nil
end

local function spawnPlant(state: PlotState, plant: ProfileStore.Plant, now: number, growMult: number)
	local weight, income = PlotService.plantStats(plant, now, growMult)
	local scale = plantScale(plant, weight)
	state.models[plant.slot] = buildPlantModel(state, plant, weight, income, scale)
	state.scales[plant.slot] = scale
	state.sprouting[plant.slot] = Config.isSprouting(plant, now) or nil
end

local function clearPlants(state: PlotState)
	for _, m in state.models do
		m:Destroy()
	end
	state.models = {}
	state.scales = {}
	state.sprouting = {}
end

----------------------------------------------------------------------------------------------------
-- Plants view for the client's Plants menu
----------------------------------------------------------------------------------------------------
local function pushPlants(s: Sessions.Session, now: number)
	local mult = Sessions.moneyMult(s)
	local grow = Sessions.growMult(s)
	local isNight = Config.dayPhase(now)
	local view = {}
	for _, plant in s.profile.plants do
		local weight, income = PlotService.plantStats(plant, now, grow)
		income *= mult * Config.timeMult(plant.zone, isNight)
		-- `sell`: what the SELL stall pays for it right now (Selling.price)
		table.insert(view, {
			-- x/z: where it stands in the plot's space (the planting preview keeps new plants clear of it)
			slot = plant.slot, zone = plant.zone, rarity = plant.rarity, mutation = plant.mutation, weight = weight, income = income,
			x = plant.x, z = plant.z,
			sproutUntil = if Config.isSprouting(plant, now) then plant.sproutUntil else nil, -- a seedling: when it is done (the card's countdown, Grow now)
			name = PlotService.plantName(plant), -- "Gold Daisy": its flower model's name (the Plants panel, the Sell cards)
			flower = CreatureModels.flowerOf(plant.zone, plant.rarity, plant.variant, plant.slot), -- its model ("Daisy"): the HUD's 3D picture
			sell = Selling.price(plant, now, mult, grow),
		})
	end
	-- The inventory (the Plants panel's Inventory part, the Sell window): each plant as it left the plot
	local inventory = {}
	for _, entry in s.profile.inventory do
		local plant = Inventory.asPlant(entry, now)
		table.insert(inventory, {
			id = entry.id, zone = entry.zone, rarity = entry.rarity, mutation = entry.mutation, weight = Inventory.weight(entry),
			sprout = entry.sprout, -- seconds of sprouting it still has (planted again, it sprouts on)
			name = PlotService.plantName(plant), sell = Selling.price(plant, now, mult),
			flower = CreatureModels.flowerOf(plant.zone, plant.rarity, plant.variant, plant.slot),
		})
	end
	Sessions.push(s.player, { plants = view, inventory = inventory, slots = Sessions.maxSlots(s) })
end

local function refreshIncome(s: Sessions.Session, now: number)
	s.income = PlotService.liveIncomeOf(s.profile, now, Sessions.growMult(s))
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

-- The Index (collection book) entries a plant fills: "zone:rarity", its flower "zone:rarity:Daisy" (model
-- name, CreatureModels.flowerOf) and its mutation "zone:Gold". Marks them in the profile and returns the
-- new ones.
function PlotService.indexKeys(plant: ProfileStore.Plant): { string }
	local keys = { `{plant.zone}:{plant.rarity}` }
	local variant = CreatureModels.flowerOf(plant.zone, plant.rarity, plant.variant, plant.slot)
	if variant then
		table.insert(keys, `{plant.zone}:{plant.rarity}:{variant}`)
	end
	if plant.mutation then
		table.insert(keys, `{plant.zone}:{plant.mutation}`)
	end
	return keys
end

local function discover(profile: ProfileStore.Profile, plant: ProfileStore.Plant): { string }
	local new = {}
	for _, key in PlotService.indexKeys(plant) do
		if not profile.index[key] then
			profile.index[key] = true
			table.insert(new, key)
		end
	end
	return new
end

-- Plants a seed (carried or from the seed bag) at (x, z) in the plot's space, under a new id: the flower
-- and size its gene decided (PlantGhosts.seedPlant: what its planting ghost showed; kept in `variant` and
-- `variance`; a seed from before genes draws its flower now), then model, Index, income and client
-- updates. With `from` (a plant from the inventory) it is that plant again: its flower, mutation and
-- growth. "Planted" carries the flower's name and the spot over the plant, where the client pops the name
-- up for a moment (the reveal: the first time the flower is named).
local flowerRng = Random.new()
local function flowerRoll(): number
	return flowerRng:NextNumber()
end
local function plantSeed(player: Player, s: Sessions.Session, state: PlotState, x: number, z: number, zone: number, rarity: number, mutation: string?,
	from: ProfileStore.InvPlant?, gene: number?, yaw: number?)
	local now = os.time()
	local slot = Planting.newId(s.profile.plants :: any)
	x, z = math.round(x * 100) / 100, math.round(z * 100) / 100
	local plant: ProfileStore.Plant = if from then Inventory.toPlant(from, slot, now, x, z, Sessions.growMult(s), yaw)
		else PlantGhosts.seedPlant(zone, rarity, mutation, gene, slot, now, x, z, flowerRoll)
	if not from then
		plant.yaw = yaw -- (nil: facing the entrance)
		-- A fresh seed sprouts first (Config.sproutTime; Fast Grow halves it), earning nothing; its growth
		-- starts when it is done. Its variance is fixed now, so moving plantedAt never changes its size.
		plant.variance = Config.varianceOf(plant)
		plant.sproutUntil = now + Config.sproutTime(zone, rarity, Sessions.growMult(s))
		plant.plantedAt = plant.sproutUntil :: number
	end
	table.insert(s.profile.plants, plant)
	spawnPlant(state, plant, now, Sessions.growMult(s))

	local newEntries = discover(s.profile, plant)
	refreshIncome(s, now)
	pushPlants(s, now)
	Sessions.pushFull(s)
	local weight = PlotService.plantStats(plant, now, Sessions.growMult(s))
	local model = state.models[plant.slot]
	local top = restOf(state.info, plant).Position
	if model then
		local cf, size = model:GetBoundingBox()
		top = cf.Position + Vector3.new(0, size.Y / 2, 0)
	end
	Net.LootEvent:FireClient(player, "Planted", {
		name = PlotService.plantName(plant),
		weight = weight,
		rarity = rarity,
		mutation = mutation,
		pos = top,
		newIndex = newEntries,
	})
	return plant
end

local function finite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

-- A plant from the inventory is named by the key "inv:<id>" (the bag's keys are "zone:rarity[:Mutation]").
local function inventoryId(key: any): number?
	local id = if type(key) == "string" then tonumber(string.match(key, "^inv:(%d+)$")) else nil
	return if id and id <= 1e9 then id else nil
end

-- Plants the carried seed, or (with `bagKey`) one from the seed bag or a plant from the inventory
-- ("inv:<id>"), at `pos`, turned `yaw` degrees: the remote PlantSeed, sent by the client's planting preview
-- (Planting.client), so nothing in it is trusted (a yaw that isn't a finite number is ignored: an inventory
-- plant keeps the way it faced, a seed faces the entrance). The spot must be on one of the player's OWN
-- dirt beds, clear of their other plants' cores (Planting.minDistance), within reach of where they stand, and the plot must have a free slot
-- (Shared/Planting.check). A refused spot toasts why and plants nothing; the seed stays carried or in the
-- bag, the plant in the inventory.
function PlotService.plantAt(player: Player, pos: any, bagKey: any, yaw: any)
	local s = Sessions.get(player)
	local state = plotOf(player)
	if not s or not state or typeof(pos) ~= "Vector3" or not finite(pos) then
		return
	end
	if bagKey ~= nil and (type(bagKey) ~= "string" or #bagKey > 40) then
		return
	end
	local zone: number?, rarity: number?, mutation: string?, gene: number?
	local invId = inventoryId(bagKey)
	local entry = if invId then Inventory.find(s.profile, invId) else nil
	if invId then
		if not entry then
			return
		end
		zone, rarity, mutation = entry.zone, entry.rarity, entry.mutation
	elseif bagKey then
		zone, rarity, mutation, gene = SeedPacks.parseBagKey(bagKey)
		if (s.profile.seedBag[bagKey] or 0) <= 0 then
			return
		end
	elseif s.carry then
		zone, rarity, mutation, gene = s.carry.zone, s.carry.rarity, s.carry.mutation, s.carry.gene
	else
		local hasBag = SeedPacks.bagCount(s.profile.seedBag) > 0
		Net.toast(player, if hasBag then "Steal a seed, or plant one from your Inventory!" else "Steal a seed from the corridor first!", "red")
		return
	end
	local root = SpeedService.trustedRoot(player) -- (the reach from where they could have walked to)
	if not zone or not rarity or not root then
		return
	end
	local ok, why = Planting.check({
		beds = state.info.beds, -- only this player's own plot
		origin = state.info.origin,
		plants = s.profile.plants :: any,
		pos = pos,
		rarity = rarity,
		root = root.Position,
		limit = Sessions.maxSlots(s),
	})
	if not ok then
		Net.toast(player, Planting.MESSAGES[why :: Planting.Reason], "red")
		return
	end
	if invId then
		if not Inventory.remove(s.profile, invId) then
			return
		end
	elseif bagKey then
		if not SeedPacks.takeFromBag(s.profile.seedBag, bagKey) then
			return
		end
	elseif not SeedService.consumeCarry(player) then
		return
	end
	local x, z = Planting.toLocal(state.info.origin, pos)
	local plant = plantSeed(player, s, state, x, z, zone, rarity, mutation, entry, gene, Planting.normalizeYaw(yaw))
	if not bagKey and Config.announcesLegendary(zone, rarity, false) then
		Net.announce(Config.legendaryAnnouncement(player.DisplayName, zone, mutation, PlotService.plantName(plant)), "gold")
	end
end

-- The Inventory's Plant button or the hotbar's seed slot, on a bagged seed or an inventory plant
-- ("inv:<id>"): if the player has it, their client shows the planting preview for it (LootEvent
-- "PlaceSeed", with `ghost` and `scale`: the flower its ghost shows, PlantGhosts.name, at the size it will
-- have when planted, and an inventory plant's `yaw`; a seed is still only called "Rare Seed"). A bag seed
-- from before genes gets one now (PlantGhosts.bagPreview), so its ghost matches too. Clicking or tapping
-- their dirt then plants it through PlotService.plantAt.
function PlotService.plantFromBag(player: Player, key: string)
	local s = Sessions.get(player)
	if not s or not plotOf(player) then
		return
	end
	local invId = inventoryId(key)
	if invId then
		local entry = Inventory.find(s.profile, invId)
		if entry then
			local now = os.time()
			local plant = Inventory.asPlant(entry, now)
			local ghost, scale = PlantGhosts.plantLook(plant, now)
			PlantGhosts.ensure(entry.zone, entry.rarity, ghost)
			Net.LootEvent:FireClient(player, "PlaceSeed", {
				key = key, zone = entry.zone, rarity = entry.rarity, name = PlotService.plantName(plant), ghost = ghost, scale = scale,
				yaw = entry.yaw or 0, -- its ghost starts facing the way the plant did (0: the entrance)
			})
		end
		return
	end
	local had = s.profile.seedBag[key]
	local seedKey, zone, rarity, mutation, ghost, scale = PlantGhosts.bagPreview(s.profile.seedBag, key, flowerRoll)
	if not seedKey or not zone or not rarity or not ghost then
		return
	end
	if s.profile.seedBag[key] ~= had then
		Sessions.pushFull(s) -- (an old seed got its gene: the bag's keys changed)
	end
	PlantGhosts.ensure(zone, rarity, ghost)
	Net.LootEvent:FireClient(player, "PlaceSeed", {
		key = seedKey, zone = zone, rarity = rarity, name = SeedService.seedName(zone, rarity, mutation), ghost = ghost, scale = scale,
	})
end

-- The HUD Plants panel's Remove button (remote RemovePlant, rate-limited): takes the player's own plant in
-- `slot` (untrusted: Inventory.take checks it is one of theirs) off the plot into their inventory, as it
-- was. It never sells (owner request): plants are sold at the SELL stall, from the plot or the inventory.
local REMOVES_PER_SECOND = 4
function PlotService.removePlant(player: Player, slot: any)
	local s = Sessions.get(player)
	local state = plotOf(player)
	if not s or not state or not Sessions.allowRequest(s, REMOVES_PER_SECOND) then
		return
	end
	local now = os.time()
	for _, plant in s.profile.plants do
		if plant.slot == slot then -- (an older plant's flower comes from its id: keep it once the id is gone)
			plant.variant = CreatureModels.flowerOf(plant.zone, plant.rarity, plant.variant, plant.slot)
		end
	end
	if not Inventory.take(s.profile, slot, now, Sessions.growMult(s)) then
		-- gone, or the inventory is full (the panel says so in its Inventory part, no toast)
		pushPlants(s, now) -- the panel was showing a plant that is gone: redraw it
		return
	end

	removePlantModel(state, slot)
	refreshIncome(s, now)
	pushPlants(s, now)
	Sessions.pushCore(s)
end

-- The SELL stall (the HUD's Sell window, remote SellPlants): sells the plants in `slots` for
-- SELL_STALL_SECONDS of their income each (Selling). The player must stand within SELL_STALL_DISTANCE of
-- a SELL stall (measured from where they could have walked to: SpeedService.trustedRoot). Like removePlant:
-- frees the slots, refreshes income and the plants view (saved by the autosave).
function PlotService.sellPlants(player: Player, slots: any, ids: any?, seeds: any?)
	local s = Sessions.get(player)
	local state = plotOf(player) -- (nil: no plot, so no models to take down; the profile is what sells)
	if not s then
		return
	end
	local root = SpeedService.trustedRoot(player)
	local distance: number?, stall: BasePart? = nil, nil -- to the nearest stall
	for _, part in sellStalls do
		local d = if root and part.Parent then (root.Position - part.Position).Magnitude else nil
		if d and (distance == nil or d < distance) then
			distance, stall = d, part
		end
	end
	local now = os.time()
	local sale, why = Selling.sell(s.profile, slots, distance, now, Sessions.moneyMult(s), ids, Sessions.growMult(s), seeds)
	if not sale then
		if why == "far" then
			Net.toast(player, "Walk up to the SELL stall in the shop plaza to sell plants.", "red")
		elseif why == "none" then
			pushPlants(s, now) -- the window was showing plants that are gone: redraw it
		end
		return
	end
	for _, slot in sale.slots do
		if state then
			removePlantModel(state, slot)
		end
	end
	refreshIncome(s, now)
	pushPlants(s, now)
	if sale.seedCount > 0 then
		Sessions.pushFull(s) -- (the seed bag changed)
	else
		Sessions.pushCore(s)
	end
	local count = #sale.slots + #sale.ids + sale.seedCount
	Net.LootEvent:FireClient(player, "SoldPlants", { amount = sale.total, count = count })
	if stall then
		Net.IncomePopup:FireClient(player, sale.total, stall.Position + Vector3.new(0, 6, 0))
	end
end

----------------------------------------------------------------------------------------------------
-- Plot upgrades: the board by each plot's entrance (money or Robux), and the Shop's "PlotUpgrade" (money)
----------------------------------------------------------------------------------------------------
local UPGRADE_PROMPT_DISTANCE = 9

-- The board's two owner-only prompts (money and Robux; no popup, see addBoardButtons).
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
-- Treadmill upgrades: the owner-only buttons on the Upgrade board next to each plot's treadmill (money or
-- Robux, one tier at a time), and the Shop's "TreadmillUpgrade" (money). The board (TreadmillBoard) is
-- built at runtime next to whatever belt the map has (the treadmill stands in front of the plot).
----------------------------------------------------------------------------------------------------
-- The board's two prompts (money and Robux).
local function treadmillPrompts(state: PlotState): { ProximityPrompt }
	local list = {}
	for _, d in state.treadmill.panel:GetDescendants() do
		if d:IsA("ProximityPrompt") and string.sub(d.Name, 1, 9) == "Treadmill" then
			table.insert(list, d)
		end
	end
	return list
end

-- The board shows its owner's tier ("Level X > Level Y") and the next tier's prices, or "MAX"; the text
-- over the belt what a second on it pays the owner right now (Treadmill.perSecond: the same number the
-- server pays a second there and the "+X" popups over the runner show). Refreshed with every payout. The prompts say what they buy; at the last tier they switch off.
local function renderTreadmillSign(state: PlotState)
	local s = state.owner and Sessions.get(state.owner)
	-- the treadmill shows the owner's tier (an empty plot: tier 1); a no-op unless the tier changed
	TreadmillBoard.showTier(state.treadmill, if s then s.profile.treadmillTier else 1)
	if not s then
		TreadmillBoard.render(state.treadmill, {})
		for _, prompt in treadmillPrompts(state) do
			prompt.MaxActivationDistance = 0
		end
		return
	end
	local tier = s.profile.treadmillTier
	local price = Config.priceOf("TreadmillUpgrade", s.profile)
	local _, product = Config.treadmillUpgradeProduct(tier)
	local robux = if product then boardRobuxPrice(product) else nil
	TreadmillBoard.render(state.treadmill, {
		tier = tier,
		cash = price,
		robux = robux,
		perSecond = Treadmill.perSecond(tier, s.profile.equippedTrail, Sessions.passSpeedMult(s)),
		nextPerSecond = if price then Treadmill.perSecond(tier + 1, s.profile.equippedTrail, Sessions.passSpeedMult(s)) else nil,
	})
	for _, prompt in treadmillPrompts(state) do
		prompt.ActionText = if price then `Upgrade to Level {tier + 1}` else "Maxed"
		prompt.ObjectText = if prompt.Name == "TreadmillCash" then (if price then Format.money(price) else "")
			else (if robux then Format.robux(robux) else "")
		prompt.MaxActivationDistance = if price then Treadmill.BOARD_PROMPT_DISTANCE else 0
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
		label = `{msg}! Your treadmill pays {Treadmill.rateText(Sessions.treadmillPerSecond(s))} Speed`,
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

-- Both Upgrade boards (the plot's, and the treadmill's) are bought from by their painted buttons, with no
-- black prompt popups (the owner's call: only the sign shows):
--   * a click or tap on the red $ or purple R$ button: an invisible part over each painted button with a
--     ClickDetector (works with mouse and touch);
--   * the E (money) and F (Robux) keys, and gamepad X/Y: a ProximityPrompt under each button with Style =
--     Custom and no custom UI, so it shows nothing but its key still works.
-- Both carry OwnerUserId: the client switches them on for the owner only (Effects.client), and the server
-- re-checks the owner and the distance (`canUse`) before buying.
local BUTTON_HITS = {
	-- where each painted button is, as shares of the panel (x from the middle, seen from the front the red
	-- one is on the panel's +X side; y from the middle; w and h its size)
	Cash = { x = 0.158, y = -0.175, w = 0.44, h = 0.25 },
	Robux = { x = -0.233, y = -0.175, w = 0.29, h = 0.25 },
}
local BUTTON_CLICK_DISTANCE = 14
-- Over a button the mouse keeps Roblox's normal arrow (a ClickDetector's default is the pointing hand);
-- the button itself inflates instead, like the HUD's.
local BUTTON_CURSOR = "rbxasset://textures/Cursors/KeyboardMouse/ArrowFarCursor.png"

type ButtonSpec = { name: string, object: string, x: number, hold: number, key: Enum.KeyCode, pad: Enum.KeyCode, buy: (Player) -> () }

local function addBoardButtons(panel: BasePart, hitParent: Instance, specs: { ButtonSpec }, promptDistance: number,
	canUse: (Player) -> boolean): { ClickDetector }
	local clicks = {}
	for _, spec in specs do
		local anchor = Instance.new("Attachment")
		anchor.Name = spec.name .. "PromptAnchor"
		anchor.Position = Vector3.new(spec.x * panel.Size.X, -panel.Size.Y / 2 - 0.6, 0)
		anchor.Parent = panel
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = spec.name
		prompt.Style = Enum.ProximityPromptStyle.Custom -- no popup: the key works, the sign is all that shows
		prompt.ActionText = "Upgrade"
		prompt.ObjectText = spec.object
		prompt.HoldDuration = spec.hold
		prompt.MaxActivationDistance = promptDistance
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = spec.key
		prompt.GamepadKeyCode = spec.pad
		prompt:SetAttribute("OwnerUserId", 0)
		prompt.Parent = anchor
		prompt.Triggered:Connect(function(player: Player)
			if canUse(player) then
				spec.buy(player)
			end
		end)

		local area = BUTTON_HITS[spec.object]
		local hit = Instance.new("Part")
		hit.Name = spec.name .. "Button"
		hit.Anchored = true
		hit.CanCollide = false
		hit.CanTouch = false
		hit.CastShadow = false
		hit.Transparency = 1
		hit.Size = Vector3.new(area.w * panel.Size.X, area.h * panel.Size.Y, 0.3)
		hit.CFrame = panel.CFrame * CFrame.new(area.x * panel.Size.X, area.y * panel.Size.Y, -(panel.Size.Z / 2 + 0.55)) -- over the front face
		-- The painted button it sits over: Effects.client inflates it while the mouse is over the hit area.
		local painted = Instance.new("ObjectValue")
		painted.Name = "Painted"
		painted.Value = panel:FindFirstChild(spec.object .. "Button", true)
		painted.Parent = hit
		local click = Instance.new("ClickDetector")
		click.CursorIcon = BUTTON_CURSOR -- the normal arrow, not the pointing hand
		click.MaxActivationDistance = 0 -- Effects.client opens it for the owner (Reach)
		click:SetAttribute("Reach", BUTTON_CLICK_DISTANCE)
		click:SetAttribute("OwnerUserId", 0)
		click.Parent = hit
		click.MouseClick:Connect(function(player: Player)
			if canUse(player) then
				spec.buy(player)
			end
		end)
		hit.Parent = hitParent
		table.insert(clicks, click)
	end
	return clicks
end

-- The treadmill board's buttons: E / the red button buys with money, F / the purple one with Robux.
local TREADMILL_PROMPTS: { ButtonSpec } = {
	{ name = "TreadmillCash", object = "Cash", x = 0.16, hold = 0, key = Enum.KeyCode.E, pad = Enum.KeyCode.ButtonX, buy = function(player: Player)
		PlotService.upgradeTreadmill(player)
	end },
	{ name = "TreadmillRobux", object = "Robux", x = -0.23, hold = 0, key = Enum.KeyCode.F, pad = Enum.KeyCode.ButtonY, buy = function(player: Player)
		PlotService.promptRobuxTreadmill(player)
	end },
}

local function addTreadmillPrompts(state: PlotState)
	local panel = state.treadmill.panel
	-- the click targets ride in the board's model, so they follow it when the belt moves (TreadmillBoard.follow)
	local clicks = addBoardButtons(panel, state.treadmill.model, TREADMILL_PROMPTS, Treadmill.BOARD_PROMPT_DISTANCE, function(player: Player)
		local root = SpeedService.trustedRoot(player)
		return Treadmill.canUseBoard(state.owner == player, if root then root.Position else nil, panel.Position)
	end)
	table.move(clicks, 1, #clicks, #state.clicks + 1, state.clicks)
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

-- The plot's Upgrade board's buttons: E / the red button buys with money, F / the purple one with Robux.
local UPGRADE_PROMPTS: { ButtonSpec } = {
	{ name = "UpgradeCash", object = "Cash", x = 0.16, hold = 0, key = Enum.KeyCode.E, pad = Enum.KeyCode.ButtonX, buy = function(player: Player)
		PlotService.upgrade(player)
	end },
	{ name = "UpgradeRobux", object = "Robux", x = -0.23, hold = 0, key = Enum.KeyCode.F, pad = Enum.KeyCode.ButtonY, buy = function(player: Player)
		PlotService.promptRobuxUpgrade(player)
	end },
}

-- Who may click, tap or press a board's buttons: its owner, with some slack over the prompts' reach.
local function setButtonsOwner(state: PlotState, userId: number)
	for _, prompt in upgradePrompts(state) do
		prompt:SetAttribute("OwnerUserId", userId)
	end
	for _, prompt in treadmillPrompts(state) do
		prompt:SetAttribute("OwnerUserId", userId)
	end
	for _, click in state.clicks do
		click:SetAttribute("OwnerUserId", userId)
	end
end

----------------------------------------------------------------------------------------------------
-- Assignment
----------------------------------------------------------------------------------------------------
-- `stalls`: the SELL stalls' prompt parts (WorldBuilder.sellPoints); none means plants can't be sold
-- at a stall (the Plants panel's Remove still works).
function PlotService.init(infos: { WorldBuilder.PlotInfo }, stalls: { BasePart }?)
	sellStalls = stalls or {}
	Net.RemovePlant.OnServerEvent:Connect(PlotService.removePlant)
	for i, info in infos do
		local state: PlotState = {
			info = info,
			treadmill = TreadmillBoard.build(info.model, info.belt, info.center),
			owner = nil,
			models = {},
			scales = {},
			sprouting = {},
			clicks = {},
		}
		-- The board and the step text follow the belt if anything moves or resizes it.
		for _, property in { "CFrame", "Size" } do
			info.belt:GetPropertyChangedSignal(property):Connect(function()
				TreadmillBoard.follow(state.treadmill)
			end)
		end
		plots[i] = state
		local board = info.upgradeBoard
		local clicks = addBoardButtons(board, board.Parent or info.model, UPGRADE_PROMPTS, UPGRADE_PROMPT_DISTANCE, function(player: Player)
			local root = SpeedService.trustedRoot(player)
			return state.owner == player and root ~= nil and (root.Position - board.Position).Magnitude <= 16
		end)
		table.move(clicks, 1, #clicks, 1, state.clicks)
		renderUpgradeSign(state)
		addTreadmillPrompts(state)
		renderTreadmillSign(state)
	end
end

-- Every flower the Index can show: catalog[zone][rarity] = its plant models' names in pick order (the
-- client shows Format.plantName of each; empty lists when a zone has no plant models).
local function catalog(): { { { string } } }
	local out = {}
	for k in Config.ZONES do
		out[k] = {}
		for r in Config.RARITIES do
			out[k][r] = CreatureModels.variants(k, r)
		end
	end
	return out
end

-- Returns the PlotInfo, or nil if all plots are taken.
function PlotService.assign(s: Sessions.Session): WorldBuilder.PlotInfo?
	for _, state in plots do
		if state.owner == nil then
			state.owner = s.player
			s.plot = state.info
			Icons.set(state.info.signLabel, {}, `{s.player.DisplayName}'s Plot`) -- the name only, no icon (owner)
			setButtonsOwner(state, s.player.UserId)
			renderTreadmillSign(state)
			renderUpgradeSign(state)
			state.info.model:SetAttribute("OwnerUserId", s.player.UserId)
			-- Every plant on a bed and clear of the others (a save from before free planting, a bed moved in
			-- Studio): Shared/Planting.settle moves the ones that don't fit to free spots.
			Planting.settle(state.info.beds, state.info.origin, s.profile.plants :: any)
			local now = os.time()
			for _, plant in s.profile.plants do
				if plant.sproutUntil and plant.sproutUntil > now + Config.SPROUT_MAX then -- (a broken save's endless seedling)
					plant.sproutUntil = now + Config.SPROUT_MAX
					plant.plantedAt = math.min(plant.plantedAt, plant.sproutUntil :: number)
				end
				spawnPlant(state, plant, now, Sessions.growMult(s))
				discover(s.profile, plant) -- saves from before flower names: their plants' flowers count in the Index
			end
			refreshIncome(s, now)
			pushPlants(s, now)
			Sessions.push(s.player, { catalog = catalog() })
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
	state.owner = nil
	Icons.set(state.info.signLabel, {}, WorldBuilder.EMPTY_PLOT)
	state.info.model:SetAttribute("OwnerUserId", nil)
	setButtonsOwner(state, 0)
	renderUpgradeSign(state)
	renderTreadmillSign(state)
end

-- After a plot upgrade (money or a Robux receipt) or the slots gamepass: the plants view (its slot count)
-- and the board.
function PlotService.refreshSlots(s: Sessions.Session)
	local state = plotOf(s.player)
	if state then
		pushPlants(s, os.time())
		renderUpgradeSign(state)
	end
end

-- Offline earnings (capped): income of the plants as they are now, with the day/night multiplier
-- averaged over a cycle and the plot level / 2x Money multiplier, times time away (each plant only for the
-- part of it after it sprouted: PlotService.offlineEarnings).
function PlotService.grantOffline(s: Sessions.Session): number
	local last = s.profile.lastSeen
	if last <= 0 then
		return 0
	end
	local now = os.time()
	local away = math.clamp(now - last, 0, Config.OFFLINE_CAP_SECONDS)
	local amount = PlotService.offlineEarnings(s.profile, now, away, Sessions.growMult(s)) * Sessions.moneyMult(s)
	if amount > 0 then
		s.profile.money += amount
		Net.LootEvent:FireClient(s.player, "Offline", { amount = amount, seconds = away })
	end
	return amount
end

----------------------------------------------------------------------------------------------------
-- Sprouting: the seedling pops into its flower when its time is up (the payout loop), or at once after a
-- Grow Now receipt (PlotService.refreshSprouts).
----------------------------------------------------------------------------------------------------
-- Swaps a plant's seedling for its flower and tells the owner's client (LootEvent "Sprouted": the pop).
function PlotService.popSprout(s: Sessions.Session, state: PlotState, plant: ProfileStore.Plant, now: number)
	plant.sproutUntil = nil -- (done: nothing left to save)
	removePlantModel(state, plant.slot)
	spawnPlant(state, plant, now, Sessions.growMult(s))
	local model = state.models[plant.slot]
	local top = restOf(state.info, plant).Position
	if model then
		local cf, size = model:GetBoundingBox()
		top = cf.Position + Vector3.new(0, size.Y / 2, 0)
	end
	Net.LootEvent:FireClient(s.player, "Sprouted", { slot = plant.slot, name = PlotService.plantName(plant), pos = top })
end

-- After a Grow Now receipt: every plant whose model no longer matches its sprouting is rebuilt (a finished
-- one pops; one only shortened gets its new end time), then income and the plants view.
function PlotService.refreshSprouts(s: Sessions.Session)
	local state = plotOf(s.player)
	local now = os.time()
	for _, plant in s.profile.plants do
		local model = if state then state.models[plant.slot] else nil
		if state and state.sprouting[plant.slot] and not Config.isSprouting(plant, now) then
			PlotService.popSprout(s, state, plant, now)
		elseif state and model and state.sprouting[plant.slot] and model:GetAttribute("SproutUntil") ~= plant.sproutUntil then
			model:SetAttribute("SproutUntil", plant.sproutUntil)
		end
	end
	refreshIncome(s, now)
	pushPlants(s, now)
end

-- "Grow now" (the hover info's and the Plants card's button; RequestBuy "GrowNow:<id>", rate-limited by
-- ShopService): `slot` (untrusted) must be one of the player's own plants, still sprouting; the Robux
-- prompt is the Grow Now product its time left calls for (Shop.canPrompt checks it all). The plant is
-- remembered per product, so the receipt grows that one (Shop.grantGrowNow).
function PlotService.promptGrowNow(player: Player, slot: any)
	local s = Sessions.get(player)
	if not s then
		return
	end
	local now = os.time()
	local plant = Shop.plantBySlot(s.profile, slot)
	if not plant then
		return -- (not one of theirs: nothing to say)
	end
	local name = Config.growNowProduct(Config.sproutLeft(plant, now))
	if not name then
		pushPlants(s, now) -- it has grown already: the card was out of date
		return
	end
	local product, why = Shop.canPrompt(s.profile, name, { slot = plant.slot, now = now })
	if not product then
		Net.toast(player, why or "Unknown product", "red")
		return
	end
	s.growNow[name] = plant.slot
	MarketplaceService:PromptProductPurchase(player, product.id)
end

----------------------------------------------------------------------------------------------------
-- Payout loop: one pass over players every PAYOUT_INTERVAL (1 s: each pass pays one second of every
-- plant's $/s, silently, no popups); weight comes from the formula. The Plants panel view is refreshed every
-- PLANTS_PUSH_EVERY passes only: it is the bulkiest push and its numbers drift slowly.
----------------------------------------------------------------------------------------------------
local PLANTS_PUSH_EVERY = 3
local payoutPass = 0
local function payout(s: Sessions.Session, state: PlotState, now: number)
	local mult = Sessions.moneyMult(s)
	local grow = Sessions.growMult(s)
	local isNight = Config.dayPhase(now)
	local total = 0
	local sprouted = false
	for _, plant in s.profile.plants do
		if state.sprouting[plant.slot] and not Config.isSprouting(plant, now) then
			sprouted = true
			PlotService.popSprout(s, state, plant, now) -- done: the seedling pops into its flower
		end
		if state.sprouting[plant.slot] then
			continue -- a seedling earns nothing (its countdown is the client's)
		end
		local weight, income = PlotService.plantStats(plant, now, grow)
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
				setIncomeLabel(incomeLabel, plant.zone, perSecond, isNight) -- also flips the "Night x0.8" note on a phase change
			end
			local scale = plantScale(plant, weight)
			if math.abs(scale - (state.scales[plant.slot] or 1)) > 0.03 then
				CreatureModels.applyScale(model, scale) -- its Scale attribute makes the client re-read the rest pose
				state.scales[plant.slot] = scale
			end
			-- (no "+$X" popup over the plant: owner 2026-10-15, plants earn silently and the money counter rises)
		end
	end
	s.profile.money += total
	s.income = total / (mult * Config.PAYOUT_INTERVAL)
	renderTreadmillSign(state)
	Sessions.pushCore(s)
	if sprouted or payoutPass % PLANTS_PUSH_EVERY == 0 then
		pushPlants(s, now)
	end
end

PlotService.HOMECOMING_INTERVAL = 0.2 -- seconds between checks for thieves who reached the base (SeedService.storeCarried)

function PlotService.start()
	task.spawn(CreatureModels.preload) -- uploaded creature models, if any are configured (yields)
	task.spawn(function()
		while true do
			task.wait(Config.PAYOUT_INTERVAL)
			payoutPass += 1
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
	-- Homecoming: a stolen seed leaves its thief's back for the seed bag as soon as they cross into the base.
	task.spawn(function()
		while true do
			task.wait(PlotService.HOMECOMING_INTERVAL)
			for _, state in plots do
				local owner = state.owner
				local s = owner and Sessions.get(owner)
				if s and s.carry then
					local ok, err = pcall(SeedService.storeCarried, owner :: Player)
					if not ok then
						warn("[PlotService]", err)
					end
				end
			end
		end
	end)
end

return PlotService
