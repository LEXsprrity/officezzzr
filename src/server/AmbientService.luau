-- Day/night lighting (the phase itself is derived from the clock in Config, so the client's timer
-- needs no remote) and an in-world "Fastest in this server" board at the corridor mouth.
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

local function buildBoard(): { TextLabel }
	local board = Instance.new("Part")
	board.Name = "Leaderboard"
	board.Anchored = true
	board.Size = Vector3.new(24, 20, 1)
	local pos = Vector3.new(Config.CORRIDOR_START_X - 30, Config.GROUND_Y + 14, 26)
	board.CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1))
	board.Color = Color3.fromRGB(40, 40, 60)
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
	local rows = buildBoard()
	local wasNight: boolean? = nil
	task.spawn(function()
		local tick = 0
		while true do
			local t = workspace:GetServerTimeNow()
			local night, left = Config.dayPhase(t)
			-- Day maps to 06:00-18:00, night to 18:00-06:00.
			if night then
				local p = 1 - left / Config.NIGHT_SECONDS
				Lighting.ClockTime = (18 + 12 * p) % 24
			else
				local p = 1 - left / Config.DAY_SECONDS
				Lighting.ClockTime = 6 + 12 * p
			end
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
