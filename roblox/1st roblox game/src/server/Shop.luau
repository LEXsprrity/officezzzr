--!strict
-- Pure purchase rules: validate against the profile, charge, apply. Prices come from Config.priceOf,
-- the same function the client uses to label buttons. Seed packs and Robux receipts are here too, so
-- their rules (odds, bag limits, idempotent grants) are testable without Roblox.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
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

-- Returns (ok, message). `income` is the player's current $/s (potion prices scale with it).
function Shop.buy(p: Profile, itemId: string, income: number): (boolean, string)
	local view = {
		money = p.money,
		speed = p.speed,
		speedMultTier = p.speedMultTier,
		treadmillTier = p.treadmillTier,
		slots = p.slots,
		income = income,
	}
	local price, label = Config.priceOf(itemId, view)
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
	else -- consumables: Sleep Dust and potions
		p.items[itemId] = (p.items[itemId] or 0) + 1
	end
	return true, label or itemId
end

----------------------------------------------------------------------------------------------------
-- Seed packs
----------------------------------------------------------------------------------------------------
type PackProfile = {
	money: number,
	speed: number,
	seedBag: { [string]: number },
	receipts: { string },
}

export type Roll = { zone: number, rarity: number, mutation: string?, name: string }

local function openPack(p: PackProfile, pack: SeedPacks.Pack, rng: () -> number): Roll
	local rarity, mutation = SeedPacks.roll(pack, rng)
	SeedPacks.addToBag(p.seedBag, pack.zone, rarity, mutation)
	return { zone = pack.zone, rarity = rarity, mutation = mutation, name = SeedPacks.seedName(pack.zone, rarity, mutation) }
end

-- Buys and opens one pack with money; the seed goes into the bag. Zone packs unlock at the zone's
-- recommended Speed; the featured pack is open to everyone while it lasts. `now` is os.time().
function Shop.buyPack(p: PackProfile, packId: string, now: number, rng: () -> number): (boolean, string, Roll?, SeedPacks.Pack?)
	local pack, why = SeedPacks.fromId(packId, now)
	if not pack then
		return false, why or "Unknown pack", nil, nil
	end
	local zone = Config.ZONES[pack.zone]
	if not pack.featured and p.speed < zone.req then
		return false, `Reach {Format.short(zone.req)} Speed to unlock the {pack.name}!`, nil, nil
	end
	if SeedPacks.bagCount(p.seedBag) >= Config.SEED_BAG_MAX then
		return false, "Your seed bag is full! Plant some seeds first.", nil, nil
	end
	if p.money < pack.price then
		return false, "Not enough money", nil, nil
	end
	p.money -= pack.price
	return true, pack.name, openPack(p, pack, rng), pack
end

-- Grants a developer product (a bundle of featured packs) at most once per PurchaseId.
-- Returns "granted" with the rolls, "duplicate" (already granted: just confirm again) or "unknown".
-- Robux grants may exceed SEED_BAG_MAX; past SEED_BAG_HARD_MAX a pack refunds its money price instead.
function Shop.grantProduct(p: PackProfile, productName: string, purchaseId: string, now: number, rng: () -> number): (string, { Roll }?, SeedPacks.Pack?)
	for _, id in p.receipts do
		if id == purchaseId then
			return "duplicate", nil, nil
		end
	end
	local product = Config.DEVELOPER_PRODUCTS[productName]
	if not product then
		return "unknown", nil, nil
	end
	local pack = SeedPacks.featuredPack(now)
	local rolls = {}
	for _ = 1, product.packs do
		if SeedPacks.bagCount(p.seedBag) < Config.SEED_BAG_HARD_MAX then
			table.insert(rolls, openPack(p, pack, rng))
		else
			p.money += pack.price
		end
	end
	table.insert(p.receipts, purchaseId)
	while #p.receipts > Config.RECEIPT_HISTORY do
		table.remove(p.receipts, 1)
	end
	return "granted", rolls, pack
end

-- The ProcessReceipt decision without Roblox objects: grant once, persist, then confirm.
-- `save` must return true only once the profile (with the receipt id) reached the DataStore.
-- Returns (confirm, status, rolls, pack); confirm = false means "NotProcessedYet" (Roblox retries).
-- A retry in the same session finds the id and doesn't grant twice; if the server died before the
-- save, neither the grant nor the id persisted, so the retry elsewhere grants exactly once.
function Shop.processReceipt(p: PackProfile?, productName: string?, purchaseId: string, now: number, rng: () -> number, save: () -> boolean): (boolean, string, { Roll }?, SeedPacks.Pack?)
	if not p or not productName then
		return false, "unavailable", nil, nil
	end
	local status, rolls, pack = Shop.grantProduct(p, productName, purchaseId, now, rng)
	if status == "unknown" then
		return false, status, nil, nil
	end
	if not save() then
		return false, status, rolls, pack
	end
	return true, status, rolls, pack
end

return Shop
