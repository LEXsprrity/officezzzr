--!strict
-- The owner's admin panel (owner 2026-10-16: "make a admin panel", to pay players back for bug reports):
-- what one grant is, how it's checked and named, and what it does to a save. Pure and shared, so the panel
-- (AdminPanel.client) reads amounts the same way the server (AdminService) checks them.
--   { kind = "Money", amount }            money
--   { kind = "Speed", amount }            Speed
--   { kind = "Seed", zone, rarity, count } seeds into the seed bag (a random flower of that rarity)
--   { kind = "TakeSeed", zone, rarity, count } takes them back (owner 2026-10-16, after giving 10 Legendary
--     seeds to the wrong player): from the bag first, then the inventory, then the plot (seedlings first)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local SeedPacks = require(Shared:WaitForChild("SeedPacks"))

local AdminGrant = {}

export type Grant = { kind: string, amount: number?, zone: number?, rarity: number?, count: number? }

AdminGrant.MAX_AMOUNT = 1e15 -- the most money or Speed one grant gives
AdminGrant.MAX_SEEDS = 20 -- the most seeds one grant gives

local SCALE = { k = 1e3, m = 1e6, b = 1e9, t = 1e12 }

-- "1.5M" -> 1500000, "200k" -> 200000, "25,000" -> 25000. nil for anything else.
function AdminGrant.parseAmount(text: any): number?
	if type(text) ~= "string" then
		return nil
	end
	local s = string.lower((string.gsub(text, "[%s,$]", "")))
	local digits, suffix = string.match(s, "^(%d+%.?%d*)([kmbt]?)$")
	local n = tonumber(digits)
	if not n then
		return nil
	end
	return math.floor(n * (SCALE[suffix] or 1) + 0.5)
end

local function whole(v: any, lo: number, hi: number): number?
	if type(v) ~= "number" or v ~= v or v ~= math.floor(v) or v < lo or v > hi then
		return nil
	end
	return v
end

-- A clean copy of a grant from anywhere (the client, the DataStore), or nil and why not.
function AdminGrant.check(g: any): (Grant?, string?)
	if type(g) ~= "table" then
		return nil, "bad grant"
	end
	if g.kind == "Money" or g.kind == "Speed" then
		local amount = whole(g.amount, 1, AdminGrant.MAX_AMOUNT)
		if not amount then
			return nil, "type an amount like 50K or 1.5M"
		end
		return { kind = g.kind, amount = amount }
	elseif g.kind == "Seed" or g.kind == "TakeSeed" then
		local zone = whole(g.zone, 1, #Config.ZONES)
		local rarity = whole(g.rarity, 1, #Config.RARITIES)
		local count = whole(g.count, 1, AdminGrant.MAX_SEEDS)
		if not zone or not rarity then
			return nil, "pick a zone and a rarity"
		end
		if not count then
			return nil, `seeds: 1 to {AdminGrant.MAX_SEEDS}`
		end
		return { kind = g.kind, zone = zone, rarity = rarity, count = count }
	end
	return nil, "bad grant"
end

-- "$1.5M", "25K Speed", "3 Legendary Seeds (Spirit Garden)"
-- (a TakeSeed reads like the seeds it takes: "3 Legendary Seeds (Spirit Garden)")
function AdminGrant.describe(g: Grant): string
	if g.kind == "Money" then
		return Format.money(g.amount :: number)
	elseif g.kind == "Speed" then
		return `{Format.short(g.amount :: number)} Speed`
	end
	local count = g.count :: number
	local rarity = Config.RARITIES[g.rarity :: number].id
	return `{count} {rarity} Seed{if count == 1 then "" else "s"} ({Config.ZONES[g.zone :: number].name})`
end

-- Takes up to g.count seeds of g.zone / g.rarity (a TakeSeed) out of a save: the bag first, then inventory
-- plants of that zone and rarity, then planted ones (seedlings first, then the newest). Returns how many it
-- took and the plot slots of the planted ones it took (PlotService takes their models down).
function AdminGrant.take(profile: any, g: Grant): (number, { number })
	local want = g.count :: number
	local taken, slots = 0, {}
	local keys = {}
	for key, n in profile.seedBag do
		local zone, rarity, mutation = SeedPacks.parseBagKey(key)
		if zone == g.zone and rarity == g.rarity and n > 0 then
			table.insert(keys, { key = key, plain = mutation == nil })
		end
	end
	table.sort(keys, function(a, b) -- plain seeds (what a Seed grant gives) before mutated ones
		if a.plain ~= b.plain then
			return a.plain
		end
		return a.key < b.key
	end)
	for _, k in keys do
		while taken < want and SeedPacks.takeFromBag(profile.seedBag, k.key) do
			taken += 1
		end
	end
	for i = #profile.inventory, 1, -1 do
		local entry = profile.inventory[i]
		if taken < want and entry.zone == g.zone and entry.rarity == g.rarity then
			table.remove(profile.inventory, i)
			taken += 1
		end
	end
	local planted = {}
	for _, plant in profile.plants do
		if plant.zone == g.zone and plant.rarity == g.rarity then
			table.insert(planted, plant)
		end
	end
	table.sort(planted, function(a, b)
		local sa, sb = a.sproutUntil ~= nil, b.sproutUntil ~= nil
		if sa ~= sb then
			return sa
		end
		return a.slot > b.slot
	end)
	for _, plant in planted do
		if taken >= want then
			break
		end
		table.insert(slots, plant.slot)
		table.remove(profile.plants, table.find(profile.plants, plant) :: number)
		taken += 1
	end
	return taken, slots
end

-- A TakeSeed for someone who isn't here: first it cancels Seed grants still waiting for them (same zone and
-- rarity). Returns the waiting list without them, how many seeds it cancelled, and the TakeSeed still left
-- to do when they join (nil: nothing left).
function AdminGrant.cancelPending(list: { any }, g: Grant): ({ any }, number, Grant?)
	local left = g.count :: number
	local out = {}
	for _, raw in list do
		local w = AdminGrant.check(raw)
		if w and left > 0 and w.kind == "Seed" and w.zone == g.zone and w.rarity == g.rarity then
			local cut = math.min(left, w.count :: number)
			left -= cut
			if (w.count :: number) > cut then
				table.insert(out, { kind = "Seed", zone = w.zone, rarity = w.rarity, count = (w.count :: number) - cut })
			end
		else
			table.insert(out, raw)
		end
	end
	local rest: Grant? = if left > 0 then { kind = "TakeSeed", zone = g.zone, rarity = g.rarity, count = left } else nil
	return out, (g.count :: number) - left, rest
end

-- Gives a checked grant to a save. Seeds stop at the bag's hard cap; returns how many seeds went in (or 1).
function AdminGrant.apply(profile: any, g: Grant, rng: () -> number): number
	if g.kind == "Money" then
		profile.money += g.amount :: number
		return 1
	elseif g.kind == "Speed" then
		profile.speed += g.amount :: number
		return 1
	end
	local given = 0
	for _ = 1, g.count :: number do
		if SeedPacks.bagCount(profile.seedBag) >= Config.SEED_BAG_HARD_MAX then
			break
		end
		SeedPacks.addToBag(profile.seedBag, g.zone :: number, g.rarity :: number, nil, Config.rollGene(rng))
		given += 1
	end
	return given
end

return AdminGrant
