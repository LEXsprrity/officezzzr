--!strict
-- Pure treadmill rules shared by the server and the client: which belt a position stands on, whether it
-- is the player's own, and when the client loops the run-in-place animation. A belt is the part tagged
-- Role = "TreadmillBelt" with its plot's PlotIndex attribute (WorldBuilder). Only your own treadmill
-- pays Speed (SpeedService checks your plot's belt), so only your own one plays the animation. Also: what
-- standing on it pays, where its Upgrade board and "+X" text go, the lock that keeps you on it, and the
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

-- Somebody else's treadmill: you can't use it, and nothing solid stands over it. (It used to have an
-- invisible solid box over it, made on each client for the belts that weren't theirs: people jumped onto
-- its top and stood there, and everyone else saw them floating over the treadmill: owner playtest.)
-- Instead each client keeps its OWN character out (Effects.client, every frame): a root inside the keep-out
-- area is put back just outside its nearest side, like walking into a wall that has no top to stand on.
-- The area is the belt's footprint plus KEEP_OUT_PAD (about half a character) on every side, from the belt's
-- bottom to BLOCK_HEIGHT studs over its top (a jump from the Upgrade board can't come down onto it).
-- Returns where to put the root, or nil when it is outside.
Treadmill.BLOCK_HEIGHT = 12
Treadmill.KEEP_OUT_PAD = 1
function Treadmill.pushOut(beltCF: CFrame, beltSize: Vector3, rootPos: Vector3): Vector3?
	local rel = beltCF:PointToObjectSpace(rootPos)
	local hx, hz = beltSize.X / 2 + Treadmill.KEEP_OUT_PAD, beltSize.Z / 2 + Treadmill.KEEP_OUT_PAD
	if math.abs(rel.X) >= hx or math.abs(rel.Z) >= hz or rel.Y < -beltSize.Y / 2 or rel.Y > beltSize.Y / 2 + Treadmill.BLOCK_HEIGHT then
		return nil
	end
	local out = if hx - math.abs(rel.X) <= hz - math.abs(rel.Z)
		then Vector3.new((if rel.X < 0 then -1 else 1) * (hx + 0.05), rel.Y, rel.Z)
		else Vector3.new(rel.X, rel.Y, (if rel.Z < 0 then -1 else 1) * (hz + 0.05))
	return beltCF:PointToWorldSpace(out)
end

-- Whether the client loops the run animation: alive and on their own treadmill (locked there, so walking
-- doesn't move them: the sprint plays whatever keys are held).
function Treadmill.shouldRun(standing: ("own" | "other")?, alive: boolean): boolean
	return alive and standing == "own"
end

-- The run animation's playback speed on the treadmill: a real sprint, the legs a blur (owner: 2.75 looked
-- like a jog). Much past 4 the default run's keyframes start to skip and the legs glitch.
Treadmill.RUN_ANIM_SPEED = 4
-- How far a locked runner leans into the sprint (degrees; client-side only, on its root joint's C0).
Treadmill.RUN_LEAN = 12

----------------------------------------------------------------------------------------------------
-- What standing on it pays, and the text over it
----------------------------------------------------------------------------------------------------
-- Speed per STEP (one server tick, Config.TICK: 4 a second) standing on your own treadmill of tier `tier`
-- with trail `trailId` equipped: the tier's fixed value x the trail x the Speed passes (`passMult`:
-- Config.passSpeedMult of the owner's passes, 1 when nil; Config.treadmillPerStep), whatever your Speed or
-- WalkSpeed. Owner decision 2026-10-15: the number shown is the number you get, every step. What the server
-- pays a tick (SpeedLogic.treadmillGain), each "+X" popup over the runner, the "+X" text over the treadmill,
-- its Upgrade board and the Shop card all show this one number ("+5K"; no "/s").
function Treadmill.perStep(tier: number?, trailId: string?, passMult: number?): number
	return Config.treadmillPerStep(tier, trailId, passMult)
end

-- ...and what a second on it really pays: 1 / Config.TICK steps (4) (Config.treadmillPerSecond).
function Treadmill.perSecond(tier: number?, trailId: string?, passMult: number?): number
	return Config.treadmillPerSecond(tier, trailId, passMult)
end

-- The "+X" popups over the runner (Effects.client): a stream of them, one every POPUP_INTERVAL seconds (the
-- server's own tick, Config.TICK), each showing what that step pays (Treadmill.perStep), so the numbers
-- popping add up to exactly what the server pays (owner: spam them like the reference). At most
-- POPUP_MAX_LIVE are on screen at once; each lives POPUP_LIFE seconds (about 6 at a time normally).
Treadmill.POPUP_INTERVAL = Config.TICK
Treadmill.POPUP_MAX_LIVE = 12
Treadmill.POPUP_LIFE = 1.5

export type PopupState = { nextAt: number }

-- A new stream (on locking): the first popup one interval after `now`.
function Treadmill.newPopups(now: number): PopupState
	return { nextAt = now + Treadmill.POPUP_INTERVAL }
end

-- One frame of the stream at `now` with `live` popups on screen: the gain the popup to spawn now shows, or
-- nil (not due yet, nothing to gain, or the cap is full: that one is skipped). A slow frame that missed
-- several intervals shows them all in one popup (`perStep` x the steps), so the shown total never drifts
-- from the real gain.
function Treadmill.stepPopups(state: PopupState, now: number, perStep: number, live: number): number?
	if now < state.nextAt then
		return nil
	end
	local due = math.floor((now - state.nextAt) / Treadmill.POPUP_INTERVAL) + 1
	state.nextAt += due * Treadmill.POPUP_INTERVAL
	if perStep <= 0 or live >= Treadmill.POPUP_MAX_LIVE then
		return nil
	end
	return perStep * due
end

-- "+0.5", "+12.3", "+200", "+1.6K" (like the HUD's "+X/step").
function Treadmill.gainText(x: number): string
	return "+" .. (if x < 100 then string.format("%.1f", x) else Format.short(x))
end

-- The text over the treadmill, on its board and Shop card: "+5K", exactly what each popup shows and each
-- step pays (no "/s": owner 2026-10-15, one number everywhere).
function Treadmill.stepText(perStep: number): string
	return Treadmill.gainText(perStep)
end

-- The "+X" text over the treadmill only shows up close (studs).
Treadmill.RATE_TEXT_DISTANCE = 35

-- The belt's long axis is its local Z unless it is wider than long.
local function axes(beltSize: Vector3): (boolean, number, number)
	local alongZ = beltSize.Z >= beltSize.X
	return alongZ, (if alongZ then beltSize.Z else beltSize.X) / 2, (if alongZ then beltSize.X else beltSize.Z) / 2
end

-- Where the "+X" text floats, in the belt's own space: over the front end, a little in from it.
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

-- The board's line under it: what a step pays now and at the next tier ("+100 > +200"), just now's
-- at the last tier ("+1.5K"), nothing with no owner.
function Treadmill.boardRateText(perStep: number?, nextPerStep: number?): string
	if perStep == nil then
		return ""
	elseif nextPerStep == nil then
		return Treadmill.stepText(perStep)
	end
	return `{Treadmill.stepText(perStep)} > {Treadmill.stepText(nextPerStep)}`
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

-- How high a standing character's root is over what it stands on: the Humanoid's HipHeight plus half the
-- root (R15), or the 2-stud legs plus half the root (R6, whose HipHeight is 0). A standard avatar: 3.
Treadmill.STAND_LIFT = 3
function Treadmill.standLift(r6: boolean, hipHeight: number, rootHeight: number): number
	local lift = (if r6 then 2 + hipHeight else hipHeight) + rootHeight / 2
	-- (at most 5: held higher, the root would leave the belt check's 7 studs over the belt's centre)
	return if lift > 0 then math.min(lift, 5) else Treadmill.STAND_LIFT
end

-- Where a locked character is held: at the CENTRE of the belt (across and along it, wherever it stepped
-- on), STANDING on its top (its root `lift` studs over it, default STAND_LIFT), facing the front end. Never
-- at the height it touched the belt: the lock fires on the first frame the root is over the belt, which on
-- a raised belt (tier 4's Sci-Fi model stands its belt 2.8 studs up) is while it is still climbing or in
-- mid-jump, and held there the runner stood inside the model, legs under the belt (owner playtest).
function Treadmill.lockCFrame(beltCF: CFrame, beltSize: Vector3, rootPos: Vector3, lift: number?): CFrame
	local alongZ = axes(beltSize)
	local pos = beltCF:PointToWorldSpace(Vector3.new(0, beltSize.Y / 2 + (lift or Treadmill.STAND_LIFT), 0))
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
