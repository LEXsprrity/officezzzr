-- 3D pictures for the HUD's cards (client): a flower from ReplicatedStorage.FlowerPreviews
-- (Server/FlowerPreviews: <zone>/<rarity>/<model name>) or a seed design from ReplicatedStorage.SeedLooks
-- (Server/SeedService.publishLooks: <zone>/<design>), cloned into a ViewportFrame with its own camera at a
-- 3/4 angle, fitted to the frame. A spinning picture turns slowly, and only while it is on screen (its GUI
-- shown and not scrolled or clipped out): one shared loop, ~30 times a second, turns the camera and the light
-- together so the flower stays lit from the front. A silhouette (an undiscovered Index flower) is the model
-- in flat black, never spinning. Pictures go when their card is destroyed (the HUD rebuilds cards only when
-- what they list changed).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(script.Parent:WaitForChild("Config"))
local Halloween = require(script.Parent:WaitForChild("Halloween"))

local FlowerView = {}

FlowerView.FOLDER = "FlowerPreviews"
FlowerView.SEEDS = "SeedLooks"
FlowerView.FALLBACK = "Creature" -- a zone or rarity without plant models (Server/FlowerPreviews.FALLBACK)
FlowerView.FOV = 30
FlowerView.SPIN = math.rad(40) -- radians a second
FlowerView.TILT = math.rad(18) -- the camera looks down this much
FlowerView.ANGLE = math.rad(-35) -- the resting 3/4 turn (the flowers face -Z)

-- The Haunted copies of the previews (Halloween.hauntify, the look the server gives a Haunted plant), made once.
local hauntedCopies: { [Model]: Model } = setmetatable({}, { __mode = "k" }) :: any

-- The preview of flower `flower` (a plant model's name; nil: FALLBACK) of (zone, rarity), or nil while it
-- hasn't replicated (or doesn't exist). With `mutation` Haunted: in its Haunted look (a copy of it).
function FlowerView.flower(zone: number, rarity: number, flower: string?, mutation: string?): Model?
	local root = ReplicatedStorage:FindFirstChild(FlowerView.FOLDER)
	local zoneFolder = root and root:FindFirstChild(tostring(zone))
	local rarityFolder = zoneFolder and zoneFolder:FindFirstChild(tostring(rarity))
	local model = rarityFolder and (rarityFolder:FindFirstChild(flower or FlowerView.FALLBACK) or rarityFolder:FindFirstChild(FlowerView.FALLBACK))
	if not (model and model:IsA("Model")) then
		return nil
	end
	if mutation == Halloween.MUTATION then
		local copy = hauntedCopies[model]
		if not copy then
			copy = model:Clone()
			Halloween.hauntify(copy)
			hauntedCopies[model] = copy
		end
		return copy
	end
	return model
end

