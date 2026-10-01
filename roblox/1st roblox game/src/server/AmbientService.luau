-- Day/night lighting (the phase itself is derived from the clock in Config, so the client's timer
-- needs no remote) and an in-world "Fastest in this server" board at the corridor mouth.
--
-- Lighting blends between a bright, saturated DAY look and a blue, still-readable NIGHT look by
-- Config.nightBlend, so night never collapses into grey and dusk/dawn fade instead of snapping.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sessions = require(script.Parent:WaitForChild("Sessions"))

local AmbientService = {}

local ROWS = Config.MAX_PLAYERS

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- property -> { day, night } per instance
type Look = { [string]: { any } }
local LIGHTING: Look = {
	Brightness = { 3, 1.8 },
	Ambient = { rgb(120, 115, 128), rgb(90, 98, 165) },
	OutdoorAmbient = { rgb(153, 153, 163), rgb(112, 124, 196) },
	ColorShift_Top = { rgb(255, 237, 204), rgb(140, 165, 255) },
	ColorShift_Bottom = { rgb(90, 115, 153), rgb(60, 50, 120) },
	ExposureCompensation = { 0.1, 0.45 },
	EnvironmentDiffuseScale = { 1, 0.75 },
}
local EFFECTS: { [string]: Look } = {
	Atmosphere = {
		Density = { 0.26, 0.3 },
		Color = { rgb(199, 224, 255), rgb(72, 84, 155) },
		Decay = { rgb(115, 153, 204), rgb(40, 40, 95) },
		Glare = { 0.15, 0 },
	},
	ColorCorrectionEffect = {
		TintColor = { rgb(255, 250, 242), rgb(205, 215, 255) },
		Saturation = { 0.22, 0.3 },
		Brightness = { 0.02, 0.05 },
	},
	BloomEffect = {
		Intensity = { 0.6, 0.95 },
	},
	SunRaysEffect = {
		Intensity = { 0.06, 0 },
	},
}

local function lerp(a: any, b: any, t: number): any
	if typeof(a) == "Color3" then
		return (a :: Color3):Lerp(b, t)
	end
	return a + (b - a) * t
end

local function applyLook(inst: Instance, look: Look, t: number)
	for prop, pair in look do
		(inst :: any)[prop] = lerp(pair[1], pair[2], t)
	end
end

-- The place file ships these under Lighting (default.project.json); create any that are missing.
local function ensureEffects(): { [string]: Instance }
	local out = {}
	for className in EFFECTS do
		local inst = Lighting:FindFirstChildOfClass(className :: any)
		if not inst then
			inst = Instance.new(className :: any)
			inst.Parent = Lighting
		end
		out[className] = inst :: Instance
	end
	if not Lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.StarCount = 3000
		sky.MoonAngularSize = 14
		sky.Parent = Lighting
	end
	return out
end

function AmbientService.applyLighting(now: number, effects: { [string]: Instance })
	local night, left = Config.dayPhase(now)
	-- Day maps to 06:00-18:00, night to 18:00-06:00 (the moon is up all night).
	if night then
		local p = 1 - left / Config.NIGHT_SECONDS
		Lighting.ClockTime = (18 + 12 * p) % 24
	else
		local p = 1 - left / Config.DAY_SECONDS
		Lighting.ClockTime = 6 + 12 * p
	end
	local t = Config.nightBlend(now)
	applyLook(Lighting, LIGHTING, t)
	for className, look in EFFECTS do
		applyLook(effects[className], look, t)
	end
end

local function buildBoard(): { TextLabel }
	local board = Instance.new("Part")
	board.Name = "Leaderboard"
	board.Anchored = true
	board.Size = Vector3.new(24, 20, 1)
	local pos = Vector3.new(Config.CORRIDOR_START_X - 30, Config.GROUND_Y + 14, 26)
	board.CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1))
	board.Color = Color3.fromRGB(40, 40, 70)
	board.Material = Enum.Material.SmoothPlastic
	board.Parent = workspace:WaitForChild("World")

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = board
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = gui

	local function row(order: number, text: string, color: Color3): TextLabel
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 1 / (ROWS + 1), 0)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = text
		label.LayoutOrder = order
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = label
		label.Parent = gui
		return label
	end
	row(0, "⚡ FASTEST HERE ⚡", Color3.fromRGB(255, 220, 80))
	local rows = {}
	for i = 1, ROWS do
		rows[i] = row(i, "", Color3.new(1, 1, 1))
	end
	return rows
end

function AmbientService.start()
	local effects = ensureEffects()
	local rows = buildBoard()
	local wasNight: boolean? = nil
	task.spawn(function()
		local tick = 0
		while true do
			local t = workspace:GetServerTimeNow()
			local night = Config.dayPhase(t)
			AmbientService.applyLighting(t, effects)
			if wasNight ~= nil and night ~= wasNight then
				for _, player in Players:GetPlayers() do
					Net.LootEvent:FireClient(player, "DayNight", { night = night })
				end
			end
			wasNight = night

			tick += 1
			if tick % 5 == 0 then
				local ranked = {}
				for player, s in Sessions.all() do
					table.insert(ranked, { name = player.DisplayName, speed = s.profile.speed, done = s.profile.reachedEnd })
				end
				table.sort(ranked, function(a, b)
					return a.speed > b.speed
				end)
				for i = 1, ROWS do
					local r = ranked[i]
					rows[i].Text = if r then `{i}. {r.name}  {Format.short(r.speed)}{if r.done then " ⛩️" else ""}` else ""
				end
			end
			task.wait(1)
		end
	end)
end

return AmbientService
