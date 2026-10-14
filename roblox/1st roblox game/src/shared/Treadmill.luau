--!strict
-- Pure treadmill rules shared by the server and the client: which belt a position stands on, whether it
-- is the player's own, and when the client loops the run-in-place animation. A belt is the part tagged
-- Role = "TreadmillBelt" with its plot's PlotIndex attribute (WorldBuilder). Only your own treadmill
-- pays Speed (SpeedService checks your plot's belt), so only your own one plays the animation. Also: what
-- standing on it pays, where its Upgrade board and "+X/s" text go, the lock that keeps you on it, and the
-- invisible wall that keeps everyone else off it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))

local Treadmill = {}

-- A CFrame at `pos` facing horizontal direction `dir`, like CFrame.lookAt, built with fromMatrix (Lune's
-- CFrame.lookAt, used when the map is baked and in the tests, points the wrong way for some directions).
local function facingCFrame(pos: Vector3, dir: Vector3): CFrame
	local look = dir.Unit
	local right = look:Cross(Vector3.yAxis).Unit
	return CFrame.fromMatrix(pos, right, right:Cross(look))
end

-- The belt's front end (where the runner faces: the treadmill's console) is its local +Z end. WorldBuilder
-- turns the belt so its front end points away from the plot, toward the middle walkway, and puts the
-- console (or the built-in stop) there.
Treadmill.FRONT = 1

-- Is `pos` (a HumanoidRootPart's position) standing on a belt with this CFrame and Size: inside its
-- footprint and up to 7 studs above its centre? Same box as WorldBuilder.onBelt, the server's check.
function Treadmill.onBelt(cf: CFrame, size: Vector3, pos: Vector3): boolean
	local rel = cf:PointToObjectSpace(pos)
	return math.abs(rel.X) <= size.X / 2 and math.abs(rel.Z) <= size.Z / 2 and rel.Y >= 0 and rel.Y <= 7
end

-- The belt `pos` stands on and its plot index (nil if the belt has none), or nil off every belt.
function Treadmill.beltAt(belts: { BasePart }, pos: Vector3): (BasePart?, number?)
	for _, belt in belts do
		if belt.Parent and Treadmill.onBelt(belt.CFrame, belt.Size, pos) then
			local plot = belt:GetAttribute("PlotIndex")
			return belt, if type(plot) == "number" then plot else nil
		end
	end
	return nil, nil
end

-- What standing at `pos` means for a player whose plot is `myPlot` (nil before the server sent it):
-- "own" (their treadmill: Speed and the run animation), "other" (somebody else's: nothing) or nil (on no
-- belt). A belt without a plot index, or a player without a plot, is never "own".
function Treadmill.standing(belts: { BasePart }, pos: Vector3, myPlot: number?): ("own" | "other")?
	local belt, plot = Treadmill.beltAt(belts, pos)
	if not belt then
		return nil
	end
	return if myPlot ~= nil and plot == myPlot then "own" else "other"
end

-- Somebody else's treadmill: an invisible solid box over its belt (Effects.client makes one, on this client
-- only, for every belt that isn't the player's), so they can't step onto it. It covers the belt's footprint
-- and a little more, from just above the belt to BLOCK_HEIGHT studs: walking into it stops you and it
-- is too tall to jump onto. Returns its CFrame and Size.
Treadmill.BLOCK_HEIGHT = 9
function Treadmill.blockBox(beltCF: CFrame, beltSize: Vector3): (CFrame, Vector3)
	local size = Vector3.new(beltSize.X + 0.6, Treadmill.BLOCK_HEIGHT, beltSize.Z + 0.6)
	return beltCF * CFrame.new(0, beltSize.Y / 2 + 0.05 + size.Y / 2, 0), size
end

