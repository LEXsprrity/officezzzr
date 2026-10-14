-- Every TICK: measure each character's HumanoidRootPart movement on the server, grant Speed
-- (walking or treadmill), enforce the movement sanity check, and set WalkSpeed from the Speed stat.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Treadmill = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Treadmill"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))
local SpeedLogic = require(script.Parent:WaitForChild("SpeedLogic"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))

local SpeedService = {}

-- Every plot's belt (SpeedService.init), to tell a player standing on somebody else's treadmill that it
-- pays them nothing: once per step onto it, at most every OTHER_BELT_TOAST_GAP seconds.
local belts: { BasePart } = {}
local OTHER_BELT_TOAST_GAP = 20
local onOtherBelt: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local otherBeltToastAt: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

function SpeedService.init(plots: { WorldBuilder.PlotInfo })
	belts = {}
	for _, info in plots do
		table.insert(belts, info.belt)
	end
end

local function checkOtherBelt(s: Sessions.Session, pos: Vector3, now: number)
	local player = s.player
	local other = Treadmill.standing(belts, pos, if s.plot then s.plot.index else nil) == "other"
	if other and not onOtherBelt[player] and now - (otherBeltToastAt[player] or -math.huge) >= OTHER_BELT_TOAST_GAP then
		otherBeltToastAt[player] = now
		Net.toast(player, "🏃 This isn't your treadmill! Only the one on your own plot gives you Speed.", "red")
	end
	onOtherBelt[player] = other or nil
end

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
	end
end

local function tickPlayer(s: Sessions.Session, dt: number, now: number)
	local root, hum = rootOf(s.player)
	if not root or not hum then
		return
	end
	local pos = root.Position
	local onTreadmill = s.plot ~= nil and WorldBuilder.onBelt(s.plot.belt, pos)
	if not onTreadmill then
		checkOtherBelt(s, pos, now)
	end
	local gain, verdict, back = SpeedLogic.step(s.tracker, pos, dt, {
		walkSpeed = s.walkSpeed,
		onTreadmill = onTreadmill,
		mult = Sessions.speedPerStud(s),
		treadmillMult = Sessions.treadmillMult(s),
	})

	if verdict == "rubberband" and back then
		local char = s.player.Character
		if char then
			char:PivotTo(CFrame.new(back) * root.CFrame.Rotation)
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
