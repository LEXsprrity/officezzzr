-- UI icons: icons/ids.json -> Config.ICONS, Shared/Icons (emoji fallback, icon rows), the world signs and
-- the uploader (tools/icon_uploader.luau) driven with a fake network.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local H = require("./harness")
local Uploader = require("../tools/icon_uploader")

local Instance, Enum = roblox.Instance, roblox.Enum
local Config = H.shared("Config")
local Icons = H.shared("Icons")
local WorldBuilder = H.server("WorldBuilder")

local KEYS = {
	"Bag", "Bat", "Close", "DoubleMoney", "ExtraSlots", "Gift", "Home", "Index", "Leaderboard", "Lock", "Money", "PackSpaceBg", "PackSpiritBg",
	"Plants", "PlotUpgrade", "Robux", "SeedPack", "Seeds", "Shop", "Speed", "Star", "Studs", "TrailShop", "Treadmill",
}

-- Runs fn with only these icon ids set (every other id 0), then puts Config.ICONS back.
local function withIds(ids: { [string]: number }, fn: () -> ())
	local saved = table.clone(Config.ICONS)
	for k in Config.ICONS do
		Config.ICONS[k] = 0
	end
	for k, v in ids do
		Config.ICONS[k] = v
	end
	local ok, err = pcall(fn)
	table.clear(Config.ICONS)
	for k, v in saved do
		Config.ICONS[k] = v
	end
	if not ok then
		error(err, 0)
	end
end

local function label(textValue: string?, align: any?): any
	local l = Instance.new("TextLabel")
	l.Text = textValue or "Label"
	l.TextScaled = true
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = l
	return l
end

-- A compact view of Icons.parse: "[Shop] Shop" etc.
local function show(pieces: { any }?): string?
	if not pieces then
		return nil
	end
	local out = {}
	for _, p in pieces do
		table.insert(out, if p.image then `[{p.key}]` else p.text)
	end
	return table.concat(out, " ")
end

