-- Nests, seed pods and carrying. Stealing is a server ProximityPrompt; the carried seed is a
-- server-made part welded to the thief's back. One seed at a time.
-- Each seed has a gene from the moment it exists (a pod's roll; Config.rollGene): it decides the flower it
-- grows into and its size, so the planting ghost shows exactly that plant. It travels with the seed (the
-- carry, the seed bag's key) and no label ever says the flower: that is revealed when it is planted.
-- A seed looks like one of its zone's 2 seed designs (assets/Seed_<ZoneId>, the owner's bought seeds; the
-- gene picks which, never the rarity: rarity shows only in the name tag), or a plain ball in its seed
-- colour without that file. No Neon, no light (owner request; seedLook).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SeedPacks = require(Shared:WaitForChild("SeedPacks"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local Assets = require(script.Parent:WaitForChild("Assets"))
local PlantGhosts = require(script.Parent:WaitForChild("PlantGhosts"))

local SeedService = {}

type Pod = {
	cframe: CFrame,
	part: BasePart,
	prompt: ProximityPrompt,
	label: TextLabel,
	gui: BillboardGui,
	available: boolean,
	rarity: number,
	mutation: string?,
	gene: number,
	luck: number, -- the luck its seed was rolled with (night or day), for the 2x Luck pass at steal time
	regrowToken: number,
}
type Nest = { info: WorldBuilder.NestInfo, pods: { Pod } }

local nests: { Nest } = {}
local rng = Random.new()

SeedService.POD_SIZE = 3 -- studs: the pod's ball (and the box an assets/Seed model is fitted in)
SeedService.CARRY_SIZE = 2.4
SeedService.LABEL_HEIGHTS = { 3, 4.1, 3.55, 4.65 } -- studs over a pod, by pod number, so neighbours' labels don't overlap

-- Set by Main: GuardService.alert
SeedService.onStolen = nil :: ((zone: number, player: Player) -> ())?

-- "Rare Seed": a pod or carried seed never says its flower (a surprise until planted; SeedPacks.seedName).
function SeedService.seedName(zone: number, rarity: number, mutation: string?): string
	return SeedPacks.seedName(zone, rarity, mutation)
end

local function isNight(): boolean
	return (Config.dayPhase(os.time()))
end

local function roll(): number
	return rng:NextNumber()
end

----------------------------------------------------------------------------------------------------
-- Looks
----------------------------------------------------------------------------------------------------
-- How many seed designs zone `zone` has (assets/Seed_<ZoneId>; 0 without the file), and which one a seed
-- with this gene looks like (Config.geneDesign; whatever its rarity).
function SeedService.designCount(zone: number): number
	return #Assets.variantNames(Assets.seedSlot(zone))
end
function SeedService.designOf(zone: number, gene: number?): number
	return Config.geneDesign(gene, SeedService.designCount(zone))
end

-- Dresses `host` (a pod's ball or the carried seed) as a seed of (zone, rarity, mutation) with this gene:
-- its zone's seed design the gene picks (assets/Seed_<ZoneId>, the owner's bought seeds), fitted in the ball,
-- which turns invisible; without the file, a plain ball in the seed colour (the mutation's, if any). Never
-- Neon or lit (owner). Its rarity shows only in its name tag. Returns the model, or nil for the ball.
function SeedService.seedLook(host: BasePart, zone: number, rarity: number, mutation: string?, gene: number?): Model?
	local old = host:FindFirstChild("SeedModel")
	if old then
		old:Destroy()
	end
	local mut = Config.mutationById(mutation)
	host.Color = if mut then mut.color else Config.ZONES[zone].seedColor
	host.Material = Enum.Material.SmoothPlastic
	for _, d in host:GetChildren() do
		if d:IsA("Light") then
			d:Destroy()
		end
	end
	host:SetAttribute("Mutation", mutation)
	host:SetAttribute("Rarity", rarity)
	host:SetAttribute("Design", nil)
	local size = host.Size.Y
	local slot = Assets.seedSlot(zone)
	local design = SeedService.designOf(zone, gene)
	local model = Assets.get(slot) and Assets.place(slot, nil, host.CFrame * CFrame.new(0, -size / 2, 0), Vector3.one * size, nil, design)
	if model then
		model.Name = "SeedModel"
		host:SetAttribute("Design", design)
		for _, d in model:GetDescendants() do -- (the exported designs have none; a hand-made one might)
			if d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("LuaSourceContainer") then
				d:Destroy()
			elseif d:IsA("BasePart") and d.Material == Enum.Material.Neon then
				d.Material = Enum.Material.SmoothPlastic
			end
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Massless = true
				if not host.Anchored then -- (the carried seed: welded to the ball on the thief's back)
					d.Anchored = false
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = host
					weld.Part1 = d
					weld.Parent = d
				end
			end
		end
		model.Parent = host
	end
	host.Transparency = if model then 1 else 0
	return model
end

-- Relief text on a world label (owner: no flat text): a thick round outline, a bevel and a dark copy
-- dropped behind it. setLabel keeps the copy's text in step.
local SHADOW = Color3.fromRGB(20, 20, 30)
local function relief(label: TextLabel)
	local stroke = label:FindFirstChildWhichIsA("UIStroke") or Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Color = SHADOW
	stroke.Parent = label
	local shadow = label:Clone()
	shadow.Name = "Shadow"
	shadow.TextColor3 = SHADOW
	shadow.Position = label.Position + UDim2.fromOffset(1, 3)
	shadow.ZIndex = label.ZIndex
	shadow.Parent = label.Parent
	label.ZIndex += 1
	local bevel = Instance.new("UIGradient")
	bevel.Rotation = 90
	bevel.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.45, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 170, 185)),
	})
	bevel.Parent = label
end

local function setLabel(label: TextLabel, text: string, color: Color3)
	label.Text = text
	label.TextColor3 = color
	local shadow = label.Parent and label.Parent:FindFirstChild("Shadow")
	if shadow and shadow:IsA("TextLabel") then
		shadow.Text = text
	end
end

-- A seed's name tag: relief text that is never hidden behind the boss, a wall or another pod (AlwaysOnTop:
-- a depth-tested tag behind geometry is how a pod showed without its name).
local function nameTag(host: BasePart, height: number, size: UDim2, maxDistance: number): (TextLabel, BillboardGui)
	local label = WorldBuilder.billboard(host, "", size, Vector3.new(0, height, 0), maxDistance)
	local gui = label.Parent :: BillboardGui
	gui.Name = "SeedLabel"
	gui.AlwaysOnTop = true
	relief(label)
	return label, gui
