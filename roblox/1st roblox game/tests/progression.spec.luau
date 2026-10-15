-- Free-to-play progression: a flat Speed per step (base x trail; a treadmill pays its tier's fixed rate x the trail; nothing that
-- grows with Speed), and a simulated free player (tests/progression_sim) who reaches every zone within
-- about ±50% of the owner's targets, each zone taking clearly longer than the one before.
-- Treadmill tiers bought with money speed it up; Robux (treadmill upgrades, Speed packs) shortens it a
-- lot but is never required; AFK farming on the treadmill is far slower than running the corridor.
local H = require("./harness")
local Config = H.shared("Config")
local Sim = require("./progression_sim")

local free = Sim.run()

H.test("progression: Speed per step is flat: the base x the trail's small multiplier, whatever your Speed", function()
	H.eq(Config.BASE_SPEED_PER_STUD, 1)
	for _, t in Config.TRAILS do
		H.eq(Config.speedPerStud(t.id), Config.BASE_SPEED_PER_STUD * t.mult, t.id)
	end
	H.eq(Config.speedPerStud(nil), Config.BASE_SPEED_PER_STUD, "no trail: the free one (x1)")
	H.eq(Config.speedPerStud("Hacked"), Config.BASE_SPEED_PER_STUD, "unknown trail: the free one")
	-- trails stay a little multiplier: x1 (free) rising to x3
	H.eq(Config.TRAILS[1].mult, 1)
	H.eq(Config.TRAILS[#Config.TRAILS].mult, 3)
	for i = 2, #Config.TRAILS do
		H.ok(Config.TRAILS[i].mult > Config.TRAILS[i - 1].mult, `{Config.TRAILS[i].id} beats the trail before it`)
	end
	-- the treadmill pays its tier's fixed value x the trail every step (server tick) (no Speed or WalkSpeed in it at all)
	local SpeedLogic = H.server("SpeedLogic")
	local dt = Config.TICK
	H.near(SpeedLogic.treadmillGain(3, Config.trailMult("Blue")), Config.TREADMILL_TIERS[3].perStep * 1.5, 1e-9, "tier 3, Blue x1.5, every step")
	H.near(Config.treadmillPerSecond(3, "Blue"), Config.TREADMILL_TIERS[3].perStep * 1.5 / dt, 1e-9, "4 steps a second")
end)

H.test("progression: each zone takes clearly longer than the one before; the Spirit Garden in ~10-14 h", function()
	local last = 0
	local parts = {}
	for k = 2, #Config.ZONES do
		local took = free.arrivals[k] - free.arrivals[k - 1]
		table.insert(parts, `{Config.ZONES[k].id} +{Sim.clock(took)}`)
		H.ok(took >= last * 1.5, `{Config.ZONES[k].id} took {Sim.clock(took)}, the zone before {Sim.clock(last)}`)
		last = took
	end
	print("        time per zone: " .. table.concat(parts, ", "))
	local spirit = free.arrivals[#Config.ZONES]
	H.ok(spirit >= 10 * 3600 and spirit <= 14 * 3600, `Spirit Garden at {Sim.clock(spirit)}`)
end)

H.test("progression: a free player reaches every zone within ±50% of the target times", function()
	print("        free player: " .. (function()
		local parts = {}
		for k = 2, #Config.ZONES do
			table.insert(parts, `{Config.ZONES[k].id} {Sim.clock(free.arrivals[k])}`)
		end
		return table.concat(parts, ", ")
	end)())
	for k, zone in Config.ZONES do
		local target = Sim.TARGETS[zone.id]
		if target then
			local got = free.arrivals[k]
			H.ok(got ~= nil, `{zone.id} never reached`)
			H.ok(got >= target * 0.5 and got <= target * 1.5, `{zone.id} at {Sim.clock(got)}, target {Sim.clock(target)}`)
		end
	end
	H.ok(free.arrivals[#Config.ZONES] >= 10 * 3600 * 0.5 and free.arrivals[#Config.ZONES] <= 15 * 3600 * 1.5, "Spirit Garden around 10-15 h")
end)

H.test("progression: the timeline is stable across RNG seeds (rarity rolls)", function()
	for _, seed in { 1, 2, 3, 99, 1234 } do
		local r = Sim.run({ seed = seed })
		for k, zone in Config.ZONES do
			local target = Sim.TARGETS[zone.id]
			if target then
				H.ok(r.arrivals[k] >= target * 0.5 and r.arrivals[k] <= target * 1.5, `seed {seed}: {zone.id} at {Sim.clock(r.arrivals[k])}`)
			end
		end
	end
end)

H.test("progression: Robux shortens it noticeably (treadmill upgrades, Speed packs) but isn't needed", function()
	-- every treadmill tier bought with Robux at the start (TreadmillT1..T3, 9 receipts)
	local tread = Sim.run({ treadmillTier = Config.TREADMILL_MAX })
	local packs = Sim.run({ treadmillTier = Config.TREADMILL_MAX, speedPacks = Sim.PACKS })
	local spirit = #Config.ZONES
	H.ok(tread.arrivals[spirit] <= free.arrivals[spirit] * 0.7, `Level {Config.TREADMILL_MAX} treadmill: {Sim.clock(tread.arrivals[spirit])} vs {Sim.clock(free.arrivals[spirit])}`)
	H.ok(packs.arrivals[spirit] < tread.arrivals[spirit], "Speed packs on top help further")
	for k = 2, spirit do
		H.ok(tread.arrivals[k] <= free.arrivals[k], `{Config.ZONES[k].id}: Robux never slows you down`)
	end
end)

H.test("progression: money treadmill tiers help, and the free player buys them all game", function()
	local without = Sim.run({ noTreadmillUpgrades = true })
	local spirit = #Config.ZONES
	-- (without them the fixed free rate never gets there in the sim's 40 h: nil)
	H.ok(without.arrivals[spirit] == nil or free.arrivals[spirit] < without.arrivals[spirit] * 0.9,
		`with tiers {Sim.clock(free.arrivals[spirit])}, without {Sim.clock(without.arrivals[spirit])}`)
	local tiers = {}
	for _, b in free.buys do
		if string.match(b.what, "^Treadmill Level") then
			table.insert(tiers, b.t)
		end
	end
	H.ok(#tiers >= 5, `{#tiers} treadmill tiers bought by the Spirit Garden`)
	H.ok(tiers[1] >= 3 * 60, `the first tier isn't instant ({Sim.clock(tiers[1])})`)
	H.ok(tiers[#tiers] > free.arrivals[5], "still buying tiers after the Snow Peaks")
	H.ok(free.treadmillTier < Config.TREADMILL_MAX, "the last tiers are late-game sinks, past the Spirit Garden")
end)

H.test("progression: AFK farming on the treadmill never beats running the corridor", function()
	-- The AFK farmer fills the plot once, then only stands on the treadmill, buying the same upgrades.
	-- Both start the same way (the Desert comes before the plot is first full), so compare from the Jungle.
	local afk = Sim.run({ afk = true, limitHours = 80 })
	for k = 3, #Config.ZONES do
		local zone = Config.ZONES[k].id
		H.ok(afk.arrivals[k] == nil or afk.arrivals[k] > free.arrivals[k], `{zone}: AFK {Sim.clock(afk.arrivals[k])}, active {Sim.clock(free.arrivals[k])}`)
	end
	H.ok(afk.arrivals[#Config.ZONES] == nil or afk.arrivals[#Config.ZONES] > 2 * free.arrivals[#Config.ZONES], "far behind by the end")
	H.ok(afk.treadmillTier < free.treadmillTier, "plants from the corridor pay for the better treadmill")
end)

H.test("progression: money stays a sink all game (trails and plot levels bought throughout)", function()
	local spirit = free.arrivals[#Config.ZONES]
	local trailAt: { [string]: number } = {}
	local plotBuys = { early = 0, middle = 0, late = 0 }
	for _, b in free.buys do
		local trail = string.match(b.what, "^(%a+) Trail$")
		if trail then
			trailAt[trail] = b.t
		elseif string.match(b.what, "^Plot Level") then
			local third = if b.t < spirit / 3 then "early" elseif b.t < spirit * 2 / 3 then "middle" else "late"
			plotBuys[third] += 1
		end
	end
	for _, t in Config.TRAILS do
		if t.price > 0 then
			H.ok(trailAt[t.id] ~= nil, `the free player buys the {t.name}`)
		end
	end
	-- the owner's early trails come early; the retuned Red and Rainbow are goals for the second half
	H.ok(trailAt.Golden < free.arrivals[5], "Golden before Snow")
	H.ok(trailAt.Red > free.arrivals[4], "Red after reaching Lava")
	H.ok(trailAt.Rainbow > free.arrivals[6], "Rainbow after reaching Deep Space")
	H.ok(plotBuys.early > 0 and plotBuys.middle > 0 and plotBuys.late > 0, "plot levels bought in every third of the run")
	H.ok(free.plotLevel < Config.PLOT_LEVEL_MAX, "the last plot levels are still ahead at the Spirit Garden")
end)

return nil
