--!strict
-- Pure purchase rules: validate against the profile, charge, apply. Prices come from Config.priceOf,
-- the same function the client uses to label buttons. Seed packs (Robux only) are here too, so their
-- rules (prompt gates, bag limits, idempotent receipt grants) are testable without Roblox.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SeedPacks = require(Shared:WaitForChild("SeedPacks"))

local Shop = {}

type Profile = {
	money: number,
	speed: number,
	speedMultTier: number,
	treadmillTier: number,
	slots: number,
	items: { [string]: number },
}

-- Returns (ok, message).
function Shop.buy(p: Profile, itemId: string): (boolean, string)
	local price, label = Config.priceOf(itemId, p)
	if price == nil then
		return false, if label then `{label}` else "Unknown item"
	end
	if price <= 0 and itemId == "SpeedMax" then
		return false, "Not enough money"
	end
	if p.money < price then
		return false, "Not enough money"
	end

	p.money -= price
	if itemId == "Speed25" or itemId == "SpeedMax" then
		p.speed += price / Config.PRICE_PER_SPEED
	elseif itemId == "SpeedMult" then
		p.speedMultTier += 1
	elseif itemId == "Treadmill" then
		p.treadmillTier += 1
	elseif itemId == "Slot" then
		p.slots += 1
	else -- consumables: Sleep Dust
		p.items[itemId] = (p.items[itemId] or 0) + 1
	end
	return true, label or itemId
end

----------------------------------------------------------------------------------------------------
-- Seed packs: Robux only. Each pack is a developer product (Config.DEVELOPER_PRODUCTS); there is no
-- money price and no money purchase path.
----------------------------------------------------------------------------------------------------
type PackProfile = {
	money: number,
	seedBag: { [string]: number },
	receipts: { string },
}

export type Roll = { zone: number, rarity: number, mutation: string?, name: string }
export type Grant = {
	pack: SeedPacks.Pack,
	roll: Roll?, -- the seed that went into the bag, or nil if it didn't fit (bag at SEED_BAG_HARD_MAX)...
	compensation: number, -- ...and the money paid instead
}

-- Whether the server may open the Robux prompt for `productName`. Returns (product, nil) or
-- (nil, message). A product without an id is "coming soon", and there are no new prompts once the
-- bag holds SEED_BAG_MAX seeds. There is no Speed gate: the packs are a premium shortcut. Only the
-- *prompt* is gated: a receipt that arrives is always granted (Shop.grantProduct).
function Shop.canPrompt(p: PackProfile, productName: string): (Config.DevProduct?, string?)
	local product = Config.DEVELOPER_PRODUCTS[productName]
	if not product then
		return nil, "Unknown pack"
	end
	if product.id == 0 then
		return nil, `{product.label}: coming soon!`
	end
	if SeedPacks.bagCount(p.seedBag) >= Config.SEED_BAG_MAX then
		return nil, "Your seed bag is full! Plant some seeds first."
	end
	return product, nil
end

-- Money paid for a pack whose seed can't fit: PACK_FULL_BAG_INCOME_SECONDS of the player's income
-- (`income` = $/s with multipliers), but at least that long of a Common plant from the pack's zone,
-- so a player with no plants yet still gets something worth having.
function Shop.fullBagCompensation(pack: SeedPacks.Pack, income: number): number
	return math.floor(math.max(income, Config.seedIncome(pack.zone)) * Config.PACK_FULL_BAG_INCOME_SECONDS)
end

-- Grants a developer product at most once per PurchaseId: one pack of its zone. Returns "granted"
-- with the grant, "duplicate" (already granted: just confirm again) or "unknown". The seed may push
-- the bag past SEED_BAG_MAX up to SEED_BAG_HARD_MAX; if it can't fit, the pack pays
-- Shop.fullBagCompensation instead, so a paid purchase is never lost.
function Shop.grantProduct(p: PackProfile, productName: string, purchaseId: string, income: number, rng: () -> number): (string, Grant?)
	for _, id in p.receipts do
		if id == purchaseId then
			return "duplicate", nil
		end
	end
	local product = Config.DEVELOPER_PRODUCTS[productName]
	if not product then
		return "unknown", nil
	end
	local pack = SeedPacks.packForProduct(product)
	local grant: Grant = { pack = pack, roll = nil, compensation = 0 }
	if SeedPacks.bagCount(p.seedBag) < Config.SEED_BAG_HARD_MAX then
		local rarity, mutation = SeedPacks.roll(pack, rng)
		SeedPacks.addToBag(p.seedBag, pack.zone, rarity, mutation)
		grant.roll = { zone = pack.zone, rarity = rarity, mutation = mutation, name = SeedPacks.seedName(pack.zone, rarity, mutation) }
	else
		grant.compensation = Shop.fullBagCompensation(pack, income)
		p.money += grant.compensation
	end
	table.insert(p.receipts, purchaseId)
	while #p.receipts > Config.RECEIPT_HISTORY do
		table.remove(p.receipts, 1)
	end
	return "granted", grant
end

-- The ProcessReceipt decision without Roblox objects: grant once, persist, then confirm.
-- `save` must return true only once the profile (with the receipt id) reached the DataStore.
-- Returns (confirm, status, grant); confirm = false means "NotProcessedYet" (Roblox retries).
-- A retry in the same session finds the id and doesn't grant twice; if the server died before the
-- save, neither the grant nor the id persisted, so the retry elsewhere grants exactly once.
function Shop.processReceipt(p: PackProfile?, productName: string?, purchaseId: string, income: number, rng: () -> number, save: () -> boolean): (boolean, string, Grant?)
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
