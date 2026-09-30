-- Local-only effects: "+$1.2M" income popups, event sounds, camera shake, the treadmill belt scroll,
-- rainbow mutations, and hiding other players' plot prompts. Nothing here affects game state.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local LootEvent = remotes:WaitForChild("LootEvent") :: RemoteEvent
local IncomePopup = remotes:WaitForChild("IncomePopup") :: RemoteEvent

----------------------------------------------------------------------------------------------------
-- Income popups
----------------------------------------------------------------------------------------------------
local MAX_POPUPS = 40
local livePopups = 0

IncomePopup.OnClientEvent:Connect(function(amount: number, position: Vector3)
	if livePopups >= MAX_POPUPS or typeof(position) ~= "Vector3" then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - position).Magnitude > 150 then
		return
	end
	livePopups += 1
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(140, 40)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = attachment
	gui.Parent = attachment
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(120, 255, 120)
	label.Text = "+" .. Format.money(amount)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = gui

	local info = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffsetWorldSpace = Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	task.delay(1.25, function()
		attachment:Destroy()
		livePopups -= 1
	end)
end)

----------------------------------------------------------------------------------------------------
-- Sounds + shake
----------------------------------------------------------------------------------------------------
local function play(name: string, volume: number?)
	local id = Config.SOUNDS[name]
	if not id then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume or 0.6
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(5, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local shakeUntil, shakePower = 0, 0
local function shake(seconds: number, power: number)
	shakeUntil = os.clock() + seconds
	shakePower = power
end

RunService:BindToRenderStep("SeedShake", Enum.RenderPriority.Camera.Value + 1, function()
	local left = shakeUntil - os.clock()
	if left > 0 then
		local camera = workspace.CurrentCamera
		local p = shakePower * left
		camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * p), math.rad((math.random() - 0.5) * p), 0)
	end
end)

local SOUND_FOR = {
	Pickup = "Pickup", Planted = "Plant", Caught = "Caught", GuardWake = "Wake",
	Bat = "Bat", Bought = "Buy", End = "Pickup", Dusted = "Click", Potion = "Buy",
}

LootEvent.OnClientEvent:Connect(function(kind: string, data: any)
	local sound = SOUND_FOR[kind]
	if sound then
		play(sound)
	end
	if kind == "Caught" then
		shake(0.6, 6)
	elseif kind == "GuardWake" then
		shake(0.4, 3)
	elseif kind == "Bat" and data and data.hit then
		shake(0.2, 3)
	end
end)

----------------------------------------------------------------------------------------------------
-- World decoration that must follow streaming: belts, rainbow mutations, owner-only prompts
----------------------------------------------------------------------------------------------------
local stripes: { [Texture]: boolean } = {}
local rainbows: { [BasePart]: boolean? } = {}

local function watchPrompt(prompt: ProximityPrompt)
	local function apply()
		local owner = prompt:GetAttribute("OwnerUserId")
		if owner ~= nil then
			prompt.Enabled = owner == player.UserId
		end
	end
	apply()
	prompt:GetAttributeChangedSignal("OwnerUserId"):Connect(apply)
end

local function consider(inst: Instance)
	if inst:IsA("Texture") and inst.Name == "Stripes" then
		stripes[inst] = true
	elseif inst:IsA("ProximityPrompt") then
		watchPrompt(inst)
	elseif inst:IsA("BasePart") and inst:GetAttribute("Mutation") == "Rainbow" then
		rainbows[inst] = true
	elseif inst:IsA("Model") and inst:GetAttribute("Mutation") == "Rainbow" then
		task.defer(function()
			local body = inst.PrimaryPart or inst:FindFirstChild("Body")
			if body and body:IsA("BasePart") then
				rainbows[body] = true
			end
		end)
	end
	-- Pods re-roll in place, so their mutation can change after they stream in.
	if inst:IsA("BasePart") and string.sub(inst.Name, 1, 7) == "SeedPod" then
		inst:GetAttributeChangedSignal("Mutation"):Connect(function()
			rainbows[inst] = if inst:GetAttribute("Mutation") == "Rainbow" then true else nil
		end)
	end
end

for _, d in workspace:GetDescendants() do
	consider(d)
end
workspace.DescendantAdded:Connect(consider)
workspace.DescendantRemoving:Connect(function(inst)
	if inst:IsA("Texture") then
		stripes[inst] = nil
	elseif inst:IsA("BasePart") then
		rainbows[inst] = nil
	end
end)

RunService.Heartbeat:Connect(function(dt)
	for tex in stripes do
		tex.OffsetStudsV = (tex.OffsetStudsV + dt * 6) % tex.StudsPerTileV
	end
	local hue = (os.clock() * 0.25) % 1
	for part in rainbows do
		part.Color = Color3.fromHSV(hue, 0.8, 1)
	end
end)
