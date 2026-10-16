-- Other players sprinting on their treadmills (owner 2026-10-16: "everyone should be able to see each other
-- run"). Your own sprint is Effects.client's (it holds you on the belt); everybody else's character gets the
-- attribute OnTreadmill from the server while they stand on their own belt (SpeedService), and this plays
-- the same run animation, looped at the same speed, on their character here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Treadmill = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Treadmill"))

local me = Players.LocalPlayer
local tracks: { [Model]: AnimationTrack } = {}

local function runAnimation(char: Model): Animation?
	local animate = char:FindFirstChild("Animate")
	local run = animate and animate:FindFirstChild("run")
	return run and run:FindFirstChildWhichIsA("Animation") or nil
end

local function update(char: Model)
	local want = char:GetAttribute("OnTreadmill") == true
	local track = tracks[char]
	if want and not track then
		local hum = char:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		local anim = runAnimation(char)
		if not (animator and anim) or (hum :: Humanoid).Health <= 0 then
			return
		end
		local t = (animator :: Animator):LoadAnimation(anim :: Animation)
		t.Looped = true
		t.Priority = Enum.AnimationPriority.Action
		t:Play(0.15)
		t:AdjustSpeed(Treadmill.RUN_ANIM_SPEED)
		tracks[char] = t
	elseif not want and track then
		track:Stop(0.2)
		tracks[char] = nil
	end
end

local function watch(char: Model)
	update(char)
	char:GetAttributeChangedSignal("OnTreadmill"):Connect(function()
		update(char)
	end)
	char.Destroying:Connect(function()
		tracks[char] = nil
	end)
end

local function onPlayer(p: Player)
	if p == me then
		return
	end
	p.CharacterAdded:Connect(watch)
	if p.Character then
		watch(p.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerRemoving:Connect(function(p)
	local char = p.Character
	if char then
		tracks[char] = nil
	end
end)
