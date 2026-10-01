-- Soft gates: the guard wakes after its zone's wakeDelay, then chases at walkSpeedFor(zone.req) * GUARD_SPEED_FACTOR (1)
-- and catches within CATCH_DISTANCE of the path it walked since its last tick.
local H = require("./harness")
local Vector3 = H.Vector3

local Config = H.shared("Config")
local GuardBrain = H.server("GuardBrain")

local DT = 1 / Config.GUARD_HZ

-- A brain that chases on the first tick after alert (for unit tests of the chase itself).
local function awakeBrain(k: number, home: any): any
	local brain = GuardBrain.new(k, home)
	brain.wakeDelay = 0
	return brain
end

type SimOpts = {
	standStill: boolean?,
	dust: boolean?,
	walk: number?, -- raw WalkSpeed instead of walkSpeedFor(speedStat)
	wakeDelay: number?, -- override the guard's wake-up delay
	reaction: number?, -- seconds the thief stands still after the steal before running
}

-- Simulates one steal: the thief grabs a pod and runs straight back toward base at the WalkSpeed
-- of `speedStat`; the guard's MoveTo is integrated at its WalkSpeed. Returns outcome, time and the
-- thief's final X and the closest the guard got while the thief was in the corridor.
local function simulate(k: number, speedStat: number, opts: SimOpts?): (string, number, number, number)
	local o: SimOpts = opts or {}
	local nestX = Config.nestX(k)
	local home = Vector3.new(nestX + Config.GUARD_HOME_OFFSET, 0, 0)
	local brain = GuardBrain.new(k, home)
	if o.wakeDelay then
		brain.wakeDelay = o.wakeDelay
	end
	local guardPos = home
	-- The pod closest to the guard (worst case).
	local a = math.pi / 2 + 0.5 * math.pi / Config.PODS_PER_NEST
	local pod = Vector3.new(nestX + math.cos(a) * 8, 0, math.sin(a) * 8)
	local playerPos = pod
	local walk = o.walk or Config.walkSpeedFor(speedStat)

	local t = 1000
	if o.dust then
		assert(GuardBrain.dust(brain, t - 1), "dust should work on a sleeping guard")
	end
	GuardBrain.alert(brain, t)
	local chased = false
	local closest = math.huge
	while t < 1000 + 180 do
		local running = not o.standStill and t - 1000 >= (o.reaction or 0) - 1e-9
		if running and playerPos.X >= Config.CORRIDOR_START_X then
			playerPos -= Vector3.new(walk * DT, 0, 0)
		end
		local safe = playerPos.X < Config.CORRIDOR_START_X
		if not safe then
			local gap = playerPos - guardPos
			closest = math.min(closest, Vector3.new(gap.X, 0, gap.Z).Magnitude)
		end
		local cmd = GuardBrain.step(brain, t, guardPos, { { id = "thief", pos = playerPos, safe = safe } })
		if cmd.caughtId then
			return "caught", t - 1000, playerPos.X, closest
		end
		if brain.state == "Chasing" then
			chased = true
		end
		if chased and (brain.state == "Returning" or brain.state == "Sleeping") then
			return "escaped", t - 1000, playerPos.X, closest
		end
		if cmd.moveTo then
			local delta = cmd.moveTo - guardPos
			delta = Vector3.new(delta.X, 0, delta.Z)
			local step = cmd.walkSpeed * DT
			guardPos = if delta.Magnitude <= step then Vector3.new(cmd.moveTo.X, 0, cmd.moveTo.Z) else guardPos + delta.Unit * step
		end
		t += DT
	end
	return "timeout", t - 1000, playerPos.X, closest
end

