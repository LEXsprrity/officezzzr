--!strict
-- Pure purchase rules: validate against the profile, charge, apply. In-game money buys only trails, plot
-- upgrades and treadmill tiers; prices come from Config.priceOf, the same function the client uses to
-- label buttons.
-- Everything else is Robux (developer products), so its rules live here too: prompt gates and
-- idempotent receipt grants, all testable without Roblox.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local SeedPacks = require(Shared:WaitForChild("SeedPacks"))

local Shop = {}

type Profile = {
	money: number,
	speed: number,
	trails: { [string]: boolean },
	equippedTrail: string,
	treadmillTier: number,
	plotLevel: number,
	items: { [string]: number },
	seedBag: { [string]: number },
	receipts: { string },
	plants: { any }?, -- (ProfileStore.Plant: GrowNow finds its plant here...)
	inventory: { any }?, -- (...or, taken off the plot, a seedling here)
}

local function ownTrail(p: Profile, trail: Config.Trail)
	p.trails[trail.id] = true
	p.equippedTrail = trail.id
end

----------------------------------------------------------------------------------------------------
-- Money: "PlotUpgrade", "TreadmillUpgrade" and "Trail:<id>". Nothing else has a money price.
----------------------------------------------------------------------------------------------------
-- Returns (ok, message).
function Shop.buy(p: Profile, itemId: string): (boolean, string)
	local price, label = Config.priceOf(itemId, p)
	if price == nil then
		return false, if label then `{label}` else "That's sold for Robux only"
	end
	if p.money < price then
		return false, "Not enough money"
	end
	p.money -= price
	if itemId == "PlotUpgrade" then
		p.plotLevel += 1
	elseif itemId == "TreadmillUpgrade" then
		p.treadmillTier += 1
	else
		ownTrail(p, Config.trailById(string.sub(itemId, 7)) :: Config.Trail) -- a bought trail is equipped
	end
	return true, label or itemId
end

-- Equips an owned trail. Returns (ok, message).
function Shop.equipTrail(p: Profile, trailId: string): (boolean, string)
	local trail = Config.trailById(trailId)
	if not trail then
		return false, "Unknown trail"
	end
	if not p.trails[trail.id] then
		return false, `You don't own the {trail.name} yet`
	end
	p.equippedTrail = trail.id
	return true, trail.name
end

----------------------------------------------------------------------------------------------------
-- Robux: developer products (Config.DEVELOPER_PRODUCTS). There is no money path to any of them.
----------------------------------------------------------------------------------------------------
export type Roll = { zone: number, rarity: number, mutation: string?, name: string, gene: number } -- gene: its seed look (the bag key has it too)
export type Grant = {
	name: string, -- product key
	product: Config.DevProduct,
	label: string, -- what the player got, for the toast
	pack: SeedPacks.Pack?, -- Pack products:
	roll: Roll?, -- the seed that went into the bag (a x10: the best one), or nil if none fit (bag at SEED_BAG_HARD_MAX)...
	rolls: { Roll }, -- every seed that went into the bag (1, or 10 for a x10 pack)
	compensation: number, -- ...and the money paid instead (also what a Money product paid)
	grown: { number }?, -- GrowNow: the plot plants (ids) whose sprouting it finished or shortened
	wasted: boolean?, -- GrowNow: no seedling anywhere to spend it on (logged by ShopService)
}

-- What a GrowNow prompt or receipt is about: the plant the player picked (`slot`, its id; untrusted until
-- found in their own profile) and the time.
export type GrowNowTarget = { slot: any, now: number }

-- The player's own plot plant with this id, or nil (an id that isn't one of theirs is just not found).
function Shop.plantBySlot(p: Profile, slot: any): any
	if type(slot) ~= "number" or slot ~= math.floor(slot) then
		return nil
	end
	for _, plant in p.plants or {} do
		if plant.slot == slot then
			return plant
		end
	end
	return nil
end

