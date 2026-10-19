-- The Halloween candy on the map (Server/CandyService, tagged "HalloweenCandy") turns slowly and bobs up and
-- down, so it catches the eye. Only on this client, and only the pieces near the camera.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "HalloweenCandy"
local NEAR = 260 -- studs from the camera: farther pieces stay still
local TURN = 1.6 -- radians a second
local BOB = 0.4 -- studs up and down
local BOB_SPEED = 2.4

local homes: { [Model]: CFrame } = {}

local function add(model: Instance)
	if model:IsA("Model") then
		homes[model] = model:GetPivot()
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(model: Instance)
	homes[model :: Model] = nil
end)
for _, model in CollectionService:GetTagged(TAG) do
	add(model)
end

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local t = os.clock()
	for model, home in homes do
		if model.Parent and (home.Position - eye).Magnitude < NEAR then
			local phase = home.Position.X * 0.37 + home.Position.Z * 0.21 -- (each piece a little out of step)
			model:PivotTo(home * CFrame.new(0, BOB * (1 + math.sin(t * BOB_SPEED + phase)), 0) * CFrame.Angles(0, t * TURN + phase, 0))
		end
	end
end)