-- Whether the client loops the run animation: alive and on their own treadmill (locked there, so walking
-- doesn't move them: the sprint plays whatever keys are held).
function Treadmill.shouldRun(standing: ("own" | "other")?, alive: boolean): boolean
	return alive and standing == "own"
end

-- The run animation's playback speed on the treadmill: a sprint, well above a normal run.
Treadmill.RUN_ANIM_SPEED = 2.75

----------------------------------------------------------------------------------------------------
-- What standing on it pays, and the text over it
----------------------------------------------------------------------------------------------------
-- Speed per second standing on your own treadmill of tier `tier` with trail `trailId` equipped: the tier's
-- fixed rate x the trail (Config.treadmillPerSecond), whatever your Speed or WalkSpeed. What the server pays
-- a second (SpeedLogic.treadmillGain every tick), the "+X" popups over the runner, the "+X/s" text over the
-- treadmill, its Upgrade board and the Shop card all show this one number.
function Treadmill.perSecond(tier: number?, trailId: string?): number
	return Config.treadmillPerSecond(tier, trailId)
end

-- "+0.5", "+12.3", "+200", "+1.6K" (like the HUD's "+X/step").
function Treadmill.gainText(x: number): string
	return "+" .. (if x < 100 then string.format("%.1f", x) else Format.short(x))
end

-- The text over the treadmill: "+60.9/s", the same number as the popups.
function Treadmill.rateText(perSecond: number): string
	return Treadmill.gainText(perSecond) .. "/s"
end

-- The "+X/s" text over the treadmill only shows up close (studs).
Treadmill.RATE_TEXT_DISTANCE = 35

-- The belt's long axis is its local Z unless it is wider than long.
local function axes(beltSize: Vector3): (boolean, number, number)
	local alongZ = beltSize.Z >= beltSize.X
	return alongZ, (if alongZ then beltSize.Z else beltSize.X) / 2, (if alongZ then beltSize.X else beltSize.Z) / 2
end

-- Where the "+X/s" text floats, in the belt's own space: over the front end, a little in from it.
function Treadmill.stepTextOffset(beltSize: Vector3): Vector3
	local alongZ, halfAlong = axes(beltSize)
	local inFrom = Treadmill.FRONT * (halfAlong + 2.5) -- just past the head (console end), so the console never hides it
	local up = beltSize.Y / 2 + 6.5
	return if alongZ then Vector3.new(0, up, inFrom) else Vector3.new(inFrom, up, 0)
end

----------------------------------------------------------------------------------------------------
-- The Upgrade board next to it
----------------------------------------------------------------------------------------------------
Treadmill.BOARD_SIZE = Vector2.new(7.6, 4.8) -- the panel (studs), like the plot's Upgrade board
Treadmill.BOARD_GAP = 1.2 -- from the treadmill's side to the board's near edge
Treadmill.BOARD_LIFT = 2 -- the panel's bottom edge above the ground

-- The board's CFrame for a belt at `beltCF`/`beltSize` whose treadmill stands on the ground at `groundY`.
-- The treadmill stands in front of its plot (`plotCenter`), between the fence and the walkway, its runner
-- facing the walkway: the board stands beside it, level with the belt's middle, on the side away from the
-- plot's middle (off the entrance path), and faces the way the runner does (front face -Z toward the
-- walkway). `clearSide` is how far the treadmill (its frame or model) reaches sideways from the belt's
-- centre line (default: the belt plus its frame).
function Treadmill.boardCFrame(beltCF: CFrame, beltSize: Vector3, plotCenter: Vector3, groundY: number, clearSide: number?): CFrame
	local alongZ, _, halfLat = axes(beltSize)
	local along = beltCF:VectorToWorldSpace((if alongZ then Vector3.zAxis else Vector3.xAxis) * Treadmill.FRONT)
	local lateral = beltCF:VectorToWorldSpace(if alongZ then Vector3.xAxis else Vector3.zAxis)
	along = Vector3.new(along.X, 0, along.Z).Unit
	lateral = Vector3.new(lateral.X, 0, lateral.Z).Unit
	local flat = Vector3.new(beltCF.Position.X, 0, beltCF.Position.Z)
	local away = flat - Vector3.new(plotCenter.X, 0, plotCenter.Z)
	local side = lateral * (if lateral:Dot(away) < 0 then -1 else 1)
	local reach = (clearSide or (halfLat + 1.3)) + Treadmill.BOARD_GAP + Treadmill.BOARD_SIZE.X / 2
	local pos = flat + side * reach + Vector3.new(0, groundY + Treadmill.BOARD_LIFT + Treadmill.BOARD_SIZE.Y / 2, 0)
	return facingCFrame(pos, along)
end

-- What the board says: the owner's tier ("Level 7 > Level 8"), "MAX" at the last tier (no buttons), or
-- "Empty plot" (no owner, no buttons).
function Treadmill.boardText(tier: number?): (string, "open" | "max" | "empty")
	if tier == nil then
		return "Empty plot", "empty"
	elseif tier >= Config.TREADMILL_MAX then
		return "MAX", "max"
	end
	return `Level {tier} > Level {tier + 1}`, "open"
end

-- The board's line under it: what a second pays now and at the next tier ("+60/s > +100/s"), just now's
-- at the last tier ("+2.5K/s"), nothing with no owner.
function Treadmill.boardRateText(perSecond: number?, nextPerSecond: number?): string
	if perSecond == nil then
		return ""
	elseif nextPerSecond == nil then
		return Treadmill.rateText(perSecond)
	end
	return `{Treadmill.rateText(perSecond)} > {Treadmill.rateText(nextPerSecond)}`
end

-- How close the owner must be to the board to see its prompts; the server re-checks with some slack.
Treadmill.BOARD_PROMPT_DISTANCE = 10
function Treadmill.canUseBoard(isOwner: boolean, rootPos: Vector3?, boardPos: Vector3): boolean
	return isOwner and rootPos ~= nil and (rootPos - boardPos).Magnitude <= Treadmill.BOARD_PROMPT_DISTANCE + 6
end

----------------------------------------------------------------------------------------------------
-- Lock: once you step on your own belt you stay on it, running, until you jump (Space / the mobile jump
-- button). Jumping puts you just off its side, and you can't be locked again for LOCK_COOLDOWN seconds.
-- Dying, a respawn, or being moved off the belt (a teleport) just unlocks. The client drives it
-- (Effects.client); the server sees a player standing still on their belt: the AFK treadmill gain.
----------------------------------------------------------------------------------------------------
Treadmill.LOCK_COOLDOWN = 1.5

export type LockMode = "free" | "locked" | "cooldown"
export type LockState = { mode: LockMode, untilTime: number }
export type LockInput = { now: number, onOwnBelt: boolean, alive: boolean, jumped: boolean }
export type LockAction = "lock" | "unlock" | "exit"

function Treadmill.newLock(): LockState
	return { mode = "free", untilTime = 0 }
end

-- One step of the lock. Returns what the client must do now: "lock" (hold the character on the belt),
-- "exit" (release it and put it off the belt), "unlock" (just release it) or nil (nothing changes).
function Treadmill.stepLock(state: LockState, input: LockInput): LockAction?
	if state.mode == "locked" then
		if not input.alive or not input.onOwnBelt then
			state.mode = "free"
			return "unlock"
		elseif input.jumped then
			state.mode = "cooldown"
			state.untilTime = input.now + Treadmill.LOCK_COOLDOWN
			return "exit"
		end
		return nil
	end
	if state.mode == "cooldown" then
		if input.now < state.untilTime then
			return nil
		end
		state.mode = "free"
	end
	if input.alive and input.onOwnBelt then
		state.mode = "locked"
		return "lock"
	end
	return nil
end

-- Where a locked character is held: at the CENTRE of the belt (across and along it, wherever it stepped
-- on), at its own height, facing the front end.
function Treadmill.lockCFrame(beltCF: CFrame, beltSize: Vector3, rootPos: Vector3): CFrame
	local alongZ = axes(beltSize)
	local rel = beltCF:PointToObjectSpace(rootPos)
	local pos = beltCF:PointToWorldSpace(Vector3.new(0, rel.Y, 0))
	local front = beltCF:VectorToWorldSpace((if alongZ then Vector3.zAxis else Vector3.xAxis) * Treadmill.FRONT)
	front = Vector3.new(front.X, 0, front.Z).Unit
	return facingCFrame(pos, front)
end

-- Where a character that jumped off is put: just beside the belt (past its rails), on the side of
-- `toward` (the plot's middle; default the belt's +X side), at the same height and spot along it.
function Treadmill.exitPosition(beltCF: CFrame, beltSize: Vector3, rootPos: Vector3, toward: Vector3?): Vector3
	local alongZ, _, halfLat = axes(beltSize)
	local rel = beltCF:PointToObjectSpace(rootPos)
	local side = 1
	if toward then
		local t = beltCF:PointToObjectSpace(toward)
		side = if (if alongZ then t.X else t.Z) < 0 then -1 else 1
	end
	local off = side * (halfLat + 3)
	return beltCF:PointToWorldSpace(if alongZ then Vector3.new(off, rel.Y, rel.Z) else Vector3.new(rel.X, rel.Y, off))
end

return Treadmill
