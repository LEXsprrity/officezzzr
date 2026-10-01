-- Soft gates: the guard waits GUARD_WAKE_DELAY, then chases at walkSpeedFor(zone.req) * GUARD_SPEED_FACTOR (1)
-- and catches within CATCH_DISTANCE.
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

-- WalkSpeed(stat) = w  =>  stat = 10^((w - 16) / a) - 1
local function statFor(walk: number): number
	return 10 ^ ((walk - Config.BASE_WALKSPEED) / Config.WALKSPEED_LOG_SCALE) - 1
end

type SimOpts = {
	headStart: number?, -- thief stands this many studs further toward the guard
	standStill: boolean?,
	dust: boolean?,
	walk: number?, -- raw WalkSpeed instead of walkSpeedFor(speedStat)
	reaction: number?, -- seconds the thief stands still after the steal before running
	wakeDelay: number?, -- override the guard's wake-up delay
}

-- Simulates one steal: the thief grabs a pod and runs straight back toward base at the WalkSpeed
-- of `speedStat`; the guard's MoveTo is integrated at its WalkSpeed. Returns outcome, time and the
-- thief's final X.
local function simulate(k: number, speedStat: number, opts: SimOpts?): (string, number, number)
	local o: SimOpts = opts or {}
	local nestX = Config.nestX(k)
	local home = Vector3.new(nestX + Config.GUARD_HOME_OFFSET, 0, 0)
	local brain = GuardBrain.new(k, home)
	if o.wakeDelay then
		brain.wakeDelay = o.wakeDelay
	end
	local guardPos = home
	-- The pod closest to the guard (worst case), optionally with the thief standing further toward it.
	local a = math.pi / 2 + 0.5 * math.pi / Config.PODS_PER_NEST
	local pod = Vector3.new(nestX + math.cos(a) * 8, 0, math.sin(a) * 8)
	local playerPos = pod + Vector3.new(o.headStart or 0, 0, 0)
	local walk = o.walk or Config.walkSpeedFor(speedStat)

	local t = 1000
	if o.dust then
		assert(GuardBrain.dust(brain, t - 1), "dust should work on a sleeping guard")
	end
	GuardBrain.alert(brain, t)
	local chased = false
	while t < 1000 + 180 do
		local running = not o.standStill and t - 1000 >= (o.reaction or 0)
		if running and playerPos.X >= Config.CORRIDOR_START_X then
			playerPos -= Vector3.new(walk * DT, 0, 0)
		end
		local safe = playerPos.X < Config.CORRIDOR_START_X
		local cmd = GuardBrain.step(brain, t, guardPos, { { id = "thief", pos = playerPos, safe = safe } })
		if cmd.caughtId then
			return "caught", t - 1000, playerPos.X
		end
		if brain.state == "Chasing" then
			chased = true
		end
		if chased and (brain.state == "Returning" or brain.state == "Sleeping") then
			return "escaped", t - 1000, playerPos.X
		end
		if cmd.moveTo then
			local delta = cmd.moveTo - guardPos
			delta = Vector3.new(delta.X, 0, delta.Z)
			local step = cmd.walkSpeed * DT
			guardPos = if delta.Magnitude <= step then Vector3.new(cmd.moveTo.X, 0, cmd.moveTo.Z) else guardPos + delta.Unit * step
		end
		t += DT
	end
	return "timeout", t - 1000, playerPos.X
end

-- Lowest WalkSpeed (as a fraction of the zone's recommended WalkSpeed) that still escapes.
local function escapeFraction(k: number): number
	local rec = Config.walkSpeedFor(Config.ZONES[k].req)
	local lo, hi = 0.3, 1.0
	for _ = 1, 30 do
		local mid = (lo + hi) / 2
		if simulate(k, 0, { walk = rec * mid }) == "escaped" then
			hi = mid
		else
			lo = mid
		end
	end
	return hi
end

H.test("guard: chase speed is walkSpeedFor(req) * 1.0 for every zone", function()
	H.eq(Config.GUARD_SPEED_FACTOR, 1)
	for k, zone in Config.ZONES do
		local brain = GuardBrain.new(k, Vector3.new(0, 0, 0))
		H.near(brain.chaseSpeed, Config.walkSpeedFor(zone.req), 1e-9, zone.id)
	end
end)

H.test("guard: wakes GUARD_WAKE_DELAY after a seed is taken, standing still until then", function()
	H.ok(Config.GUARD_WAKE_DELAY > 0, "there is a head start")
	local brain = GuardBrain.new(2, Vector3.new(0, 0, 0))
	GuardBrain.alert(brain, 10)
	local target = { { id = 1, pos = Vector3.new(-40, 0, 0), safe = false } }
	local cmd = GuardBrain.step(brain, 10 + Config.GUARD_WAKE_DELAY - 0.05, Vector3.new(0, 0, 0), target)
	H.eq(brain.state, "Waking")
	H.eq(cmd.walkSpeed, 0)
	H.eq(cmd.moveTo, nil)
	cmd = GuardBrain.step(brain, 10 + Config.GUARD_WAKE_DELAY, Vector3.new(0, 0, 0), target)
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

H.test("guard: a player AT the recommended speed reaches the base before being caught, in every zone", function()
	for k, zone in Config.ZONES do
		local outcome, _, x = simulate(k, zone.req)
		H.eq(outcome, "escaped", `{zone.id} at req {zone.req}`)
		H.ok(x < Config.CORRIDOR_START_X, `{zone.id}: reached the base (x = {x})`)
	end
end)

H.test("guard: at the recommended speed you escape standing 12 studs toward the guard and reacting 0.5 s late", function()
	for k, zone in Config.ZONES do
		local outcome, _, x = simulate(k, zone.req, { headStart = Config.PICKUP_DISTANCE, reaction = 0.5 })
		H.eq(outcome, "escaped", zone.id)
		H.ok(x < Config.CORRIDOR_START_X, `{zone.id}: reached the base`)
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
	local lines = {}
	for k = 2, #Config.ZONES do
		local zone = Config.ZONES[k]
		local f = escapeFraction(k)
		local stat = statFor(Config.walkSpeedFor(zone.req) * f)
		table.insert(lines, string.format("%s: rec %.3g, escape from WalkSpeed %.0f%% of rec = Speed %.3g (%.0f%% of rec)",
			zone.id, zone.req, 100 * f, stat, 100 * stat / zone.req))
	end
	print("        escape thresholds  " .. table.concat(lines, "\n                           "))
end)

H.test("guard: Meadow (req 0) lets anyone escape", function()
	H.eq(simulate(1, 0), "escaped")
end)

H.test("guard: standing still with the seed gets you caught, however slow", function()
	H.eq(simulate(1, 0, { standStill = true }), "caught")
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
		H.ok(runHome + Config.GUARD_WAKE_DELAY < Config.CHASE_TIMEOUT, `{zone.id}: {runHome}s`)
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
	local wake = 10 + Config.GUARD_WAKE_DELAY + Config.SLEEP_DUST_EXTRA
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
