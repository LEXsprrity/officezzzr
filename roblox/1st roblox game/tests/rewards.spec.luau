-- Community rewards (TODO 6): the Free Gift's claim rules (group only, once, 0 id = coming soon), no free
-- chest any more, the "MOST MONEY/s" board's pure parts (encoding, merging, formatting, the DataStore
-- fallback), the v4 save fields, and the gift spot + board in the generated and committed maps.
-- RewardService (group checks, prompts, the OrderedDataStore loop) is a thin Roblox wrapper Lune can't run.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local H = require("./harness")
local MapTool = require("../tools/map_tool")
local Config = H.shared("Config")
local Rewards = H.server("Rewards")
local ProfileStore = H.server("ProfileStore")
local WorldBuilder = H.server("WorldBuilder")
local GiftBox = H.server("GiftBox")
local Vector3 = H.Vector3

local GROUP = 1234567
local NOW = 1_800_000_000

-- An IsInGroup stand-in that counts its calls.
local function member(answer: boolean?)
	local calls = 0
	return function(): boolean?
		calls += 1
		return answer
	end, function(): number
		return calls
	end
end

local function roundTrip(p: ProfileStore.Profile): ProfileStore.Profile
	return ProfileStore.deserialize(serde.decode("json", serde.encode("json", ProfileStore.serialize(p))))
end

----------------------------------------------------------------------------------------------------
-- Free Gift
----------------------------------------------------------------------------------------------------
H.test("rewards: the Free Gift is 10,000 Speed for community members, once per account", function()
	H.eq(Config.FREE_GIFT_SPEED, 25_000)
	local p = ProfileStore.defaultProfile()
	p.speed = 500
	local yes, calls = member(true)
	H.eq(Rewards.claimGift(p, GROUP, yes), "granted")
	H.eq(p.speed, 500 + Config.FREE_GIFT_SPEED)
	H.ok(p.freeGift, "flagged")
	H.eq(Rewards.claimGift(p, GROUP, yes), "claimed", "a second claim")
	H.eq(p.speed, 500 + Config.FREE_GIFT_SPEED, "paid once")
	H.eq(calls(), 1, "a claimed gift doesn't even check the group again")
	-- The flag is saved: after a rejoin it's still claimed.
	local back = roundTrip(p)
	H.ok(back.freeGift, "saved")
	H.eq(Rewards.claimGift(back, GROUP, yes), "claimed", "after rejoining")
	H.eq(back.speed, 500 + Config.FREE_GIFT_SPEED)
end)

