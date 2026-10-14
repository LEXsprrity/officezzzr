-- The HUD: Speed levels (for the "LEVEL N!" pop-up), the Shop's small Speed products (+10K / +100K / +1M),
-- granted through the normal receipt path, and the layout: no level bar, only Shop and Index on the left.
local H = require("./harness")
local Config = H.shared("Config")
local Format = H.shared("Format")
local Shop = H.server("Shop")
local ProfileStore = H.server("ProfileStore")
local Sim = require("./progression_sim")

local NICE = { [1] = true, [1.5] = true, [2] = true, [2.5] = true, [3] = true, [4] = true, [5] = true, [7.5] = true }

local function mantissa(x: number): number
	local m = x / 10 ^ math.floor(math.log10(x))
	return math.round(m * 1000) / 1000
end

H.test("speed levels: level 1 at 0, strictly increasing, nice round thresholds", function()
	H.eq(Config.SPEED_LEVELS[1], 0)
	local level, start, nextAt = Config.speedLevel(0)
	H.eq(level, 1)
	H.eq(start, 0)
	H.eq(nextAt, Config.SPEED_LEVELS[2])
	for n = 2, #Config.SPEED_LEVELS + 12 do
		local t = Config.speedLevelThreshold(n)
		H.ok(t > Config.speedLevelThreshold(n - 1), `level {n} above level {n - 1}`)
		H.ok(NICE[mantissa(t)], `level {n} at {Format.short(t)} is a nice number`)
		H.ok(not string.find(Format.short(t), "%.%d%d"), `"{Format.short(t)}" reads short`)
	end
	-- past the table: 10B, 20B, 50B, 100B
	local n = #Config.SPEED_LEVELS
	H.eq(Config.speedLevelThreshold(n + 1), 10e9)
	H.eq(Config.speedLevelThreshold(n + 2), 20e9)
	H.eq(Config.speedLevelThreshold(n + 3), 50e9)
	H.eq(Config.speedLevelThreshold(n + 4), 100e9)
end)

