-- The Halloween event's candy on the map (Shared/Halloween): candy corn spread along the corridor and the
-- base's walkway. Walking over a piece picks it up (no click, no prompt): the server checks every player's
-- trusted position a few times a second (SpeedService.trustedRoot, so a teleport doesn't count), pays
-- CANDY_VALUE into profile.candy and puts the piece somewhere else CANDY_RESPAWN seconds later. Shared by the
-- whole server: whoever gets there first. The look is assets/Candy.rbxm (the "Candy" slot: the owner's candy
-- corn model) when it is there, else a candy corn built here; Client/CandySpin turns and bobs them.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Halloween = require(Shared:WaitForChild("Halloween"))
local Assets = require(script.Parent:WaitForChild("Assets"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))
local SpeedService = require(script.Parent:WaitForChild("SpeedService"))

local CandyService = {}

CandyService.TAG = "HalloweenCandy" -- (Client/CandySpin animates the tagged models)
CandyService.CHECK_INTERVAL = 0.15

local rng = Random.new()
local function roll(): number
	return rng:NextNumber()
end

type Piece = { model: Model, position: Vector3, inBase: boolean }
local pieces: { Piece } = {}
local folder: Folder? = nil

-- A candy corn from code: a yellow base, an orange middle and a white tip, stacked and tapering, with a warm glow.
local function builtCandy(): Model
	local model = Instance.new("Model")
	local function layer(name: string, size: Vector3, y: number, color: Color3): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(0, y, 0)
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		p.Parent = model
		return p
	end
	local base = layer("Base", Vector3.new(2.2, 1.3, 2.2), 0.65, Color3.fromRGB(255, 205, 40))
	layer("Middle", Vector3.new(1.75, 1.3, 1.75), 1.45, Color3.fromRGB(255, 135, 20))
	layer("Tip", Vector3.new(1.1, 1.1, 1.1), 2.25, Color3.fromRGB(255, 250, 240))
	model.PrimaryPart = base
	base.PivotOffset = base.CFrame:Inverse() -- pivot on the ground under it
	return model
end

local function place(position: Vector3): Model
	local cf = CFrame.new(position)
	local model = Assets.place("Candy", nil, cf, Halloween.CANDY_SIZE) -- (bottom centre at cf, fitted)
	if not model then
		model = builtCandy()
		model:PivotTo(cf)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 160, 50)
	glow.Range = 10
	glow.Brightness = 1.5
	glow.Shadows = false
	glow.Parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	model.Name = "Candy"
	CollectionService:AddTag(model, CandyService.TAG)
	model.Parent = folder
	return model
end

-- A clear spot on the ground: drawn by Halloween.spot until a ray down from above lands on the floor (not on a
-- tree, a rock or a fence), at most a few tries.
local function groundSpot(inBase: boolean): Vector3
	local world = workspace:FindFirstChild("World")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = if world then { world } else {}
	local p = Halloween.spot(inBase, roll)
	for _ = 1, 12 do
		local hit = workspace:Raycast(p + Vector3.new(0, 80, 0), Vector3.new(0, -120, 0), params)
		if hit and hit.Position.Y <= Config.GROUND_Y + 1.5 then
			return Vector3.new(p.X, hit.Position.Y, p.Z)
		end
		p = Halloween.spot(inBase, roll)
	end
	return p
end

local function spawnPiece(inBase: boolean)
	local position = groundSpot(inBase)
	table.insert(pieces, { model = place(position), position = position, inBase = inBase })
end

local function collect(i: number, s: Sessions.Session)
	local piece = table.remove(pieces, i) :: Piece
	piece.model:Destroy()
	s.profile.candy = math.min(s.profile.candy + Halloween.CANDY_VALUE, Halloween.CANDY_MAX)
	Sessions.push(s.player, { candy = s.profile.candy })
	Net.LootEvent:FireClient(s.player, "Candy", { position = piece.position })
	task.delay(Halloween.CANDY_RESPAWN, function()
		if Halloween.active(os.time()) then
			spawnPiece(piece.inBase)
		end
	end)
end

local function check()
	if not Halloween.active(os.time()) then
		if #pieces > 0 then -- the event just ended: the candy goes
			for _, piece in pieces do
				piece.model:Destroy()
			end
			table.clear(pieces)
		end
		return
	end
	local r2 = Halloween.CANDY_RADIUS * Halloween.CANDY_RADIUS
	for _, s in Sessions.all() do
		local root = SpeedService.trustedRoot(s.player)
		if root then
			local at = root.Position
			for i = #pieces, 1, -1 do
				local d = pieces[i].position - at
				if d.X * d.X + d.Z * d.Z <= r2 and math.abs(d.Y) < 8 then
					collect(i, s)
				end
			end
		end
	end
end

function CandyService.init()
	if not Halloween.active(os.time()) then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "HalloweenCandy"
	f.Parent = workspace
	folder = f
	for _ = 1, Halloween.CANDY_CORRIDOR do
		spawnPiece(false)
	end
	for _ = 1, Halloween.CANDY_BASE do
		spawnPiece(true)
	end
	task.spawn(function()
		while true do
			task.wait(CandyService.CHECK_INTERVAL)
			local ok, err = pcall(check)
			if not ok then
				warn("[CandyService]", err)
			end
		end
	end)
end

return CandyService