-- Lowest Speed stat (as a share of the zone's recommended Speed) that still escapes, by bisection.
local function escapeShare(k: number): number
	local req = Config.ZONES[k].req
	local lo, hi = 0, 1
	for _ = 1, 30 do
		local mid = (lo + hi) / 2
		if simulate(k, req * mid) == "escaped" then
			hi = mid
		else
			lo = mid
		end
	end
	return hi
end

-- Slack: the longest a thief at exactly the recommended Speed can stand still after the steal (reaction
-- time, lag) and still get home, by bisection. The sim ticks at GUARD_HZ, so this moves in 0.1 s steps.
local function slackOf(k: number): number
	local lo, hi = 0, 3
	for _ = 1, 30 do
		local mid = (lo + hi) / 2
		if simulate(k, Config.ZONES[k].req, { reaction = mid }) == "escaped" then
			lo = mid
		else
			hi = mid
		end
	end
	return lo
end

H.test("guard: chase speed is walkSpeedFor(req) * 1.0 for every zone", function()
	H.eq(Config.GUARD_SPEED_FACTOR, 1)
	for k, zone in Config.ZONES do
		local brain = GuardBrain.new(k, Vector3.new(0, 0, 0))
		H.near(brain.chaseSpeed, Config.walkSpeedFor(zone.req), 1e-9, zone.id)
	end
end)

H.test("guard: every zone has its own wake-up delay, and the guard uses it", function()
	local want = { Meadow = 0.5, Desert = 0, Jungle = 0.15, Lava = 0.25, Snow = 0.3, Space = 0.3, Spirit = 0.5 }
	for k, zone in Config.ZONES do
		H.eq(zone.wakeDelay, want[zone.id], zone.id)
		H.eq(GuardBrain.new(k, Vector3.new(0, 0, 0)).wakeDelay, zone.wakeDelay, zone.id)
	end
end)

H.test("guard: the Desert guard (no delay) wakes the moment a seed is taken", function()
	local brain = GuardBrain.new(2, Vector3.new(0, 0, 0))
	GuardBrain.alert(brain, 10)
	local target = { { id = 1, pos = Vector3.new(-40, 0, 0), safe = false } }
	local cmd = GuardBrain.step(brain, 10, Vector3.new(0, 0, 0), target)
	H.eq(brain.state, "Chasing", "first tick after the steal is a chase")
	H.ok(cmd.woke, "woke flag")
end)

H.test("guard: a wake-up delay holds the guard still until it has passed", function()
	local brain = GuardBrain.new(2, Vector3.new(0, 0, 0))
	brain.wakeDelay = 0.5
	GuardBrain.alert(brain, 10)
	local target = { { id = 1, pos = Vector3.new(-40, 0, 0), safe = false } }
	local cmd = GuardBrain.step(brain, 10.45, Vector3.new(0, 0, 0), target)
	H.eq(brain.state, "Waking")
	H.eq(cmd.walkSpeed, 0)
	H.eq(cmd.moveTo, nil)
	cmd = GuardBrain.step(brain, 10.5, Vector3.new(0, 0, 0), target)
	H.eq(brain.state, "Chasing")
	H.ok(cmd.woke, "woke flag")
	H.ok(cmd.moveTo ~= nil, "moving toward the thief")
	H.ok(cmd.moveTo.X < -40, "chases along the corridor axis, aiming past the thief")
end)

H.test("guard: a faster guard catches a fast runner despite 10 Hz MoveTo sampling", function()
	-- Regression: aiming at the sampled position left the guard one tick (> CATCH_DISTANCE) behind.
	-- No wake-up delay here: this is about the chase itself.
	for k = 2, #Config.ZONES do
		local zone = Config.ZONES[k]
		local walk = Config.guardChaseSpeed(k) * 0.9
		H.ok(walk / Config.GUARD_HZ > Config.CATCH_DISTANCE, "runner outpaces one catch radius per tick")
		H.eq(simulate(k, 0, { walk = walk, wakeDelay = 0 }), "caught", zone.id)
	end
end)

H.test("guard: a player AT the recommended speed who runs at once reaches the base with margin, in every zone", function()
	for k, zone in Config.ZONES do
		local outcome, _, x, closest = simulate(k, zone.req)
		H.eq(outcome, "escaped", `{zone.id} at req {zone.req}`)
		H.ok(x < Config.CORRIDOR_START_X, `{zone.id}: reached the base (x = {x})`)
		-- margin: the guard never got within 20 studs of a catch (~0.2-0.4 s of running)
		H.ok(closest >= Config.CATCH_DISTANCE + 20, `{zone.id}: guard got within {closest} studs`)
	end
end)

H.test("guard: the lowest Speed that escapes is at least 50% of the recommended Speed (zones 2-7)", function()
	local lines = {}
	for k = 2, #Config.ZONES do
		local zone = Config.ZONES[k]
		local share = escapeShare(k)
		H.ok(share >= 0.5, `{zone.id}: escapes from {math.floor(share * 1000) / 10}% of the recommended Speed`)
		H.ok(share < 1, `{zone.id}: the recommended Speed itself escapes`)
		table.insert(lines, string.format("%s: delay %.2fs, escape from Speed %.3g (%.1f%% of rec, WalkSpeed %.1f vs guard %.1f), slack %.1fs",
			zone.id, zone.wakeDelay, zone.req * share, 100 * share, Config.walkSpeedFor(zone.req * share), Config.guardChaseSpeed(k), slackOf(k)))
	end
	print("        escape thresholds  " .. table.concat(lines, "\n                           "))
end)

H.test("guard: at the recommended Speed there is >= 0.5 s of slack to start running (Desert: 0.3 s)", function()
	-- The Desert's run home is only ~580 studs: any head start worth 0.4+ s also lets players under 50% of
	-- its recommended Speed escape, and the 50% gate wins. Every other zone gets the full 0.5 s.
	for k = 2, #Config.ZONES do
		local zone = Config.ZONES[k]
		local need = if zone.id == "Desert" then 0.3 else 0.5
		H.eq(simulate(k, zone.req, { reaction = need }), "escaped", `{zone.id} reacting {need}s late`)
		H.ok(slackOf(k) >= need - 1e-6, zone.id)
	end
end)

H.test("guard: at ~70% of the recommended WalkSpeed you get caught, in every zone", function()
	for k, zone in Config.ZONES do
		local walk = Config.walkSpeedFor(zone.req) * 0.7 -- the Meadow's 11.2 is below the 16 floor, but the gate still holds
		local outcome, t, x = simulate(k, 0, { walk = walk })
		H.eq(outcome, "caught", `{zone.id} at WalkSpeed {walk}`)
		H.ok(t < Config.CHASE_TIMEOUT, "caught before the timeout")
		H.ok(x >= Config.CORRIDOR_START_X, "caught in the corridor")
	end
end)

H.test("guard: a player well BELOW the recommended speed gets caught (zones 2-7)", function()
	for k = 2, #Config.ZONES do
		local zone = Config.ZONES[k]
		local outcome, t = simulate(k, zone.req / 100)
		H.eq(outcome, "caught", `{zone.id} at req/100`)
		H.ok(t < Config.CHASE_TIMEOUT, "caught before the timeout")
	end
end)

H.test("guard: a player at the previous zone's recommended speed gets caught (zones 2-7)", function()
	for k = 2, #Config.ZONES do
		local outcome = simulate(k, Config.ZONES[k - 1].req)
		H.eq(outcome, "caught", Config.ZONES[k].id)
	end
end)

H.test("guard: Meadow (req 0) lets anyone escape", function()
	H.eq(simulate(1, 0), "escaped")
end)

H.test("guard: standing still with the seed gets you caught, in every zone", function()
	-- Regression: a Spirit Garden guard moves 17 studs per tick, more than the 12-stud catch circle, and
	-- used to step back and forth over a standing thief forever. The catch now checks the path walked.
	for k, zone in Config.ZONES do
		H.eq(simulate(k, 0, { standStill = true }), "caught", zone.id)
	end
end)

H.test("guard: a guard that steps over a thief between ticks still catches them", function()
	local brain = awakeBrain(7, Vector3.new(100, 0, 0))
	GuardBrain.alert(brain, 0)
	local thief = { { id = "p", pos = Vector3.new(50, 0, 0), safe = false } }
	GuardBrain.step(brain, 0, Vector3.new(58, 0, 0), thief) -- 8 studs short
	H.eq(brain.state, "Chasing")
	local cmd = GuardBrain.step(brain, 0.1, Vector3.new(41, 0, 0), thief) -- 9 studs past
	H.eq(cmd.caughtId, "p")
end)

H.test("guard: catch uses distance < CATCH_DISTANCE, then walks home and sleeps", function()
	local home = Vector3.new(100, 0, 0)
	local brain = awakeBrain(3, home)
	GuardBrain.alert(brain, 0)
	local guardPos = Vector3.new(60, 0, 0) -- mid-chase, away from home
	local near = guardPos - Vector3.new(Config.CATCH_DISTANCE - 0.5, 0, 0)
	local cmd = GuardBrain.step(brain, 0, guardPos, { { id = "p", pos = near, safe = false } })
	H.eq(cmd.caughtId, "p")
	H.eq(brain.state, "Returning")
	cmd = GuardBrain.step(brain, 1, Vector3.new(50, 0, 0), {})
	H.ok(cmd.moveTo == home, "heads home")
	H.eq(cmd.walkSpeed, brain.returnSpeed)
	GuardBrain.step(brain, 2, Vector3.new(101, 0, 0), {})
	H.eq(brain.state, "Sleeping")
end)

H.test("guard: chase times out and the guard goes back to sleep", function()
	local brain = awakeBrain(2, Vector3.new(0, 0, 0))
	GuardBrain.alert(brain, 0)
	local far = { { id = "p", pos = Vector3.new(-500, 0, 0), safe = false } }
	GuardBrain.step(brain, 0, Vector3.new(0, 0, 0), far)
	H.eq(brain.state, "Chasing")
	GuardBrain.step(brain, Config.CHASE_TIMEOUT + 1, Vector3.new(-10, 0, 0), far)
	H.eq(brain.state, "Returning")
end)

H.test("guard: the slowest chase still fits in CHASE_TIMEOUT (a recommended-Speed run home from any nest)", function()
	for k, zone in Config.ZONES do
		local runHome = (Config.nestX(k) - Config.CORRIDOR_START_X) / Config.walkSpeedFor(zone.req)
		H.ok(runHome + zone.wakeDelay < Config.CHASE_TIMEOUT, `{zone.id}: {runHome}s`)
	end
end)

H.test("guard: reaching base (safe) ends the chase", function()
	local brain = awakeBrain(2, Vector3.new(0, 0, 0))
	GuardBrain.alert(brain, 0)
	GuardBrain.step(brain, 0, Vector3.new(0, 0, 0), { { id = "p", pos = Vector3.new(-50, 0, 0), safe = false } })
	GuardBrain.step(brain, 1, Vector3.new(-10, 0, 0), { { id = "p", pos = Vector3.new(-50, 0, 0), safe = true } })
	H.eq(brain.state, "Returning")
end)

H.test("guard: Sleep Dust delays waking by SLEEP_DUST_EXTRA more seconds", function()
	local brain = GuardBrain.new(2, Vector3.new(0, 0, 0))
	H.ok(GuardBrain.dust(brain, 0))
	GuardBrain.alert(brain, 10)
	local wake = 10 + brain.wakeDelay + Config.SLEEP_DUST_EXTRA
	local target = { { id = "p", pos = Vector3.new(-40, 0, 0), safe = false } }
	GuardBrain.step(brain, wake - 0.1, Vector3.new(0, 0, 0), target)
	H.eq(brain.state, "Waking")
	GuardBrain.step(brain, wake, Vector3.new(0, 0, 0), target)
	H.eq(brain.state, "Chasing")
	-- dust is used up by that steal
	GuardBrain.step(brain, wake + 1, Vector3.new(0, 0, 0), {})
	H.eq(brain.dustedUntil, 0)
end)

H.test("guard: bat stun freezes the guard for BAT_STUN seconds, then it resumes the chase", function()
	local brain = awakeBrain(2, Vector3.new(0, 0, 0))
	H.eq(GuardBrain.stun(brain, 0, Config.BAT_STUN), false, "can't stun a sleeping guard")
	GuardBrain.alert(brain, 0)
	local target = { { id = "p", pos = Vector3.new(-40, 0, 0), safe = false } }
	GuardBrain.step(brain, 0, Vector3.new(0, 0, 0), target)
	H.ok(GuardBrain.stun(brain, 1, Config.BAT_STUN))
	local cmd = GuardBrain.step(brain, 1 + Config.BAT_STUN - 0.1, Vector3.new(0, 0, 0), target)
	H.eq(cmd.walkSpeed, 0)
	H.eq(cmd.moveTo, nil)
	cmd = GuardBrain.step(brain, 1 + Config.BAT_STUN, Vector3.new(0, 0, 0), target)
	H.eq(brain.state, "Chasing")
	H.ok(cmd.moveTo ~= nil)
end)

H.test("guard: with the seed dusted, even a slow thief gets 5s more head start", function()
	local _, tPlain = simulate(3, 0)
	local _, tDusted = simulate(3, 0, { dust = true })
	H.ok(tDusted > tPlain + Config.SLEEP_DUST_EXTRA - 0.5, `dusted {tDusted} vs plain {tPlain}`)
end)

return nil
