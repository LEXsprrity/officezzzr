-- The Halloween event's candy (Shared/Halloween): candy corn appearing in the corridor, never in the base.
-- CANDY_START pieces when the server starts, then one more every CANDY_EVERY seconds while fewer than
-- CANDY_ON_MAP lie there (owner 2026-10-19: "only 25 per 5 minutes"). Walking over a piece picks it up (no
-- click, no prompt): the server checks every player's trusted position a few times a second
-- (SpeedService.trustedRoot, so a teleport doesn't count) and pays CANDY_VALUE into profile.candy. Shared by
-- the whole server: whoever gets there first. The look: assets/Candy.rbxm (the "Candy" slot) if it is there,
-- else the owner's Creator Store candy corn (Halloween.CANDY_ASSET, loaded once with InsertService), else a
-- candy corn built here. Client/CandySpin turns and bobs them.
local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
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

type Piece = { model: Model, position: Vector3 }
local pieces: { Piece } = {}
local folder: Folder? = nil
local template: Model? = nil -- the owner's candy corn from the Creator Store, fitted, its pivot at its bottom centre

-- A candy corn from code: a yellow base, an orange middle and a white tip, stacked and tapering.
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

-- The owner's Creator Store candy corn, loaded once (yields): its parts in one Model, scripts removed, scaled to
-- fit Halloween.CANDY_SIZE, its pivot at its bottom centre. nil (warned) when Roblox won't load it.
local function loadTemplate(): Model?
	local ok, result = pcall(InsertService.LoadAsset, InsertService, Halloween.CANDY_ASSET)
	if not ok or not result then
		warn("[CandyService] could not load the candy corn model", Halloween.CANDY_ASSET, result)
		return nil
	end
	local inner = result:FindFirstChildWhichIsA("Model")
	local model = if inner and #result:GetChildren() == 1 then inner else result
	model.Parent = nil
	local biggest: BasePart? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		elseif d:IsA("BasePart") and (not biggest or d.Size.Magnitude > biggest.Size.Magnitude) then
			biggest = d
		end
	end
	if not biggest then
		warn("[CandyService] the candy corn model has no parts")
		return nil
	end
	model.PrimaryPart = biggest
	local _, size = model:GetBoundingBox()
	local fit = Halloween.CANDY_SIZE
	model:ScaleTo(model:GetScale() * math.min(fit.Y / size.Y, fit.X / math.max(size.X, size.Z)))
	local box, scaled = model:GetBoundingBox()
	biggest.PivotOffset = biggest.CFrame:Inverse() * (box * CFrame.new(0, -scaled.Y / 2, 0))
	return model
end

local function place(position: Vector3): Model
	local cf = CFrame.new(position)
	local model = Assets.place("Candy", nil, cf, Halloween.CANDY_SIZE) -- (bottom centre at cf, fitted)
	if not model then
		model = if template then template:Clone() else builtCandy()
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

-- A clear spot on the corridor's ground: drawn by Halloween.spot until a ray down from above lands on the floor
-- (not on a tree, a rock or a fence), at most a few tries.
local function groundSpot(): Vector3
	local world = workspace:FindFirstChild("World")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = if world then { world } else {}
	local p = Halloween.spot(roll)
	for _ = 1, 12 do
		local hit = workspace:Raycast(p + Vector3.new(0, 80, 0), Vector3.new(0, -120, 0), params)
		if hit and hit.Position.Y <= Config.GROUND_Y + 1.5 then
			return Vector3.new(p.X, hit.Position.Y, p.Z)
		end
		p = Halloween.spot(roll)
	end
	return p
end

local function spawnPiece()
	local position = groundSpot()
	table.insert(pieces, { model = place(position), position = position })
end

local function collect(i: number, s: Sessions.Session)
	local piece = table.remove(pieces, i) :: Piece
	piece.model:Destroy()
	s.profile.candy = math.min(s.profile.candy + Halloween.CANDY_VALUE, Halloween.CANDY_MAX)
	Sessions.push(s.player, { candy = s.profile.candy })
	Net.LootEvent:FireClient(s.player, "Candy", { position = piece.position })
end

local function clearAll()
	for _, piece in pieces do
		piece.model:Destroy()
	end
	table.clear(pieces)
end

local function check()
	if not Halloween.active(os.time()) then
		clearAll() -- (the event just ended: the candy goes)
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
	task.spawn(function()
		if not Assets.get("Candy") then
			template = loadTemplate()
		end
		for _ = 1, Halloween.CANDY_START do
			spawnPiece()
		end
		-- one more every CANDY_EVERY seconds while there's room
		while Halloween.active(os.time()) do
			task.wait(Halloween.CANDY_EVERY)
			if #pieces < Halloween.CANDY_ON_MAP and Halloween.active(os.time()) then
				local ok, err = pcall(spawnPiece)
				if not ok then
					warn("[CandyService]", err)
				end
			end
		end
	end)
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
