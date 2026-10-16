-- Builds one sleeping boss per zone (its body: GuardBody) and runs them at ~10 Hz: GuardBrain decides,
-- this applies it with Humanoid:MoveTo (no pathfinding) and handles catches and bat stuns.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))
local GuardBrain = require(script.Parent:WaitForChild("GuardBrain"))
local SeedService = require(script.Parent:WaitForChild("SeedService"))
local SpeedService = require(script.Parent:WaitForChild("SpeedService"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local GuardBody = require(script.Parent:WaitForChild("GuardBody"))

local GuardService = {}

type Guard = {
	zone: number,
	brain: GuardBrain.Brain,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	status: TextLabel,
	eyes: { BasePart },
	rigged: boolean, -- a rigged boss: its clients animate it and float its own Zzz
	shownState: string,
}

local guards: { Guard } = {}

-- A giant facing -X (toward the base), scaled by GUARD_SCALE: the blocky body or a model from the assets
-- folder (GuardBody), either way joined to an invisible HumanoidRootPart that Humanoid:MoveTo drives.
local function buildGuard(info: WorldBuilder.NestInfo): Guard
	local zone = Config.ZONES[info.zone]
	local S = Config.GUARD_SCALE
	local model = Instance.new("Model")
	model.Name = "Guard_" .. zone.id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local hip = 2 * S
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1) * S
	root.Transparency = 1
	root.CanCollide = false
	root.CFrame = CFrame.lookAt(info.guardHome + Vector3.new(0, hip + root.Size.Y / 2, 0), info.guardHome + Vector3.new(-10, hip + root.Size.Y / 2, 0))
	root.Parent = model
	model.PrimaryPart = root

	-- Every zone's boss is a rigged pet from the assets folder (Guard_<Name>); without one (a missing or
	-- broken file), the blocky giant.
	local eyes: { BasePart } = {}
	local placed, rig = GuardBody.fromAsset(model, root, zone, hip)
	if not placed then
		eyes = GuardBody.procedural(model, root, zone, hip)
	end
	local rigged = rig ~= nil

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15 -- R15 honours HipHeight on a legless custom rig
	hum.HipHeight = hip
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false -- welded, no Neck Motor6D
	hum.AutoJumpEnabled = false
	hum.WalkSpeed = 0
	hum.Parent = model
	for _, state in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Dead, Enum.HumanoidStateType.Seated } do
		hum:SetStateEnabled(state, false)
	end

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Guards"
		end
	end

	local head = model:FindFirstChild("Head") :: BasePart
	-- A rigged boss floats its own animated Zzz (GuardAnimator.client), so its status label is empty while
	-- it sleeps. No name floats over it (owner playtest), and the status shows only fairly close.
	local statusY = 3 * S
	local status = WorldBuilder.billboard(head, if rigged then "" else "💤", UDim2.fromOffset(120, 60), Vector3.new(0, statusY, 0), 100)

	model.Parent = info.model.Parent
	root:SetNetworkOwner(nil)

	return {
		zone = info.zone,
		brain = GuardBrain.new(info.zone, info.guardHome),
		model = model,
		humanoid = hum,
		root = root,
		status = status,
		eyes = eyes,
		rigged = rigged,
		shownState = "Sleeping",
	}
end

local function showState(g: Guard)
	local state = g.brain.state
	if state == g.shownState then
		return
	end
	g.shownState = state
	local text = ({ Sleeping = "💤", Waking = "❗", Chasing = "", Returning = "", Stunned = "" } :: any)[state] -- only Zzz (sleep) and ❗ (waking) show (owner)
	g.status.Text = if state == "Sleeping" and g.rigged then "" else text or ""
	for _, eye in g.eyes do
		local open = state ~= "Sleeping"
		eye.Size = Vector3.new(0.7, if open then 0.7 else 0.15, 0.2) * Config.GUARD_SCALE
		eye.Color = if state == "Chasing" then Color3.fromRGB(255, 40, 40) else Color3.new(0, 0, 0)
		eye.Material = if state == "Chasing" then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	g.model:SetAttribute("State", state)
end