-- Whether the server may open the Robux prompt for `productName`. Returns (product, nil) or
-- (nil, message). A product without an id is "coming soon"; packs aren't prompted unless all their seeds fit
-- under SEED_BAG_MAX (a x10 needs 10 free spaces), trails the player already has aren't prompted at all, a plot or treadmill
-- upgrade only through the price tier of the plot's level / treadmill's tier (never once maxed), and Grow
-- Now only for `target`: one of the player's own plants that is still sprouting, with the product its time
-- left calls for (Config.growNowProduct). A `retired` product is never prompted. Only the *prompt* is gated:
-- a receipt that arrives is always granted (Shop.grantProduct), a retired product's too.
function Shop.canPrompt(p: Profile, productName: string, target: GrowNowTarget?): (Config.DevProduct?, string?)
	local product = Config.DEVELOPER_PRODUCTS[productName]
	if not product then
		return nil, "Unknown product"
	end
	if product.retired then
		return nil, `The {product.label} isn't sold any more.`
	end
	if product.id == 0 then
		return nil, `{product.label}: coming soon!`
	end
	local free = Config.SEED_BAG_MAX - SeedPacks.bagCount(p.seedBag)
	if product.kind == "Pack" and SeedPacks.count(product) > free then
		local count = SeedPacks.count(product)
		if count > 1 and free > 0 then
			return nil, `A x{count} pack needs {count} free spaces in your seed bag (you have {free}). Plant some seeds first!`
		end
		return nil, "Your seed bag is full! Plant some seeds first."
	elseif product.kind == "Trail" and p.trails[product.trail :: string] then
		return nil, `You already own the {product.label}.`
	elseif product.kind == "TreadmillUpgrade" then
		-- Only the price tier that sells this treadmill's next tier.
		local current = Config.treadmillUpgradeProduct(p.treadmillTier)
		if not current then
			return nil, "Your treadmill is fully upgraded!"
		elseif current ~= productName then
			return nil, "That isn't the upgrade for your treadmill's tier."
		end
	elseif product.kind == "GrowNow" then
		local plant = if target then Shop.plantBySlot(p, target.slot) else nil
		if not plant or not target then
			return nil, "Pick one of your sprouting plants first."
		end
		local left = Config.sproutLeft(plant, target.now)
		if left <= 0 then
			return nil, "That plant has already grown!"
		elseif Config.growNowProduct(left) ~= productName then
			return nil, "That isn't the Grow Now for this plant's time left."
		end
	elseif product.kind == "PlotUpgrade" then
		-- Only the tier that sells this plot's next level (a cheaper tier can't buy a late level).
		local current = Config.plotUpgradeProduct(p.plotLevel)
		if not current then
			return nil, "Your plot is fully upgraded!"
		elseif current ~= productName then
			return nil, "That isn't the upgrade for your plot's level."
		end
	end
	return product, nil
end

-- Money paid for a pack whose seed can't fit: PACK_FULL_BAG_INCOME_SECONDS of the player's income
-- (`income` = $/s with multipliers), but at least that long of a Common plant from the pack's zone,
-- so a player with no plants yet still gets something worth having.
function Shop.fullBagCompensation(pack: SeedPacks.Pack, income: number): number
	return math.floor(math.max(income, Config.seedIncome(pack.zone)) * Config.PACK_FULL_BAG_INCOME_SECONDS)
end

local function remember(p: Profile, purchaseId: string)
	table.insert(p.receipts, purchaseId)
	while #p.receipts > Config.RECEIPT_HISTORY do
		table.remove(p.receipts, 1)
	end
end

-- Shortens a plot plant's sprouting by `seconds` (math.huge: all of it) at `now`; its growth still starts
-- when the sprouting ends (its plantedAt moves with it).
local function skipSprout(plant: any, seconds: number, now: number)
	local offset = plant.plantedAt - plant.sproutUntil -- (0 for a seedling)
	if Config.sproutLeft(plant, now) <= seconds then
		plant.sproutUntil = nil
		plant.plantedAt = now + offset
	else
		plant.sproutUntil -= seconds
		plant.plantedAt = plant.sproutUntil + offset
	end
end

-- A Grow Now receipt (`target`: the plant it was prompted for, nil when the prompt was in another server).
-- That plant, if it is still one of the player's seedlings, sprouts at once. If it isn't (it finished
-- while the prompt was open, or was sold or taken off the plot), the purchase is not lost: it goes to the
-- seedling with the most time left, on the plot first, then in the inventory, skipping up to what the
-- product covers (its upTo; the top one all of it). With no seedling anywhere it does nothing but say so
-- (`wasted`; ShopService logs it). Robux can't be refunded from a game.
function Shop.grantGrowNow(p: Profile, product: Config.DevProduct, target: GrowNowTarget?, grant: Grant)
	local now = if target then target.now else os.time()
	local plant = if target then Shop.plantBySlot(p, target.slot) else nil
	if plant and Config.isSprouting(plant, now) then
		skipSprout(plant, math.huge, now)
		grant.grown = { plant.slot }
		grant.label = "Your plant grew!"
		return
	end
	local skip = product.upTo or math.huge
	local best, bestLeft = nil, 0
	for _, other in p.plants or {} do
		local left = Config.sproutLeft(other, now)
		if left > bestLeft then
			best, bestLeft = other, left
		end
	end
	if best then
		skipSprout(best, skip, now)
		grant.grown = { best.slot }
		grant.label = if Config.isSprouting(best, now) then "Your seedling grows faster!" else "Your plant grew!"
		return
	end
	local entry, entryLeft = nil, 0
	for _, e in p.inventory or {} do
		if (e.sprout or 0) > entryLeft then
			entry, entryLeft = e, e.sprout
		end
	end
	if entry then
		local left = math.max(entryLeft - skip, 0)
		entry.sprout = if left > 0 then left else nil
		grant.label = "A seedling in your Inventory grew!"
		return
	end
	grant.wasted = true
	grant.label = "Your plants had all grown already."
