-- Every TICK: measure each character's HumanoidRootPart movement on the server, grant Speed
-- (walking or treadmill), enforce the movement sanity check, and set WalkSpeed from the Speed stat.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))
local SpeedLogic = require(script.Parent:WaitForChild("SpeedLogic"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))

local SpeedService = {}

local function rootOf(player: Player): (BasePart?, Humanoid?)
	local char = player.Character
	if not char then
		return nil, nil
	end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then
		return nil, nil
	end
	return root, hum
end
SpeedService.rootOf = rootOf

-- Server-initiated move: keeps the sanity check from treating it as a speed hack.
function SpeedService.teleport(player: Player, cf: CFrame)
	local char = player.Character
	local s = Sessions.get(player)
	if not char then
		return
	end
	char:PivotTo(cf)
	if s then
		SpeedLogic.teleported(s.tracker, cf.Position)
		s.tracker.at = os.clock()
	end
end

-- Knocked away (a boss's catch, a bat hit; owner 2026-10-16: "flies a bit away"): the victim's own client
-- flings its character (it owns its physics; BatSwing.client on LootEvent "Knock") `dir` (horizontal)
-- at KNOCK_SPEED and up at KNOCK_UP, a little way through the air. The flight isn't a speed hack:
-- the movement check skips it (tickPlayer) for KNOCK_TIME and starts again where they land.
function SpeedService.knock(player: Player, dir: Vector3)
	local s = Sessions.get(player)
	if not s then
		return
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else -Vector3.xAxis
	s.knockedUntil = os.clock() + Config.KNOCK_TIME
	s.stunnedUntil = math.max(s.stunnedUntil, os.clock() + Config.KNOCK_TIME)
	Net.LootEvent:FireClient(player, "Knock", { velocity = flat * Config.KNOCK_SPEED + Vector3.yAxis * Config.KNOCK_UP, seconds = Config.KNOCK_TIME })
end

-- The character's root, if it is alive and where the server sees it now is somewhere it could have walked to
-- since the movement check last saw it (SpeedLogic.plausible). Every position check made between ticks
-- (stealing a seed, getting home with it, selling, planting, the Upgrade boards, the bat) goes through this:
-- the client moves its own character, so a teleport, or a client ignoring the rubber-band, would otherwise
-- count right away. nil when dead, before the first tick, or right after a refused move.
function SpeedService.trustedRoot(player: Player): BasePart?
	local s = Sessions.get(player)
	local root = rootOf(player)
	if not s or not root then
		return nil
	end
	if not SpeedLogic.plausible(s.tracker, root.CFrame.Position, os.clock() - (s.tracker.at or 0), s.walkSpeed) then
		return nil
	end
	return root
end

-- Where the server last saw the character get to: its root now if trusted (trustedRoot), else the last
-- position the movement check accepted. The guards chase this, so a thief can't shake one off by
-- teleporting into the base and waiting there. nil when dead or never seen.
function SpeedService.seenPosition(player: Player): Vector3?
	local root = SpeedService.trustedRoot(player)
	if root then
		return root.CFrame.Position
	end
	local s = Sessions.get(player)
	if not s or not rootOf(player) then
		return nil
	end
	return s.tracker.lastGood or s.tracker.lastPos
end

-- Ticks in a row a session's character has had a root but no Humanoid.
local headless: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any

-- A root without a Humanoid only happens when a client deletes it (a deletion in your own character can
-- replicate, see Workspace.RejectCharacterDeletions): then the movement check, the guards and the Died hook
-- would all skip the character. Two such ticks in a row and it is respawned (CharacterRemoving sends a
-- carried seed back to its pod).
local function checkHeadless(s: Sessions.Session)
	local char = s.player.Character
	if char and char.Parent and char:FindFirstChild("HumanoidRootPart") and not char:FindFirstChildOfClass("Humanoid") then
		headless[s] = (headless[s] or 0) + 1
		if headless[s] >= 2 then
			headless[s] = nil
			task.spawn(s.player.LoadCharacter, s.player)
		end
	else
		headless[s] = nil
	end
end

-- One player's tick (also SpeedService.tickPlayer: the tests drive it like the loop below does).
local function tickPlayer(s: Sessions.Session, dt: number, now: number)
	local root, hum = rootOf(s.player)
	if not root or not hum then
		checkHeadless(s)
		return
	end
	headless[s] = nil
	local pos = root.Position
	if os.clock() < s.knockedUntil then
		-- flying from a hit (SpeedService.knock): no Speed for it, and the movement check starts afresh
		-- where they land
		SpeedLogic.teleported(s.tracker, pos)
		s.tracker.at = os.clock()
		return
	end
	-- Only your own plot's belt pays; nobody can step onto somebody else's (Effects.client blocks it).
	local onTreadmill = s.plot ~= nil and WorldBuilder.onBelt(s.plot.belt, pos)
	-- Everyone sees them sprint on it (TreadmillRunners.client plays the run on other players' characters)
	local char = s.player.Character
	if typeof(char) == "Instance" and char:GetAttribute("OnTreadmill") ~= onTreadmill then
		char:SetAttribute("OnTreadmill", onTreadmill)
	end
	local gain, verdict, back = SpeedLogic.step(s.tracker, pos, dt, {
		walkSpeed = s.walkSpeed,
		onTreadmill = onTreadmill,
		mult = Sessions.speedPerStud(s),
		treadmillTier = s.profile.treadmillTier,
		trailMult = Sessions.speedMult(s),
	})
	s.tracker.at = now

	if verdict == "rubberband" and back then
		local char = s.player.Character
		if char then
			local turn = root.CFrame.Rotation
			char:PivotTo(CFrame.new(back) * (if SpeedLogic.finite(turn.LookVector) then turn else CFrame.new()))
		end
	end

	local before = s.profile.speed
	if gain > 0 then
		s.profile.speed += gain
	end
	local newWalk = Config.walkSpeedFor(s.profile.speed)
	s.walkSpeed = newWalk

	local wanted = if now < s.stunnedUntil then 0 else newWalk
	if hum.WalkSpeed ~= wanted then
		hum.WalkSpeed = wanted
	end

	if s.profile.speed ~= before then
		Sessions.pushCore(s)
	end
end

SpeedService.tickPlayer = tickPlayer

function SpeedService.start()
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.TICK)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, s in Sessions.all() do
				local ok, err = pcall(tickPlayer, s, dt, now)
				if not ok then
					warn("[SpeedService]", err)
				end
			end
		end
	end)
end

-- Called after purchases that change WalkSpeed, so the new speed applies right away.
function SpeedService.refresh(s: Sessions.Session)
	local newWalk = Config.walkSpeedFor(s.profile.speed)
	s.walkSpeed = math.max(s.walkSpeed, newWalk)
	local _, hum = rootOf(s.player)
	if hum and os.clock() >= s.stunnedUntil then
		hum.WalkSpeed = newWalk
	end
end

return SpeedService