local function onCaught(g: Guard, player: Player)
	local s = Sessions.get(player)
	local root = SpeedService.rootOf(player)
	g.model:SetAttribute("CatchAt", workspace:GetServerTimeNow()) -- the rigged boss lunges and bites
	SeedService.returnCarry(player)
	if not s or not root then
		return
	end
	-- The player flies a little way from the guard (SpeedService.knock; the corridor's walls stop them).
	local away = root.Position - g.root.Position
	SpeedService.knock(player, if Vector3.new(away.X, 0, away.Z).Magnitude > 0.1 then away else -Vector3.xAxis)
	s.stunnedUntil = os.clock() + Config.CATCH_STUN
	Net.LootEvent:FireClient(player, "Caught", { guard = Config.ZONES[g.zone].guard })
end

local function step(g: Guard, now: number)
	local targets = {}
	for player, s in Sessions.all() do
		if s.carry and s.carry.zone == g.zone then
			-- (where the server saw the thief get to: a teleport home doesn't make them safe)
			local pos = SpeedService.seenPosition(player)
			if pos then
				table.insert(targets, { id = player, pos = pos, safe = pos.X < Config.CORRIDOR_START_X, speed = s.profile.speed })
			end
		end
	end

	local before = g.brain.state
	local wasAwake = before ~= "Sleeping"
	local cmd = GuardBrain.step(g.brain, now, g.root.Position, targets)
	g.humanoid.WalkSpeed = cmd.walkSpeed
	if cmd.moveTo then
		g.humanoid:MoveTo(cmd.moveTo)
	elseif wasAwake then
		g.humanoid:MoveTo(g.root.Position) -- stand still
	end

	if cmd.woke then
		for _, t in targets do
			Net.LootEvent:FireClient(t.id, "GuardWake", { guard = Config.ZONES[g.zone].guard, zone = g.zone })
		end
	end
	if cmd.caughtId then
		onCaught(g, cmd.caughtId)
	elseif before == "Chasing" and g.brain.state == "Returning" then
		-- Chase ended without a catch: everyone still holding this nest's seed got away.
		for _, t in targets do
			Net.LootEvent:FireClient(t.id, "Escaped", { guard = Config.ZONES[g.zone].guard })
		end
	end
	if g.brain.state == "Sleeping" and wasAwake then
		-- Settle exactly at home facing the base so the next thief gets the same head start.
		local home = g.brain.home + Vector3.new(0, g.root.Position.Y - g.brain.home.Y, 0)
		g.model:PivotTo(CFrame.lookAt(home, home - Vector3.xAxis))
	end
	showState(g)
end

function GuardService.init(nestInfos: { WorldBuilder.NestInfo })
	for k, info in nestInfos do
		guards[k] = buildGuard(info)
	end
	SeedService.onStolen = function(zone: number, _player: Player)
		local g = guards[zone]
		if g then
			GuardBrain.alert(g.brain, os.clock())
		end
	end
	task.spawn(function()
		while true do
			task.wait(1 / Config.GUARD_HZ)
			local now = os.clock()
			for _, g in guards do
				local ok, err = pcall(step, g, now)
				if not ok then
					warn("[GuardService]", err)
				end
			end
		end
	end)
end

local function nearestGuard(pos: Vector3, range: number, filter: (Guard) -> boolean): Guard?
	local best, bestDist = nil, range
	for _, g in guards do
		local d = (g.root.Position - pos).Magnitude
		if d <= bestDist and filter(g) then
			best, bestDist = g, d
		end
	end
	return best
end

-- Bat: stun the nearest awake guard in reach. The distance is measured on the server, from where the
-- player could have walked to (SpeedService.trustedRoot).
function GuardService.batHit(player: Player): boolean
	local root = SpeedService.trustedRoot(player)
	if not root then
		return false
	end
	local reach = Config.BAT_RANGE + 1.5 * Config.GUARD_SCALE -- giants are wide
	local g = nearestGuard(root.Position, reach, function(g)
		return g.brain.state ~= "Sleeping"
	end)
	if g and GuardBrain.stun(g.brain, os.clock(), Config.BAT_STUN) then
		showState(g)
		return true
	end
	return false
end

return GuardService