H.test("rewards: the Free Gift needs the group; likes and favourites are never checked", function()
	local p = ProfileStore.defaultProfile()
	local no = member(false)
	H.eq(Rewards.claimGift(p, GROUP, no), "notMember")
	H.eq(p.speed, 0)
	H.ok(not p.freeGift, "not flagged, so joining later still works")
	local failed = member(nil)
	H.eq(Rewards.claimGift(p, GROUP, failed), "error", "a failed check (pcall) grants nothing")
	H.eq(p.speed, 0)
	H.eq(Rewards.claimGift(p, GROUP, (member(true))), "granted", "joined: now it works")
	-- The only input is the membership check: the rules have no like/favourite parameter at all.
	for _, result in { "granted", "soon", "claimed", "notMember", "error" } do
		local text = Rewards.giftMessage(result)
		H.ok(type(text) == "string" and #text > 0, result)
	end
end)

H.test("rewards: the real community id is set; an invalid id (0, negative, fractional) is 'coming soon' and never opens by itself", function()
	H.eq(Config.COMMUNITY_GROUP_ID, 48006453, "LeBandit Games")
	local p = ProfileStore.defaultProfile()
	local yes, calls = member(true)
	for _, id in { 0, -5, 1.5 } do
		H.eq(Rewards.claimGift(p, id, yes), "soon", `id {id}`)
	end
	H.eq(calls(), 0, "no group check")
	H.eq(p.speed, 0)
	H.ok(not p.freeGift)
	H.ok(string.find((Rewards.giftMessage("soon")), "coming soon", 1, true), "says coming soon")
	H.eq(Rewards.autoOpenGift(p, 0), false)
	H.ok(not p.giftShown, "so it still opens once after the id is set")
end)

H.test("rewards: the window opens by itself once per account, and not once claimed", function()
	local p = ProfileStore.defaultProfile()
	H.eq(Rewards.autoOpenGift(p, GROUP), true)
	H.eq(Rewards.autoOpenGift(p, GROUP), false, "only once")
	H.eq(Rewards.autoOpenGift(roundTrip(p), GROUP), false, "not again after a rejoin")
	local claimed = ProfileStore.defaultProfile()
	claimed.freeGift = true
	H.eq(Rewards.autoOpenGift(claimed, GROUP), false)
end)

H.test("rewards: the membership cache keeps a yes, re-checks a no after a few seconds, never caches a failure", function()
	local cache = {}
	local yes, yesCalls = member(true)
	H.eq(Rewards.cachedMember(cache, 1, NOW, yes), true)
	H.eq(Rewards.cachedMember(cache, 1, NOW + 9999, yes), true)
	H.eq(yesCalls(), 1, "a yes is cached")
	local no, noCalls = member(false)
	H.eq(Rewards.cachedMember(cache, 2, NOW, no), false)
	H.eq(Rewards.cachedMember(cache, 2, NOW + 1, no), false)
	H.eq(noCalls(), 1, "spam clicks don't re-check")
	H.eq(Rewards.cachedMember(cache, 2, NOW + Rewards.NEGATIVE_CACHE, yes), true, "joined since: checked again")
	local fail, failCalls = member(nil)
	H.eq(Rewards.cachedMember(cache, 3, NOW, fail), nil)
	H.eq(Rewards.cachedMember(cache, 3, NOW, fail), nil)
	H.eq(failCalls(), 2, "failures are retried")
end)

----------------------------------------------------------------------------------------------------
-- No free chest (owner request): only the Free Gift, where the chest stood
----------------------------------------------------------------------------------------------------
H.test("rewards: the free chest is gone (no payout, no claim, no slot, no sound); old saves keep chestAt", function()
	H.eq(Config.FREE_CHEST_COOLDOWN, nil)
	H.eq(Config.freeChestAmount, nil)
	H.eq(Rewards.claimChest, nil)
	H.eq(Rewards.chestReadyIn, nil)
	local Assets = H.server("Assets")
	H.ok(not table.find(Assets.SLOTS, "FreeChest"), "no FreeChest asset slot")
	for _, path in { "src/server/RewardService.luau", "src/client/Rewards.client.luau", "src/client/Effects.client.luau", "src/server/Sessions.luau" } do
		local source = fs.readFile(path)
		H.ok(not string.find(source, "FreeChest", 1, true) and not string.find(source, "chestAt", 1, true), `{path}: no chest claim, countdown or sound`)
	end
	-- a save that claimed the chest still loads and saves it unchanged (nothing reads it)
	local p = ProfileStore.defaultProfile()
	p.chestAt = NOW
	H.eq(roundTrip(p).chestAt, NOW)
end)

----------------------------------------------------------------------------------------------------
-- "MOST MONEY/s" board
----------------------------------------------------------------------------------------------------
H.test("rewards: the board's encoding keeps the order and reads back closely, from $0 to past $1Qa/s", function()
	H.eq(Rewards.encodeIncome(0), 0)
	H.eq(Rewards.encodeIncome(-3), 0)
	H.eq(Rewards.encodeIncome(0 / 0), 0)
	H.eq(Rewards.decodeIncome(0), 0)
	H.eq(Rewards.decodeIncome("x"), 0)
	local last = 0
	local x = 0.5
	while x < 1e20 do
		local v = Rewards.encodeIncome(x)
		H.ok(v == math.floor(v) and v < 2 ^ 53, "a whole number an OrderedDataStore takes")
		H.ok(v >= last, `monotonic at {x}`)
		H.near(Rewards.decodeIncome(v), x, x * 1e-5 + 1e-3, `reads back {x}`)
		last = v
		x *= 1.37
	end
	H.ok(Rewards.encodeIncome(54.8e12) > Rewards.encodeIncome(42.3e12), "54.8T ranks above 42.3T")
	H.ok(Rewards.encodeIncome(math.huge) < 2 ^ 53, "even infinite income stays storable")
end)

H.test("rewards: a server writes a player's value only when it changed, and never a first 0", function()
	H.eq(Rewards.shouldWrite(nil, 0), false)
	H.eq(Rewards.shouldWrite(nil, 5), true)
	H.eq(Rewards.shouldWrite(5, 5), false)
	H.eq(Rewards.shouldWrite(5, 6), true)
	H.eq(Rewards.shouldWrite(5, 0), true, "dropping to 0 is written once")
	H.eq(Rewards.shouldWrite(0, 0), false)
end)

H.test("rewards: the board ranks the global top with this server's live incomes, best first, 10 rows", function()
	local function row(id: number, income: number, name: string?)
		return { userId = id, income = income, name = name }
	end
	local global = Rewards.parsePage({
		{ key = "11", value = Rewards.encodeIncome(42.3e12) },
		{ key = "12", value = Rewards.encodeIncome(54.8e12) },
		{ key = "13", value = Rewards.encodeIncome(5e9) },
		{ key = "nope", value = 5 }, -- bad entries are skipped
		{ key = "14", value = "5" },
		"junk",
	})
	H.eq(#global, 3)
	-- Player 13 is in this server and earns more now than the stored value.
	local rows, source = Rewards.boardRows(global, { row(13, 60e12, "Here"), row(99, 0, "Broke") }, 10)
	H.eq(source, "global")
	H.eq(#rows, 3, "a 0 income doesn't make the global board")
	H.eq(rows[1].userId, 13, "the live value counts")
	H.eq(rows[1].name, "Here")
	H.eq(rows[2].userId, 12)
	H.eq(rows[3].userId, 11)
	-- Ten at most, ties by user id, nobody twice.
	local many = {}
	for i = 1, 25 do
		table.insert(many, row(i, if i <= 4 then 100 else i))
	end
	local top = Rewards.boardRows(many, { row(25, 25) }, Config.MONEY_BOARD_ROWS)
	H.eq(#top, Config.MONEY_BOARD_ROWS)
	H.eq(top[1].userId, 1)
	H.eq(top[4].userId, 4)
	H.eq(top[5].userId, 25)
	local seen = {}
	for _, r in top do
		H.ok(not seen[r.userId], "nobody twice")
		seen[r.userId] = true
	end
end)

H.test("rewards: without the DataStore the board shows this server's players", function()
	local here = { { userId = 1, income = 50, name = "A" }, { userId = 2, income = 0, name = "B" }, { userId = 3, income = 900, name = "C" } }
	local rows, source = Rewards.boardRows(nil, here, 10)
	H.eq(source, "server")
	H.eq(#rows, 3, "everyone here, even at $0/s")
	H.eq(rows[1].name, "C")
	H.eq(rows[3].name, "B")
	H.ok(string.find(Rewards.boardStatus("server", 3), "This server", 1, true))
	H.ok(string.find(Rewards.boardStatus("global", 3), "All servers", 1, true))
	H.eq(Rewards.boardStatus("server", 0), "No one is earning yet!")
	H.eq(#(Rewards.parsePage(nil)), 0, "a failed read parses to nothing")
end)

H.test("rewards: board rows read like the reference (rank, short name, $ value)", function()
	local f = Rewards.formatRow(1, { userId = 1, name = "NukleoRl", income = 54.8e12 })
	H.eq(f.rank, "1")
	H.eq(f.name, "NukleoRl")
	H.eq(f.value, "$54.8T")
	local long = Rewards.formatRow(10, { userId = 2, name = "AVeryLongUsername_123", income = 999 })
	H.ok(#long.name <= Rewards.NAME_MAX, "long names are cut")
	H.eq(string.sub(long.name, -2), "..")
	H.eq(long.value, "$999")
	H.eq(Rewards.formatRow(3, { userId = 3, income = 0 }).name, "Player", "a name that couldn't be looked up")
end)

----------------------------------------------------------------------------------------------------
-- Saves
----------------------------------------------------------------------------------------------------
H.test("rewards: v3 saves load with the gift unclaimed, the window unseen and chestAt 0 (v4; the chest is gone, the field stays)", function()
	H.ok(ProfileStore.VERSION >= 4, "v4 added these fields")
	local v3 = { v = 3, money = 12, speed = 34, plotLevel = 2, trails = { "Grey" }, trail = "Grey", plants = {}, index = {} }
	local p = ProfileStore.deserialize(serde.decode("json", serde.encode("json", v3)))
	H.eq(p.freeGift, false)
	H.eq(p.giftShown, false)
	H.eq(p.chestAt, 0)
	H.eq(p.money, 12, "the rest loads as before")
	H.eq(p.plotLevel, 2)
	local data = ProfileStore.serialize(p)
	H.eq(data.v, ProfileStore.VERSION)
	-- v4 round trip, and junk in the new fields falls back to the defaults
	p.freeGift, p.giftShown, p.chestAt = true, true, NOW
	local back = roundTrip(p)
	H.eq(back.freeGift, true)
	H.eq(back.giftShown, true)
	H.eq(back.chestAt, NOW)
	local junk = ProfileStore.deserialize({ v = 4, freeGift = "yes", giftShown = 1, chestAt = -50 })
	H.eq(junk.freeGift, false)
	H.eq(junk.giftShown, false)
	H.eq(junk.chestAt, 0)
	H.eq(ProfileStore.deserialize({ v = 4, chestAt = 0 / 0 }).chestAt, 0)
end)

----------------------------------------------------------------------------------------------------
-- World
----------------------------------------------------------------------------------------------------
local function checkRewardsCorner(world: any, label: string)
	local spot, board = WorldBuilder.rewardPoints(world)
	H.ok(spot, `{label}: the gift's spot`)
	H.ok(board, `{label}: the board's labels`)
	H.ok(spot.Transparency >= 1 and not spot.CanCollide, `{label}: the spot is an invisible marker`)
	H.eq(#board.rows, Config.MONEY_BOARD_ROWS, "ten rows")
	H.eq(board.status.Text, "Loading...", "until the first update")
	-- no free chest left anywhere in the map: no model, circle, "FREE!" sign, countdown or prompt
	for _, d in world:GetDescendants() do
		local chesty = string.find(d.Name, "Chest", 1, true) ~= nil or d:GetAttribute("AssetSlot") == "FreeChest"
			or d:GetAttribute("Role") == "FreeChest" or d:GetAttribute("FreeChest") ~= nil
			or (d:IsA("TextLabel") and d.Text == "FREE!")
		H.ok(not chesty, `{label}: a free chest piece is left ({d:GetFullName()})`)
	end
	local title
	for _, d in board.status.Parent:GetChildren() do
		if d:IsA("TextLabel") and d.Text == "MOST MONEY/s" then
			title = d
		end
	end
	H.ok(title, "the MOST MONEY/s title")
	return spot, board
end

-- Where the free chest stood (WorldBuilder, before the owner removed it): the gift box takes its place.
local CHEST_GROUND = Vector3.new(Config.CORRIDOR_START_X - 10, Config.GROUND_Y, -(Config.CORRIDOR_WIDTH / 2 + 28))

H.test("rewards: the base has the gift's spot (where the free chest stood) and the MOST MONEY/s board, out of everyone's way", function()
	local plots = WorldBuilder.build()
	local world = H.workspace:FindFirstChild("World")
	local spot, board = checkRewardsCorner(world, "generated")
	local ground = GiftBox.groundCFrame(spot)
	H.ok((ground.Position - CHEST_GROUND).Magnitude < 1e-3, "the gift's spot is the chest's old ground point")
	H.ok(ground.LookVector:Dot(-Vector3.xAxis) > 0.99, "facing the base, like the chest did")
	local panel = board.status.Parent.Parent
	H.eq(panel:GetAttribute("Role"), "MoneyBoard")
	-- Inside the base, off the walkway (|z| < 18) and the corridor mouth (|z| < HALF_W), clear of every plot
	-- and the plaza, on the -Z side.
	local half = Config.PLOT_SIZE / 2
	-- `margin`: the gift's circle around its 4-stud spot, the board's frame around its panel.
	for _, piece in { { part = spot, margin = GiftBox.CIRCLE / 2 - 1.5 }, { part = panel, margin = 1.5 } } do
		local part = piece.part
		local cf, s = part.CFrame, part.Size / 2
		local function extent(axis: any): number -- half the part's world size along `axis`, plus the margin
			return math.abs(cf.RightVector:Dot(axis)) * s.X + math.abs(cf.UpVector:Dot(axis)) * s.Y + math.abs(cf.LookVector:Dot(axis)) * s.Z + piece.margin
		end
		local p, ex, ez = cf.Position, extent(Vector3.xAxis), extent(Vector3.zAxis)
		H.ok(p.X + ex <= Config.CORRIDOR_START_X and p.Z < 0, `{part.Name} in the base (in front of the wall), -Z side`)
		H.ok(math.abs(p.Z) - ez > Config.CORRIDOR_WIDTH / 2, `{part.Name} clear of the walkway and the corridor mouth`)
		for i = 1, Config.MAX_PLAYERS + 1 do
			local cx, cz = Config.spotXZ(i)
			H.ok(math.abs(p.X - cx) > half + ex or math.abs(p.Z - cz) > half + ez, `{part.Name} clear of spot {i}`)
		end
	end
	H.ok(panel.CFrame.LookVector:Dot(-Vector3.xAxis) > 0.99, "the board faces into the base")
	H.ok(panel.Size.Y <= 20 and panel.Size.X <= 14, "not too big")
	H.ok((spot.CFrame.Position - panel.CFrame.Position).Magnitude < 30, "the gift stands by the board")
	-- The board's rows get written
	WorldBuilder.setMoneyBoard(board, { { name = "A", value = "$1K" } }, "This server")
	H.eq(board.rows[1].frame.Visible, true)
	H.eq(board.rows[1].name.Text, "A")
	H.eq(board.rows[1].value.Text, "$1K")
	H.eq(board.rows[2].frame.Visible, false)
	H.eq(board.status.Text, "This server")
	H.eq(#plots, Config.MAX_PLAYERS)
end)

H.test("rewards: the committed map/World.rbxm has the gift's spot where the chest stood, the board, and no free chest", function()
	local world = MapTool.load(MapTool.PATH)
	local spot = checkRewardsCorner(world, "map/World.rbxm")
	H.ok((GiftBox.groundCFrame(spot).Position - CHEST_GROUND).Magnitude < 1e-3, "the gift's spot is where the chest stood")
	H.ok(WorldBuilder.adopt(world), "and the map still validates")
end)

-- The gift box RewardService builds on the gift's spot: the prompt that opens the Free Gift window and the
-- floating "FREE GIFT", on its circle where the free chest stood, still clear of the walkway, the board
-- and the plots.
local function checkGiftBox(world: any, label: string)
	local spot, board = WorldBuilder.rewardPoints(world)
	H.ok(spot and board, label)
	local model, prompt = GiftBox.build(spot)
	H.eq(model.Parent, spot.Parent, `{label}: in the Rewards model`)
	H.eq(prompt:GetAttribute("FreeGift"), true, "its prompt opens the Free Gift window (Rewards.client)")
	H.eq(prompt.ObjectText, "Free Gift")
	H.ok(prompt.RequiresLineOfSight == false and prompt.MaxActivationDistance >= 8, "easy to trigger")
	local sign
	for _, d in model:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "FREE GIFT" then
			sign = d
		end
	end
	H.ok(sign and sign:FindFirstChildOfClass("UIStroke").Thickness >= 4 and sign.Parent:IsA("BillboardGui"), "a big outlined FREE GIFT floats above it")
	local body = model:FindFirstChild("GiftBody")
	local flat = Vector3.new(1, 0, 1)
	H.ok(((body.CFrame.Position - CHEST_GROUND) * flat).Magnitude < 0.01, `{label}: exactly where the free chest stood`)
	H.ok(math.abs(model.GiftCircle.CFrame.Position.Y - Config.GROUND_Y) < 0.5, "its circle on the ground")
	H.ok(math.abs(body.CFrame.Position.Y - body.Size.Y / 2 - Config.GROUND_Y) < 0.5, "the box on the ground")
	local panel = board.status.Parent.Parent
	H.ok(((body.CFrame.Position - panel.CFrame.Position) * flat).Magnitude < 30, "by the board")
	local p, r = body.CFrame.Position, GiftBox.CIRCLE / 2
	H.ok(p.X + r <= Config.CORRIDOR_START_X and p.Z < 0, "in the base, -Z side")
	H.ok(math.abs(p.Z) - r > Config.CORRIDOR_WIDTH / 2, "clear of the walkway and the corridor mouth")
	local sideWall: any = nil
	for _, d in world.Base:GetChildren() do -- the base's -Z side wall: the box stays in front of it
		if d:IsA("BasePart") and d.Name == "Wall" and d.CFrame.Position.Z < -Config.CORRIDOR_WIDTH / 2 and d.Size.Z > 100 then
			sideWall = d
		end
	end
	H.ok(sideWall and math.abs(p.Z) + r < math.abs(sideWall.CFrame.Position.Z) - 2, `{label}: inside the base, clear of its side wall`)
	-- clear of the board (its panel is 12 wide along Z, facing the base, its frame a little wider)
	local b = panel.CFrame.Position
	H.ok(math.abs(p.Z - b.Z) > r + panel.Size.X / 2 + 1 or math.abs(p.X - b.X) > r + 3, `{label}: clear of the board`)
	local half = Config.PLOT_SIZE / 2
	for i = 1, Config.MAX_PLAYERS + 1 do
		local cx, cz = Config.spotXZ(i)
		H.ok(math.abs(p.X - cx) > half + r or math.abs(p.Z - cz) > half + r, `clear of spot {i}`)
	end
	model:Destroy()
end

H.test("rewards: a gift box with a FREE GIFT prompt stands where the free chest stood", function()
	WorldBuilder.build()
	checkGiftBox(H.workspace:FindFirstChild("World"), "generated")
	checkGiftBox(MapTool.load(MapTool.PATH), "map/World.rbxm")
end)

return nil
