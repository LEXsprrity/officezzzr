-- One steal as the live game runs it, for tests/guard.spec: the thief walks up to a pod and stands within
-- the prompt's reach (PICKUP_DISTANCE, any side of it, even inside the sleeping boss: players pass through
-- guards), the steal lands on the server, and the thief starts running home `reaction` seconds later (the
-- Pickup event's trip to the client plus a human's reaction). The server sees the character `lag` seconds
-- late (the client moves it; its position replicates), the 0.25 s movement tracker (SpeedLogic, as in
-- SpeedService) decides what SpeedService.seenPosition returns, and the guard's loop runs GuardBrain.step
-- at GUARD_HZ (at any phase against the steal), with its Humanoid:MoveTo walked at WalkSpeed every
-- physics frame between ticks. The guard.spec `simulate` above it is the ideal case: no stance, lag or
-- reaction.
local H = require("./harness")
local Vector3 = H.Vector3

local Config = H.shared("Config")
local GuardBrain = H.server("GuardBrain")
local SpeedLogic = H.server("SpeedLogic")

local Flow = {}

local FRAME = 1 / 60 -- physics step
Flow.LAG = 0.1 -- s the server's view of a character trails the client (Studio playtest; a live server is worse)

export type Opts = {
	speed: number?, -- Speed stat (WalkSpeed = Config.walkSpeedFor)
	walk: number?, -- raw WalkSpeed instead
	reaction: number?, -- s from the server's steal to the thief starting to run (default 0.3)
	lag: number?, -- default Flow.LAG
	pod: number?, -- which pod (default: every pod, worst case)
	stance: Vector3?, -- where the thief stands, from the pod (default: every stance, worst case)
	phase: number?, -- s from the steal to the guard loop's next tick (default: several, worst case)
	wakeDelay: number?, -- override the guard's wake-up (Config.wakeDelay)
	standStill: boolean?,
}

-- Where a thief may stand to steal (from the pod, horizontal): on it, on the base side, toward the
-- corridor's middle, and 2 studs inside the prompt's reach toward the sleeping boss (the worst spot).
function Flow.stances(k: number, i: number): { Vector3 }
	local pod = Config.podOffset(k, i)
	local toGuard = Vector3.new(Config.GUARD_HOME_OFFSET - pod.X, 0, -pod.Z)
	local reach = Config.PICKUP_DISTANCE - 2
	local near = if toGuard.Magnitude > reach then toGuard.Unit * reach else toGuard
	return { Vector3.zero, Vector3.new(-6, 0, 0), Vector3.new(0, 0, 8), near }
end

local function run(k: number, walk: number, i: number, stance: Vector3, phase: number, reaction: number, lag: number, o: Opts): (string, number)
	local standStill = o.standStill == true
	local center = Config.nestCenter(k)
	local home = center + Vector3.new(Config.GUARD_HOME_OFFSET, 0, 0)
	local pod = center + Config.podOffset(k, i)
	local start = Vector3.new(pod.X, 0, pod.Z) + stance
	local brain = GuardBrain.new(k, home)
	if o.wakeDelay then
		brain.wakeDelay = o.wakeDelay
	end
	local guardPos = home
	local moveTo: any = nil
	local guardWalk = 0

	-- The thief's client position at time t (the steal lands on the server at t = 0).
	local function clientAt(t: number): Vector3
		if standStill or t <= reaction then
			return start
		end
		local x = start.X - walk * (t - reaction)
		return Vector3.new(math.max(x, Config.CORRIDOR_START_X - 20), 0, start.Z)
	end
	local function serverAt(t: number): Vector3
		return clientAt(t - lag)
	end

	-- The movement tracker, already settled on the thief standing at the pod.
	local tracker = SpeedLogic.newState()
	local speedTick = -0.25 + (phase * 7) % 0.25 -- (its own phase, tied to the guard's for repeatability)
	SpeedLogic.step(tracker, serverAt(speedTick - 0.25), 0.25, { walkSpeed = walk, onTreadmill = false, mult = 1, treadmillTier = 0, trailMult = 1 })
	SpeedLogic.step(tracker, serverAt(speedTick), 0.25, { walkSpeed = walk, onTreadmill = false, mult = 1, treadmillTier = 0, trailMult = 1 })
	tracker.at = speedTick
	local function seenPosition(t: number): Vector3
		local pos = serverAt(t)
		if SpeedLogic.plausible(tracker, pos, t - (tracker.at or 0), walk) then
			return pos
		end
		return tracker.lastGood or tracker.lastPos
	end

	GuardBrain.alert(brain, 0)
	local nextGuard = phase
	local chased = false
	local t = 0
	while t < Config.CHASE_TIMEOUT + 5 do
		t += FRAME
		-- the guard's Humanoid walks toward its MoveTo
		if moveTo then
			local d = Vector3.new(moveTo.X - guardPos.X, 0, moveTo.Z - guardPos.Z)
			local step = guardWalk * FRAME
			guardPos = if d.Magnitude <= step then Vector3.new(moveTo.X, 0, moveTo.Z) else guardPos + d.Unit * step
		end
		if t >= speedTick + 0.25 then
			speedTick += 0.25
			SpeedLogic.step(tracker, serverAt(speedTick), 0.25, { walkSpeed = walk, onTreadmill = false, mult = 1, treadmillTier = 0, trailMult = 1 })
			tracker.at = speedTick
		end
		if t >= nextGuard then
			nextGuard += 1 / Config.GUARD_HZ
			local pos = seenPosition(t)
			local safe = pos.X < Config.CORRIDOR_START_X
			local cmd = GuardBrain.step(brain, t, guardPos, { { id = "thief", pos = pos, safe = safe, speed = o.speed } })
			if cmd.caughtId then
				return "caught", t
			end
			if brain.state == "Chasing" then
				chased = true
			end
			if chased and (brain.state == "Returning" or brain.state == "Sleeping") then
				return "escaped", t
			end
			guardWalk = cmd.walkSpeed
			moveTo = cmd.moveTo or (if brain.state ~= "Sleeping" and brain.state ~= "Waking" then guardPos else nil)
		end
	end
	return "timeout", t
end

-- The outcome over every pod, stance and loop phase asked for: the first one that isn't an escape (its
-- outcome, time and which one it was), else "escaped".
function Flow.steal(k: number, opts: Opts?): (string, number, string?)
	local o: Opts = opts or {}
	local walk = o.walk or Config.walkSpeedFor(o.speed or Config.ZONES[k].req)
	local reaction = o.reaction or 0.3
	local lag = o.lag or Flow.LAG
	local pods = if o.pod then { o.pod } else { 1, 2, 3, 4 }
	for _, i in pods do
		local stances = if o.stance then { o.stance } else Flow.stances(k, i)
		for si, stance in stances do
			for _, phase in (if o.phase then { o.phase } else { 0.001, 0.034, 0.067, 0.099 }) do
				local result, t = run(k, walk, i, stance, phase, reaction, lag, o)
				if result ~= "escaped" then
					return result, t, `pod {i}, stance {si}, phase {phase}`
				end
			end
		end
	end
	return "escaped", 0, nil
end

-- The longest reaction (s) that still escapes from every pod and stance, by bisection.
function Flow.slack(k: number, opts: Opts?): number
	local lo, hi = 0, 3
	for _ = 1, 14 do
		local mid = (lo + hi) / 2
		local o = table.clone(opts or {}) :: any
		o.reaction = mid
		if Flow.steal(k, o) == "escaped" then
			lo = mid
		else
			hi = mid
		end
	end
	return lo
end

return Flow