H.test("icons: ids.json loads as Config.ICONS with all 24 keys (uploaded ids or 0)", function()
	local raw = serde.decode("json", fs.readFile("icons/ids.json"))
	local n = 0
	for key, id in raw do
		n += 1
		H.ok(table.find(KEYS, key), `unexpected key {key} in ids.json`)
		H.eq(type(id), "number", `ids.json {key}`)
		H.eq(Config.ICONS[key], id, `Config.ICONS.{key}`)
	end
	H.eq(n, #KEYS, "ids.json key count")
	for _, key in KEYS do
		H.ok(Config.ICONS[key] ~= nil, `Config.ICONS has no {key}`)
	end
	-- Each id is 0 (not uploaded: the emoji shows) or a whole positive asset id.
	for key, id in Config.ICONS do
		H.ok(id == 0 or (id > 0 and id == math.floor(id)), `ids.json {key} is 0 or an asset id`)
	end
	-- The uploader writes the same format the repo keeps.
	H.eq(Uploader.encodeIds(Config.ICONS), string.gsub(fs.readFile("icons/ids.json"), "\r", ""), "ids.json is in the uploader's format")
end)

H.test("icons: every Config.ICONS key has icons/<key>.png and an emoji token (or is a texture), and vice versa", function()
	local pngs = {}
	for _, entry in fs.readDir("icons") do
		local key = string.match(entry, "^(.+)%.png$")
		if key then
			pngs[key] = true
			H.ok(Config.ICONS[key] ~= nil, `icons/{entry} has no key in icons/ids.json`)
			H.eq(string.sub(fs.readFile("icons/" .. entry), 2, 4), "PNG", `icons/{entry} is a PNG`)
		end
	end
	for key in Config.ICONS do
		H.ok(pngs[key], `Config.ICONS.{key} has no icons/{key}.png`)
		H.ok((Icons.TOKENS[key] and #Icons.TOKENS[key] > 0) or Icons.TEXTURES[key], `Icons.TOKENS has nothing for {key}`)
	end
	for key in Icons.TOKENS do
		H.ok(Config.ICONS[key] ~= nil, `Icons.TOKENS.{key} is not in ids.json`)
	end
end)

H.test("icons: with every id at 0 nothing changes (no images, labels keep their emoji text)", function()
	withIds({}, function()
	for _, key in KEYS do
		H.eq(Icons.image(key), nil, `Icons.image({key})`)
	end
	H.eq(Icons.image("NoSuchIcon"), nil)
	for _, case in {
		{ "Shop", "🛒 Shop" }, { "Bat", "🏏\nBat" }, { { "Robux" }, "Buy · R$ 2,000" }, { "Money", "$1.2K" },
		{ { "Seeds", "Bag" }, "🌱 Seeds · 🎒 3/50" }, { "Leaderboard", "⚡ FASTEST HERE ⚡" },
	} do
		H.eq(Icons.parse(case[1], case[2]), nil, case[2])
		local l = label("old")
		Icons.set(l, case[1], case[2], 0.85)
		H.eq(l.Text, case[2], "text unchanged")
		H.eq(#l:GetChildren(), 1, "only the label's own UIStroke") -- no IconRow
	end
	-- The world signs are left alone too.
	local world = roblox.deserializeModel(fs.readFile("map/World.rbxm"))[1]
	H.eq(WorldBuilder.applyIcons(world), 0)
	for _, d in world:GetDescendants() do
		H.ok(d.Name ~= "IconRow", "no icon rows on the map with no ids")
	end
	end)
end)

H.test("icons: with an id set, Icons.image returns its rbxassetid", function()
	withIds({ Shop = 123, Robux = 98765432101, Star = -5, Gift = 1.5 }, function()
		H.eq(Icons.image("Shop"), "rbxassetid://123")
		H.eq(Icons.image("Robux"), "rbxassetid://98765432101", "big ids keep every digit")
		H.eq(Icons.image("Star"), nil, "negative ids are ignored")
		H.eq(Icons.image("Gift"), nil, "fractional ids are ignored")
		H.eq(Icons.image("Index"), nil, "others still 0")
	end)
	H.eq(Icons.image("Shop"), if Config.ICONS.Shop > 0 then `rbxassetid://{Config.ICONS.Shop}` else nil, "restored to the repo id")
end)

H.test("icons: emoji become icon pieces (in front, inline, both ends, above the text)", function()
	withIds({ Shop = 1, Robux = 2, Money = 3, Bat = 4, Seeds = 5, Bag = 6, Star = 7, Leaderboard = 8, Lock = 9, PlotUpgrade = 10 }, function()
		H.eq(show(Icons.parse("Shop", "🛒 Shop")), "[Shop] Shop")
		H.eq(show(Icons.parse({ "Robux" }, "Buy · R$ 2,000")), "Buy · [Robux] 2,000")
		H.eq(show(Icons.parse({ "Robux" }, "R$ 64 soon")), "[Robux] 64 soon")
		H.eq(show(Icons.parse({ "Robux" }, "Owned")), nil, "a list of keys never adds an icon that isn't in the text")
		H.eq(show(Icons.parse("Money", "$1.2K")), "[Money] $1.2K", "one key: the icon goes in front")
		H.eq(show(Icons.parse("Money", "💰 $24K")), "[Money] $24K")
		H.eq(show(Icons.parse({ "Seeds", "Bag" }, "🌱 Seeds · 🎒 3/50")), "[Seeds] Seeds · [Bag] 3/50")
		H.eq(show(Icons.parse("Leaderboard", "⚡ FASTEST HERE ⚡")), "[Leaderboard] FASTEST HERE [Leaderboard]")
		H.eq(show(Icons.parse({ "Star" }, "🌟 Celestial 0.5%  ·  ✨ Gold 8%")), "[Star] Celestial 0.5%  · [Star] Gold 8%")
		H.eq(show(Icons.parse({ "Lock" }, "✅ Rec. Speed 10K")), nil)
		H.eq(show(Icons.parse({ "Lock" }, "🔒 Rec. Speed 10K")), "[Lock] Rec. Speed 10K")
		H.eq(show(Icons.parse("PlotUpgrade", "⬆️ UPGRADE PLOT")), "[PlotUpgrade] UPGRADE PLOT")
		H.eq(show(Icons.parse("PlotUpgrade", "🏡 Level 2 → 3")), "[PlotUpgrade] Level 2 → 3")
		local pieces, vertical = Icons.parse("Bat", "🏏\nBat")
		H.eq(show(pieces), "[Bat] Bat")
		H.ok(vertical, "a line break after the icon puts it above the text")
		H.eq(show(Icons.parse({ "Index" }, "📖 Index")), nil, "Index has no id here")
	end)
end)

H.test("icons: Icons.set lays out ImageLabels (Fit, square) and styled text, and goes back to plain text", function()
	withIds({ Robux = 2 }, function()
		local l = label("x", Enum.TextXAlignment.Center)
		l.TextColor3 = roblox.Color3.fromRGB(10, 20, 30)
		Icons.set(l, { "Robux" }, "Buy · R$ 2,000", 0.7)
		H.eq(l.Text, "", "the label's own text is emptied")
		local row = l:FindFirstChild("IconRow")
		H.ok(row, "IconRow")
		local icon = row:FindFirstChild("Icon_Robux")
		H.ok(icon and icon:IsA("ImageLabel"), "icon")
		H.eq(icon.Image, "rbxassetid://2")
		H.eq(icon.ScaleType, Enum.ScaleType.Fit)
		H.eq(icon.SizeConstraint, Enum.SizeConstraint.RelativeYY)
		H.eq(icon.Size, roblox.UDim2.fromScale(0.7, 0.7))
		local before, after = row:FindFirstChild("Text1"), row:FindFirstChild("Text3")
		H.eq(before.Text, "Buy ·")
		H.eq(after.Text, "2,000")
		H.eq(before.TextXAlignment, Enum.TextXAlignment.Right, "hugs the icon")
		H.eq(after.TextXAlignment, Enum.TextXAlignment.Left, "hugs the icon")
		H.eq(after.TextColor3, l.TextColor3)
		H.ok(after:FindFirstChildOfClass("UIStroke"), "text keeps the label's stroke")
		H.ok(after:FindFirstChildOfClass("UIFlexItem"), "text pieces share the room")
		-- Same text again: nothing is rebuilt
		Icons.set(l, { "Robux" }, "Buy · R$ 2,000", 0.7)
		H.eq(l:FindFirstChild("IconRow"), row, "unchanged text keeps the row")
		Icons.set(l, { "Robux" }, "Buy · R$ 3,000", 0.7)
		H.eq(l:FindFirstChild("IconRow"):FindFirstChild("Text3").Text, "3,000")
		H.eq(#l:GetChildren(), 2, "one row, rebuilt in place")
		-- Text without the token: back to a plain label
		Icons.set(l, { "Robux" }, "Owned", 0.7)
		H.eq(l.Text, "Owned")
		H.eq(l:FindFirstChild("IconRow"), nil)
	end)
	withIds({ Bat = 4, Treadmill = 5 }, function()
		local l = label()
		Icons.set(l, "Bat", "🏏\nBat")
		local row = l:FindFirstChild("IconRow")
		H.eq(row:FindFirstChildOfClass("UIListLayout").FillDirection, Enum.FillDirection.Vertical)
		H.eq(row:FindFirstChild("Icon_Bat").Size, roblox.UDim2.fromScale(0.6, 0.6))
		local t = label()
		Icons.set(t, "Treadmill", "🏃 TREADMILL x2\n+1.2K Speed/s")
		H.eq(t:FindFirstChild("IconRow"):FindFirstChild("Text2").Text, "TREADMILL x2\n+1.2K Speed/s", "a line break later on stays in the text")
		local s = label()
		Icons.set(s, "Treadmill", "-- TREADMILL --", 0.85, 30)
		local part = s:FindFirstChild("IconRow"):FindFirstChild("Text2")
		H.eq(part.AutomaticSize, Enum.AutomaticSize.X, "a fixed text size keeps its natural width")
		H.eq(part.TextScaled, false)
		H.eq(part.TextSize, 30)
	end)
end)

H.test("icons: world signs get their icons at runtime (stalls, Upgrade boards, plot signs)", function()
	local all = {}
	for _, key in KEYS do
		all[key] = 1000 + #key
	end
	withIds(all, function()
		local world = roblox.deserializeModel(fs.readFile("map/World.rbxm"))[1]
		local count = WorldBuilder.applyIcons(world)
		H.ok(count >= 3 + Config.MAX_PLAYERS, `{count} signs got icons`) -- (no treadmill sign any more)
		-- The Upgrade boards are written by PlotService (WorldBuilder.setUpgradeBoard): the PlotUpgrade icon
		-- on the red button, the Robux icon on the purple one.
		local plots = WorldBuilder.adopt(world)
		for _, plot in plots do
			WorldBuilder.setUpgradeBoard(plot.upgradeLabels, 6)
		end
		local seen = {}
		for _, d in world:GetDescendants() do
			if d:IsA("ImageLabel") and string.match(d.Name, "^Icon_") then
				seen[string.sub(d.Name, 6)] = (seen[string.sub(d.Name, 6)] or 0) + 1
			end
		end
		H.eq(seen.Shop, 1, "SHOP stall")
		H.eq(seen.TrailShop, 1, "TRAIL SHOP stall")
		H.eq(seen.Index, 1, "INDEX stall")
		H.eq(seen.PlotUpgrade, Config.MAX_PLAYERS, "Upgrade boards: red button")
		H.eq(seen.Robux, Config.MAX_PLAYERS, "Upgrade boards: purple button")
		H.eq(seen.Home, Config.MAX_PLAYERS, "plot signs")
		H.eq(seen.Treadmill, nil, "no treadmill sign (owner playtest: removed)")
	end)
end)

----------------------------------------------------------------------------------------------------
-- Uploader
----------------------------------------------------------------------------------------------------
local SECRET = "test-key-SHOULD-NEVER-BE-PRINTED"

-- Deps over the real icons/ folder, with writes, prints and the network captured. ids.json starts with
-- every id at 0 (as before any upload), whatever the repo's real ids are.
local function fakeDeps(env: { [string]: string? }, handler: ((req: any) -> any)?)
	local out = { lines = {}, writes = {}, requests = {} }
	local zero = {}
	for key in Config.ICONS do
		zero[key] = 0
	end
	local seed = { [Uploader.IDS_FILE] = Uploader.encodeIds(zero), [Uploader.UPLOADS_FILE] = "{}" }
	out.deps = {
		request = function(req)
			table.insert(out.requests, req)
			if not handler then
				error("the network must not be used here")
			end
			return handler(req)
		end,
		env = env,
		print = function(s)
			table.insert(out.lines, s)
		end,
		wait = function() end,
		readDir = fs.readDir,
		readFile = function(path)
			return out.writes[path] or seed[path] or fs.readFile(path)
		end,
		writeFile = function(path, data)
			out.writes[path] = data
		end,
		isFile = function(path)
			return out.writes[path] ~= nil or seed[path] ~= nil or fs.isFile(path)
		end,
	}
	return out
end

local function reply(code: number, body: any)
	return {
		ok = code >= 200 and code < 300, statusCode = code, statusMessage = "", headers = {},
		body = if type(body) == "string" then body else serde.encode("json", body),
	}
end

H.test("uploader: --dry-run lists all 24 icons and never needs a key or the network", function()
	local opts = Uploader.parseArgs({ "--dry-run" })
	H.ok(opts and opts.dryRun)
	local run = fakeDeps({})
	H.eq(Uploader.run(opts :: any, run.deps), 0)
	H.eq(#run.requests, 0, "no network")
	H.eq(next(run.writes), nil, "no files written")
	local would = 0
	for _, line in run.lines do
		if string.find(line, "would upload icons/", 1, true) then
			would += 1
		end
	end
	H.eq(would, #KEYS, "one line per icon")
	H.eq(#Uploader.listIcons(run.deps), #KEYS)
end)

H.test("uploader: arguments, creator and the multipart body", function()
	H.eq(select(2, Uploader.parseArgs({ "--type", "Mesh" })), "--type must be Image or Decal (got Mesh)")
	local opts = Uploader.parseArgs({ "--type", "Decal", "--only", "Shop,Index", "--force" }) :: any
	H.eq(opts.assetType, "Decal")
	H.ok(opts.force)
	H.eq(table.concat(opts.only, ","), "Shop,Index")
	H.ok(H.deepEq(Uploader.creator({ ROBLOX_USER_ID = "42" }), { userId = "42" }))
	H.ok(H.deepEq(Uploader.creator({ ROBLOX_GROUP_ID = "7" }), { groupId = "7" }))
	H.eq(Uploader.creator({ ROBLOX_USER_ID = "42", ROBLOX_GROUP_ID = "7" }), nil, "not both")
	H.eq(Uploader.creator({ ROBLOX_USER_ID = "me" }), nil, "numeric ids only")

	local json = Uploader.requestJson("Shop", "Image", { userId = "42" })
	local request = serde.decode("json", json)
	H.eq(request.assetType, "Image")
	H.eq(request.displayName, "StealASeed_Shop")
	H.eq(request.creationContext.creator.userId, "42")
	local png = fs.readFile("icons/Shop.png")
	local body, boundary = Uploader.multipart(json, "Shop.png", png)
	H.ok(string.find(body, `--{boundary}\r\nContent-Disposition: form-data; name="request"\r\nContent-Type: application/json\r\n\r\n{json}\r\n`, 1, true), "request part")
	H.ok(string.find(body, `name="fileContent"; filename="Shop.png"\r\nContent-Type: image/png\r\n\r\n`, 1, true), "file part")
	H.ok(string.find(body, png, 1, true), "the PNG bytes as they are")
	H.eq(string.sub(body, -(#boundary + 6)), `--{boundary}--\r\n`, "closing boundary")
end)

H.test("uploader: an Image upload polls the operation and writes the asset id to ids.json", function()
	local polls = 0
	local run = fakeDeps({ ROBLOX_API_KEY = SECRET, ROBLOX_USER_ID = "42" }, function(req)
		H.eq(req.headers["x-api-key"], SECRET, "key in the header")
		if req.method == "POST" then
			H.eq(req.url, Uploader.CREATE_URL)
			local key = string.match(req.body, 'filename="(%a+)%.png"')
			return reply(200, { path = "operations/op-" .. key })
		end
		local key = string.match(req.url, "operations/op%-(%a+)$")
		polls += 1
		if polls % 2 == 1 then
			return reply(200, { path = "operations/op-" .. key, done = false })
		end
		return reply(200, { done = true, response = { assetId = tostring(5000 + #key), assetType = "Image" } })
	end)
	local opts = Uploader.parseArgs({ "--only", "Shop,Robux" }) :: any
	H.eq(Uploader.run(opts, run.deps), 0, table.concat(run.lines, "\n"))
	local ids = serde.decode("json", run.writes[Uploader.IDS_FILE])
	H.eq(ids.Shop, 5004)
	H.eq(ids.Robux, 5005)
	H.eq(ids.Index, 0, "--only")
	local n = 0
	for _ in ids do
		n += 1
	end
	H.eq(n, #KEYS, "every key stays in ids.json")
	for _, line in run.lines do
		H.ok(not string.find(line, SECRET, 1, true), "the key is never printed")
	end
	for path, data in run.writes do
		H.ok(not string.find(data, SECRET, 1, true), `the key is never written ({path})`)
	end
end)

H.test("uploader: a Decal upload resolves the image id from the decal; failures keep 0", function()
	local decalXml = [[<roblox version="4"><Item class="Decal" referent="RBX0"><Properties>]]
		.. [[<Content name="Texture"><url>http://www.roblox.com/asset/?id=777001</url></Content>]]
		.. [[<string name="Name">Decal</string></Properties></Item></roblox>]]
	H.eq(Uploader.imageIdFromDecal(decalXml), "777001")
	local run = fakeDeps({ ROBLOX_API_KEY = SECRET, ROBLOX_GROUP_ID = "9" }, function(req)
		if req.method == "POST" then
			local request = serde.decode("json", string.match(req.body, "application/json\r\n\r\n(.-)\r\n%-%-"))
			H.eq(request.assetType, "Decal")
			H.eq(request.creationContext.creator.groupId, "9")
			local key = string.match(req.body, 'filename="(%a+)%.png"')
			return reply(200, { path = "operations/op-" .. key, done = true, response = { assetId = if key == "Shop" then "111" else "222", assetType = "ASSET_TYPE_DECAL" } })
		elseif string.find(req.url, Uploader.DELIVERY_URL, 1, true) then
			if string.find(req.url, "222", 1, true) then
				return reply(403, { message = "forbidden" })
			end
			return reply(200, { location = "https://cdn.example/decal111" })
		end
		H.eq(req.url, "https://cdn.example/decal111")
		H.eq(req.headers["x-api-key"], nil, "the key only goes to apis.roblox.com")
		return reply(200, decalXml)
	end)
	local opts = Uploader.parseArgs({ "--type", "Decal", "--only", "Shop,Index" }) :: any
	H.eq(Uploader.run(opts, run.deps), 1, "one failure")
	local ids = serde.decode("json", run.writes[Uploader.IDS_FILE])
	H.eq(ids.Shop, 777001, "the image id, not the decal id")
	H.eq(ids.Index, 0, "unresolved decal keeps 0")
	local uploads = serde.decode("json", run.writes[Uploader.UPLOADS_FILE])
	H.eq(uploads.Shop.assetId, "111")
	H.eq(uploads.Index.assetId, "222", "the decal id is kept for the manual fix")
end)

H.test("uploader: no key means no upload (and a hint), already-uploaded icons are skipped", function()
	local run = fakeDeps({ ROBLOX_USER_ID = "42" })
	H.eq(Uploader.run(Uploader.parseArgs({}) :: any, run.deps), 1)
	H.eq(#run.requests, 0)
	H.ok(string.find(run.lines[1], "ROBLOX_API_KEY", 1, true))

	local skip = fakeDeps({})
	local ids = table.clone(Config.ICONS)
	ids.Shop = 99
	skip.writes[Uploader.IDS_FILE] = Uploader.encodeIds(ids)
	Uploader.run(Uploader.parseArgs({ "--dry-run" }) :: any, skip.deps)
	local skipped = false
	for _, line in skip.lines do
		skipped = skipped or string.find(line, "skip icons/Shop.png", 1, true) ~= nil
	end
	H.ok(skipped, "Shop already has an id")
end)
