-- Free-to-play progression: the Speed curve (gain per stud compounds with Speed), and a simulated free
-- player (tests/progression_sim) who reaches every zone within about ±50% of the owner's targets.
-- Robux (the x5 treadmill, Speed packs) shortens that a lot but is never required.
local H = require("./harness")
local Config = H.shared("Config")
local Sim = require("./progression_sim")

local free = Sim.run()

H.test("progression: Speed per step starts small and compounds with Speed (sublinearly)", function()
	H.eq(Config.gainPerStud(0), Config.GAIN_PER_STUD)
	local last = 0
	for e = 0, 10 do
		local g = Config.gainPerStud(10 ^ e)
		H.ok(g > last, "grows with Speed")
		H.ok(g < 10 ^ e or e == 0, "sublinear: never more than the Speed you already have")
		last = g
	end
	H.eq(Config.gainPerStud(-5), Config.GAIN_PER_STUD, "negative Speed is treated as 0")
	-- the trail multiplies the curve
	for _, t in Config.TRAILS do
		H.near(Config.speedPerStud(5e6, t.id), Config.gainPerStud(5e6) * t.mult, 1e-9, t.id)
	end
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

H.test("progression: Robux shortens it noticeably (x5 treadmill, Speed packs) but isn't needed", function()
	local tread = Sim.run({ treadmillTier = 3 })
	local packs = Sim.run({ treadmillTier = 3, speedPacks = { 1e6, 10e6 } })
	local spirit = #Config.ZONES
	H.ok(tread.arrivals[spirit] <= free.arrivals[spirit] * 0.7, `x5 treadmill: {Sim.clock(tread.arrivals[spirit])} vs {Sim.clock(free.arrivals[spirit])}`)
	H.ok(packs.arrivals[spirit] < tread.arrivals[spirit], "Speed packs on top help further")
	for k = 2, spirit do
		H.ok(tread.arrivals[k] <= free.arrivals[k], `{Config.ZONES[k].id}: Robux never slows you down`)
	end
end)

H.test("progression: money stays a sink all game (trails and plot levels bought throughout)", function()
	local spirit = free.arrivals[#Config.ZONES]
	local trailAt: { [string]: number } = {}
	local plotBuys = { early = 0, middle = 0, late = 0 }
	for _, b in free.buys do
		local trail = string.match(b.what, "^(%a+) Trail$")
		if trail then
			trailAt[trail] = b.t
		else
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
