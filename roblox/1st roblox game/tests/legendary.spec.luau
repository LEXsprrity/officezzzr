-- Legendary plants are trophies (owner's TODO item 4): rare everywhere, extremely rare in the last two
-- zones (Deep Space, Spirit Garden), rare in the premium packs too, and announced to the whole server.
local H = require("./harness")
local Config = H.shared("Config")
local SeedPacks = H.shared("SeedPacks")

local L = Config.LEGENDARY
local LAST_ZONES = { 6, 7 }

local function seeded(seed: number): () -> number
	local r = H.Random.new(seed)
	return function()
		return r:NextNumber()
	end
end

-- Legendary chance per pod roll, in zone k (day or night)
local function podChance(k: number, night: boolean): number
	local w = Config.rarityWeights(k, if night then Config.NIGHT_LUCK else 1)
	local total = 0
	for _, x in w do
		total += x
	end
	return w[L] / total
end

H.test("legendary: about 0.5-1% per steal by day in zones 1-5", function()
	H.eq(Config.RARITIES[L].id, "Legendary")
	for k = 1, 5 do
		local p = podChance(k, false)
		H.ok(p >= 0.005 and p <= 0.01, `{Config.ZONES[k].id}: {p * 100}% by day`)
		H.ok(podChance(k, true) <= 0.02, `{Config.ZONES[k].id}: {podChance(k, true) * 100}% at night`)
	end
end)

H.test("legendary: about 1 in 2,000 by day in Deep Space and the Spirit Garden, at most ~0.1% at night", function()
	for _, k in LAST_ZONES do
		local day, night = podChance(k, false), podChance(k, true)
		H.ok(day >= 0.0003 and day <= 0.0006, `{Config.ZONES[k].id}: {day * 100}% by day`)
		H.ok(night > day, `{Config.ZONES[k].id}: night luck still helps`)
		H.ok(night <= 0.001 + 1e-12, `{Config.ZONES[k].id}: {night * 100}% at night`)
	end
end)

H.test("legendary: never more common deeper in, and the last two zones are far rarer than any other", function()
	for _, night in { false, true } do
		for k = 2, #Config.ZONES do
			H.ok(podChance(k, night) <= podChance(k - 1, night) + 1e-12, `zone {k} vs {k - 1} (night {night})`)
		end
		local rarestEarly = math.huge
		for k = 1, 5 do
			rarestEarly = math.min(rarestEarly, podChance(k, night))
		end
		for _, k in LAST_ZONES do
			H.ok(podChance(k, night) * 5 <= rarestEarly, `zone {k} at least 5x rarer than zones 1-5 (night {night})`)
		end
	end
end)

H.test("legendary: the other rarities stay sane (weights sum to 1, Epic still common enough late)", function()
	for k = 1, #Config.ZONES do
		for _, luck in { 1, Config.NIGHT_LUCK } do
			local w = Config.rarityWeights(k, luck)
			local sum = 0
			for i, x in w do
				H.ok(x > 0, `zone {k} rarity {i}`)
				sum += x
			end
			H.near(sum, 1, 1e-9, `zone {k} luck {luck}`)
		end
	end
	local epicSpiritDay = Config.rarityWeights(7, 1)[4]
	H.ok(epicSpiritDay >= 0.05 and epicSpiritDay <= 0.15, `Spirit Garden Epic by day {epicSpiritDay * 100}%`)
end)

H.test("legendary: packs roll it at 1-2%, Celestial stays 0.5% pack-only", function()
	for _, entry in Config.products("Pack") do
		local pack = SeedPacks.packForProduct(entry.product)
		local odds = SeedPacks.odds(pack)
		H.ok(odds.rarities[L] >= 1 and odds.rarities[L] <= 2, `{pack.name}: {odds.rarities[L]}%`)
		H.ok(odds.rarities[L] / 100 > podChance(pack.zone, true), `{pack.name} still beats a night steal`)
		H.eq(odds.mutations[1].id, "Celestial")
		H.near(odds.mutations[1].pct, 0.5, 1e-12)
	end
	H.eq(Config.mutationById("Celestial").chance, 0, "pods never roll Celestial")
end)

H.test("legendary: a large seeded roll matches the odds (pods by day/night, packs)", function()
	-- pods: N rolls per case, hits within 15% of the expected count (>= 400 expected: about 4 sigma)
	for _, case in { { 1, false, 100000 }, { 5, false, 150000 }, { 6, false, 1000000 }, { 7, false, 1000000 }, { 7, true, 600000 } } do
		local k, night, N = case[1], case[2], case[3]
		local rng = seeded(4000 + k * 2 + (if night then 1 else 0))
		local hits = 0
		for _ = 1, N do
			local r = Config.rollSeed(k, if night then Config.NIGHT_LUCK else 1, night, rng)
			if r == L then
				hits += 1
			end
		end
		local expected = podChance(k, night) * N
		H.ok(math.abs(hits - expected) <= expected * 0.15, `zone {k} night {night}: {hits} Legendaries in {N}, expected {expected}`)
	end
	-- packs: 1.5% of 100k = 1,500 expected
	for _, entry in Config.products("Pack") do
		local pack = SeedPacks.packForProduct(entry.product)
		local rng = seeded(77 + pack.zone)
		local N, hits = 100000, 0
		for _ = 1, N do
			if SeedPacks.roll(pack, rng) == L then
				hits += 1
			end
		end
		local expected = pack.legendaryChance * N
		H.ok(math.abs(hits - expected) <= expected * 0.1, `{pack.name}: {hits} in {N}, expected {expected}`)
	end
end)

H.test("announce: only a Legendary from Deep Space / Spirit Garden, or from a pack", function()
	for k = 1, #Config.ZONES do
		for r = 1, #Config.RARITIES do
			local fromPod = Config.announcesLegendary(k, r, false)
			local fromPack = Config.announcesLegendary(k, r, true)
			H.eq(fromPod, r == L and k >= 6, `pod zone {k} rarity {r}`)
			H.eq(fromPack, r == L, `pack zone {k} rarity {r}`)
		end
	end
	H.eq(Config.legendaryAnnouncement("Alex", 6, nil), "🌟 Alex got a LEGENDARY Starpetal!")
	H.eq(Config.legendaryAnnouncement("Alex", 7, "Celestial"), "🌟 Alex got a LEGENDARY Celestial Lotus Wyrm!")
end)

return nil
