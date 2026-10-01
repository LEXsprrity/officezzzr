-- Every TICK: measure each character's HumanoidRootPart movement on the server, grant Speed
-- (walking or treadmill), enforce the movement sanity check, and set WalkSpeed from the Speed stat.
local Players = game:GetService("Players")
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
	end
end

local function reachEnd(s: Sessions.Session)
	s.profile.reachedEnd = true
	Net.LootEvent:FireClient(s.player, "End", {})
	for _, other in Players:GetPlayers() do
		if other ~= s.player then
			Net.toast(other, `⛩️ {s.player.DisplayName} reached the End of the Line!`, "gold")
		end
	end
	Sessions.pushFull(s)
end

local function tickPlayer(s: Sessions.Session, dt: number, now: number)
	local root, hum = rootOf(s.player)
	if not root or not hum then
		return
	end
	local pos = root.Position
	local onTreadmill = s.plot ~= nil and WorldBuilder.onBelt(s.plot.belt, pos)
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

	if not s.profile.reachedEnd and pos.X >= Config.END_X - 40 then
		reachEnd(s)
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
