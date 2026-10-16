-- Swinging the Bat (owner 2026-10-16): 1 / the hotbar slot only equips it (HUD.client); with it in hand a
-- left click (a tap on mobile: the Tool's Activated) swings it: the strike animation, the swoosh and the
-- bat's trail, then RequestUseItem "Bat" (the server stuns the nearest awake guard in reach, only while
-- the bat is in hand: BatTool.equipped). One swing per Config.BAT_COOLDOWN, like the server's.
-- The strike: a quick wind-up over the shoulder and a hard swing down and across, played on the right
-- arm's shoulder joint (R15 RightShoulder, R6 "Right Shoulder"), so it needs no uploaded animation.
-- A joint's Transform doesn't replicate, so the server passes each swing on (LootEvent "BatSwing" to every
-- client) and every other client plays the same strike on that character.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestUseItem = remotes:WaitForChild("RequestUseItem") :: RemoteEvent
local LootEvent = remotes:WaitForChild("LootEvent") :: RemoteEvent

local player = Players.LocalPlayer

local WIND_UP, STRIKE, RECOVER = 0.12, 0.14, 0.22 -- seconds
local nextSwing = 0
local swinging = false

local function shoulderOf(char: Model): Motor6D?
	local m = char:FindFirstChild("RightShoulder", true) or char:FindFirstChild("Right Shoulder", true)
	return if m and m:IsA("Motor6D") then m else nil
end

local function play(sound: Instance?)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

-- The arm's offset at time t of the swing (the joint's Transform, on top of the hold animation): raised
-- back over the shoulder, then whipped forward and down across the body, then eased back.
local function poseAt(t: number): CFrame
	local up = CFrame.Angles(math.rad(80), 0, math.rad(-15)) -- from the hold pose (arm forward): up over the head
	local down = CFrame.Angles(math.rad(-55), math.rad(-30), math.rad(20)) -- whipped down and across
	if t < WIND_UP then
		local a = t / WIND_UP
		return CFrame.identity:Lerp(up, a * (2 - a))
	elseif t < WIND_UP + STRIKE then
		local a = (t - WIND_UP) / STRIKE
		return up:Lerp(down, a * a)
	end
	local a = math.clamp((t - WIND_UP - STRIKE) / RECOVER, 0, 1)
	return down:Lerp(CFrame.identity, a * (2 - a))
end

local animate: (char: Model, tool: Instance, onHit: (() -> ())?, onDone: (() -> ())?) -> ()

local function swing(tool: Tool)
	local now = os.clock()
	if swinging or now < nextSwing then
		return
	end
	local char = tool.Parent
	if not char or not char:IsA("Model") then
		return
	end
	nextSwing = now + Config.BAT_COOLDOWN
	swinging = true
	animate(char, tool, function()
		RequestUseItem:FireServer("Bat") -- the hit lands mid-swing
	end, function()
		swinging = false
	end)
end

-- The strike on `char`'s arm with `tool`: the swoosh and trail, `onHit` mid-swing, `onDone` at the end.
animate = function(char: Model, tool: Instance, onHit: (() -> ())?, onDone: (() -> ())?)
	local handle = tool:FindFirstChild("Handle")
	play(handle and handle:FindFirstChild("Swoosh"))
	local trail = handle and handle:FindFirstChildWhichIsA("Trail")
	if trail then
		trail.Enabled = true
	end
	local shoulder = shoulderOf(char)
	local start = os.clock()
	local fired = false
	local base, written = CFrame.identity, nil :: CFrame?
	local conn: RBXScriptConnection
	conn = RunService.Stepped:Connect(function()
		local t = os.clock() - start
		if shoulder and shoulder.Parent then
			-- the animations set Transform every frame; when none did since our last write, keep our base
			-- (multiplying our own pose again would spin the arm)
			if shoulder.Transform ~= written then
				base = shoulder.Transform
			end
			written = base * poseAt(t)
			shoulder.Transform = written :: CFrame
		end
		if not fired and t >= WIND_UP + STRIKE * 0.5 then
			fired = true
			if onHit then
				onHit()
			end
		end
		if t >= WIND_UP + STRIKE + RECOVER then
			conn:Disconnect()
			if shoulder and shoulder.Parent and shoulder.Transform == written then
				shoulder.Transform = base
			end
			if onDone then
				onDone()
			end
			if trail then
				trail.Enabled = false
			end
		end
	end)
end

local function watchTool(tool: Instance)
	if tool and tool:IsA("Tool") and tool.Name == "Bat" and not tool:GetAttribute("SwingWired") then
		tool:SetAttribute("SwingWired", true)
		tool.Activated:Connect(function()
			swing(tool)
		end)
		tool.Equipped:Connect(function()
			local handle = tool:FindFirstChild("Handle")
			play(handle and handle:FindFirstChild("Equip"))
		end)
	end
end

local function watch(container: Instance)
	for _, c in container:GetChildren() do
		watchTool(c)
	end
	container.ChildAdded:Connect(watchTool)
end

player.CharacterAdded:Connect(watch)
if player.Character then
	watch(player.Character)
end
local backpack = player:FindFirstChildOfClass("Backpack") -- (a later one: ChildAdded below)
if backpack then
	watch(backpack)
end
player.ChildAdded:Connect(function(c)
	if c:IsA("Backpack") then
		watch(c)
	end
end)

-- Someone else's swing (the server passes it on), and a hit: the bat's thwack
LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "BatSwing" and type(data) == "table" and typeof(data.player) == "Instance" and data.player ~= player then
		local char = (data.player :: Player).Character
		local tool = char and char:FindFirstChild("Bat")
		if char and tool then
			animate(char, tool)
		end
	elseif kind == "Bat" and type(data) == "table" and data.hit then
		local char = player.Character
		local tool = char and char:FindFirstChild("Bat")
		local handle = tool and tool:FindFirstChild("Handle")
		play(handle and handle:FindFirstChild("Hit"))
	end
end)
