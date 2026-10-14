-- Each plot's treadmill visuals, built at runtime around whatever belt the map has (so they follow the
-- treadmill wherever it is moved): an "Upgrade" board beside it (a chunky dark navy sign on a post, like
-- the plot's Upgrade board: "Level X > Level Y", a red button with the money price and a purple one with
-- the Robux price) and a small "+X/step" text floating over the belt's front end. The map's old
-- "TREADMILL" billboard is switched off. PlotService writes them and owns the board's prompts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local Icons = require(Shared:WaitForChild("Icons"))
local Treadmill = require(Shared:WaitForChild("Treadmill"))
local Config = require(Shared:WaitForChild("Config"))
local Props = require(script.Parent:WaitForChild("Props"))
local Assets = require(script.Parent:WaitForChild("Assets"))

local TreadmillBoard = {}

export type Labels = { level: TextLabel, cash: TextLabel, robux: TextLabel, buttons: Frame }
export type Board = {
	model: Model,
	panel: BasePart, -- the board with the text; PlotService puts the prompts on it
	labels: Labels,
	stepGui: BillboardGui,
	stepLabel: TextLabel,
	plot: Model,
	belt: BasePart,
	center: Vector3,
}
-- What the board shows: the owner's tier (nil: nobody owns the plot), the next tier's prices, and what
-- one step on the belt pays the owner right now.
export type View = { tier: number?, cash: number?, robux: number?, perStep: number? }

