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
export type Roll = { zone: number, rarity: number, mutation: string?, name: string }
export type Grant = {
	name: string, -- product key
	product: Config.DevProduct,
	label: string, -- what the player got, for the toast
	pack: SeedPacks.Pack?, -- Pack products:
	roll: Roll?, -- the seed that went into the bag, or nil if it didn't fit (bag at SEED_BAG_HARD_MAX)...
	compensation: number, -- ...and the money paid instead (also what a Money product paid)
}

-- Whether the server may open the Robux prompt for `productName`. Returns (product, nil) or
-- (nil, message). A product without an id is "coming soon"; packs aren't prompted once the bag holds
-- SEED_BAG_MAX seeds, trails the player already has aren't prompted at all, and a plot or treadmill
-- upgrade only through the price tier of the plot's level / treadmill's tier (never once maxed). Only the
-- *prompt* is gated: a receipt that arrives is always granted (Shop.grantProduct).
function Shop.canPrompt(p: Profile, productName: string): (Config.DevProduct?, string?)
	local product = Config.DEVELOPER_PRODUCTS[productName]
	if not product then
		return nil, "Unknown product"
	end
	if product.id == 0 then
		return nil, `{product.label}: coming soon!`
	end
	if product.kind == "Pack" and SeedPacks.bagCount(p.seedBag) >= Config.SEED_BAG_MAX then
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

-- Applies one product to the profile. `income` = the player's $/s with all multipliers.
local function apply(p: Profile, name: string, product: Config.DevProduct, income: number, rng: () -> number): Grant
	local grant: Grant = { name = name, product = product, label = product.label, pack = nil, roll = nil, compensation = 0 }
	local kind = product.kind
	if kind == "Pack" then
		-- The seed may push the bag past SEED_BAG_MAX up to SEED_BAG_HARD_MAX; if it can't fit, the pack
		-- pays Shop.fullBagCompensation instead.
		local pack = SeedPacks.packForProduct(product)
		grant.pack = pack
		if SeedPacks.bagCount(p.seedBag) < Config.SEED_BAG_HARD_MAX then
			local rarity, mutation = SeedPacks.roll(pack, rng)
			SeedPacks.addToBag(p.seedBag, pack.zone, rarity, mutation)
			grant.roll = { zone = pack.zone, rarity = rarity, mutation = mutation, name = SeedPacks.seedName(pack.zone, rarity, mutation) }
		else
			grant.compensation = Shop.fullBagCompensation(pack, income)
			p.money += grant.compensation
		end
	elseif kind == "Speed" then
		p.speed += product.amount :: number
	elseif kind == "Money" then
		grant.compensation = Config.moneyPackAmount(product, income)
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
-- "duplicate" (already granted: just confirm again) or "unknown".
function Shop.grantProduct(p: Profile, productName: string, purchaseId: string, income: number, rng: () -> number): (string, Grant?)
	for _, id in p.receipts do
		if id == purchaseId then
			return "duplicate", nil
		end
	end
	local product = Config.DEVELOPER_PRODUCTS[productName]
	if not product then
		return "unknown", nil
	end
	local grant = apply(p, productName, product, income, rng)
	remember(p, purchaseId)
	return "granted", grant
end

-- The ProcessReceipt decision without Roblox objects: grant once, persist, then confirm.
-- `save` must return true only once the profile (with the receipt id) reached the DataStore.
-- Returns (confirm, status, grant); confirm = false means "NotProcessedYet" (Roblox retries).
-- A retry in the same session finds the id and doesn't grant twice; if the server died before the
-- save, neither the grant nor the id persisted, so the retry elsewhere grants exactly once.
function Shop.processReceipt(p: Profile?, productName: string?, purchaseId: string, income: number, rng: () -> number, save: () -> boolean): (boolean, string, Grant?)
	if not p or not productName then
		return false, "unavailable", nil
	end
	local status, grant = Shop.grantProduct(p, productName, purchaseId, income, rng)
	if status == "unknown" then
		return false, status, nil
	end
	if not save() then
		return false, status, grant
	end
	return true, status, grant
end

return Shop