-- The seed design a seed of `zone` with this gene looks like (like the hotbar's seed slot), or nil.
function FlowerView.seed(zone: number, gene: number?): Model?
	local root = ReplicatedStorage:FindFirstChild(FlowerView.SEEDS)
	local zoneFolder = root and root:FindFirstChild(tostring(zone))
	if not zoneFolder then
		return nil
	end
	local model = zoneFolder:FindFirstChild(tostring(Config.geneDesign(gene, #zoneFolder:GetChildren())))
	return if model and model:IsA("Model") then model else nil
end

-- (radius, height) of a picture: the preview's own measures, else its bounding box, else a seed's box.
local function measures(model: Model): (number, number)
	local radius, height = model:GetAttribute("ViewRadius"), model:GetAttribute("ViewHeight")
	if type(radius) == "number" and type(height) == "number" and height > 0 then
		return radius, height
	end
	local ok, box, size = pcall(function()
		local cf, s = model:GetBoundingBox()
		return cf, s
	end)
	if ok and box and size then
		return math.max(size.X, size.Z) / 2, box.Position.Y + size.Y / 2
	end
	return 1.5, 3
end

type View = { frame: ViewportFrame, camera: Camera, focus: Vector3, distance: number, angle: number }
local spinning: { View } = {}
local loop: RBXScriptConnection? = nil

local function aim(v: View)
	local turn = CFrame.Angles(0, v.angle, 0)
	local offset = turn * (CFrame.Angles(FlowerView.TILT, 0, 0) * Vector3.new(0, 0, -v.distance))
	v.camera.CFrame = CFrame.lookAt(v.focus + offset, v.focus)
	v.frame.LightDirection = turn * Vector3.new(-0.6, -1, 0.8) -- from over the camera's shoulder
end

-- Whether `frame` can be seen: every GUI above it shown, inside every clipping frame above it (a scrolled
-- list), on an enabled ScreenGui.
function FlowerView.onScreen(frame: GuiObject): boolean
	local pos, size
	local node: Instance? = frame
	while node and node:IsA("GuiObject") do
		if not node.Visible then
			return false
		end
		if node ~= frame and node.ClipsDescendants then
			pos, size = pos or frame.AbsolutePosition, size or frame.AbsoluteSize
			local p, s = node.AbsolutePosition, node.AbsoluteSize
			if pos.X > p.X + s.X or pos.Y > p.Y + s.Y or pos.X + size.X < p.X or pos.Y + size.Y < p.Y then
				return false
			end
		end
		node = node.Parent
	end
	return node ~= nil and node:IsA("LayerCollector") and node.Enabled
end

local function startLoop()
	if loop then
		return
	end
	local acc = 0
	loop = game:GetService("RunService").RenderStepped:Connect(function(dt: number)
		acc += dt
		if acc < 1 / 30 then
			return
		end
		local step = acc
		acc = 0
		for i = #spinning, 1, -1 do
			local v = spinning[i]
			if not v.frame:FindFirstAncestorWhichIsA("LayerCollector") then -- its card is gone (destroyed or taken off the GUI)
				table.remove(spinning, i)
			elseif FlowerView.onScreen(v.frame) then
				v.angle += FlowerView.SPIN * step
				aim(v)
			end
		end
		if #spinning == 0 and loop then
			loop:Disconnect()
			loop = nil
		end
	end)
end

export type Options = {
	size: UDim2?,
	position: UDim2?,
	anchor: Vector2?,
	zindex: number?,
	spin: boolean?, -- turn slowly while on screen
	silhouette: boolean?, -- flat black (an undiscovered flower)
	zoom: number?, -- >1 fills more of the frame
}

-- A ViewportFrame named "FlowerView" in `parent` showing a clone of `template` (nil: an empty frame, so a
-- card keeps its layout while the previews replicate). Returns it.
function FlowerView.show(parent: Instance, template: Model?, options: Options?): ViewportFrame
	local o: Options = options or {}
	local frame = Instance.new("ViewportFrame")
	frame.Name = "FlowerView"
	frame.BackgroundTransparency = 1
	frame.Size = o.size or UDim2.fromScale(1, 1)
	frame.Position = o.position or UDim2.new()
	frame.AnchorPoint = o.anchor or Vector2.zero
	frame.ZIndex = o.zindex or 1
	frame.Ambient = Color3.fromRGB(170, 170, 180)
	frame.LightColor = Color3.fromRGB(255, 250, 240)
	if o.silhouette then
		frame.ImageColor3 = Color3.new(0, 0, 0)
		frame.Ambient = Color3.new(0, 0, 0)
		frame.LightColor = Color3.new(0, 0, 0)
		frame.ImageTransparency = 0.1
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = FlowerView.FOV
	camera.Parent = frame
	frame.CurrentCamera = camera
	if template then
		local model = template:Clone()
		model.Parent = frame
		local radius, height = measures(template)
		local half = height / 2
		local reach = math.sqrt(radius * radius + half * half) -- a sphere round the middle holds it all
		local distance = reach / math.sin(math.rad(FlowerView.FOV) / 2) / (o.zoom or 1.15)
		local view: View = { frame = frame, camera = camera, focus = Vector3.new(0, half, 0), distance = distance, angle = FlowerView.ANGLE }
		aim(view)
		if o.spin and not o.silhouette then
			table.insert(spinning, view)
			startLoop()
		end
	end
	frame.Parent = parent
	return frame
end

-- How many pictures are registered to spin (the tests; destroyed cards drop out on the next tick).
function FlowerView.spinCount(): number
	return #spinning
end

return FlowerView
