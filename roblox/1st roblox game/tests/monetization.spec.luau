-- Gamepass / developer product ids and store catalog: monetization/ids.json -> Config (Shared.MonetizationIds),
-- monetization/catalog.json (tools/monetization_catalog.luau) and the creator tool's own tests
-- (tests/monetization.test.mjs, run with node).
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local H = require("./harness")
local Catalog = require("../tools/monetization_catalog")

local Config = H.shared("Config")
local Format = H.shared("Format")

local function readText(path: string): string
	return (string.gsub(fs.readFile(path), "\r", ""))
end

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local STUB = serde.decode("json", fs.readFile("tests/fixtures/monetization_stub.json")) -- what the other specs run with

-- Products added since tools/create_monetization.mjs last ran: 0 in ids.json until it runs again (the Shop says
-- "coming soon" for them meanwhile). Empty: every product and pass is created on Roblox.
local PENDING: { [string]: boolean } = {}

H.test("monetization: ids.json has every pass and product created (a real id each), and Config reads it", function()
	local raw = serde.decode("json", fs.readFile("monetization/ids.json"))
	Config.applyMonetizationIds(raw)
	H.eq(count(raw), 2, "ids.json has only passes + products")
	for section, list in { passes = Config.GAMEPASSES, products = Config.DEVELOPER_PRODUCTS } do
		local ids = raw[section]
		H.eq(type(ids), "table", `ids.json {section}`)
		H.eq(count(ids), count(list), `ids.json {section} key count`)
		for key, item in list :: { [string]: any } do
			local id = ids[key]
			H.eq(type(id), "number", `ids.json {section}.{key}`)
			if PENDING[key] and id == 0 then
				H.eq(item.id, 0, `{key}: not created yet (coming soon)`)
				continue
			end
			H.ok(id > 0 and id == math.floor(id), `ids.json {section}.{key} is a real id (created on Roblox)`)
			H.eq(item.id, id, `Config {section}.{key}.id`)
		end
	end
	for key in PENDING do
		H.ok(Config.DEVELOPER_PRODUCTS[key] ~= nil and raw.products[key] ~= nil, `{key} has its ids.json slot`)
	end
	H.eq(Catalog.encodeIds(raw), readText("monetization/ids.json"), "ids.json is in the tool's format")
	Config.applyMonetizationIds(STUB)
end)

H.test("monetization: a missing or bad id is 0, a good one is used", function()
	local raw = serde.decode("json", fs.readFile("monetization/ids.json"))
	local ok, err = pcall(function()
		Config.applyMonetizationIds({ passes = { VIP = 123, DoubleLuck = -4, FastGrow = "9" }, products = { Speed25K = 456, Money24K = 1.5 } })
		H.eq(Config.GAMEPASSES.VIP.id, 123)
		H.eq(Config.GAMEPASSES.DoubleLuck.id, 0, "negative")
		H.eq(Config.GAMEPASSES.FastGrow.id, 0, "string")
		H.eq(Config.GAMEPASSES.DoubleMoney.id, 0, "missing")
		H.eq(Config.DEVELOPER_PRODUCTS.Speed25K.id, 456)
		H.eq(Config.DEVELOPER_PRODUCTS.Money24K.id, 0, "fraction")
		H.eq(Config.DEVELOPER_PRODUCTS.PackSpace.id, 0, "missing")
		local name = Config.productById(456)
		H.eq(name, "Speed25K", "productById sees the loaded id")
		Config.applyMonetizationIds({ passes = 5 })
		H.eq(Config.GAMEPASSES.VIP.id, 0, "bad section")
		Config.applyMonetizationIds(nil)
		H.eq(Config.DEVELOPER_PRODUCTS.Speed25K.id, 0, "no file data")
	end)
	Config.applyMonetizationIds(STUB)
	if not ok then
		error(err, 0)
	end
end)

H.test("monetization: catalog.json is up to date and covers every pass and product", function()
	local list = Catalog.build(Config, Format)
	H.eq(Catalog.encode(list), readText(Catalog.FILE), "catalog.json is stale: run lune run tools/export_monetization.luau")
	H.eq(#serde.decode("json", fs.readFile(Catalog.FILE)), #list, "catalog.json decodes")
	local seen = { pass = {}, product = {} }
	local names = { pass = {}, product = {} }
	for _, e in list do
		local source = if e.kind == "pass" then Config.GAMEPASSES else if e.kind == "product" then Config.DEVELOPER_PRODUCTS else nil
		H.ok(source and source[e.key], `{e.kind} {e.key} is in Config`)
		H.ok(not seen[e.kind][e.key], `{e.key} listed once`)
		seen[e.kind][e.key] = true
		H.ok(e.price > 0 and e.price == math.floor(e.price), `{e.key} price {e.price}`)
		if source and source[e.key].robux > 0 then
			H.eq(e.price, source[e.key].robux, `{e.key} price is Config's robux`)
		end
		H.ok(string.match(e.image, "^icons/[%w]+%.png$") and fs.isFile(e.image), `{e.key} image {e.image} exists`)
		H.ok(#e.name > 0 and #e.name <= 50, `{e.key} name length`)
		H.eq(e.name, source[e.key].label, `{e.key} name is its Shop label`)
		H.ok(not names[e.kind][string.lower(e.name)], `{e.key} name "{e.name}" is unique (the tool dedupes by name)`)
		names[e.kind][string.lower(e.name)] = true
		H.ok(#e.description >= 20 and #e.description <= 1000, `{e.key} description length`)
		H.ok(not string.find(e.description, "[\128-\255]"), `{e.key} description is plain text`)
	end
	H.eq(count(seen.pass), count(Config.GAMEPASSES), "every pass")
	H.eq(count(seen.product), count(Config.DEVELOPER_PRODUCTS), "every product")
	H.eq(#list, 40, "6 passes + 34 products (the x10 packs, the Grow Now products: owner 2026-10-15)")
	-- The passes without a placeholder price get the agreed ones.
	for _, e in list do
		if e.key == "DoubleMoney" then
			H.eq(e.price, 349)
		elseif e.key == "ExtraSlots" then
			H.eq(e.price, 199)
		end
	end
end)

H.test("monetization: tools/create_monetization.mjs (node --test tests/monetization.test.mjs)", function()
	local ok, res = pcall(process.exec, "node", { "--test", "tests/monetization.test.mjs" })
	if not ok then
		print("  (skipped: node not found)")
		return
	end
	H.ok(res.ok, `node tests failed:\n{res.stdout}\n{res.stderr}`)
end)
