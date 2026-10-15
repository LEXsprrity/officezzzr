-- The store catalog of every gamepass and developer product: what tools/create_monetization.mjs creates on
-- Roblox (name, description, price, icon). Built from Config (labels, robux prices, kinds); written to
-- monetization/catalog.json by tools/export_monetization.luau, checked by tests/monetization.spec.
local Catalog = {}

Catalog.FILE = "monetization/catalog.json"

export type Entry = {
	key: string, -- Config.GAMEPASSES / Config.DEVELOPER_PRODUCTS key (and monetization/ids.json key)
	kind: string, -- "pass" | "product"
	name: string,
	description: string,
	price: number, -- Robux
	image: string, -- PNG under icons/, uploaded as the item's icon
}

-- Passes with no placeholder price in Config (robux = 0): the price they are created with.
Catalog.PASS_PRICES = { DoubleMoney = 349, ExtraSlots = 199 } :: { [string]: number }

-- The passes' store descriptions.
Catalog.PASS_DESCRIPTIONS = {
	DoubleMoney = "Doubles the money all your plants make. Works offline and when you sell, too.",
	DoubleSpeed = "Doubles all the Speed you get from walking and from the treadmill.",
	DoubleLuck = "The seeds you steal roll with double luck, so rare ones show up a lot more often.",
	VIP = "A gold VIP tag over your head and in chat, plus 1.25x money and 1.25x Speed.",
	FastGrow = "Your plants grow twice as fast, even while you're offline.",
	ExtraSlots = "10 more plant slots on your plot, on top of the ones your plot level gives you.",
} :: { [string]: string }

-- The icons/ PNG of each product kind; a pass uses its Shop icon (Config.GAMEPASSES[*].icon) or this.
Catalog.KIND_ICONS = {
	Pack = "SeedPack",
	Speed = "Speed",
	Money = "Money",
	TreadmillUpgrade = "Treadmill",
	Trail = "TrailShop",
	PlotUpgrade = "PlotUpgrade",
	GrowNow = "Seeds",
} :: { [string]: string }
Catalog.PASS_ICON = "Star" -- VIP has no Shop icon (a gold badge)
Catalog.KIND_ORDER = { "Pack", "Speed", "Money", "TreadmillUpgrade", "Trail", "PlotUpgrade", "GrowNow" }

local function mult(x: number): string
	return (string.gsub(string.format("%.2f", x), "%.?0+$", "")) .. "x"
end

-- "Treadmill Upgrade (Lv 2-4)" -> "levels 2 to 4"
local function levels(label: string): string
	local a, b = string.match(label, "Lv (%d+)%-(%d+)")
	assert(a and b, `no level range in "{label}"`)
	return `levels {a} to {b}`
end

local function productDescription(Config: any, Format: any, product: any): string
	local kind = product.kind
	if kind == "Pack" then
		local zone = Config.ZONES[product.zone]
		local count = product.count or 1
		if count > 1 then
			return `{count} {zone.name} seeds for your seed bag at once, each rolled with double luck. Each has a small chance of the pack-only {Config.PACK_EXCLUSIVE} mutation. Needs {count} free spaces in your bag.`
		end
		return `One {zone.name} seed for your seed bag, rolled with double luck. It has a small chance of the pack-only {Config.PACK_EXCLUSIVE} mutation.`
	elseif kind == "Speed" then
		return `Adds {Format.commas(product.amount)} Speed right away, so you can reach farther zones.`
	elseif kind == "Money" then
		return `Gives you {Format.money(product.amount)} right away.`
	elseif kind == "TreadmillUpgrade" then
		return `Upgrades your treadmill by one level. This one covers {levels(product.label)}.`
	elseif kind == "Trail" then
		for _, trail in Config.TRAILS do
			if trail.id == product.trail then
				return `Unlocks and equips the {trail.name}. While it's on, walking and the treadmill give you {mult(trail.mult)} Speed.`
			end
		end
		error(`no trail {product.trail}`)
	elseif kind == "PlotUpgrade" then
		return `Upgrades your plot by one level. This one covers {levels(product.label)}.`
	elseif kind == "GrowNow" then
		local upTo = product.upTo or math.huge
		if upTo == math.huge then
			return "Your sprouting plant finishes growing right away and starts earning, however long it had left."
		end
		return `Your sprouting plant finishes growing right away and starts earning (up to {upTo // 60} minutes left).`
	end
	error(`no description for product kind {kind}`)
end

-- Every pass (Shop order) then every product (by kind, cheapest first).
function Catalog.build(Config: any, Format: any): { Entry }
	local list: { Entry } = {}
	for _, key in Config.passNames() do
		local pass = Config.GAMEPASSES[key]
		table.insert(list, {
			key = key,
			kind = "pass",
			name = pass.label,
			description = assert(Catalog.PASS_DESCRIPTIONS[key], `no description for pass {key}`),
			price = if pass.robux > 0 then pass.robux else assert(Catalog.PASS_PRICES[key], `no price for pass {key}`),
			image = `icons/{pass.icon or Catalog.PASS_ICON}.png`,
		})
	end
	for _, kind in Catalog.KIND_ORDER do
		for _, item in Config.products(kind) do
			table.insert(list, {
				key = item.name,
				kind = "product",
				name = item.product.label,
				description = productDescription(Config, Format, item.product),
				price = item.product.robux,
				image = `icons/{Catalog.KIND_ICONS[kind]}.png`,
			})
		end
	end
	return list
end

local function jsonString(s: string): string
	return '"' .. string.gsub(s, '[%c"\\]', function(c)
		return if c == '"' then '\\"' elseif c == "\\" then "\\\\" else string.format("\\u%04x", string.byte(c))
	end) .. '"'
end

-- catalog.json: one entry per line group, fields in a fixed order (stable diffs).
function Catalog.encode(list: { Entry }): string
	local items = {}
	for _, e in list do
		table.insert(items, table.concat({
			"  {",
			`    "key": {jsonString(e.key)},`,
			`    "kind": {jsonString(e.kind)},`,
			`    "name": {jsonString(e.name)},`,
			`    "description": {jsonString(e.description)},`,
			`    "price": {string.format("%d", e.price)},`,
			`    "image": {jsonString(e.image)}`,
			"  }",
		}, "\n"))
	end
	return "[\n" .. table.concat(items, ",\n") .. "\n]\n"
end

-- monetization/ids.json in the format tools/create_monetization.mjs writes (JSON.stringify(_, null, 2)
-- with sorted keys): { "passes": { key: id }, "products": { key: id } }.
function Catalog.encodeIds(ids: { passes: { [string]: number }, products: { [string]: number } }): string
	local function section(name: string, t: { [string]: number }): string
		local keys = {}
		for k in t do
			table.insert(keys, k)
		end
		table.sort(keys)
		local lines = {}
		for i, k in keys do
			table.insert(lines, string.format('    %s: %d%s', jsonString(k), t[k], if i < #keys then "," else ""))
		end
		return if #keys == 0 then `  "{name}": \{}` else `  "{name}": \{\n` .. table.concat(lines, "\n") .. "\n  }"
	end
	return "{\n" .. section("passes", ids.passes) .. ",\n" .. section("products", ids.products) .. "\n}\n"
end

return Catalog
