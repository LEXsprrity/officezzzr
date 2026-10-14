--!strict
-- Player save data: defaults, (de)serialization with validation and migrations, and a DataStore wrapper
-- that uses UpdateAsync with retries. The DataStore is injected so tests can pass a mock.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SeedPacks = require(Shared:WaitForChild("SeedPacks"))
local Planting = require(Shared:WaitForChild("Planting"))

local ProfileStore = {}
ProfileStore.__index = ProfileStore

-- v2 added the seed bag and Robux receipt history; v1 saves load with both empty.
-- v3 (economy rework) replaced the Speed Gain tier with owned/equipped trails and bought slots with the
-- plot level; v1/v2 saves are migrated on load (see migrateSpeedMult and the plot level below).
-- v4 added the community rewards: the Free Gift flag, whether its window has opened by itself, and the
-- free chest's last claim. Older saves load with the gift unclaimed, the window not shown yet and the
-- chest ready.
-- v5 grew the treadmill from 3 tiers (x2, Robux x3, Robux x5) to Config.TREADMILL_TIERS (money or
-- Robux, one tier at a time). An older save's tier becomes the v5 tier with the same multiplier
-- (migrateTreadmillTier), so nobody's treadmill changes speed.
-- v6 replaced the fixed plant slots with free planting: each plant saves where it stands on the plot (x, z in
-- the plot's space, Shared/Planting) and keeps its slot number as its id. An older save's plant gets its old
-- slot's spot moved onto the new dirt beds (Planting.legacySpot), so the plot keeps its arrangement.
-- v7 removed the Speed levels and made the Speed per step flat (BASE_SPEED_PER_STUD x trail, no longer
-- growing with Speed), which shrank the whole Speed scale: the zones' recommended Speed went from
-- 10K..5B to 25K..75M, and the trails from x1.5..x5 to x1..x3. An older save's Speed is moved onto the
-- new scale by where it stood between the old zones (migrateSpeed), so everyone keeps every zone they had
-- reached and the same share of the way to the next one. Money, trails and tiers stay as they were.
-- Later the treadmill tiers changed from a multiplier to a fixed Speed per second each; a tier keeps its
-- number, so `treadmillTier` saves unchanged (no new version).
ProfileStore.VERSION = 7

-- The zones' recommended Speed before v7 (Config.ZONES order), for migrateSpeed.
ProfileStore.LEGACY_ZONE_REQ = { 0, 10e3, 500e3, 5e6, 50e6, 500e6, 5e9 }

-- The trails' multipliers before v7 (v3-v6), for the v1/v2 Speed Gain migration (migrateSpeedMult).
ProfileStore.LEGACY_TRAIL_MULT = { Grey = 1.5, Green = 2, Blue = 2.5, Purple = 3, Golden = 3.5, Red = 4, Rainbow = 5 } :: { [string]: number }

-- The multipliers of the v1-v4 treadmill tiers (`treadmillTier` 1..3).
ProfileStore.LEGACY_TREADMILL_MULT = { 2, 3, 5 }

-- The multipliers of the v5-v7 tiers 1..10, which paid the walking gain x this. Tiers now pay a fixed
-- Speed per second (Config.TREADMILL_TIERS) but keep their number, so saves keep `treadmillTier` as it is;
-- this only maps the v1-v4 tiers onto them (migrateTreadmillTier).
ProfileStore.TIER_MULT_V5 = { 2, 2.25, 2.5, 2.75, 3, 3.5, 4, 5, 6, 8 }

-- Items removed from the game (the potions, the guards' sleep item) may still be in saves of any version.
-- Only ids listed in Config.START_ITEMS are loaded; anything else in `items` is dropped, and old potion
-- timers (`potions`) are ignored.

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
	slot: number, -- its id (unique per profile): the remove prompt, the Plants menu and the SELL stall use it; seeds its variance
	zone: number,
	rarity: number,
	mutation: string?,
	plantedAt: number, -- unix seconds; weight is derived from this, never stored
	x: number, -- where it stands, in the plot's space (Shared/Planting): across
	z: number, -- ...and along (+z toward the entrance)
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
	reachedEnd: boolean, -- legacy (the old "End of the Line" finish, now gone): kept so saves round-trip
	lastSeen: number,
	freeGift: boolean, -- the Free Gift (community Speed) was claimed: never again on this account
	giftShown: boolean, -- the Free Gift window already opened by itself once
	chestAt: number, -- unix seconds of the last free chest claim (0 = never)
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
		freeGift = false,
		giftShown = false,
		chestAt = 0,
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
-- multiplier dropped. x10 and x25 are above the best trail (Rainbow x5): those players get Rainbow and the
-- money they paid for the tiers above x5 back. Returns (trail id, refund). Compared with the trails'
-- multipliers of the time (LEGACY_TRAIL_MULT): v7 shrank them all, and every trail with them.
function ProfileStore.migrateSpeedMult(tier: number): (string, number)
	local old = ProfileStore.LEGACY_SPEED_MULT[tier] or ProfileStore.LEGACY_SPEED_MULT[1]
	local legacy = ProfileStore.LEGACY_TRAIL_MULT
	local best = Config.DEFAULT_TRAIL
	for _, t in Config.TRAILS do
		local mult = legacy[t.id]
		if mult and mult <= old.mult and mult > legacy[best] then
			best = t.id
		end
	end
	local refund = 0
	for i = 1, tier do
		local paid = ProfileStore.LEGACY_SPEED_MULT[i]
		if paid and paid.mult > legacy[best] then
			refund += paid.price
		end
	end
	return best, refund
end

-- v1-v6 -> v7: an old Speed (pre-flat-gain scale) onto today's scale. Between two zones' old recommended
-- Speeds (LEGACY_ZONE_REQ) it lands the same share of the way between their new ones, measured on a log
-- scale (the old Speeds grew about x10 a zone): 10K -> 25K (the Desert), 50M -> 7.5M (the Snow Peaks),
-- 5B -> the Spirit Garden's. Below the Desert it scales linearly; past the Spirit Garden it keeps the
-- last stretch's slope (5B -> 75M, 50B -> ~225M). Monotonic, so nobody overtakes anybody.
function ProfileStore.migrateSpeed(old: number): number
	if old ~= old or old <= 0 then
		return 0
	end
	local from = ProfileStore.LEGACY_ZONE_REQ
	local n = math.min(#from, #Config.ZONES)
	local function to(k: number): number
		return Config.ZONES[k].req
	end
	if old < from[2] then
		return old * to(2) / from[2]
	end
	for k = 2, n - 1 do
		if old < from[k + 1] then
			local share = math.log(old / from[k]) / math.log(from[k + 1] / from[k])
			return to(k) * (to(k + 1) / to(k)) ^ share
		end
	end
	local slope = math.log(to(n) / to(n - 1)) / math.log(from[n] / from[n - 1])
	return math.min(to(n) * (old / from[n]) ^ slope, 1e300)
end

-- v1/v2 -> v3: bought slots become the plot level that has them (5 slots = level 1), so everyone keeps
-- their slots.
function ProfileStore.levelForSlots(slots: number): number
	return math.clamp(math.floor(slots) - Config.SLOTS_START + 1, 1, Config.PLOT_LEVEL_MAX)
end

-- v1-v4 -> v5: an old treadmill tier (1..3) becomes the highest new tier whose multiplier isn't above
-- the old one (x2 -> 1, x3 -> 5, x5 -> 8).
function ProfileStore.migrateTreadmillTier(oldTier: number): number
	local oldMult = ProfileStore.LEGACY_TREADMILL_MULT[oldTier] or ProfileStore.LEGACY_TREADMILL_MULT[1]
	local best = 1
	for tier, mult in ProfileStore.TIER_MULT_V5 do
		if mult <= oldMult then
			best = tier
		end
	end
	return best
end

-- Plain JSON-safe table for the DataStore.
function ProfileStore.serialize(p: Profile): { [string]: any }
	local plants = {}
	for _, pl in p.plants do
		table.insert(plants, { s = pl.slot, z = pl.zone, r = pl.rarity, m = pl.mutation, t = pl.plantedAt, px = pl.x, pz = pl.z })
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
		freeGift = p.freeGift,
		giftShown = p.giftShown,
		chestAt = p.chestAt,
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
	if not (type(data.v) == "number" and data.v >= 7) then
		p.speed = ProfileStore.migrateSpeed(p.speed) -- v1-v6: the old Speed scale
	end
	if type(data.v) == "number" and data.v >= 5 then
		p.treadmillTier = int(data.treadmillTier, 1, 1, Config.TREADMILL_MAX)
	else
		p.treadmillTier = ProfileStore.migrateTreadmillTier(int(data.treadmillTier, 1, 1, #ProfileStore.LEGACY_TREADMILL_MULT))
	end
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
	-- v4 fields (absent before: gift unclaimed, window not shown, chest ready)
	p.freeGift = data.freeGift == true
	p.giftShown = data.giftShown == true
	p.chestAt = num(data.chestAt, 0, 0, math.huge)

	local used = {}
	local modern = type(data.v) == "number" and data.v >= 6 -- plants saved with their spot
	if type(data.plants) == "table" then
		for _, raw in data.plants do
			if type(raw) == "table" then
				local slot = int(raw.s, 0, 0, maxSlots)
				local zone = int(raw.z, 0, 0, #Config.ZONES)
				local rarity = int(raw.r, 0, 0, #Config.RARITIES)
				local mutation = if type(raw.m) == "string" and Config.mutationById(raw.m) then raw.m else nil
				if slot >= 1 and zone >= 1 and rarity >= 1 and not used[slot] and type(raw.t) == "number" then
					used[slot] = true
					-- v6: its saved spot (kept when it is a sane number on the plot; PlotService.assign still checks it
					-- against the real beds). Older saves, or a bad spot: the old slot's spot on the new beds.
					local x, z = Planting.legacySpot(slot)
					local half = Config.PLOT_SIZE / 2
					if modern and type(raw.px) == "number" and type(raw.pz) == "number" and math.abs(raw.px) <= half and math.abs(raw.pz) <= half then
						x, z = raw.px, raw.pz
					end
					table.insert(p.plants, { slot = slot, zone = zone, rarity = rarity, mutation = mutation, plantedAt = raw.t, x = x, z = z })
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
			if type(id) == "string" and type(n) == "number" and Config.START_ITEMS[id] ~= nil then
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
