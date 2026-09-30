--!strict
-- Pure speed-from-moving math: per-tick gain, cap, treadmill, and the movement sanity check.
-- SpeedService feeds it server-side HumanoidRootPart positions; nothing here trusts the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SpeedLogic = {}

export type State = {
	lastPos: Vector3?,
	lastGood: Vector3?,
	bucket: number, -- movement budget (studs) for the rubber-band check
}

export type Verdict = "ok" | "reset" | "ignored" | "rubberband"

export type Opts = {
	walkSpeed: number, -- the server's WalkSpeed for this player (highest of this and last tick)
	onTreadmill: boolean,
	mult: number, -- speed-gain multipliers (shop tier * potion)
	treadmillMult: number, -- 2 / 3 / 5
}

function SpeedLogic.newState(): State
	return { lastPos = nil, lastGood = nil, bucket = 0 }
end

-- Server moved the character (spawn, knockback, rubber-band): restart tracking from here.
function SpeedLogic.teleported(state: State, pos: Vector3)
	state.lastPos = pos
	state.lastGood = pos
	state.bucket = 0
end

local function horizontal(v: Vector3): number
	return math.sqrt(v.X * v.X + v.Z * v.Z)
end

-- Gain for walking `dist` studs, capped per tick.
function SpeedLogic.walkGain(dist: number, mult: number): number
	return math.min(dist, Config.GAIN_CAP_STUDS_PER_TICK) * Config.GAIN_PER_STUD * mult
end

-- Treadmill = the full walking rate for this tick (as if you walked WalkSpeed*dt), times its tier.
-- Standing still (AFK) on it counts; the cap still applies to the walking part.
function SpeedLogic.treadmillGain(walkSpeed: number, dt: number, mult: number, treadmillMult: number): number
	return SpeedLogic.walkGain(walkSpeed * dt, mult) * treadmillMult
end

function SpeedLogic.allowedPerTick(walkSpeed: number, dt: number): number
	return walkSpeed * dt * Config.MOVE_SLACK + Config.MOVE_EPSILON
end

-- One tick. Returns the Speed to grant, a verdict, and (for "rubberband") where to put the player back.
function SpeedLogic.step(state: State, pos: Vector3, dt: number, opts: Opts): (number, Verdict, Vector3?)
	local last = state.lastPos
	if last == nil then
		SpeedLogic.teleported(state, pos)
		return 0, "reset", nil
	end

	local dist = horizontal(pos - last)
	state.lastPos = pos

	local allowed = SpeedLogic.allowedPerTick(opts.walkSpeed, dt)
	-- Leaky budget: a single laggy tick is fine, but going too fast for over a second is not.
	local bucketMax = opts.walkSpeed * Config.MOVE_BUCKET_SECONDS * Config.MOVE_SLACK + Config.MOVE_EPSILON
	state.bucket = math.min(bucketMax, state.bucket + allowed) - dist
	if state.bucket < 0 then
		local back = state.lastGood or last
		SpeedLogic.teleported(state, back)
		return 0, "rubberband", back
	end

	if dist > allowed then
		return 0, "ignored", nil
	end
	state.lastGood = pos

	if opts.onTreadmill then
		return SpeedLogic.treadmillGain(opts.walkSpeed, dt, opts.mult, opts.treadmillMult), "ok", nil
	end
	return SpeedLogic.walkGain(dist, opts.mult), "ok", nil
end

return SpeedLogic