end

----------------------------------------------------------------------------------------------------
-- Pods
----------------------------------------------------------------------------------------------------
-- The one place a pod is shown or hidden: shown, it has its seed's look, an enabled prompt and an enabled
-- name tag with the seed's name; hidden, none of them.
local function setPod(pod: Pod, zone: number, shown: boolean)
	pod.available = shown
	pod.prompt.Enabled = shown
	pod.gui.Enabled = shown
	if shown then
		local name = SeedService.seedName(zone, pod.rarity, pod.mutation)
		pod.prompt.ObjectText = name
		setLabel(pod.label, name, Config.RARITIES[pod.rarity].color)
		SeedService.seedLook(pod.part, zone, pod.rarity, pod.mutation, pod.gene)
	else
		local model = pod.part:FindFirstChild("SeedModel")
		if model then
			model:Destroy()
		end
		pod.part.Transparency = 1
	end
end

local function regrow(pod: Pod, zone: number)
	pod.luck = if isNight() then Config.NIGHT_LUCK else 1
	pod.rarity, pod.mutation = Config.rollSeed(zone, pod.luck, isNight(), roll)
	pod.gene = Config.rollGene(roll)
	setPod(pod, zone, true)
end

-- Zone `zone`'s pods (tests read them; nothing outside changes them).
function SeedService.pods(zone: number): { Pod }
	local nest = nests[zone]
	return if nest then nest.pods else {}
end

