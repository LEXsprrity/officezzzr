-- The owner's admin panel (owner 2026-10-16): AdminGrant's amounts, checks, names and what a grant does to a
-- save. AdminService (group ranks, the pending-grants DataStore, remotes) is a thin Roblox wrapper.
local fs = require("@lune/fs")
local H = require("./harness")
local Config = H.shared("Config")
local AdminGrant = H.shared("AdminGrant")
local SeedPacks = H.shared("SeedPacks")
local ProfileStore = H.server("ProfileStore")

local function rng(): number
	return 0.5
end

H.test("admin: amounts read like 50K, 1.5M, $25,000", function()
	H.eq(AdminGrant.parseAmount("50K"), 50_000)
	H.eq(AdminGrant.parseAmount("1.5m"), 1_500_000)
	H.eq(AdminGrant.parseAmount("$25,000"), 25_000)
	H.eq(AdminGrant.parseAmount(" 2 B "), 2e9)
	H.eq(AdminGrant.parseAmount("7"), 7)
	for _, bad in { "", "abc", "-5", "1e400", "5x", "1.2.3" } do
		H.eq(AdminGrant.parseAmount(bad), nil, bad)
	end
	H.eq(AdminGrant.parseAmount(5 :: any), nil)
end)

H.test("admin: check keeps good grants and refuses junk", function()
	H.ok(AdminGrant.check({ kind = "Money", amount = 1000 }))
	H.ok(AdminGrant.check({ kind = "Speed", amount = 25_000 }))
	H.ok(AdminGrant.check({ kind = "Seed", zone = #Config.ZONES, rarity = Config.LEGENDARY, count = AdminGrant.MAX_SEEDS }))
	local bad = {
		{ kind = "Money", amount = 0 }, { kind = "Money", amount = -5 }, { kind = "Money", amount = 0 / 0 },
		{ kind = "Money", amount = math.huge }, { kind = "Money", amount = 1.5 }, { kind = "Money", amount = AdminGrant.MAX_AMOUNT + 1 },
		{ kind = "Speed", amount = "5" }, { kind = "Seed", zone = 0, rarity = 1, count = 1 }, { kind = "Seed", zone = 1, rarity = 99, count = 1 },
		{ kind = "Seed", zone = 1, rarity = 1, count = AdminGrant.MAX_SEEDS + 1 }, { kind = "Robux", amount = 5 }, "Money", nil,
	}
	for i, g in bad do
		H.eq(AdminGrant.check(g), nil, `bad grant {i}`)
	end
	-- the copy has only the grant's own fields
	local g = AdminGrant.check({ kind = "Money", amount = 5, evil = true }) :: any
	H.eq(g.evil, nil)
end)

H.test("admin: grants name themselves", function()
	H.eq(AdminGrant.describe({ kind = "Money", amount = 1_500_000 }), "$1.5M")
	H.eq(AdminGrant.describe({ kind = "Speed", amount = 25_000 }), "25K Speed")
	H.eq(AdminGrant.describe({ kind = "Seed", zone = 1, rarity = 1, count = 1 }), `1 Common Seed ({Config.ZONES[1].name})`)
	H.eq(AdminGrant.describe({ kind = "Seed", zone = 7, rarity = 5, count = 3 }), `3 Legendary Seeds ({Config.ZONES[7].name})`)
end)

H.test("admin: a grant adds money, Speed or seeds to a save (seeds stop at the bag's hard cap)", function()
	local p = ProfileStore.defaultProfile()
	p.money, p.speed = 100, 50
	AdminGrant.apply(p, { kind = "Money", amount = 900 }, rng)
	AdminGrant.apply(p, { kind = "Speed", amount = 50 }, rng)
	H.eq(p.money, 1000)
	H.eq(p.speed, 100)
	H.eq(AdminGrant.apply(p, { kind = "Seed", zone = 3, rarity = 4, count = 5 }, rng), 5)
	H.eq(SeedPacks.bagCount(p.seedBag), 5)
	for key in p.seedBag do
		H.ok(string.sub(key, 1, 4) == "3:4#", key)
	end
	p.seedBag = { ["1:1"] = Config.SEED_BAG_HARD_MAX - 2 }
	H.eq(AdminGrant.apply(p, { kind = "Seed", zone = 1, rarity = 1, count = 10 }, rng), 2)
	H.eq(SeedPacks.bagCount(p.seedBag), Config.SEED_BAG_HARD_MAX)
end)

H.test("admin: only the owner's ids and the community's top ranks are admins; the remote is wired", function()
	H.ok(table.find(Config.ADMIN_USER_IDS, 9301943082))
	H.ok(Config.ADMIN_MIN_RANK >= 254)
	local net = fs.readFile("src/server/Net.luau")
	H.ok(string.find(net, 'Admin = remote("Admin")', 1, true))
	local svc = fs.readFile("src/server/AdminService.luau")
	H.ok(string.find(svc, "if not admins[admin] then", 1, true), "non-admins are ignored")
	local main = fs.readFile("src/server/Main.server.luau")
	H.ok(string.find(main, "AdminService.init()", 1, true) and string.find(main, "AdminService.playerReady", 1, true))
end)
