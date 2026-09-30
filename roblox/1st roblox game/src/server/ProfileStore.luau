--!strict
-- Player save data: defaults, (de)serialization with validation, and a DataStore wrapper that
-- uses UpdateAsync with retries. The DataStore is injected so tests can pass a mock.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local ProfileStore = {}
ProfileStore.__index = ProfileStore

ProfileStore.VERSION = 1

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
	speedMultTier: number,
	treadmillTier: number,
	slots: number,
	plants: { Plant },
	index: { [string]: boolean }, -- "zone:rarity" and "zone:Mutation" keys
	items: { [string]: number },
	potions: { [string]: number }, -- stat -> expiry (unix seconds)
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
		speedMultTier = 1,
		treadmillTier = 1,
		slots = Config.SLOTS_START,
		plants = {},
		index = {},
		items = items,
		potions = {},
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
	return {
		v = ProfileStore.VERSION,
		money = p.money,
		speed = p.speed,
		speedMultTier = p.speedMultTier,
		treadmillTier = p.treadmillTier,
		slots = p.slots,
		plants = plants,
		index = index,
		items = table.clone(p.items),
		potions = table.clone(p.potions),
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
	p.speedMultTier = int(data.speedMultTier, 1, 1, #Config.SPEED_MULT_TIERS)
	p.treadmillTier = int(data.treadmillTier, 1, 1, #Config.TREADMILL_TIERS)
	p.slots = int(data.slots, Config.SLOTS_START, Config.SLOTS_START, Config.SLOTS_MAX)
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
			if type(id) == "string" and type(n) == "number" then
				p.items[id] = math.max(0, math.floor(n))
			end
		end
	end
	if type(data.potions) == "table" then
		for stat, expiry in data.potions do
			if type(stat) == "string" and type(expiry) == "number" then
				p.potions[stat] = expiry
			end
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
