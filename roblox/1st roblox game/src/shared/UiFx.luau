--!strict
-- Shared UI juice for the client scripts (HUD, Rewards, DayTimer, Effects):
--   * UiFx.pop(button): the button inflates with a springy pop while the mouse is over it or a finger holds
--     it, squashes a little while the mouse holds it down, and springs back on release. A UIScale named
--     "Pop" does it; a button outside a layout is scaled about its centre (its AnchorPoint moves to the
--     centre while it is popped and back once it rests, so it never shifts).
--   * UiFx.worldPop(button, how): the same pop for a button painted on a board in the world (Effects).
--   * UiFx.watch(root): pop() on every button already under `root` and every one added later (the Shop's
--     cards are rebuilt on every render). A button with the attribute NoPop, or its own UIScale, is skipped.
--     A button with the number attribute PopScale inflates to that instead of HOVER: a long button beside
--     another one (the Shop's R$ button next to its gift button) pops less, so it never grows over it.
--   * UiFx.click / UiFx.clicks(button): a soft click sound on every button press (pop and watch hook it).
--   * UiFx.relief(label): text with relief instead of flat 2D: a bevel gradient (lighter top, darker
--     bottom), a thick round dark outline and a dark copy dropped behind it, like a raised sticker.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UiFx = {}

UiFx.HOVER = 1.1 -- hovered / held by a finger
UiFx.PRESS = 0.92 -- held down by the mouse

local GROW = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHRINK = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SQUASH = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SPRING = TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local CENTRE = Vector2.new(0.5, 0.5)

local INK = Color3.fromRGB(25, 25, 35)
local SHADOW = Color3.fromRGB(10, 10, 18)
local BEVEL = Color3.fromRGB(185, 188, 205) -- multiplies the text colour at the bottom

-- A soft click on every UI button press (owner 2026-10-20: "a sound every time you click ... shop, index,
-- ui stuff"): UiFx.pop and UiFx.watch hook each button once (attribute ClickSound), NoPop ones too. The
-- sound is Config.SOUNDS.Click's.
UiFx.CLICK_SOUND = "rbxassetid://" .. 15675059323 -- Roblox_UI_Bright_Click
UiFx.CLICK_VOLUME = 0.5
-- And a soft tick when the mouse moves onto a button (owner 2026-10-22: "Ui Hover"); Config.SOUNDS.Hover.
UiFx.HOVER_SOUND = "rbxassetid://" .. 10066931761 -- RBLX UI Hover 01
UiFx.HOVER_VOLUME = 0.3
UiFx.HOVER_GAP = 0.06 -- seconds: sweeping over a row of buttons doesn't rattle

local sounds: { [string]: Sound } = {}
local function playUi(name: string, id: string, volume: number): boolean
	return (pcall(function()
		local sound = sounds[name]
		if not sound then
			local s = Instance.new("Sound")
			s.Name = name
			s.SoundId = id
			s.Volume = volume
			s.Parent = game:GetService("SoundService")
			sounds[name] = s
			sound = s
		end
		game:GetService("SoundService"):PlayLocalSound(sound :: Sound)
	end))
end
function UiFx.click()
	return playUi("UiClick", UiFx.CLICK_SOUND, UiFx.CLICK_VOLUME)
end
local lastHover = 0
function UiFx.hover()
	local now = os.clock()
	if now - lastHover < UiFx.HOVER_GAP then
		return false
	end
	lastHover = now
	return playUi("UiHover", UiFx.HOVER_SOUND, UiFx.HOVER_VOLUME)
end
function UiFx.clicks(b: GuiButton)
	if typeof(b) ~= "Instance" or b:GetAttribute("ClickSound") then -- (tests pop stand-in tables)
		return
	end
	b:SetAttribute("ClickSound", true)
	pcall(function() -- (Lune, in the tests, has no events)
		b.Activated:Connect(function()
			UiFx.click()
		end)
	end)
end

-- Whether a layout places `g` (it ignores Position, so it can't be re-anchored to scale about its centre).
local function inLayout(g: GuiObject): boolean
	local parent = g.Parent
	return parent ~= nil and parent:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
end

-- Whether `g` is on screen: it and every GuiObject above it visible, inside an enabled ScreenGui.
local function shown(g: Instance): boolean
	local node: Instance? = g
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled and node.Parent ~= nil
		end
		node = node.Parent
	end
	return false
end

local function touching(): boolean
	return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

function UiFx.pop(b: GuiButton)
	UiFx.clicks(b)
	if b:GetAttribute("NoPop") or b:FindFirstChildWhichIsA("UIScale") then
		return
	end
	local scale = Instance.new("UIScale")
	scale.Name = "Pop"
	scale.Parent = b

	local hovered, pressed, held = false, false, false -- mouse over, mouse down, finger down
	local released = false -- the next change springs back from a press
	local current = 1
	local tween: Tween? = nil
	local watcher: RBXScriptConnection? = nil
	local saved: { anchor: Vector2, position: UDim2, centred: UDim2 }? = nil

	local function centre()
		if saved or b.AnchorPoint == CENTRE or inLayout(b) then
			return
		end
		local a, p, s = b.AnchorPoint, b.Position, b.Size
		local dx, dy = CENTRE.X - a.X, CENTRE.Y - a.Y
		local centred = p + UDim2.new(s.X.Scale * dx, s.X.Offset * dx, s.Y.Scale * dy, s.Y.Offset * dy)
		saved = { anchor = a, position = p, centred = centred }
		b.AnchorPoint = CENTRE
		b.Position = centred
	end
	local function uncentre()
		local s = saved
		if s then
			saved = nil
			if b.Position == s.centred then
				b.Position = s.position
			end -- else the script moved it meanwhile (in its own anchor's terms): keep that
			b.AnchorPoint = s.anchor
		end
	end
	local function rest()
		if watcher then
			watcher:Disconnect()
			watcher = nil
		end
		uncentre()
	end

	local update: () -> ()
	local function watch()
		if watcher then
			return
		end
		-- While popped: let go of a press released off the button, and snap back when it is hidden
		-- (a window closed under the mouse never sends MouseLeave).
		watcher = RunService.RenderStepped:Connect(function()
			if not shown(b) then
				hovered, pressed, held = false, false, false
				if tween then
					tween:Cancel()
					tween = nil
				end
				current = 1
				scale.Scale = 1
				rest()
			elseif pressed and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				pressed, released = false, true
				update()
			end
		end)
	end

	update = function()
		local own = b:GetAttribute("PopScale")
		local hover = if type(own) == "number" and own > 1 then own else UiFx.HOVER
		local goal = if held then hover elseif pressed then UiFx.PRESS elseif hovered then hover else 1
		if goal == current then
			return
		end
		local info = if goal == UiFx.PRESS then SQUASH elseif released then SPRING elseif goal > current then GROW else SHRINK
		released = false
		current = goal
		if goal ~= 1 then
			centre()
			watch()
		end
		if tween then
			tween:Cancel()
		end
		local t = TweenService:Create(scale, info, { Scale = goal })
		tween = t
		t.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and tween == t and current == 1 then
				tween = nil
				rest()
			end
		end)
		t:Play()
	end

	b.MouseEnter:Connect(function()
		if not touching() then -- a tap sends MouseEnter but no MouseLeave
			hovered = true
			UiFx.hover()
			update()
		end
	end)
	b.MouseLeave:Connect(function()
		hovered = false
		update()
	end)
	b.MouseButton1Down:Connect(function()
		if not touching() then
			pressed = true
			update()
		end
	end)
	b.MouseButton1Up:Connect(function()
		if pressed then
			pressed, released = false, true
			update()
		end
	end)
	b.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			held = true
			update()
		end
	end)
	b.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch and held then
			held, released = false, true
			update()
		end
	end)
end

-- A button painted on a board in the world (a SurfaceGui on a part gets no mouse events: a ClickDetector
-- over it calls this): "hover" inflates it with the same springy pop, "rest" shrinks it back, "press"
-- squashes it and springs back to the hover size. It grows its Size (it sits in a centred row layout, so
-- it grows about its centre); the size it had the first time is its rest size.
local worldBase: { [GuiObject]: UDim2 } = setmetatable({}, { __mode = "k" }) :: any
local worldTween: { [GuiObject]: Tween } = setmetatable({}, { __mode = "k" }) :: any
function UiFx.worldPop(g: GuiObject, how: "hover" | "rest" | "press")
	if how == "hover" then
		UiFx.hover()
	end
	local base = worldBase[g] or g.Size
	worldBase[g] = base
	local function sized(k: number): UDim2
		return UDim2.new(base.X.Scale * k, base.X.Offset * k, base.Y.Scale * k, base.Y.Offset * k)
	end
	local old = worldTween[g]
	if old then
		old:Cancel()
	end
	local tween
	if how == "press" then
		tween = TweenService:Create(g, SQUASH, { Size = sized(UiFx.PRESS) })
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and worldTween[g] == tween then
				local back = TweenService:Create(g, SPRING, { Size = sized(UiFx.HOVER) })
				worldTween[g] = back
				back:Play()
			end
		end)
	else
		tween = TweenService:Create(g, if how == "hover" then GROW else SHRINK, { Size = sized(if how == "hover" then UiFx.HOVER else 1) })
	end
	worldTween[g] = tween
	tween:Play()
