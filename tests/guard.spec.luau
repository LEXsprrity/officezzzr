-- Soft gates: the guard chases at walkSpeedFor(zone.req) * 0.9 and catches within CATCH_DISTANCE.
local H = require("./harness")
local Vector3 = H.Vector3

local Config = H.shared("Config")
local GuardBrain = H.server("GuardBrain")

local DT = 1 / Config.GUARD_HZ

-- Simulates one steal: the thief grabs a pod and runs straight back toward base at the WalkSpeed
-- of `speedStat`; the guard's MoveTo is integrated at its WalkSpeed. Returns outcome and time.
local function simulate(k: number, speedStat: number, opts: { headStart: number?, standStill: boolean?, dust: boolean? }?)
	opts = opts or {}
	local nestX = Config.nestX(k)
	local home = Vector3.new(nestX + Config.GUARD_HOME_OFFSET, 0, 0)
	local brain = GuardBrain.new(k, home)
	local guardPos = home
	-- The pod closest to the guard (worst case), optionally with the thief standing further toward it.
	local a = math.pi / 2 + 0.5 * math.pi / Config.PODS_PER_NEST
	local pod = Vector3.new(nestX + math.cos(a) * 8, 0, math.sin(a) * 8)
	local playerPos = pod + Vector3.new(opts.headStart or 0, 0, 0)
	local walk = Config.walkSpeedFor(speedStat)

	local t = 1000
	if opts.dust then
		assert(GuardBrain.dust(brain, t - 1), "dust should work on a sleeping guard")
	end
	GuardBrain.alert(brain, t)
	local chased = false
	while t < 1000 + 180 do
		if not opts.standStill and playerPos.X >= Config.CORRIDOR_START_X then
			playerPos -= Vector3.new(walk * DT, 0, 0)
		end
		local safe = playerPos.X < Config.CORRIDOR_START_X
		local cmd = GuardBrain.step(brain, t, guardPos, { { id = "thief", pos = playerPos, safe = safe } })
		if cmd.caughtId then
			return "caught", t - 1000, brain
		end
		if brain.state == "Chasing" then
			chased = true
		end
		if chased and (brain.state == "Returning" or brain.state == "Sleeping") then
			return "escaped", t - 1000, brain
		end
		if cmd.moveTo then
			local delta = cmd.moveTo - guardPos
			delta = Vector3.new(delta.X, 0, delta.Z)
			local step = cmd.walkSpeed * DT
			guardPos = if delta.Magnitude <= step then Vector3.new(cmd.moveTo.X, 0, cmd.moveTo.Z) else guardPos + delta.Unit * step
		end
		t += DT
	end
	return "timeout", t - 1000, brain
end

H.test("guard: chase speed is walkSpeedFor(req) * 0.9 for every zone", function()
	for k, zone in Config.ZONES do
		local brain = GuardBrain.new(k, Vector3.new(0, 0, 0))
		H.near(brain.chaseSpeed, Config.walkSpeedFor(zone.req) * 0.9, 1e-9, zone.id)
	end
end)

H.test("guard: wakes the moment a seed is taken (first tick after alert is a chase)", function()
	local brain = GuardBrain.new(2, Vector3.new(0, 0, 0))
	GuardBrain.alert(brain, 10)
	local cmd = GuardBrain.step(brain, 10, Vector3.new(0, 0, 0), { { id = 1, pos = Vector3.new(-40, 0, 0), safe = false } })
	H.eq(brain.state, "Chasing")
	H.ok(cmd.woke, "woke flag")
	H.ok(cmd.moveTo ~= nil, "moving toward the thief")
	H.ok(cmd.moveTo.X < -40, "chases along the corridor axis, aiming past the thief")
end)

H.test("guard: a faster guard catches a fast runner despite 10 Hz MoveTo sampling", function()
	-- Regression: aiming at the sampled position left the guard one tick (> CATCH_DISTANCE) behind.
	for k = 2, #Config.ZONES do
		local zone = Config.ZONES[k]
		local walk = Config.guardChaseSpeed(k) * 0.97 -- just slower than the guard
		local stat = 10 ^ ((walk - Config.BASE_WALKSPEED) / Config.WALKSPEED_LOG_SCALE) - 1
		H.ok(walk / Config.GUARD_HZ > Config.CATCH_DISTANCE or k < 3, "runner outpaces one catch radius per tick")
		H.eq(simulate(k, stat), "caught", zone.id)
	end
end)

