-- Speed from moving: per-tick gain, cap, treadmill multiplier, movement sanity check.
local H = require("./harness")
local Vector3 = H.Vector3

local Config = H.shared("Config")
local SpeedLogic = H.server("SpeedLogic")

local DT = Config.TICK

local function opts(walkSpeed: number, onTreadmill: boolean?, mult: number?, tier: number?)
	return { walkSpeed = walkSpeed, onTreadmill = onTreadmill == true, mult = mult or 1, treadmillMult = tier or 2 }
end

-- Warm a tracker up at `pos` (standing for a second refills the movement budget).
local function tracker(pos: Vector3, walkSpeed: number?)
	local s = SpeedLogic.newState()
	for _ = 1, 5 do
		SpeedLogic.step(s, pos, DT, opts(walkSpeed or 16))
	end
	return s
end

H.test("speed: WalkSpeed = clamp(16 + a*log10(1+Speed), 16, 180)", function()
	H.eq(Config.walkSpeedFor(0), 16)
	H.near(Config.walkSpeedFor(9), 16 + Config.WALKSPEED_LOG_SCALE, 1e-9)
	H.eq(Config.walkSpeedFor(1e30), Config.MAX_WALKSPEED)
	local last = 0
	for e = 0, 12 do
		local w = Config.walkSpeedFor(10 ^ e)
		H.ok(w >= last, "monotonic")
		last = w
	end
end)

H.test("speed: walking gain = horizontal distance x gainRate x multipliers", function()
	local s = tracker(Vector3.new(0, 0, 0))
	local walk = 80
	local d = walk * DT -- a normal step
	local gain, verdict = SpeedLogic.step(s, Vector3.new(d, 5, 0), DT, opts(walk, false, 3))
	H.eq(verdict, "ok")
	H.near(gain, d * Config.GAIN_PER_STUD * 3, 1e-9, "vertical movement doesn't count, mult applies")
end)

H.test("speed: treadmill gives exactly 2x the walking gain (starting tier)", function()
	for _, walk in { 16, 50, 107, 180 } do
		-- walking a full tick at WalkSpeed...
		local s1 = tracker(Vector3.new(0, 0, 0))
		local walkGain = SpeedLogic.step(s1, Vector3.new(walk * DT, 0, 0), DT, opts(walk))
		-- ...vs standing (AFK) on the treadmill for a tick
		local s2 = tracker(Vector3.new(0, 0, 0))
		local tmGain, verdict = SpeedLogic.step(s2, Vector3.new(0, 0, 0), DT, opts(walk, true, 1, Config.TREADMILL_TIERS[1].mult))
		H.eq(verdict, "ok")
		H.eq(Config.TREADMILL_TIERS[1].mult, 2)
		H.near(tmGain, 2 * walkGain, 1e-9, `WalkSpeed {walk}`)
	end
end)

H.test("speed: treadmill shop tiers are 3x and 5x", function()
	H.eq(Config.TREADMILL_TIERS[2].mult, 3)
	H.eq(Config.TREADMILL_TIERS[3].mult, 5)
	local s = tracker(Vector3.new(0, 0, 0))
	local gain = SpeedLogic.step(s, Vector3.new(0, 0, 0), DT, opts(100, true, 1, 5))
	H.near(gain, 5 * 100 * DT * Config.GAIN_PER_STUD, 1e-9)
end)

H.test("speed: gain is capped per tick (walking and treadmill)", function()
	local cap = Config.GAIN_CAP_STUDS_PER_TICK * Config.GAIN_PER_STUD
	H.eq(SpeedLogic.walkGain(1e6, 1), cap)
	H.eq(SpeedLogic.walkGain(1e6, 4), cap * 4)
	H.eq(SpeedLogic.treadmillGain(1e6, DT, 1, 2), cap * 2, "AFK treadmill is capped too")
	-- through step(): at max WalkSpeed with slack, one tick never pays more than the cap
	local walk = Config.MAX_WALKSPEED
	local s = tracker(Vector3.new(0, 0, 0))
	local within = SpeedLogic.allowedPerTick(walk, DT) - 0.01
	local gain, verdict = SpeedLogic.step(s, Vector3.new(within, 0, 0), DT, opts(walk))
	H.eq(verdict, "ok")
	H.ok(within > Config.GAIN_CAP_STUDS_PER_TICK, "test moves further than the cap")
	H.eq(gain, cap)
end)

H.test("speed: moving faster than WalkSpeed*dt*slack earns nothing", function()
	local walk = 50
	local s = tracker(Vector3.new(0, 0, 0), walk)
	local tooFar = SpeedLogic.allowedPerTick(walk, DT) + 1
	local gain, verdict = SpeedLogic.step(s, Vector3.new(tooFar, 0, 0), DT, opts(walk))
	H.eq(gain, 0)
	H.eq(verdict, "ignored")
end)

H.test("speed: a sustained speed hack is rubber-banded to the last good position", function()
	local walk = 80
	local s = SpeedLogic.newState()
	local x = 0
	-- walk normally for 2 s
	SpeedLogic.step(s, Vector3.new(x, 0, 0), DT, opts(walk))
	for _ = 1, 8 do
		x += walk * DT
		SpeedLogic.step(s, Vector3.new(x, 0, 0), DT, opts(walk))
	end
	local lastGood = x
	-- then move at 3x WalkSpeed
	local banded, back = false, nil
	for _ = 1, 20 do
		x += walk * 3 * DT
		local gain, verdict, pos = SpeedLogic.step(s, Vector3.new(x, 0, 0), DT, opts(walk))
		H.eq(gain, 0, "no gain while hacking")
		if verdict == "rubberband" then
			banded, back = true, pos
			break
		end
	end
	H.ok(banded, "was rubber-banded")
	H.eq(back.X, lastGood, "snapped back to the last valid position")
end)

H.test("speed: a teleport-sized jump is rubber-banded immediately", function()
	local s = tracker(Vector3.new(0, 0, 0))
	for i = 1, 8 do
		SpeedLogic.step(s, Vector3.new(i * 20 * DT, 0, 0), DT, opts(20))
	end
	local _, verdict = SpeedLogic.step(s, Vector3.new(5000, 0, 0), DT, opts(20))
	H.eq(verdict, "rubberband")
end)

H.test("speed: one laggy burst (1 s of movement in one tick) is tolerated, not rubber-banded", function()
	local walk = 60
	local s = tracker(Vector3.new(0, 0, 0))
	local x = 0
	for _ = 1, 8 do
		x += walk * DT
		SpeedLogic.step(s, Vector3.new(x, 0, 0), DT, opts(walk))
	end
	-- three ticks with no update, then the whole second arrives at once
	for _ = 1, 3 do
		SpeedLogic.step(s, Vector3.new(x, 0, 0), DT, opts(walk))
	end
	x += walk * 1.0
	local _, verdict = SpeedLogic.step(s, Vector3.new(x, 0, 0), DT, opts(walk))
	H.ok(verdict ~= "rubberband", "burst tolerated (" .. verdict .. ")")
end)

H.test("speed: server teleports reset tracking (no false positive after knockback)", function()
	local s = tracker(Vector3.new(0, 0, 0))
	SpeedLogic.teleported(s, Vector3.new(300, 0, 0))
	local _, verdict = SpeedLogic.step(s, Vector3.new(300 + 16 * DT, 0, 0), DT, opts(16))
	H.eq(verdict, "ok")
end)

return nil
