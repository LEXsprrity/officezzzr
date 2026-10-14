-- Prints the rarity odds per zone (day and night pods) and per premium pack, as Markdown tables.
-- Handy for tuning:  lune run tests/rarity_table.luau
local H = require("./harness")
local Config = H.shared("Config")
local SeedPacks = H.shared("SeedPacks")

local function pct(x: number): string
	return SeedPacks.percent(x)
end

local function shares(k: number, luck: number): { number }
	local w = Config.rarityWeights(k, luck)
	local total = 0
	for _, x in w do
		total += x
	end
	local out = {}
	for i, x in w do
		out[i] = x / total * 100
	end
	return out
end

local head = { "Zone", "When" }
for _, r in Config.RARITIES do
	table.insert(head, r.id)
end
table.insert(head, "Legendary 1 in")
local lines = { "| " .. table.concat(head, " | ") .. " |", string.rep("|---", #head) .. "|" }
for k, zone in Config.ZONES do
	for _, night in { false, true } do
		local s = shares(k, if night then Config.NIGHT_LUCK else 1)
		local row = { `{k} {zone.name}`, if night then "night" else "day" }
		for _, x in s do
			table.insert(row, pct(x))
		end
		table.insert(row, string.format("%d", math.floor(100 / s[#s] + 0.5)))
		table.insert(lines, "| " .. table.concat(row, " | ") .. " |")
	end
end
table.insert(lines, "")
for _, entry in Config.products("Pack") do
	local pack = SeedPacks.packForProduct(entry.product)
	local odds = SeedPacks.odds(pack)
	local row = { pack.name, "pack" }
	for _, x in odds.rarities do
		table.insert(row, pct(x))
	end
	table.insert(row, string.format("%d", math.floor(100 / odds.rarities[#odds.rarities] + 0.5)))
	table.insert(lines, "| " .. table.concat(row, " | ") .. " |")
end
print(table.concat(lines, "\n"))
