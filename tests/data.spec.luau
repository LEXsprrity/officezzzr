-- Save/load: serialization round-trip, JSON safety, UpdateAsync retries, sanitizing bad data.
local serde = require("@lune/serde")
local H = require("./harness")

local Config = H.shared("Config")
local ProfileStore = H.server("ProfileStore")

-- A DataStore that stores JSON (like the real one) and can be told to fail N times.
local function mockDataStore(failTimes: number?)
	local store = { data = {} :: { [string]: string }, calls = 0, failTimes = failTimes or 0 }
	function store.UpdateAsync(self, key: string, transform: (any) -> any)
		self.calls += 1
		if self.failTimes > 0 then
			self.failTimes -= 1
			error("502: API Services rejected request (mock)")
		end
		local old = if self.data[key] then serde.decode("json", self.data[key]) else nil
		local new = transform(old)
		if new ~= nil then
			self.data[key] = serde.encode("json", new)
		end
		return new
	end
	return store
end

local function richProfile()
	local p = ProfileStore.defaultProfile()
	p.money = 1234567.89
	p.speed = 5.5e9
	p.speedMultTier = 4
	p.treadmillTier = 3
	p.slots = 14
	p.plants = {
		{ slot = 1, zone = 1, rarity = 1, mutation = nil, plantedAt = 1790000000 },
		{ slot = 2, zone = 4, rarity = 5, mutation = "Gold", plantedAt = 1790000123 },
		{ slot = 7, zone = 7, rarity = 3, mutation = "Rainbow", plantedAt = 1790000456 },
	}
	p.index = { ["1:1"] = true, ["4:5"] = true, ["4:Gold"] = true, ["7:3"] = true, ["7:Rainbow"] = true }
	p.items = { SleepDust = 2, PotionLuck = 1 }
	p.potions = { Money = 1790001000 }
	p.reachedEnd = true
	p.lastSeen = 1790000999
	return p
end

H.test("data: serialize -> deserialize round-trips every field", function()
	local p = richProfile()
	local back = ProfileStore.deserialize(ProfileStore.serialize(p))
	local ok, why = H.deepEq(back, p)
	H.ok(ok, why)
end)

H.test("data: save then load through a (JSON) DataStore round-trips", function()
	local ds = mockDataStore()
	local p = richProfile()
	H.ok(ProfileStore.new(ds):save(42, p), "save ok")
	-- a fresh store object, as on another server
	local loaded, ok = ProfileStore.new(ds):load(42)
	H.ok(ok, "load ok")
	local same, why = H.deepEq(loaded, p)
	H.ok(same, why)
end)

H.test("data: only the plant timestamp is stored, not weight or income", function()
	local data = ProfileStore.serialize(richProfile())
	for _, plant in data.plants do
		for key in plant do
			H.ok(key == "s" or key == "z" or key == "r" or key == "m" or key == "t", "unexpected plant field " .. key)
		end
	end
end)

H.test("data: a new player gets defaults (10 slots, 3 Sleep Dust, 2x treadmill)", function()
	local p, ok = ProfileStore.new(mockDataStore()):load(7)
	H.ok(ok)
	H.eq(p.slots, Config.SLOTS_START)
	H.eq(p.slots, 10)
	H.eq(p.items.SleepDust, 3)
	H.eq(Config.TREADMILL_TIERS[p.treadmillTier].mult, 2)
	H.eq(p.money, 0)
	H.eq(#p.plants, 0)
end)

H.test("data: UpdateAsync is retried on failure", function()
	local ds = mockDataStore(2)
	local store = ProfileStore.new(ds, 4, 0)
	H.ok(store:save(1, richProfile()), "eventually saved")
	H.eq(ds.calls, 3)
end)

H.test("data: a failed load is flagged so the session never overwrites real data", function()
	local ds = mockDataStore(99)
	local p, ok = ProfileStore.new(ds, 3, 0):load(1)
	H.eq(ok, false)
	H.eq(ds.calls, 3)
	H.eq(p.money, 0, "plays on defaults")
end)

H.test("data: garbage and out-of-range values are sanitized", function()
	local p = ProfileStore.deserialize({
		money = "lots", speed = -5, speedMultTier = 999, treadmillTier = 0, slots = 1e9,
		plants = {
			{ s = 1, z = 2, r = 3, t = 100 },
			{ s = 1, z = 2, r = 3, t = 200 }, -- duplicate slot
			{ s = 2, z = 99, r = 1, t = 1 }, -- bad zone
			{ s = 3, z = 1, r = 1, m = "Hacked", t = 5 }, -- unknown mutation dropped
			"nope",
		},
		index = { "1:1", 5, string.rep("x", 100) },
		items = { SleepDust = 2.7, Bad = "x" },
	})
	H.eq(p.money, 0)
	H.eq(p.speed, 0)
	H.eq(p.speedMultTier, #Config.SPEED_MULT_TIERS)
	H.eq(p.treadmillTier, 1)
	H.eq(p.slots, Config.SLOTS_MAX)
	H.eq(#p.plants, 3)
	H.eq(p.plants[1].plantedAt, 100)
	H.eq(p.plants[3].mutation, nil)
	H.ok(p.index["1:1"])
	H.eq(p.items.SleepDust, 2)
	H.eq(p.items.Bad, nil)
end)

return nil