H.test("speed levels: every zone's recommended Speed is a level; 25-30 levels to the Spirit Garden", function()
	for k, zone in Config.ZONES do
		local level, start = Config.speedLevel(zone.req)
		H.eq(start, zone.req, `{zone.name} starts a level`)
		if k > 1 then
			H.ok(Config.speedLevel(zone.req - 1) == level - 1, `{zone.name}: one Speed short is the level below`)
		end
	end
	local spirit = Config.speedLevel(Config.ZONES[#Config.ZONES].req)
	H.ok(spirit >= 25 and spirit <= 30, `level {spirit} at 5B`)
end)

H.test("speed levels: speedLevel is monotonic and consistent with its thresholds", function()
	local last = 0
	local speed = 0
	while speed < 1e15 do
		local level, start, nextAt = Config.speedLevel(speed)
		H.ok(level >= last, `monotonic at {speed}`)
		H.ok(start <= speed and speed < nextAt, `{speed} in [{start}, {nextAt})`)
		H.eq(start, Config.speedLevelThreshold(level))
		H.eq(nextAt, Config.speedLevelThreshold(level + 1))
		last = level
		speed = speed * 1.07 + 13
	end
	-- exactly on and just under each threshold
	for n = 2, #Config.SPEED_LEVELS + 9 do
		local t = Config.speedLevelThreshold(n)
		H.eq((Config.speedLevel(t)), n, `on {Format.short(t)}`)
		H.eq((Config.speedLevel(t * 0.999)), n - 1, `under {Format.short(t)}`)
	end
	-- garbage in, sane level out
	H.eq((Config.speedLevel(-5)), 1)
	H.eq((Config.speedLevel(0 / 0)), 1)
	local huge, hs, hn = Config.speedLevel(math.huge)
	H.ok(huge > 100 and hs < hn and hn < math.huge, "infinite Speed is clamped")
end)

H.test("speed levels: a free player levels up every few minutes early and keeps levelling up all game", function()
	local free = Sim.run()
	local spirit = Config.speedLevel(Config.ZONES[#Config.ZONES].req)
	H.ok(#free.levels >= spirit, "the free player reaches the Spirit Garden's level")
	H.ok(free.levels[2] <= 2 * 60, `level 2 at {Sim.clock(free.levels[2])}`)
	local gaps = {}
	for n = 2, spirit do
		local gap = free.levels[n] - free.levels[n - 1]
		table.insert(gaps, Sim.clock(gap))
		if free.levels[n] <= 30 * 60 then
			H.ok(gap <= 10 * 60, `level {n} came {Sim.clock(gap)} after the last (first half hour)`)
		end
		H.ok(gap <= 75 * 60, `level {n} came {Sim.clock(gap)} after the last`)
	end
	print("        free player's level gaps: " .. table.concat(gaps, ", "))
end)

H.test("level up: no pop-up on the first stats, one per new level, the highest when several at once", function()
	local best, show = Config.levelUp(nil, 12)
	H.eq(best, 12)
	H.eq(show, nil, "joining at level 12 isn't a level-up")
	best, show = Config.levelUp(best, 12)
	H.eq(show, nil, "same level")
	best, show = Config.levelUp(best, 13)
	H.eq(show, 13)
	best, show = Config.levelUp(best, 18) -- a Speed pack jumps five levels
	H.eq(show, 18, "only the highest")
	H.eq(best, 18)
	best, show = Config.levelUp(best, 17)
	H.eq(show, nil, "never announces going down")
	H.eq(best, 18, "keeps the best")
	best, show = Config.levelUp(best, 18)
	H.eq(show, nil, "nor coming back to a level already announced")
end)

H.test("Speed packs: Speed10K, Speed100K and Speed1M are id = 0 Speed products, coming soon until set", function()
	local p = ProfileStore.defaultProfile()
	for name, want in { Speed10K = { 10e3, 9 }, Speed100K = { 100e3, 36 }, Speed1M = { 1e6, 76 } } do
		local product = Config.DEVELOPER_PRODUCTS[name]
		H.ok(product ~= nil, name)
		H.eq(product.kind, "Speed", name)
		H.eq(product.amount, want[1], name)
		H.eq(product.robux, want[2], name)
		H.eq(product.id, 0, name .. " ships as a stub")
		local ok, why = Shop.canPrompt(p, name)
		H.eq(ok, nil)
		H.ok(why and string.find(why, "coming soon"), why)
	end
end)

H.test("Speed packs: each grants its Speed exactly once per receipt", function()
	local p = ProfileStore.defaultProfile()
	local function never(): number
		error("Speed packs don't roll")
	end
	local saves = 0
	local function save(): boolean
		saves += 1
		return true
	end
	local total = 0
	for i, c in { { "Speed10K", 10e3 }, { "Speed100K", 100e3 }, { "Speed1M", 1e6 } } do
		total += c[2]
		local confirm, status, grant = Shop.processReceipt(p, c[1], "q" .. i, 0, never, save)
		H.eq(confirm, true)
		H.eq(status, "granted")
		H.eq(grant.label, Config.DEVELOPER_PRODUCTS[c[1]].label)
		H.eq(p.speed, total, c[1])
		local again, dup = Shop.processReceipt(p, c[1], "q" .. i, 0, never, save)
		H.eq(again, true, "a retried receipt is confirmed...")
		H.eq(dup, "duplicate")
		H.eq(p.speed, total, "...but not granted twice")
	end
	H.eq(p.money, 0)
	H.eq(saves, 6)
end)

----------------------------------------------------------------------------------------------------
-- The HUD's layout (from the source: Lune can't run a LocalScript)
----------------------------------------------------------------------------------------------------
local fs = require("@lune/fs")
local HUD = fs.readFile("src/client/HUD.client.luau")
local REWARDS = fs.readFile("src/client/Rewards.client.luau")

H.test("HUD: no level bar and no quick-buy buttons; bottom left is just Speed and money", function()
	for _, gone in { "levelPanel", "levelBar", "levelFill", "QUICK_BUY", "quickRow", "quickPrices", "refreshQuickBuy", "levelMultLabel" } do
		H.ok(not string.find(HUD, gone, 1, true), `"{gone}" is gone from the HUD`)
	end
	H.ok(string.find(HUD, "local speedValue", 1, true) and string.find(HUD, "local moneyValue", 1, true), "the Speed and money readouts stay")
	H.ok(string.find(HUD, "announceLevel(announce)", 1, true), `"LEVEL N!" still pops up`)
end)

H.test("HUD: the left column has only Shop and Index (and Slow Mode); Trails opens from its stall", function()
	local buttons = {}
	for name in string.gmatch(HUD, "\nsideButton%(%d+, \"(%w+)\"") do
		table.insert(buttons, name)
	end
	H.eq(table.concat(buttons, ","), "Shop,Index")
	H.ok(string.find(HUD, "Name = \"SlowMode\"", 1, true), "the Slow Mode switch")
	H.ok(string.find(HUD, "opens == \"Trails\"", 1, true), "the TRAIL SHOP stall still opens the Trail Shop")
	H.ok(not string.find(REWARDS, "LeftColumn", 1, true), "Rewards.client adds no Gift button to the column")
	H.ok(string.find(REWARDS, "GetAttribute(\"FreeGift\")", 1, true), "the gift box's prompt opens the Free Gift window")
end)

H.test("Shop: bright cards with light rays, green R$ buttons, no filler text or SOON tags", function()
	H.ok(not string.find(HUD, "Added to your Speed right away", 1, true), "no filler line on the Speed cards")
	H.ok(not string.find(HUD, "\"SOON\"", 1, true) and not string.find(HUD, "soonTag", 1, true), "no SOON tags on the prices")
	H.ok(string.find(HUD, "local function sunburst", 1, true), "the cards' sunburst")
	H.ok(string.find(HUD, "Speed = Color3.fromRGB(30, 165, 255)", 1, true), "Speed cards blue")
	H.ok(string.find(HUD, "Money = Color3.fromRGB(70, 205, 30)", 1, true), "Money cards green")
	H.ok(string.find(HUD, "ROBUX_GREEN = Color3.fromRGB(105, 235, 25)", 1, true), "bright green R$ buttons")
	-- every Speed product's label splits into the green number and the word ("+150K" / "SPEED")
	for _, entry in Config.products("Speed") do
		local amount, rest = string.match(string.upper(entry.product.label), "^(%S+)%s+(.+)$")
		H.ok(amount and string.sub(amount, 1, 1) == "+" and rest == "SPEED", entry.product.label)
	end
end)

H.test("HUD: no zone / recommended-Speed banner at the top; the carry banner takes its place", function()
	for _, gone in { "zoneBanner", "zoneLabel", "lastZone", "zoneAtX" } do
		H.ok(not string.find(HUD, gone, 1, true), `"{gone}" is gone from the HUD`)
	end
	H.ok(not string.find(HUD, "string.upper(z.name)", 1, true), "no \"SNOW PEAKS · Rec. Speed\" text")
	local carry = string.match(HUD, "local carryBanner = new%(\"Frame\", (%b{})")
	H.ok(carry and string.find(carry, "Position = UDim2.new(0.5, 0, 0, 8)", 1, true), "the carry banner sits at the top")
end)

H.test("HUD: Shop / Index / Slow Mode are centred on the left edge; Speed and money stay bottom-left", function()
	local column = string.match(HUD, "local leftColumn = new%(\"Frame\", (%b{})")
	H.ok(column and string.find(column, "AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0)", 1, true), "anchored at the middle")
	local layout = string.match(HUD, "local leftColumn = new%(\"Frame\", %b{}, (%b{})")
	H.ok(layout and string.find(layout, "VerticalAlignment.Center", 1, true), "its buttons centred in it")
	local statsFrame = string.match(HUD, "local statsFrame = new%(\"Frame\", (%b{})")
	H.ok(statsFrame and string.find(statsFrame, "AnchorPoint = Vector2.new(0, 1)", 1, true), "Speed and money at the bottom")
	H.ok(string.find(HUD, "height / 2 - STATS_BOTTOM - STATS_H", 1, true), "the column shrinks before it reaches them")
end)

H.test("HUD: bright windows: the modal body takes the bar's colours, no dark slate", function()
	for _, gone in { "BODY_COLOR", "SELL_DARK", "Color3.fromRGB(44, 50, 66)", "Color3.fromRGB(52, 58, 76)", "Color3.fromRGB(28, 24, 46)" } do
		H.ok(not string.find(HUD, gone, 1, true), `"{gone}" is gone from the HUD`)
	end
	H.ok(string.find(HUD, "modal.BackgroundColor3 = window.from:Lerp(window.to, 0.5):Lerp(WHITE, 0.25)", 1, true), "tinted per window")
	H.ok(not string.find(REWARDS, "Color3.fromRGB(44, 50, 66)", 1, true), "the Free Gift window is bright too")
end)

H.test("ZoneBanner.client: entering a zone flashes its name and a face for ~2 s (from Config.zoneAtX)", function()
	H.ok(fs.isFile("src/client/ZoneBanner.client.luau"), "the script exists")
	local BANNER = fs.readFile("src/client/ZoneBanner.client.luau")
	H.ok(string.find(BANNER, "Config.zoneAtX(root.Position.X)", 1, true), "zone from Config.zoneAtX")
	H.ok(string.find(BANNER, "local HOLD = 2", 1, true), "holds about two seconds")
	H.ok(string.find(BANNER, "CanvasGroup", 1, true) and string.find(BANNER, "{ GroupTransparency = 0 }", 1, true), "fades in as one")
	H.ok(string.find(BANNER, "{ GroupTransparency = 1, Position", 1, true), "fades and slides out")
	H.ok(string.find(BANNER, "NumberSequenceKeypoint.new(0, 1)", 1, true) and string.find(BANNER, "NumberSequenceKeypoint.new(1, 1)", 1, true),
		"the strip fades out at both ends")
	H.ok(string.find(BANNER, "\"Your Base\"", 1, true), "back at the base")
	for _, zone in Config.ZONES do
		H.ok(string.find(BANNER, `%s{zone.id} = \{ color = Color3.fromRGB%(%d+, %d+, %d+%), face = "[^"]+" \}`), `{zone.id} has a colour and a face`)
	end
end)

----------------------------------------------------------------------------------------------------
-- The day/night timer (DayTimer.client) and the shared UI juice (Shared/UiFx)
----------------------------------------------------------------------------------------------------
H.test("Format.countdown: \"in 2m 58s\" style", function()
	H.eq(Format.countdown(178), "2m 58s")
	H.eq(Format.countdown(178.9), "2m 58s")
	H.eq(Format.countdown(60), "1m 00s")
	H.eq(Format.countdown(45), "45s")
	H.eq(Format.countdown(0), "0s")
	H.eq(Format.countdown(-3), "0s")
	H.eq(Format.countdown(3725), "1h 2m")
end)

H.test("DayTimer.client: top right, a translucent dark strip, a phase icon and bold italic relief text", function()
	H.ok(fs.isFile("src/client/DayTimer.client.luau"), "the script exists")
	local TIMER = fs.readFile("src/client/DayTimer.client.luau")
	local strip = string.match(TIMER, "local strip = new%(\"Frame\", (%b{})")
	H.ok(strip ~= nil, "the strip")
	H.ok(strip and string.find(strip, "AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -TIMER_RIGHT, 0, TIMER_TOP)", 1, true),
		"anchored at the top-right corner")
	local right, top = string.match(TIMER, "local TIMER_RIGHT, TIMER_TOP = (%d+), (%d+)")
	H.ok(right and tonumber(right) <= 20 and top and tonumber(top) <= 10, "hugging the top-right edge")
	H.ok(string.find(TIMER, "IgnoreGuiInset = true", 1, true), "in the top bar's row, clear of the player list")
	H.ok(strip and string.find(strip, "BackgroundTransparency = 0.4", 1, true), "translucent")
	H.ok(string.find(TIMER, "Enum.FontStyle.Italic", 1, true) and string.find(TIMER, "Enum.FontWeight.Heavy", 1, true), "heavy italic")
	H.ok(string.find(TIMER, "UiFx.relief(timeLabel", 1, true), "the time has relief")
	H.ok(string.find(TIMER, "`in {Format.countdown(remaining)}`", 1, true), "\"in 2m 58s\"")
	H.ok(string.find(TIMER, "\"☀️\"", 1, true) and string.find(TIMER, "\"🌙\"", 1, true) and string.find(TIMER, "\"☁️\"", 1, true), "sun / cloud-moon")
	H.ok(string.find(TIMER, "Config.dayPhase(workspace:GetServerTimeNow())", 1, true), "the shared clock")
	-- the old flat yellow box at the bottom right is gone from the HUD
	for _, gone in { "bottomRight", "dayFrame", "dayLabel", "Night in" } do
		H.ok(not string.find(HUD, gone, 1, true), `"{gone}" is gone from the HUD`)
	end
end)

H.test("HUD: Speed and money readouts have relief", function()
	H.ok(string.find(HUD, "UiFx.relief(speedValue", 1, true), "Speed")
	H.ok(string.find(HUD, "UiFx.relief(moneyValue", 1, true), "money")
end)

H.test("HUD: every button gets the shared hover pop (UiFx.watch on the HUD's ScreenGui, Rewards inside it)", function()
	H.ok(string.find(HUD, "local UiFx = require(Shared:WaitForChild(\"UiFx\"))", 1, true), "HUD requires UiFx")
	local a = string.find(HUD, "local gui = new(\"ScreenGui\"", 1, true)
	local w = string.find(HUD, "UiFx.watch(gui)", 1, true)
	local first = string.find(HUD, "new(\"TextButton\"", (a or 1), true)
	H.ok(a and w and first and a < w and w < first, "watching before the first button is made")
	H.ok(string.find(REWARDS, "WaitForChild(\"SeedHUD\")", 1, true), "the Rewards window lives in the HUD's ScreenGui")
	-- Shop and Index sit centred in a holder so they pop from the middle
	H.ok(string.find(HUD, "local holder = new(\"Frame\", { Name = label", 1, true), "side buttons in holders")
	H.ok(string.find(HUD, "AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1)", 1, true),
		"centred in them")
	H.ok(string.find(HUD, "closeButton:SetAttribute(\"NoPop\", true)", 1, true), "not the full-screen \"Click to continue\"")
	local FX = fs.readFile("src/shared/UiFx.luau")
	for _, event in { "MouseEnter", "MouseLeave", "MouseButton1Down", "MouseButton1Up", "InputBegan", "InputEnded" } do
		H.ok(string.find(FX, `b.{event}:Connect`, 1, true), `UiFx.pop hooks {event}`)
	end
	H.ok(string.find(FX, "Enum.EasingStyle.Back", 1, true) and string.find(FX, "Enum.EasingStyle.Elastic", 1, true), "springy easing")
end)

-- UiFx.pop on fake buttons: the tweens it plays as the mouse / a finger comes and goes.
do
	local luau = require("@lune/luau")
	local roblox = require("@lune/roblox")

	local function signal()
		local s = { handlers = {} }
		function s.Connect(self, f)
			table.insert(self.handlers, f)
			return { Disconnect = function() end }
		end
		function s.Fire(self, ...)
			for _, f in self.handlers do
				f(...)
			end
		end
		return s
	end

	type Fake = any
	local function loadFx(lastInput: string)
		local tweens = {}
		local env = {
			game = {
				GetService = function(_, name)
					if name == "TweenService" then
						return {
							Create = function(_, inst, info, goal)
								local t = { info = info, goal = goal, Completed = signal() }
								function t.Play()
									table.insert(tweens, t)
								end
								function t.Cancel() end
								return t
							end,
						}
					elseif name == "UserInputService" then
						return {
							GetLastInputType = function()
								return (roblox.Enum.UserInputType :: any)[lastInput]
							end,
							IsMouseButtonPressed = function()
								return true
							end,
						}
					end
					return { RenderStepped = signal() }
				end,
			},
			Instance = {
				new = function(class)
					return { ClassName = class, Scale = 1 }
				end,
			},
			TweenInfo = {
				new = function(time, style, direction)
					return { time = time, style = style, direction = direction }
				end,
			},
			Enum = roblox.Enum, Vector2 = roblox.Vector2, UDim2 = roblox.UDim2, Color3 = roblox.Color3,
			ColorSequence = roblox.ColorSequence, ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
			task = { defer = function(f, ...) f(...) end },
			math = math, string = string, table = table, assert = assert, ipairs = ipairs, pairs = pairs,
		}
		local Fx = luau.load(fs.readFile("src/shared/UiFx.luau"), { debugName = "UiFx", environment = env })()
		return Fx, tweens
	end

	local function fakeButton(inLayout: boolean): Fake
		local parent = {
			FindFirstChildWhichIsA = function(_, class)
				return if class == "UIGridStyleLayout" and inLayout then {} else nil
			end,
		}
		local b: Fake = {
			AnchorPoint = roblox.Vector2.new(0, 0), Position = roblox.UDim2.fromOffset(100, 50), Size = roblox.UDim2.fromOffset(80, 40),
			Parent = parent, children = {},
		}
		for _, e in { "MouseEnter", "MouseLeave", "MouseButton1Down", "MouseButton1Up", "InputBegan", "InputEnded" } do
			b[e] = signal()
		end
		function b.GetAttribute()
			return nil
		end
		function b.FindFirstChildWhichIsA(self, class)
			for _, c in self.children do
				if c.ClassName == class then
					return c
				end
			end
			return nil
		end
		return b
	end

	H.test("UiFx.pop: hover inflates to 1.1 (Back), leaving shrinks back, a click squashes then springs", function()
		local Fx, tweens = loadFx("MouseMovement")
		local b = fakeButton(false)
		Fx.pop(b)
		b.MouseEnter:Fire()
		H.eq(#tweens, 1)
		H.eq(tweens[1].goal.Scale, 1.1)
		H.eq(tweens[1].info.style, roblox.Enum.EasingStyle.Back)
		-- scaled about its centre while popped
		H.eq(b.AnchorPoint, roblox.Vector2.new(0.5, 0.5))
		H.eq(b.Position, roblox.UDim2.fromOffset(140, 70))
		b.MouseButton1Down:Fire()
		H.eq(tweens[2].goal.Scale, Fx.PRESS)
		H.ok(Fx.PRESS < 1, "squash")
		b.MouseButton1Up:Fire()
		H.eq(tweens[3].goal.Scale, 1.1)
		H.eq(tweens[3].info.style, roblox.Enum.EasingStyle.Elastic)
		b.MouseLeave:Fire()
		H.eq(tweens[4].goal.Scale, 1)
		tweens[4].Completed:Fire(roblox.Enum.PlaybackState.Completed)
		H.eq(b.AnchorPoint, roblox.Vector2.new(0, 0), "back to its own anchor at rest")
		H.eq(b.Position, roblox.UDim2.fromOffset(100, 50))
	end)

	H.test("UiFx.pop: a finger press inflates, lifting it springs back; taps don't stick as hovers", function()
		local Fx, tweens = loadFx("Touch")
		local b = fakeButton(true)
		Fx.pop(b)
		b.MouseEnter:Fire() -- a tap sends MouseEnter but never MouseLeave
		b.MouseButton1Down:Fire()
		H.eq(#tweens, 0, "no hover and no squash from a tap")
		local touch = { UserInputType = roblox.Enum.UserInputType.Touch }
		b.InputBegan:Fire(touch)
		H.eq(tweens[1].goal.Scale, 1.1)
		H.eq(b.AnchorPoint, roblox.Vector2.new(0, 0), "a layout places it: never re-anchored")
		b.InputEnded:Fire(touch)
		H.eq(tweens[2].goal.Scale, 1)
		H.eq(tweens[2].info.style, roblox.Enum.EasingStyle.Elastic)
	end)
end

return nil
