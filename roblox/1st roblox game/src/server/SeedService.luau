-- Nests, seed pods and carrying. Stealing is a server ProximityPrompt; the carried seed is a
-- server-made part welded to the thief's back. One seed at a time.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))

local SeedService = {}

type Pod = {
	cframe: CFrame,
	part: BasePart,
	prompt: ProximityPrompt,
	label: TextLabel,
	available: boolean,
	rarity: number,
	mutation: string?,
	regrowToken: number,
}
type Nest = { info: WorldBuilder.NestInfo, pods: { Pod } }

local nests: { Nest } = {}
local rng = Random.new()

-- Set by Main: GuardService.alert
SeedService.onStolen = nil :: ((zone: number, player: Player) -> ())?

function SeedService.seedName(zone: number, rarity: number, mutation: string?): string
	local prefix = if mutation then mutation .. " " else ""
	return `{prefix}{Config.RARITIES[rarity].id} {Config.ZONES[zone].seed}`
end

local function isNight(): boolean
	return (Config.dayPhase(os.time()))
end

local function applyLook(part: BasePart, zone: number, rarity: number, mutation: string?)
	local mut = Config.mutationById(mutation)
	part.Color = if mut then mut.color else Config.ZONES[zone].seedColor
	part.Material = Enum.Material.Neon
	local light = part:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = Config.RARITIES[rarity].color
		light.Range = 6 + rarity * 3
		light.Brightness = if rarity >= 3 or mut then 3 else 1
	end
	part:SetAttribute("Mutation", mutation)
	part:SetAttribute("Rarity", rarity)
end

local function showPod(pod: Pod, zone: number)
	pod.available = true
	pod.part.Transparency = 0
	pod.prompt.Enabled = true
	pod.prompt.ObjectText = SeedService.seedName(zone, pod.rarity, pod.mutation)
	pod.label.Text = SeedService.seedName(zone, pod.rarity, pod.mutation)
	pod.label.TextColor3 = Config.RARITIES[pod.rarity].color
	local gui = pod.label.Parent :: BillboardGui
	gui.Enabled = true
	applyLook(pod.part, zone, pod.rarity, pod.mutation)
end

local function hidePod(pod: Pod)
	pod.available = false
	pod.part.Transparency = 1
	pod.prompt.Enabled = false
	local gui = pod.label.Parent :: BillboardGui
	gui.Enabled = false
end

local function regrow(pod: Pod, zone: number)
	pod.rarity, pod.mutation = Config.rollSeed(zone, if isNight() then Config.NIGHT_LUCK else 1, isNight(), function()
		return rng:NextNumber()
	end)
	showPod(pod, zone)
end

local function makeCarryModel(char: Model, carry: Sessions.Carry): Model?
	local torso = (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: any
	if not torso then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "CarriedSeed"
	local seed = Instance.new("Part")
	seed.Name = "Seed"
	seed.Shape = Enum.PartType.Ball
	seed.Size = Vector3.one * 2.4
	seed.CanCollide = false
	seed.CanQuery = false
	seed.CanTouch = false
	seed.Massless = true
	local light = Instance.new("PointLight")
	light.Parent = seed
	applyLook(seed, carry.zone, carry.rarity, carry.mutation)
	seed.CFrame = torso.CFrame * CFrame.new(0, 0.3, torso.Size.Z / 2 + 1.1)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = seed
	weld.Parent = seed
	seed.Parent = model
	local label = WorldBuilder.billboard(seed, SeedService.seedName(carry.zone, carry.rarity, carry.mutation),
		UDim2.fromOffset(220, 30), Vector3.new(0, 3.5, 0), 150)
	label.TextColor3 = Config.RARITIES[carry.rarity].color
	model.PrimaryPart = seed
	model.Parent = char
	return model
end

local function steal(player: Player, zone: number, podIndex: number)
	local s = Sessions.get(player)
	local nest = nests[zone]
	local pod = nest and nest.pods[podIndex]
	if not s or not pod or not pod.available then
		return
	end
	if s.carry then
		Net.toast(player, "You can only carry one seed at a time!", "red")
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root or not hum or hum.Health <= 0 then
		return
	end
	if (root.Position - pod.part.Position).Magnitude > Config.PICKUP_DISTANCE then
		return
	end

	local rarity, mutation = pod.rarity, pod.mutation
	hidePod(pod)
	local carry: Sessions.Carry = { zone = zone, rarity = rarity, mutation = mutation, pod = podIndex, model = nil }
	carry.model = makeCarryModel(char, carry)
	s.carry = carry
	Sessions.pushCarry(s)
	Net.LootEvent:FireClient(player, "Pickup", { zone = zone, rarity = rarity, mutation = mutation, name = SeedService.seedName(zone, rarity, mutation) })
	if SeedService.onStolen then
		SeedService.onStolen(zone, player)
	end
end

function SeedService.init(nestInfos: { WorldBuilder.NestInfo })
	for k, info in nestInfos do
		local nest: Nest = { info = info, pods = {} }
		nests[k] = nest
		for i, cf in info.podCFrames do
			local part = Instance.new("Part")
			part.Name = "SeedPod" .. i
			part.Shape = Enum.PartType.Ball
			part.Size = Vector3.one * 3
			part.CFrame = cf
			part.Anchored = true
			part.CanCollide = false
			local light = Instance.new("PointLight")
			light.Parent = part
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Steal Seed"
			prompt.HoldDuration = 0.3
			prompt.MaxActivationDistance = Config.PICKUP_DISTANCE
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.Parent = part
			local label = WorldBuilder.billboard(part, "", UDim2.fromOffset(200, 28), Vector3.new(0, 3, 0), 80)
			part.Parent = info.model
			local pod: Pod = {
				cframe = cf, part = part, prompt = prompt, label = label,
				available = false, rarity = 1, mutation = nil, regrowToken = 0,
			}
			nest.pods[i] = pod
			regrow(pod, k)
			prompt.Triggered:Connect(function(player: Player)
				steal(player, k, i)
			end)
		end
	end
end

local function clearCarry(s: Sessions.Session): Sessions.Carry?
	local carry = s.carry
	if not carry then
		return nil
	end
	s.carry = nil
	if carry.model then
		carry.model:Destroy()
	end
	if s.player.Parent then
		Sessions.pushCarry(s)
	end
	return carry
end

-- Caught, died or left: the seed goes back to its pod, unchanged.
function SeedService.returnCarry(player: Player)
	local s = Sessions.get(player)
	local carry = s and clearCarry(s)
	if not carry then
		return
	end
	local pod = nests[carry.zone].pods[carry.pod]
	pod.regrowToken += 1
	pod.rarity, pod.mutation = carry.rarity, carry.mutation
	showPod(pod, carry.zone)
end

-- Planted: the pod regrows later with a fresh roll.
function SeedService.consumeCarry(player: Player): Sessions.Carry?
	local s = Sessions.get(player)
	local carry = s and clearCarry(s)
	if not carry then
		return nil
	end
	local pod = nests[carry.zone].pods[carry.pod]
	pod.regrowToken += 1
	local token = pod.regrowToken
	task.delay(Config.POD_REGROW, function()
		if pod.regrowToken == token and not pod.available then
			regrow(pod, carry.zone)
		end
	end)
	return carry
end

return SeedService
