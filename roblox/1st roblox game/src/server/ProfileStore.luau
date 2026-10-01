--!strict
-- Player save data: defaults, (de)serialization with validation and migrations, and a DataStore wrapper
-- that uses UpdateAsync with retries. The DataStore is injected so tests can pass a mock.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SeedPacks = require(Shared:WaitForChild("SeedPacks"))

local ProfileStore = {}
ProfileStore.__index = ProfileStore

-- v2 added the seed bag and Robux receipt history; v1 saves load with both empty.
-- v3 (economy rework) replaced the Speed Gain tier with owned/equipped trails and bought slots with the
-- plot level; v1/v2 saves are migrated on load (see migrateSpeedMult and the plot level below).
ProfileStore.VERSION = 3

-- Potions were removed from the game. Saves of any version may still hold potion timers
-- (`potions`, ignored) and potion items, which are dropped from the inventory on load.
local RETIRED_ITEMS = { PotionSpeed = true, PotionMoney = true, PotionLuck = true }

-- The removed money-bought Speed Gain tiers (v1/v2 `speedMultTier`): their multiplier and what they cost.
ProfileStore.LEGACY_SPEED_MULT = {
	{ mult = 1, price = 0 },
	{ mult = 2, price = 15e3 },
	{ mult = 3, price = 400e3 },
	{ mult = 5, price = 8e6 },
	{ mult = 10, price = 250e6 },
	{ mult = 25, price = 10e9 },
}

export type Plant = {
	slot: number,
	zone: number,
	rarity: number,
	mutation: string?,
	plantedAt: number, -- unix seconds; weight is derived from this, never stored
}

export type Profile = {
	money: number,
	speed: number,
	trails: { [string]: boolean }, -- owned trail ids (always includes the free one)
	equippedTrail: string,
	treadmillTier: number,
	plotLevel: number, -- 1..Config.PLOT_LEVEL_MAX; slots = Config.plotSlots(plotLevel)
	plants: { Plant },
	index: { [string]: boolean }, -- "zone:rarity" and "zone:Mutation" keys
	items: { [string]: number },
	seedBag: { [string]: number }, -- seeds from packs, "zone:rarity[:Mutation]" -> count
	receipts: { string }, -- last Config.RECEIPT_HISTORY processed Robux PurchaseIds
	reachedEnd: boolean,
	lastSeen: number,
}

function ProfileStore.defaultProfile(): Profile
	local items: { [string]: number } = {}
	for id, n in Config.START_ITEMS do
		items[id] = n
	end
	return {
		money = 0,
		speed = 0,
		trails = { [Config.DEFAULT_TRAIL] = true },
		equippedTrail = Config.DEFAULT_TRAIL,
		treadmillTier = 1,
		plotLevel = 1,
		plants = {},
		index = {},
		items = items,
		seedBag = {},
		receipts = {},
		reachedEnd = false,
		lastSeen = 0,
	}
end

local function num(v: any, default: number, lo: number, hi: number): number
	if type(v) ~= "number" or v ~= v then
		return default
	end
	return math.clamp(v, lo, hi)
end

local function int(v: any, default: number, lo: number, hi: number): number
	return math.floor(num(v, default, lo, hi))
end

-- v1/v2 -> v3: an old Speed Gain tier becomes the trail with the nearest multiplier at or below it
-- (x1 -> Grey x1.5, x2 -> Green x2, x3 -> Purple x3, x5 -> Rainbow x5), owned and equipped, so nobody's
-- multiplier drops. x10 and x25 are above the best trail (Rainbow x5): those players get Rainbow and the
-- money they paid for the tiers above x5 back. Returns (trail id, refund).
function ProfileStore.migrateSpeedMult(tier: number): (string, number)
	local old = ProfileStore.LEGACY_SPEED_MULT[tier] or ProfileStore.LEGACY_SPEED_MULT[1]
	local best = Config.trailById(Config.DEFAULT_TRAIL) :: Config.Trail
	for _, t in Config.TRAILS do
		if t.mult <= old.mult and t.mult > best.mult then
			best = t
		end
	end
	local refund = 0
	for i = 1, tier do
		local paid = ProfileStore.LEGACY_SPEED_MULT[i]
		if paid and paid.mult > best.mult then
			refund += paid.price
		end
	end
	return best.id, refund
end

-- v1/v2 -> v3: bought slots become the plot level that has them (5 slots = level 1), so everyone keeps
-- their slots.
function ProfileStore.levelForSlots(slots: number): number
	return math.clamp(math.floor(slots) - Config.SLOTS_START + 1, 1, Config.PLOT_LEVEL_MAX)
end

-- Plain JSON-safe table for the DataStore.
function ProfileStore.serialize(p: Profile): { [string]: any }
	local plants = {}
	for _, pl in p.plants do
		table.insert(plants, { s = pl.slot, z = pl.zone, r = pl.rarity, m = pl.mutation, t = pl.plantedAt })
	end
	local index = {}
	for key, v in p.index do
		if v then
			table.insert(index, key)
		end
	end
	table.sort(index)
	local trails = {}
	for id, owned in p.trails do
		if owned then
			table.insert(trails, id)
		end
	end
	table.sort(trails)
	return {
		v = ProfileStore.VERSION,
		money = p.money,
		speed = p.speed,
		trails = trails,
		trail = p.equippedTrail,
		treadmillTier = p.treadmillTier,
		plotLevel = p.plotLevel,
		plants = plants,
		index = index,
		items = table.clone(p.items),
		bag = table.clone(p.seedBag),
		receipts = table.clone(p.receipts),
		reachedEnd = p.reachedEnd,
		lastSeen = p.lastSeen,
	}
end