local NAVY = Color3.fromRGB(30, 36, 60)
local CORNER = Color3.fromRGB(44, 54, 92)
local POST = Color3.fromRGB(24, 29, 50)
local RIM = 0.8 -- the frame's width
local PPS = 50 -- SurfaceGui pixels per stud
local TEXT = {
	open = Color3.fromRGB(110, 240, 70), -- "Level 6 > Level 7"
	max = Color3.fromRGB(255, 210, 60), -- "MAX"
	empty = Color3.fromRGB(190, 195, 210), -- nobody owns the plot
}
local BUTTONS = {
	{ name = "Cash", fill = Color3.fromRGB(225, 40, 40), edge = Color3.fromRGB(90, 10, 10), width = 0.58 },
	{ name = "Robux", fill = Color3.fromRGB(165, 45, 230), edge = Color3.fromRGB(55, 10, 80), width = 0.38 },
}
local STEP_COLOR = Color3.fromRGB(196, 168, 255) -- light purple, dark outline (owner's reference)

-- The classic studded plastic look on the given faces.
local function studs(p: BasePart, faces: { string }): BasePart
	p.Material = Enum.Material.Plastic
	for _, face in faces do
		(p :: any)[face] = Enum.SurfaceType.Studs
	end
	return p
end

local function text(parent: Instance, name: string, value: string, color: Color3, size: UDim2, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = value
	label.TextColor3 = color
	label.LayoutOrder = order
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(15, 15, 25)
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function list(parent: Instance, direction: Enum.FillDirection, gap: number)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(gap, 0)
	layout.Parent = parent
end

-- The panel's SurfaceGui: "Upgrade", "Level X > Level Y" and the row of two buttons.
local function buildGui(panel: BasePart): Labels
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PPS
	gui.LightInfluence = 0
	gui.MaxDistance = 60
	gui.Parent = panel
	local inset = UDim.new(0, math.round((RIM + 0.15) * PPS))
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = inset
	padding.PaddingRight = inset
	padding.PaddingTop = inset
	padding.PaddingBottom = inset
	padding.Parent = gui
	list(gui, Enum.FillDirection.Vertical, 0.03)
	text(gui, "Title", "Upgrade", Color3.new(1, 1, 1), UDim2.fromScale(1, 0.3), 1)
	local level = text(gui, "Level", "Empty plot", TEXT.empty, UDim2.fromScale(1, 0.22), 2)
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 0.4)
	row.LayoutOrder = 3
	row.Visible = false
	row.Parent = gui
	list(row, Enum.FillDirection.Horizontal, 0.04)
	local labels = {}
	for i, spec in BUTTONS do
		local button = Instance.new("Frame")
		button.Name = spec.name .. "Button"
		button.BackgroundColor3 = spec.fill
		button.Size = UDim2.fromScale(spec.width, 1)
		button.LayoutOrder = i
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button
		local edge = Instance.new("UIStroke")
		edge.Thickness = 3
		edge.Color = spec.edge
		edge.Parent = button
		local shine = Instance.new("UIGradient") -- a little lighter at the top, like a raised button
		shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
		shine.Rotation = 90
		shine.Parent = button
		local label = text(button, spec.name, "", Color3.new(1, 1, 1), UDim2.fromScale(0.88, 0.78), 1)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		labels[spec.name] = label
		button.Parent = row
	end
	return { level = level, cash = labels.Cash, robux = labels.Robux, buttons = row }
end

-- The frame, corner blocks and post around a panel at `cf` (built in the panel's own space, so a pivot
-- moves them together).
local function buildFrame(model: Model, cf: CFrame)
	local w, h = Treadmill.BOARD_SIZE.X, Treadmill.BOARD_SIZE.Y
	local front = cf * CFrame.new(0, 0, -0.15) -- the frame stands a little proud of the panel
	for _, s in { -1, 1 } do
		studs(Props.deco(model, "BoardFrame", Vector3.new(w, RIM, 1), front * CFrame.new(0, s * (h - RIM) / 2, 0), NAVY), { "FrontSurface", "TopSurface" })
		studs(Props.deco(model, "BoardFrame", Vector3.new(RIM, h - 2 * RIM, 1), front * CFrame.new(s * (w - RIM) / 2, 0, 0), NAVY), { "FrontSurface" })
		for _, t in { -1, 1 } do
			studs(Props.deco(model, "BoardCorner", Vector3.new(RIM + 0.2, RIM + 0.2, 1.15), front * CFrame.new(s * (w - RIM) / 2, t * (h - RIM) / 2, 0), CORNER), { "FrontSurface", "TopSurface" })
		end
	end
	local postHeight = Treadmill.BOARD_LIFT + 0.2
	studs(Props.deco(model, "BoardPost", Vector3.new(1.4, postHeight, 1), cf * CFrame.new(0, -(h / 2 + postHeight / 2 - 0.2), 0.05), POST), { "FrontSurface" })
end

-- The ground the treadmill stands on: the bottom of its frame or model (the plot's "Treadmill" group), or
-- the belt's bottom.
local function groundOf(model: Model, belt: BasePart): number
	local tm = model:FindFirstChild("Treadmill")
	local lo = if tm then Assets.bounds(tm) else nil
	if lo then
		return lo.Y
	end
	return belt.CFrame.Position.Y - belt.Size.Y / 2
end

-- How far the treadmill (its model, if the plot has one) reaches past the belt's centre along the belt.
local function clearAlong(model: Model, belt: BasePart): number?
	local tm = model:FindFirstChild("Treadmill")
	if not tm then
		return nil
	end
	local lo, hi = Assets.bounds(tm, belt.CFrame)
	if not lo or not hi then
		return nil
	end
	local long = if belt.Size.Z >= belt.Size.X then math.max(math.abs(lo.Z), math.abs(hi.Z)) else math.max(math.abs(lo.X), math.abs(hi.X))
	return math.max(long, math.max(belt.Size.X, belt.Size.Z) / 2)
end

-- Where the board goes for this plot's belt right now: in line with the treadmill, past its back end.
function TreadmillBoard.placement(model: Model, belt: BasePart, center: Vector3): CFrame
	return Treadmill.boardCFrame(belt.CFrame, belt.Size, center, groundOf(model, belt), clearAlong(model, belt))
end

-- Builds the board and the "+X/step" text for one plot (`model` the plot Model, `center` its centre),
-- and switches off the map's "TREADMILL" billboard (`oldLabel`, the label WorldBuilder made over the belt).
function TreadmillBoard.build(model: Model, belt: BasePart, center: Vector3, oldLabel: TextLabel?): Board
	local old = oldLabel and oldLabel:FindFirstAncestorWhichIsA("BillboardGui")
	if old then
		old.Enabled = false
	end
	local oldBoard, oldAnchor = model:FindFirstChild("TreadmillBoard"), belt:FindFirstChild("StepTextAnchor")
	if oldBoard then
		oldBoard:Destroy()
	end
	if oldAnchor then
		oldAnchor:Destroy()
	end

	local boardModel = Instance.new("Model")
	boardModel.Name = "TreadmillBoard"
	local cf = TreadmillBoard.placement(model, belt, center)
	local panel = studs(Props.deco(boardModel, "Panel", Vector3.new(Treadmill.BOARD_SIZE.X, Treadmill.BOARD_SIZE.Y, 0.6), cf, NAVY), { "BackSurface" })
	panel:SetAttribute("Role", "TreadmillBoard")
	panel:SetAttribute("PlotIndex", model:GetAttribute("PlotIndex"))
	boardModel.PrimaryPart = panel
	buildFrame(boardModel, cf)
	local labels = buildGui(panel)
	boardModel.Parent = model

	-- "+X/step" over the front end of the belt, on an attachment that follows it.
	local anchor = Instance.new("Attachment")
	anchor.Name = "StepTextAnchor"
	anchor.Position = Treadmill.stepTextOffset(belt.Size)
	anchor.Parent = belt
	local gui = Instance.new("BillboardGui")
	gui.Name = "StepText"
	gui.Size = UDim2.fromScale(7, 1.8) -- studs: small, it shrinks with distance
	gui.LightInfluence = 0
	gui.MaxDistance = 70
	gui.Adornee = anchor
	gui.Enabled = false
	gui.Parent = anchor
	local stepLabel = Instance.new("TextLabel")
	stepLabel.Name = "PerStep"
	stepLabel.BackgroundTransparency = 1
	stepLabel.Size = UDim2.fromScale(1, 1)
	stepLabel.Font = Enum.Font.FredokaOne
	stepLabel.TextScaled = true
	stepLabel.TextColor3 = STEP_COLOR
	stepLabel.Text = ""
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(30, 20, 60)
	stroke.Parent = stepLabel
	stepLabel.Parent = gui

	return {
		model = boardModel,
		panel = panel,
		labels = labels,
		stepGui = gui,
		stepLabel = stepLabel,
		plot = model,
		belt = belt,
		center = center,
	}
end

-- Puts the board and the step text back beside the belt after the belt moved or was resized (PlotService
-- calls it when the belt's CFrame or Size changes).
function TreadmillBoard.follow(board: Board)
	local to = TreadmillBoard.placement(board.plot, board.belt, board.center)
	local move = to * board.panel.CFrame:Inverse()
	for _, d in board.model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = move * d.CFrame
		end
	end
	local anchor = board.stepGui.Adornee :: Attachment
	anchor.Position = Treadmill.stepTextOffset(board.belt.Size)
end

-- Writes the board and the "+X/step" text. Below the last tier: "Level X > Level Y" and both buttons
-- (the red one with the money price and the Treadmill icon, the purple one with the Robux icon); at the
-- last tier "MAX" and no buttons; with no owner "Empty plot", no buttons and no step text.
function TreadmillBoard.render(board: Board, view: View)
	local line, kind = Treadmill.boardText(view.tier)
	local labels = board.labels
	labels.level.Text = line
	labels.level.TextColor3 = TEXT[kind]
	local open = kind == "open" and view.cash ~= nil
	labels.buttons.Visible = open
	if open then
		Icons.set(labels.cash, "Treadmill", Format.money(view.cash :: number), 0.8)
		Icons.set(labels.robux, "Robux", if view.robux then Format.robux(view.robux) else "R$ ?", 0.8)
	else
		Icons.set(labels.cash, {}, "")
		Icons.set(labels.robux, {}, "")
	end
	board.stepGui.Enabled = view.perStep ~= nil
	board.stepLabel.Text = if view.perStep then Treadmill.gainText(view.perStep) .. "/step" else ""
end

return TreadmillBoard
