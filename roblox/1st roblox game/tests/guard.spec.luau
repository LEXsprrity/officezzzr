-- Soft gates: the guard wakes after Config.wakeDelay (WAKE_REACTION for the thief to notice, then a GUARD_HEAD_START-stud
-- head start at the recommended Speed plus its zone's wakeDelay slack), then chases at walkSpeedFor(zone.req) * GUARD_SPEED_FACTOR (1)
-- and catches within CATCH_DISTANCE of the path it walked since its last tick.
local H = require("./harness")
local Vector3 = H.Vector3

local Config = H.shared("Config")
local GuardBrain = H.server("GuardBrain")
local Flow = require("./steal_flow")

local DT = 1 / Config.GUARD_HZ

-- A brain that chases on the first tick after alert (for unit tests of the chase itself).
local function awakeBrain(k: number, home: any): any
	local brain = GuardBrain.new(k, home)
	brain.wakeDelay = 0
	return brain
end

type SimOpts = {
	standStill: boolean?,
	walk: number?, -- raw WalkSpeed instead of walkSpeedFor(speedStat)
	wakeDelay: number?, -- override the guard's wake-up delay
	reaction: number?, -- seconds the thief stands still after the steal before running
}

-- Simulates one steal: the thief grabs a pod and runs straight back toward base at the WalkSpeed
-- of `speedStat`; the guard's MoveTo is integrated at its WalkSpeed. Returns outcome, time and the
-- thief's final X and the closest the awake guard got while the thief was in the corridor.
local function simulate(k: number, speedStat: number, opts: SimOpts?): (string, number, number, number)
	local o: SimOpts = opts or {}
	local center = Config.nestCenter(k) -- on the left side of the corridor
	local home = center + Vector3.new(Config.GUARD_HOME_OFFSET, 0, 0)
	local brain = GuardBrain.new(k, home)
	if o.wakeDelay then
		brain.wakeDelay = o.wakeDelay
	end
	local guardPos = home
	-- The pod closest to the guard (worst case).
	local pod
	for i = 1, Config.PODS_PER_NEST do
		local p = center + Config.podOffset(k, i)
		if not pod or (p - home).Magnitude < (pod - home).Magnitude then
			pod = p
		end
	end
	pod = Vector3.new(pod.X, 0, pod.Z)
	local playerPos = pod
	local walk = o.walk or Config.walkSpeedFor(speedStat)

	local t = 1000
	GuardBrain.alert(brain, t)
	local chased = false
	local closest = math.huge
	while t < 1000 + 180 do
		local running = not o.standStill and t - 1000 >= (o.reaction or 0) - 1e-9
		if running and playerPos.X >= Config.CORRIDOR_START_X then
			playerPos -= Vector3.new(walk * DT, 0, 0)
		end
		local safe = playerPos.X < Config.CORRIDOR_START_X
		if not safe and brain.state ~= "Waking" then -- (the pods lie right by the sleeping guard)
			local gap = playerPos - guardPos
			closest = math.min(closest, Vector3.new(gap.X, 0, gap.Z).Magnitude)
		end
		local cmd = GuardBrain.step(brain, t, guardPos, { { id = "thief", pos = playerPos, safe = safe, speed = if o.walk then nil else speedStat } })
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

H.test("guard: every guard wakes after the thief's reaction time, then a 28-stud head start at the recommended Speed", function()
	H.eq(Config.GUARD_HEAD_START, 28)
	H.eq(Config.WAKE_REACTION, 0.5)
	for k, zone in Config.ZONES do
		H.eq(zone.wakeDelay, 0, zone.id)
		local delay = Config.wakeDelay(k)
		H.near((delay - Config.WAKE_REACTION) * Config.walkSpeedFor(zone.req), Config.GUARD_HEAD_START, 1e-6, `{zone.id}: the head start in studs`)
		H.ok(delay >= 0.65, `{zone.id}: wakes after {delay}s, not before a human can react (it was 0.26 s in the Spirit Garden)`)
		H.eq(GuardBrain.new(k, Vector3.new(0, 0, 0)).wakeDelay, delay, zone.id)
	end
end)

H.test("guard: the Desert guard (no slack) wakes as soon as its head start has run out", function()
	local brain = GuardBrain.new(2, Vector3.new(0, 0, 0))
	GuardBrain.alert(brain, 10)
	local target = { { id = 1, pos = Vector3.new(-40, 0, 0), safe = false } }
	local cmd = GuardBrain.step(brain, 10 + Config.wakeDelay(2) - 0.01, Vector3.new(0, 0, 0), target)
	H.eq(brain.state, "Waking", "still waking up")
	cmd = GuardBrain.step(brain, 10 + Config.wakeDelay(2), Vector3.new(0, 0, 0), target)
	H.eq(brain.state, "Chasing", "chasing the moment the head start is gone")
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
	-- (0.8: at 0.9 the Desert's 264-stud run home is too short for the guard to close a 30-stud head start)
	for k = 2, #Config.ZONES do
		local zone = Config.ZONES[k]
		local walk = Config.guardChaseSpeed(k) * 0.8
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

----------------------------------------------------------------------------------------------------
-- The steal as the live game runs it (tests/steal_flow): the thief stands anywhere in the prompt's reach of
-- a pod, starts running a human reaction after the steal, the server sees them 0.1 s late through the
-- movement tracker (SpeedService.seenPosition), and the guard loop ticks at 10 Hz at any phase.
----------------------------------------------------------------------------------------------------
H.test("guard flow: the Studio report: 100M in the Spirit Garden, running 0.3 s after the steal, gets away", function()
	-- Owner playtest: caught "as soon as I take the seed". The guard used to wake after 0.26 s, while the
	-- thief still stood by the pod, 10-16 studs from its root: a 17-stud tick or two and it had them, whatever
	-- their Speed. (Pinned here with the old wake-up.)
	local old = Config.GUARD_HEAD_START / Config.guardChaseSpeed(7) + 0.1
	local outcome, t = Flow.steal(7, { speed = 100e6, reaction = 0.3, wakeDelay = old })
	H.eq(outcome, "caught", "with the old 0.26 s wake-up")
	H.ok(t < old + 0.2, `within its first chase ticks ({t}s)`)
	H.eq((Flow.steal(7, { speed = 1e12, reaction = 0.3, wakeDelay = old })), "caught", "...at any Speed (the WalkSpeed cap): it was the wake-up")
	for _, speed in { 100e6, 75e6 } do
		local result, at, where = Flow.steal(7, { speed = speed, reaction = 0.3 })
		H.eq(result, "escaped", `{speed}: caught at {at}s ({where})`)
	end
end)

H.test("guard flow: at the recommended Speed or more you escape if you start running within 0.45 s, from any pod and stance, in every zone", function()
	for k = 2, #Config.ZONES do
		local zone = Config.ZONES[k]
		for _, share in { 1, 4 / 3 } do
			local result, at, where = Flow.steal(k, { speed = zone.req * share, reaction = 0.45 })
			H.eq(result, "escaped", `{zone.id} at {share}x the sign: caught at {at}s ({where})`)
		end
	end
end)

H.test("guard flow: below the recommended Speed you get caught, even reacting at once (zones 2-7)", function()
	-- A quick thief (0.2 s) escapes from ~84-96% of the sign (Config.guardSpeedVs; WalkSpeed is
	-- logarithmic in Speed (README "Soft gates").
	for k = 2, #Config.ZONES do
		local zone = Config.ZONES[k]
		H.eq((Flow.steal(k, { speed = Config.ZONES[k - 1].req, reaction = 0 })), "caught", `{zone.id} at the previous zone's sign`)
		local share = if zone.id == "Desert" then 0.4 else 0.5
		H.eq((Flow.steal(k, { speed = zone.req * share, reaction = 0.2 })), "caught", `{zone.id} at {share * 100}% of the sign`)
		-- (owner 2026-10-19: 65M farmed the 75M Spirit Garden) 90% of the sign doesn't make it either (the Desert 80%)
		local close = if zone.id == "Desert" then 0.8 else 0.9
		H.eq((Flow.steal(k, { speed = zone.req * close, reaction = 0.2 })), "caught", `{zone.id} at {close * 100}% of the sign`)
		H.eq((Flow.steal(k, { speed = zone.req, standStill = true })), "caught", `{zone.id}: standing by the pod`)
	end
end)

H.test("guard: at the recommended Speed there is >= 0.3 s of slack to start running, in every zone", function()
	-- More slack is a bigger head start, which also lets slower thieves escape; 0.3 s keeps the gates above.
	for k = 2, #Config.ZONES do
		local zone = Config.ZONES[k]
		local need = 0.3
		H.eq(simulate(k, zone.req, { reaction = need }), "escaped", `{zone.id} reacting {need}s late`)
		H.ok(slackOf(k) >= need - 1e-6, zone.id)
	end
end)

H.test("guard: at ~70% of the recommended WalkSpeed you get caught (zones 2-7)", function()
	-- (the Meadow's guard is the tutorial: its 64-stud run home is too short to catch anyone running)
	for k = 2, #Config.ZONES do
		local zone = Config.ZONES[k]
		local walk = Config.walkSpeedFor(zone.req) * 0.7
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

H.test("guard: the chase covers the whole 192-stud corridor (a thief hugging a wall is followed there, never past it)", function()
	H.eq(Config.CORRIDOR_WIDTH, 192)
	local halfW = Config.CORRIDOR_WIDTH / 2
	for _, s in { -1, 1 } do
		local k = 4
		local home = Config.nestCenter(k) + Vector3.new(Config.GUARD_HOME_OFFSET, 0, 0)
		local brain = awakeBrain(k, home)
		GuardBrain.alert(brain, 0)
		local guardPos = home
		local thief = Vector3.new(Config.nestX(k) - 30, 0, s * (halfW - 3)) -- against the wall, standing still
		local caught, widest, t = false, 0, 0
		while t < 20 and not caught do
			local cmd = GuardBrain.step(brain, t, guardPos, { { id = "p", pos = thief, safe = false } })
			caught = cmd.caughtId == "p"
			if cmd.moveTo then
				H.ok(math.abs(cmd.moveTo.Z) <= halfW - 4, `the guard aims inside the walls ({cmd.moveTo.Z})`)
				widest = math.max(widest, math.abs(cmd.moveTo.Z))
				local d = cmd.moveTo - guardPos
				local step = math.min(d.Magnitude, cmd.walkSpeed * DT)
				guardPos += if d.Magnitude > 1e-3 then d.Unit * step else Vector3.zero
			end
			t += DT
		end
		H.ok(caught, "the thief by the wall is caught")
		H.ok(widest > 64, `the chase reaches past the old 64-stud corridor ({widest})`)
	end
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
		H.ok(runHome + Config.wakeDelay(k) < Config.CHASE_TIMEOUT, `{zone.id}: {runHome}s`)
	end
end)

H.test("guard: reaching base (safe) ends the chase", function()
	local brain = awakeBrain(2, Vector3.new(0, 0, 0))
	GuardBrain.alert(brain, 0)
	GuardBrain.step(brain, 0, Vector3.new(0, 0, 0), { { id = "p", pos = Vector3.new(-50, 0, 0), safe = false } })
	GuardBrain.step(brain, 1, Vector3.new(-10, 0, 0), { { id = "p", pos = Vector3.new(-50, 0, 0), safe = true } })
	H.eq(brain.state, "Returning")
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

H.test("guard flow: below the sign the guard runs faster after you (owner: 5M outran the 7.5M Snow Peaks)", function()
	local snow = 5
	H.eq(Config.ZONES[snow].id, "Snow")
	H.eq((Flow.steal(snow, { speed = 5e6, reaction = 0 })), "caught", "5M in the Snow Peaks, even running at once")
	H.eq((Flow.steal(snow, { speed = 7.5e6, reaction = 0.3 })), "escaped", "7.5M (the sign) still gets away")
	H.eq(Config.guardSpeedVs(snow, 7.5e6), Config.guardChaseSpeed(snow), "at the sign: the plain chase speed")
	H.eq(Config.guardSpeedVs(snow, 1e9), Config.guardChaseSpeed(snow), "above it: no change")
	H.ok(Config.guardSpeedVs(snow, 5e6) > Config.guardChaseSpeed(snow) * 1.1, "2/3 of the sign: >10% faster")
	H.ok(Config.guardSpeedVs(snow, 0) <= Config.guardChaseSpeed(snow) * Config.GUARD_UNDERSPEED_MAX + 1e-9, "capped")
	H.eq(Config.guardSpeedVs(1, 0), Config.guardChaseSpeed(1), "the Meadow (no sign) never speeds up")
	H.eq(Config.GUARD_RETURN_FACTOR, 1.2, "owner: home 2x faster than the old 0.6")
end)

return nil