-- Rebuild a Profile from stored data; anything missing or malformed falls back to defaults.
function ProfileStore.deserialize(data: any): Profile
	local p = ProfileStore.defaultProfile()
	if type(data) ~= "table" then
		return p
	end
	local maxSlots = Config.SLOTS_MAX + Config.PASS_EXTRA_SLOTS
	p.money = num(data.money, 0, 0, math.huge)
	p.speed = num(data.speed, 0, 0, math.huge)
	p.treadmillTier = int(data.treadmillTier, 1, 1, #Config.TREADMILL_TIERS)
	if type(data.v) == "number" and data.v >= 3 then
		p.plotLevel = int(data.plotLevel, 1, 1, Config.PLOT_LEVEL_MAX)
		if type(data.trails) == "table" then
			for _, id in data.trails do
				local trail = Config.trailById(id)
				if trail then
					p.trails[trail.id] = true
				end
			end
		end
		local equipped = Config.trailById(data.trail)
		p.equippedTrail = if equipped and p.trails[equipped.id] then equipped.id else Config.DEFAULT_TRAIL
	else
		-- v1/v2: bought slots -> plot level; Speed Gain tier -> a trail (+ a refund above Rainbow)
		p.plotLevel = ProfileStore.levelForSlots(int(data.slots, Config.SLOTS_START, Config.SLOTS_START, Config.SLOTS_MAX))
		local trail, refund = ProfileStore.migrateSpeedMult(int(data.speedMultTier, 1, 1, #ProfileStore.LEGACY_SPEED_MULT))
		p.trails[trail] = true
		p.equippedTrail = trail
		p.money += refund
	end
	p.reachedEnd = data.reachedEnd == true
	p.lastSeen = num(data.lastSeen, 0, 0, math.huge)

	local used = {}
	if type(data.plants) == "table" then
		for _, raw in data.plants do
			if type(raw) == "table" then
				local slot = int(raw.s, 0, 0, maxSlots)
				local zone = int(raw.z, 0, 0, #Config.ZONES)
				local rarity = int(raw.r, 0, 0, #Config.RARITIES)
				local mutation = if type(raw.m) == "string" and Config.mutationById(raw.m) then raw.m else nil
				if slot >= 1 and zone >= 1 and rarity >= 1 and not used[slot] and type(raw.t) == "number" then
					used[slot] = true
					table.insert(p.plants, { slot = slot, zone = zone, rarity = rarity, mutation = mutation, plantedAt = raw.t })
				end
			end
		end
	end
	if type(data.index) == "table" then
		for _, key in data.index do
			if type(key) == "string" and #key < 40 then
				p.index[key] = true
			end
		end
	end
	if type(data.items) == "table" then
		for id, n in data.items do
			if type(id) == "string" and type(n) == "number" and not RETIRED_ITEMS[id] then
				p.items[id] = math.max(0, math.floor(n))
			end
		end
	end
	-- data.potions (timers of the removed potions) is deliberately ignored.
	-- v2 fields (absent in v1 saves, which keep the empty defaults)
	if type(data.bag) == "table" then
		local keys = {}
		for key, n in data.bag do
			if SeedPacks.parseBagKey(key) and type(n) == "number" and n >= 1 and n == n then
				table.insert(keys, key)
			end
		end
		table.sort(keys) -- deterministic clamping below
		local total = 0
		for _, key in keys do
			local take = math.min(math.floor(data.bag[key]), Config.SEED_BAG_HARD_MAX - total)
			if take > 0 then
				p.seedBag[key] = take
				total += take
			end
		end
	end
	if type(data.receipts) == "table" then
		for _, id in data.receipts do
			if type(id) == "string" and #id <= 64 then
				table.insert(p.receipts, id)
			end
		end
		while #p.receipts > Config.RECEIPT_HISTORY do
			table.remove(p.receipts, 1)
		end
	end
	return p
end

----------------------------------------------------------------------------------------------------
-- DataStore wrapper
----------------------------------------------------------------------------------------------------
export type Store = typeof(setmetatable({} :: { store: any, retries: number, backoff: number }, ProfileStore))

function ProfileStore.new(dataStore: any, retries: number?, backoff: number?): Store
	return setmetatable({ store = dataStore, retries = retries or Config.SAVE_RETRIES, backoff = backoff or 1 }, ProfileStore)
end

local function keyFor(userId: number): string
	return "Player_" .. tostring(userId)
end

function ProfileStore.retry(self: Store, fn: () -> ()): (boolean, string?)
	local lastErr: string? = nil
	for attempt = 1, self.retries do
		local ok, err = pcall(fn :: any)
		if ok then
			return true, nil
		end
		lastErr = tostring(err)
		if attempt < self.retries then
			task.wait(self.backoff * 2 ^ (attempt - 1))
		end
	end
	return false, lastErr
end

-- Returns (profile, loadedOk). If loading failed, the caller must NOT save over the real data.
function ProfileStore.load(self: Store, userId: number): (Profile, boolean)
	local raw: any = nil
	local ok, err = self:retry(function()
		-- UpdateAsync that returns nil just reads, without writing.
		self.store:UpdateAsync(keyFor(userId), function(old: any)
			raw = old
			return nil
		end)
	end)
	if not ok then
		warn(`[ProfileStore] load failed for {userId}: {err}`)
		return ProfileStore.defaultProfile(), false
	end
	return ProfileStore.deserialize(raw), true
end

function ProfileStore.save(self: Store, userId: number, profile: Profile): boolean
	local data = ProfileStore.serialize(profile)
	local ok, err = self:retry(function()
		self.store:UpdateAsync(keyFor(userId), function(_old: any)
			return data
		end)
	end)
	if not ok then
		warn(`[ProfileStore] save failed for {userId}: {err}`)
	end
	return ok
end

return ProfileStore