H.test("guard: a player AT the recommended speed escapes, in every zone", function()
	for k, zone in Config.ZONES do
		local outcome = simulate(k, zone.req)
		H.eq(outcome, "escaped", `{zone.id} at req {zone.req}`)
	end
end)

H.test("guard: at the recommended speed you escape even standing 12 studs toward the guard", function()
	for k, zone in Config.ZONES do
		local outcome = simulate(k, zone.req, { headStart = Config.PICKUP_DISTANCE })
		H.eq(outcome, "escaped", zone.id)
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

H.test("guard: a player at the previous zone's recommended speed gets caught (zones 2-5)", function()
	-- Zones 6-7 are the exception: 0.9 x a log-scale WalkSpeed is about one zone of Speed at the
	-- top end, so the previous zone's Speed is (almost) enough. See "Soft gates" in the README.
	for k = 2, 5 do
		local outcome = simulate(k, Config.ZONES[k - 1].req)
		H.eq(outcome, "caught", Config.ZONES[k].id)
	end
	local lines = {}
	for k = 2, #Config.ZONES do
		-- WalkSpeed(stat) = guard speed  =>  stat = 10^((w - 16) / a) - 1
		local w = Config.guardChaseSpeed(k)
		local stat = 10 ^ ((w - Config.BASE_WALKSPEED) / Config.WALKSPEED_LOG_SCALE) - 1
		table.insert(lines, string.format("%s: rec %.3g, guard outrun from %.3g (%.0f%% of rec)",
			Config.ZONES[k].id, Config.ZONES[k].req, stat, 100 * stat / Config.ZONES[k].req))
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
	local brain = GuardBrain.new(3, home)
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
	local brain = GuardBrain.new(2, Vector3.new(0, 0, 0))
	GuardBrain.alert(brain, 0)
	local far = { { id = "p", pos = Vector3.new(-500, 0, 0), safe = false } }
	GuardBrain.step(brain, 0, Vector3.new(0, 0, 0), far)
	H.eq(brain.state, "Chasing")
	GuardBrain.step(brain, Config.CHASE_TIMEOUT + 1, Vector3.new(-10, 0, 0), far)
	H.eq(brain.state, "Returning")
end)

H.test("guard: reaching base (safe) ends the chase", function()
	local brain = GuardBrain.new(2, Vector3.new(0, 0, 0))
	GuardBrain.alert(brain, 0)
	GuardBrain.step(brain, 0, Vector3.new(0, 0, 0), { { id = "p", pos = Vector3.new(-50, 0, 0), safe = false } })
	GuardBrain.step(brain, 1, Vector3.new(-10, 0, 0), { { id = "p", pos = Vector3.new(-50, 0, 0), safe = true } })
	H.eq(brain.state, "Returning")
end)

H.test("guard: Sleep Dust delays waking by SLEEP_DUST_EXTRA seconds", function()
	local brain = GuardBrain.new(2, Vector3.new(0, 0, 0))
	H.ok(GuardBrain.dust(brain, 0))
	GuardBrain.alert(brain, 10)
	local target = { { id = "p", pos = Vector3.new(-40, 0, 0), safe = false } }
	GuardBrain.step(brain, 10 + Config.SLEEP_DUST_EXTRA - 0.1, Vector3.new(0, 0, 0), target)
	H.eq(brain.state, "Waking")
	GuardBrain.step(brain, 10 + Config.SLEEP_DUST_EXTRA, Vector3.new(0, 0, 0), target)
	H.eq(brain.state, "Chasing")
	-- dust is used up by that steal
	GuardBrain.step(brain, 11 + Config.SLEEP_DUST_EXTRA, Vector3.new(0, 0, 0), {})
	H.eq(brain.dustedUntil, 0)
end)

H.test("guard: bat stun freezes the guard for BAT_STUN seconds, then it resumes the chase", function()
	local brain = GuardBrain.new(2, Vector3.new(0, 0, 0))
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
