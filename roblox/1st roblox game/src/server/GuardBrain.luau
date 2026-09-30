--!strict
-- Pure guard state machine. GuardService calls step() at ~10 Hz and applies the command with
-- Humanoid:MoveTo; catching is a horizontal distance check, never Touched.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local GuardBrain = {}

export type GuardState = "Sleeping" | "Waking" | "Chasing" | "Returning" | "Stunned"

export type Brain = {
	state: GuardState,
	home: Vector3,
	chaseSpeed: number,
	returnSpeed: number,
	wakeAt: number,
	chaseStarted: number,
	stunnedUntil: number,
	afterStun: GuardState,
	dustedUntil: number,
	targetId: any?,
}

export type Target = { id: any, pos: Vector3, safe: boolean }

export type Command = {
	moveTo: Vector3?, -- nil = stand still
	walkSpeed: number,
	caughtId: any?,
	woke: boolean, -- true on the tick the guard starts chasing
}

function GuardBrain.new(zoneIndex: number, home: Vector3): Brain
	local chase = Config.guardChaseSpeed(zoneIndex)
	return {
		state = "Sleeping",
		home = home,
		chaseSpeed = chase,
		returnSpeed = math.max(Config.BASE_WALKSPEED, chase * Config.GUARD_RETURN_FACTOR),
		wakeAt = 0,
		chaseStarted = 0,
		stunnedUntil = 0,
		afterStun = "Sleeping",
		dustedUntil = 0,
		targetId = nil,
	}
end

local function horizontalDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- A seed was taken from this guard's nest.
function GuardBrain.alert(brain: Brain, now: number)
	if brain.state == "Sleeping" or brain.state == "Returning" then
		local extra = if now < brain.dustedUntil then Config.SLEEP_DUST_EXTRA else 0
		brain.dustedUntil = 0 -- one steal uses up the dust
		brain.state = "Waking"
		brain.wakeAt = now + extra
	elseif brain.state == "Stunned" then
		brain.afterStun = "Chasing"
	end
end

-- Sleep Dust only works on a sleeping guard.
function GuardBrain.dust(brain: Brain, now: number): boolean
	if brain.state ~= "Sleeping" then
		return false
	end
	brain.dustedUntil = now + Config.SLEEP_DUST_LASTS
	return true
end

function GuardBrain.stun(brain: Brain, now: number, seconds: number): boolean
	if brain.state == "Sleeping" then
		return false
	end
	if brain.state ~= "Stunned" then
		brain.afterStun = brain.state
	end
	brain.state = "Stunned"
	brain.stunnedUntil = now + seconds
	return true
end

-- Where to run: at the target along the corridor, aiming *past* it. MoveTo is re-issued only at
-- GUARD_HZ, and a fast runner moves further than CATCH_DISTANCE between ticks, so aiming at the
-- sampled position would leave the guard one tick behind forever. The lead keeps it at full speed.
local function chasePoint(brain: Brain, guardPos: Vector3, target: Vector3): Vector3
	local halfWidth = Config.CORRIDOR_WIDTH / 2 - 6
	local dx, dz = target.X - guardPos.X, target.Z - guardPos.Z
	local len = math.sqrt(dx * dx + dz * dz)
	local x, z = target.X, target.Z
	if len > 0.01 then
		local lead = 2 * brain.chaseSpeed / Config.GUARD_HZ + Config.CATCH_DISTANCE
		x += dx / len * lead
		z += dz / len * lead
	end
	return Vector3.new(x, brain.home.Y, math.clamp(z, -halfWidth, halfWidth))
end

function GuardBrain.step(brain: Brain, now: number, guardPos: Vector3, targets: { Target }): Command
	local cmd: Command = { moveTo = nil, walkSpeed = brain.chaseSpeed, caughtId = nil, woke = false }

	if brain.state == "Stunned" then
		if now < brain.stunnedUntil then
			cmd.walkSpeed = 0
			return cmd
		end
		local resume = brain.afterStun
		if resume == "Chasing" or resume == "Waking" then
			brain.chaseStarted = now -- a fresh chase after the stun, same timeout
			brain.state = "Chasing"
		else
			brain.state = resume :: GuardState
		end
	end

	if brain.state == "Waking" then
		if now < brain.wakeAt then
			cmd.walkSpeed = 0
			return cmd
		end
		brain.state = "Chasing"
		brain.chaseStarted = now
		cmd.woke = true
	end

	-- After a catch, keep going if another thief of this nest is still in the corridor.
	if brain.state == "Returning" and now - brain.chaseStarted <= Config.CHASE_TIMEOUT then
		for _, t in targets do
			if not t.safe then
				brain.state = "Chasing"
				break
			end
		end
	end

	if brain.state == "Chasing" then
		local best: Target? = nil
		local bestDist = math.huge
		for _, t in targets do
			if not t.safe then
				local d = horizontalDist(guardPos, t.pos)
				if d < bestDist then
					best, bestDist = t, d
				end
			end
		end
		if best == nil or now - brain.chaseStarted > Config.CHASE_TIMEOUT then
			brain.state = "Returning"
			brain.targetId = nil
		elseif bestDist < Config.CATCH_DISTANCE then
			cmd.caughtId = best.id
			brain.state = "Returning"
			brain.targetId = nil
		else
			brain.targetId = best.id
			cmd.moveTo = chasePoint(brain, guardPos, best.pos)
			cmd.walkSpeed = brain.chaseSpeed
			return cmd
		end
	end

	if brain.state == "Returning" then
		if horizontalDist(guardPos, brain.home) < 3 then
			brain.state = "Sleeping"
			return cmd
		end
		cmd.moveTo = brain.home
		cmd.walkSpeed = brain.returnSpeed
	end

	return cmd
end

return GuardBrain
