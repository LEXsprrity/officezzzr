-- Builds one sleeping giant per zone and runs them at ~10 Hz: GuardBrain decides, this applies it
-- with Humanoid:MoveTo (no pathfinding) and handles catches, bat stuns and Sleep Dust.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))
local GuardBrain = require(script.Parent:WaitForChild("GuardBrain"))
local SeedService = require(script.Parent:WaitForChild("SeedService"))
local SpeedService = require(script.Parent:WaitForChild("SpeedService"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local Assets = require(script.Parent:WaitForChild("Assets"))

local GuardService = {}

type Guard = {
	zone: number,
	brain: GuardBrain.Brain,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	status: TextLabel,
	eyes: { BasePart },
	shownState: string,
}

local guards: { Guard } = {}

local function weldPart(model: Model, root: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Shape = shape or Enum.PartType.Block
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
	p.CFrame = root.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
	p.Parent = model
	return p
end

-- The blocky giant's body, welded to the root, with a few zone-specific bits. Returns its eyes.
local function proceduralBody(model: Model, root: BasePart, zone: Config.Zone, hip: number): { BasePart }
	local S = Config.GUARD_SCALE
	local c = zone.guardColor
	local dark = c:Lerp(Color3.new(0, 0, 0), 0.35)
	weldPart(model, root, "Body", Vector3.new(4, 4, 3) * S, CFrame.new(0, 0.5 * S, 0), c)
	weldPart(model, root, "Head", Vector3.new(3, 2.5, 2.5) * S, CFrame.new(0, 3.5 * S, -0.3 * S), c)
	local eyes: { BasePart } = {}
	for _, x in { -0.7, 0.7 } do
		table.insert(eyes, weldPart(model, root, "Eye", Vector3.new(0.7, 0.15, 0.2) * S, CFrame.new(x * S, 3.8 * S, -1.6 * S), Color3.new(0, 0, 0)))
	end
	for _, x in { -1, 1 } do
		weldPart(model, root, "Leg", Vector3.new(1.4 * S, hip, 1.4 * S), CFrame.new(x * S, -S - hip / 2, 0), dark)
		weldPart(model, root, "Arm", Vector3.new(1.2, 3.5, 1.2) * S, CFrame.new(x * 2.6 * S, 0.3 * S, 0), dark)
	end

	if zone.id == "Desert" then
		weldPart(model, root, "Tail", Vector3.new(1, 1, 4) * S, CFrame.new(0, 2.5 * S, 2.5 * S) * CFrame.Angles(math.rad(-40), 0, 0), dark)
		weldPart(model, root, "Stinger", Vector3.one * S, CFrame.new(0, 4.5 * S, 3.5 * S), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
	elseif zone.id == "Jungle" or zone.id == "Spirit" then
		weldPart(model, root, "Snout", Vector3.new(2, 1.2, 2) * S, CFrame.new(0, 3.1 * S, -2.4 * S), c)
		weldPart(model, root, "Tail", Vector3.new(1.2, 1.2, 5) * S, CFrame.new(0, 0, 3.5 * S), dark)
		if zone.id == "Spirit" then
			for _, x in { -1, 1 } do
				weldPart(model, root, "Horn", Vector3.new(0.4, 1.6, 0.4) * S, CFrame.new(x * 0.9 * S, 5.2 * S, 0), Color3.fromRGB(255, 215, 0), Enum.Material.Neon)
			end
		end
	elseif zone.id == "Lava" then
		for i = 1, 4 do
			weldPart(model, root, "Magma", Vector3.one * 0.9 * S, CFrame.new((i - 2.5) * 0.9 * S, 1.2 * S, -1.55 * S), Color3.fromRGB(255, 140, 20), Enum.Material.Neon)
		end
	elseif zone.id == "Snow" then
		weldPart(model, root, "Fur", Vector3.new(4.4, 1.2, 3.4) * S, CFrame.new(0, 2.5 * S, 0), Color3.new(1, 1, 1), Enum.Material.Fabric)
	elseif zone.id == "Space" then
		weldPart(model, root, "Antenna", Vector3.new(0.2, 2, 0.2) * S, CFrame.new(0, 5.5 * S, 0), c)
		weldPart(model, root, "AntennaTip", Vector3.one * 0.6 * S, CFrame.new(0, 6.5 * S, 0), Color3.fromRGB(255, 255, 120), Enum.Material.Neon, Enum.PartType.Ball)
	end
	return eyes
end

-- A body from the assets folder (slot Guard_<Name>, e.g. Guard_GiantMole), if there is one: fitted to
-- about the blocky giant's size with its feet on the ground under the invisible root, facing the root's
-- front, then unanchored, massless and welded to the root so it moves with the chase like the blocky
-- body. A rigged model stays in its saved pose (no animation). An invisible "Head" at its top carries
-- the name and state labels. Returns false when there is no usable model.
local function assetBody(model: Model, root: BasePart, zone: Config.Zone, hip: number): boolean
	local slot = "Guard_" .. string.gsub(zone.guard, "%s", "")
	if not Assets.get(slot) then
		return false
	end
	local S = Config.GUARD_SCALE
	local ground = root.CFrame * CFrame.new(0, -(hip + root.Size.Y / 2), 0)
	local body = Assets.place(slot, model, ground, Vector3.new(10, 7.75, 10) * S)
	if not body then
		return false
	end
	local _, hi = Assets.bounds(body, ground)
	local top = if hi then hi.Y else 7.75 * S
	for _, d in body:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = d
			w.Parent = d
			d.Anchored = false
		end
	end
	local head = weldPart(model, root, "Head", Vector3.new(3, 2.5, 2.5) * S, root.CFrame:ToObjectSpace(ground * CFrame.new(0, top - 1.25 * S, 0)), zone.guardColor)
	head.Transparency = 1
	return true
end

-- A giant facing -X (toward the base), scaled by GUARD_SCALE: the blocky body or a model from the assets
-- folder, either way welded to an invisible HumanoidRootPart that Humanoid:MoveTo drives.
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

	local eyes = if assetBody(model, root, zone, hip) then {} else proceduralBody(model, root, zone, hip)

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
	local status = WorldBuilder.billboard(head, "💤", UDim2.fromOffset(120, 60), Vector3.new(0, 3 * S, 0), 300)
	local nameLabel = WorldBuilder.billboard(head, zone.guard, UDim2.fromOffset(240, 30), Vector3.new(0, 1.6 * S, 0), 200)
	nameLabel.TextColor3 = Color3.fromRGB(255, 200, 200)

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
		shownState = "Sleeping",
	}
end

local function showState(g: Guard)
	local state = g.brain.state
	if state == g.shownState then
		return
	end
	g.shownState = state
	local text = ({ Sleeping = "💤", Waking = "❗", Chasing = "😡", Returning = "😤", Stunned = "💫" } :: any)[state]
	g.status.Text = text or ""
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
	SeedService.returnCarry(player)
	if not s or not root then
		return
	end
	-- Knock the player away from the guard (toward base), keep them inside the corridor.
	local away = root.Position - g.root.Position
	away = Vector3.new(away.X, 0, away.Z)
	local dir = if away.Magnitude > 0.1 then away.Unit else -Vector3.xAxis
	local target = root.Position + dir * Config.KNOCKBACK_STUDS
	local halfWidth = Config.CORRIDOR_WIDTH / 2 - 4
	target = Vector3.new(target.X, root.Position.Y + 3, math.clamp(target.Z, -halfWidth, halfWidth))
	SpeedService.teleport(player, CFrame.lookAt(target, target + dir))
	s.stunnedUntil = os.clock() + Config.CATCH_STUN
	Net.LootEvent:FireClient(player, "Caught", { guard = Config.ZONES[g.zone].guard })
end

local function step(g: Guard, now: number)
	local targets = {}
	for player, s in Sessions.all() do
		if s.carry and s.carry.zone == g.zone then
			local root = SpeedService.rootOf(player)
			if root then
				table.insert(targets, { id = player, pos = root.Position, safe = root.Position.X < Config.CORRIDOR_START_X })
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

-- Bat: stun the nearest awake guard in reach. The distance is measured on the server.
function GuardService.batHit(player: Player): boolean
	local root = SpeedService.rootOf(player)
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

-- Sleep Dust: the nearest sleeping guard stays asleep longer after the next steal.
function GuardService.dust(player: Player): string?
	local root = SpeedService.rootOf(player)
	if not root then
		return nil
	end
	local g = nearestGuard(root.Position, Config.SLEEP_DUST_RANGE, function(g)
		return g.brain.state == "Sleeping"
	end)
	if g and GuardBrain.dust(g.brain, os.clock()) then
		return Config.ZONES[g.zone].guard
	end
	return nil
end

return GuardService
