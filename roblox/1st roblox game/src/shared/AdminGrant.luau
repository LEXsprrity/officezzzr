--!strict
-- The owner's admin panel (owner 2026-10-16: "make a admin panel", to pay players back for bug reports):
-- what one grant is, how it's checked and named, and what it does to a save. Pure and shared, so the panel
-- (AdminPanel.client) reads amounts the same way the server (AdminService) checks them.
--   { kind = "Money", amount }            money
--   { kind = "Speed", amount }            Speed
--   { kind = "Seed", zone, rarity, count } seeds into the seed bag (a random flower of that rarity)
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
	elseif g.kind == "Seed" then
		local zone = whole(g.zone, 1, #Config.ZONES)
		local rarity = whole(g.rarity, 1, #Config.RARITIES)
		local count = whole(g.count, 1, AdminGrant.MAX_SEEDS)
		if not zone or not rarity then
			return nil, "pick a zone and a rarity"
		end
		if not count then
			return nil, `seeds: 1 to {AdminGrant.MAX_SEEDS}`
		end
		return { kind = "Seed", zone = zone, rarity = rarity, count = count }
	end
	return nil, "bad grant"
end

-- "$1.5M", "25K Speed", "3 Legendary Seeds (Spirit Garden)"
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