----------------------------------------------------------------------------------------------------
-- Carrying
----------------------------------------------------------------------------------------------------
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
	seed.Size = Vector3.one * SeedService.CARRY_SIZE
	seed.CanCollide = false
	seed.CanQuery = false
	seed.CanTouch = false
	seed.Massless = true
	seed.CFrame = torso.CFrame * CFrame.new(0, 0.3, torso.Size.Z / 2 + 1.1)
	SeedService.seedLook(seed, carry.zone, carry.rarity, carry.mutation, carry.gene) -- (the same design as its pod)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = seed
	weld.Parent = seed
	seed.Parent = model
	local label = nameTag(seed, 3.5, UDim2.fromOffset(220, 30), 60)
	setLabel(label, SeedService.seedName(carry.zone, carry.rarity, carry.mutation), Config.RARITIES[carry.rarity].color)
	model.PrimaryPart = seed
	model.Parent = char
	return model
end

-- The carry for a pod's seed, with what its planting ghost shows (the ghost is built now, so it reaches
-- the thief's client before the carry does).
function SeedService.newCarry(zone: number, podIndex: number, rarity: number, mutation: string?, gene: number): Sessions.Carry
	local ghost, scale = PlantGhosts.seedLook(zone, rarity, gene)
	PlantGhosts.ensure(zone, rarity, ghost)
	return { zone = zone, rarity = rarity, mutation = mutation, gene = gene, ghost = ghost, scale = scale, pod = podIndex, model = nil }
end

