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
	at: number?, -- os.clock() of the tick (or server move) that saw lastPos; SpeedService keeps it (plausible)
}

export type Verdict = "ok" | "reset" | "ignored" | "rubberband"

export type Opts = {
	walkSpeed: number, -- the server's WalkSpeed for this player (highest of this and last tick)
	onTreadmill: boolean,
	mult: number, -- Speed per stud: Config.speedPerStud (the flat base x the equipped trail)
	treadmillTier: number, -- the owner's treadmill tier (profile.treadmillTier)
	trailMult: number, -- Config.trailMult of the equipped trail (the treadmill pays its tier's rate x this)
}

function SpeedLogic.newState(): State
	return { lastPos = nil, lastGood = nil, bucket = 0, at = nil }
end

-- A position a character can really have: no NaN or infinity (what a broken or hostile client might send)
-- and within a million studs of the origin.
function SpeedLogic.finite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
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

-- Gain for walking `dist` studs at `mult` Speed per stud, capped per tick.
function SpeedLogic.walkGain(dist: number, mult: number): number
	return math.min(dist, Config.GAIN_CAP_STUDS_PER_TICK) * mult
end

-- Treadmill: one step (server tick, Config.TICK) on it pays the tier's fixed Speed per step
-- (Config.treadmillRate) x `trailMult` (the equipped trail x the Speed passes), in full, every tick: the
-- exact "+X" its popups and sign show (owner 2026-10-15). Nothing else: not WalkSpeed, not the Speed you
-- have, not how long the tick took. Standing still (AFK) on it counts.
function SpeedLogic.treadmillGain(tier: number, trailMult: number): number
	return Config.treadmillRate(tier) * trailMult
end

function SpeedLogic.allowedPerTick(walkSpeed: number, dt: number): number
	return walkSpeed * dt * Config.MOVE_SLACK + Config.MOVE_EPSILON
end

-- Leaky budget: a single laggy tick is fine, but going too fast for over a second is not.
local function bucketMax(walkSpeed: number): number
	return walkSpeed * Config.MOVE_BUCKET_SECONDS * Config.MOVE_SLACK + Config.MOVE_EPSILON
end

-- One tick. Returns the Speed to grant, a verdict, and (for "rubberband") where to put the player back.
function SpeedLogic.step(state: State, pos: Vector3, dt: number, opts: Opts): (number, Verdict, Vector3?)
	if not SpeedLogic.finite(pos) then
		-- Never let a NaN in: a NaN budget is never below 0, so the check would never rubber-band again.
		local back = state.lastGood or state.lastPos
		if back then
			SpeedLogic.teleported(state, back)
			return 0, "rubberband", back
		end
		return 0, "ignored", nil
	end
	local last = state.lastPos
	if last == nil then
		SpeedLogic.teleported(state, pos)
		return 0, "reset", nil
	end

	local dist = horizontal(pos - last)
	state.lastPos = pos

	local allowed = SpeedLogic.allowedPerTick(opts.walkSpeed, dt)
	state.bucket = math.min(bucketMax(opts.walkSpeed), state.bucket + allowed) - dist
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
		return SpeedLogic.treadmillGain(opts.treadmillTier, opts.trailMult), "ok", nil
	end
	return SpeedLogic.walkGain(dist, opts.mult), "ok", nil
end

-- Could the character have got from where the last tick saw it to `pos` in the `dt` seconds since, without
-- the next tick rubber-banding it (the same budget as step, changing nothing)? The client moves its own
-- character, so a position check made between ticks (a seed stolen, a seed home, a sale) uses this: a
-- teleport, or a client that ignores the rubber-band, gets nothing done. False before the first tick.
function SpeedLogic.plausible(state: State, pos: Vector3, dt: number, walkSpeed: number): boolean
	local last = state.lastPos
	if last == nil or not SpeedLogic.finite(pos) then
		return false
	end
	local budget = math.min(bucketMax(walkSpeed), state.bucket + SpeedLogic.allowedPerTick(walkSpeed, math.max(dt, 0)))
	return horizontal(pos - last) <= budget
end

return SpeedLogic