end

-- Applies one product to the profile. `income` = the player's $/s with all multipliers.
local function apply(p: Profile, name: string, product: Config.DevProduct, income: number, rng: () -> number, target: GrowNowTarget?): Grant
	local grant: Grant = { name = name, product = product, label = product.label, pack = nil, roll = nil, rolls = {}, compensation = 0 }
	local kind = product.kind
	if kind == "Pack" then
		-- `count` seeds (a x10 pack: all 10, in this one grant). They may push the bag past SEED_BAG_MAX up to
		-- SEED_BAG_HARD_MAX; a seed that can't fit pays Shop.fullBagCompensation instead, so a paid pack always
		-- grants all of it.
		local pack = SeedPacks.packForProduct(product)
		grant.pack = pack
		for _ = 1, SeedPacks.count(product) do
			if SeedPacks.bagCount(p.seedBag) < Config.SEED_BAG_HARD_MAX then
				local rarity, mutation = SeedPacks.roll(pack, rng)
				local gene = Config.rollGene(rng)
				SeedPacks.addToBag(p.seedBag, pack.zone, rarity, mutation, gene) -- (its hidden flower and size)
				local roll = { zone = pack.zone, rarity = rarity, mutation = mutation, name = SeedPacks.seedName(pack.zone, rarity, mutation), gene = gene }
				table.insert(grant.rolls, roll)
				if SeedPacks.better(roll, grant.roll) then
					grant.roll = roll
				end
			else
				local pay = Shop.fullBagCompensation(pack, income)
				grant.compensation += pay
				p.money += pay
			end
		end
	elseif kind == "Speed" then
		p.speed += product.amount :: number
	elseif kind == "Money" then
		grant.compensation = Config.moneyPackAmount(product) -- a fixed amount
		p.money += grant.compensation
		grant.label = `{product.label}: +{Format.money(grant.compensation)}`
	elseif kind == "TreadmillUpgrade" then
		-- Exactly one tier, from the tier the treadmill has now (the player may have bought tiers with
		-- money since the prompt). Already maxed: the last tier's money price instead.
		if p.treadmillTier < Config.TREADMILL_MAX then
			p.treadmillTier += 1
			grant.label = `Treadmill Level {p.treadmillTier}`
		else
			grant.compensation = Config.treadmillUpgradeMaxedPay()
			p.money += grant.compensation
			grant.label = `Your treadmill is maxed: +{Format.money(grant.compensation)} instead`
		end
	elseif kind == "Trail" then
		ownTrail(p, Config.trailById(product.trail) :: Config.Trail)
	elseif kind == "GrowNow" then
		Shop.grantGrowNow(p, product, target, grant)
	elseif kind == "PlotUpgrade" then
		-- Exactly one level, from the level the plot has now (whatever the tier: the player may have bought
		-- levels with money since the prompt). Already maxed: the last level's money price instead.
		if p.plotLevel < Config.PLOT_LEVEL_MAX then
			p.plotLevel += 1
			grant.label = `Plot Level {p.plotLevel}`
		else
			grant.compensation = Config.plotUpgradeMaxedPay()
			p.money += grant.compensation
			grant.label = `Your plot is maxed: +{Format.money(grant.compensation)} instead`
		end
	end
	return grant
end

-- Grants a developer product at most once per PurchaseId. Returns "granted" with the grant,
-- "duplicate" (already granted: just confirm again) or "unknown". `target`: a Grow Now's plant.
function Shop.grantProduct(p: Profile, productName: string, purchaseId: string, income: number, rng: () -> number, target: GrowNowTarget?): (string, Grant?)
	for _, id in p.receipts do
		if id == purchaseId then
			return "duplicate", nil
		end
	end
	local product = Config.DEVELOPER_PRODUCTS[productName]
	if not product then
		return "unknown", nil
	end
	local grant = apply(p, productName, product, income, rng, target)
	remember(p, purchaseId)
	return "granted", grant
end

-- The ProcessReceipt decision without Roblox objects: grant once, persist, then confirm.
-- `save` must return true only once the profile (with the receipt id) reached the DataStore.
-- Returns (confirm, status, grant); confirm = false means "NotProcessedYet" (Roblox retries).
-- A retry in the same session finds the id and doesn't grant twice; if the server died before the
-- save, neither the grant nor the id persisted, so the retry elsewhere grants exactly once.
function Shop.processReceipt(p: Profile?, productName: string?, purchaseId: string, income: number, rng: () -> number, save: () -> boolean,
	target: GrowNowTarget?): (boolean, string, Grant?)
	if not p or not productName then
		return false, "unavailable", nil
	end
	local status, grant = Shop.grantProduct(p, productName, purchaseId, income, rng, target)
	if status == "unknown" then
		return false, status, nil
	end
	if not save() then
		return false, status, grant
	end
	return true, status, grant
end

return Shop