-- The 2x Luck draw (Config.luckUpgrade's uniform number) for a seed with this gene stolen by this player: fixed
-- by the two, so a seed that went back to its pod (caught, a reset) and is stolen again by the same player
-- comes out the same: the pass can't be farmed by re-stealing. Another seed or another player draws anew.
function SeedService.luckRoll(gene: number, userId: number): number
	local h = (math.floor(gene) * 2654435761 + (math.floor(userId) % 1e9) * 40503 + 12345) % 4294967296
	return h / 4294967296
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
	if (root.CFrame.Position - pod.part.CFrame.Position).Magnitude > Config.PICKUP_DISTANCE then
		return
	end

	-- 2x Luck: the thief's own luck re-draws the rarity, never below what the pod showed (Config.luckUpgrade)
	local rarity = Config.luckUpgrade(zone, pod.rarity, pod.luck, Sessions.luckMult(s), function()
		return SeedService.luckRoll(pod.gene, player.UserId)
	end)
	local mutation = pod.mutation
	setPod(pod, zone, false)
	local carry = SeedService.newCarry(zone, podIndex, rarity, mutation, pod.gene)
	carry.shown = pod.rarity
	carry.model = makeCarryModel(char, carry)
	s.carry = carry
	Sessions.pushCarry(s)
	Net.LootEvent:FireClient(player, "Pickup", { zone = zone, rarity = rarity, mutation = mutation, name = SeedService.seedName(zone, rarity, mutation) })
	if SeedService.onStolen then
		SeedService.onStolen(zone, player)
	end
end
SeedService.steal = steal

-- The seed designs for the client's hotbar seed slot (Planting.client shows the seed it would plant):
-- ReplicatedStorage.SeedLooks.<zone>.<design>, each fitted in a 3-stud box at the origin. Returns the folder.
SeedService.LOOKS = "SeedLooks"
function SeedService.publishLooks(parent: Instance?): Folder
	local into = parent or ReplicatedStorage
	local old = into:FindFirstChild(SeedService.LOOKS)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = SeedService.LOOKS
	for k in Config.ZONES do
		local zoneFolder = Instance.new("Folder")
		zoneFolder.Name = tostring(k)
		for design = 1, SeedService.designCount(k) do
			local model = Assets.place(Assets.seedSlot(k), nil, CFrame.identity, Vector3.one * SeedService.POD_SIZE, nil, design)
			if model then
				model.Name = tostring(design)
				model.Parent = zoneFolder
			end
		end
		zoneFolder.Parent = folder
	end
	folder.Parent = into
	return folder
end

-- Builds every nest's pods (each rolls its first seed). init also wires their prompts.
function SeedService.buildPods(nestInfos: { WorldBuilder.NestInfo })
	for k, info in nestInfos do
		local nest: Nest = { info = info, pods = {} }
		nests[k] = nest
		for i, cf in info.podCFrames do
			local part = Instance.new("Part")
			part.Name = "SeedPod" .. i
			part.Shape = Enum.PartType.Ball
			part.Size = Vector3.one * SeedService.POD_SIZE
			part.CFrame = cf
			part.Anchored = true
			part.CanCollide = false
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Steal Seed"
			prompt.HoldDuration = 0.3
			prompt.MaxActivationDistance = Config.PICKUP_DISTANCE
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.Parent = part
			local heights = SeedService.LABEL_HEIGHTS
			local label, gui = nameTag(part, heights[(i - 1) % #heights + 1], UDim2.fromOffset(190, 28), 45)
			part.Parent = info.model
			local pod: Pod = {
				cframe = cf, part = part, prompt = prompt, label = label, gui = gui,
				available = false, rarity = 1, mutation = nil, gene = 1, luck = 1, regrowToken = 0,
			}
			nest.pods[i] = pod
			regrow(pod, k)
		end
	end
end

function SeedService.init(nestInfos: { WorldBuilder.NestInfo })
	SeedService.buildPods(nestInfos)
	for k, nest in nests do
		for i, pod in nest.pods do
			pod.prompt.Triggered:Connect(function(player: Player)
				steal(player, k, i)
			end)
		end
	end
	SeedService.publishLooks()
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

-- Caught, died or left: the seed goes back to its pod as the pod showed it (its gene too; a 2x Luck upgrade
-- was the thief's own and stays with them: SeedService.luckRoll gives them the same one if they steal it again).
function SeedService.returnCarry(player: Player)
	local s = Sessions.get(player)
	local carry = s and clearCarry(s)
	if not carry then
		return
	end
	local pod = nests[carry.zone].pods[carry.pod]
	pod.regrowToken += 1
	pod.rarity, pod.mutation, pod.gene = carry.shown or carry.rarity, carry.mutation, carry.gene or Config.rollGene(roll)
	setPod(pod, carry.zone, true)
end

-- A stolen seed goes into the seed bag by itself as soon as its thief crosses from the corridor into the
-- base (Inventory.carryHome; owner request): off their back, gene and all, and the pod regrows as if it was
-- planted. They plant it from the hotbar's seed slot or the Inventory. A Legendary from the last zones is
-- announced now (planting from the bag never announces). With the bag full it stays carried (the Inventory
-- and the planting hint say so). PlotService's homecoming loop checks every plot owner several times a
-- second. Returns whether it stored the seed.
function SeedService.storeCarried(player: Player): boolean
	local s = Sessions.get(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not s or not s.carry or not root then
		return false
	end
	if Inventory.carryHome(s.profile, Inventory.isHome(root.CFrame.Position)) ~= "store" then
		return false
	end
	local carry = SeedService.consumeCarry(player)
	if not carry then
		return false
	end
	SeedPacks.addToBag(s.profile.seedBag, carry.zone, carry.rarity, carry.mutation, carry.gene)
	Sessions.pushFull(s)
	Net.LootEvent:FireClient(player, "Stored", { zone = carry.zone, rarity = carry.rarity, mutation = carry.mutation })
	if Config.announcesLegendary(carry.zone, carry.rarity, false) then
		Net.announce(Config.legendaryAnnouncement(player.DisplayName, carry.zone, carry.mutation), "gold")
	end
	return true
end

-- Planted (or stored): the pod regrows later with a fresh roll.
function SeedService.consumeCarry(player: Player): Sessions.Carry?
	local s = Sessions.get(player)
	local carry = s and clearCarry(s)
	if not carry then
		return nil
	end
	local nest = nests[carry.zone]
	local pod = nest and nest.pods[carry.pod]
	if pod then -- (always, unless the nest's pods were never set up)
		pod.regrowToken += 1
		local token = pod.regrowToken
		task.delay(Config.POD_REGROW, function()
			if pod.regrowToken == token and not pod.available then
				regrow(pod, carry.zone)
			end
		end)
	end
	return carry
end

return SeedService