end

function UiFx.watch(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") then
			UiFx.pop(d)
		end
	end
	root.DescendantAdded:Connect(function(d)
		if d:IsA("GuiButton") then
			-- after the script that made it has finished (it may still add NoPop or its own UIScale)
			task.defer(function()
				if d:IsDescendantOf(root) then
					UiFx.pop(d :: GuiButton)
				end
			end)
		end
	end)
end

-- Relief for `label` (free-positioned, not in a layout): returns the shadow copy, which follows the
-- label's text, visibility and placement. `depth`: how far the shadow drops, in pixels (default 3).
local MIRRORED = { "Text", "Visible", "TextTransparency", "Size", "AnchorPoint", "TextXAlignment", "TextYAlignment", "Rotation" }
-- Outlines and shadows are toned down (owner 2026-10-23: "the black around the words is too intense, and the
-- menu titles' shadow"): every outline at UiFx.OUTLINE of its asked thickness, the shadow half as deep and see-through.
UiFx.OUTLINE = 0.6
UiFx.SHADOW_FADE = 0.55

function UiFx.relief(label: TextLabel, depth: number?, outline: number?): TextLabel
	local d = math.max(1, math.ceil((depth or 3) / 2))
	local stroke = label:FindFirstChildWhichIsA("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Color = INK
		stroke.Parent = label
	end
	assert(stroke)
	stroke.Thickness = if outline then math.max(1.5, outline * UiFx.OUTLINE) else math.max(stroke.Thickness, 1.5)
	stroke.LineJoinMode = Enum.LineJoinMode.Round

	local shadow = label:Clone()
	shadow.Name = label.Name .. "Shadow"
	for _, c in shadow:GetChildren() do
		if not c:IsA("UIStroke") then
			c:Destroy()
		end
	end
	shadow.TextColor3 = SHADOW
	shadow.TextTransparency = UiFx.SHADOW_FADE
	local shadowStroke = shadow:FindFirstChildWhichIsA("UIStroke")
	if shadowStroke then
		shadowStroke.Color = SHADOW
		shadowStroke.Transparency = UiFx.SHADOW_FADE
	end
	local offset = UDim2.fromOffset(math.ceil(d / 3), d)
	shadow.Position = label.Position + offset
	shadow.ZIndex = label.ZIndex
	label.ZIndex += 1 -- in front of its shadow
	shadow.Parent = label.Parent

	for _, prop in MIRRORED do
		label:GetPropertyChangedSignal(prop):Connect(function()
			(shadow :: any)[prop] = (label :: any)[prop]
		end)
	end
	label:GetPropertyChangedSignal("Position"):Connect(function()
		shadow.Position = label.Position + offset
	end)
	label.Destroying:Connect(function()
		shadow:Destroy()
	end)

	-- the bevel: full colour on top, a shade darker at the bottom
	local bevel = Instance.new("UIGradient")
	bevel.Name = "Bevel"
	bevel.Rotation = 90
	bevel.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.45, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, BEVEL),
	})
	bevel.Parent = label
	return shadow
end

return UiFx
