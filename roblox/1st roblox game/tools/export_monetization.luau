-- Writes monetization/catalog.json: every gamepass and developer product with its store name, description,
-- Robux price and icon (tools/monetization_catalog.luau builds it from Config). tools/create_monetization.mjs
-- creates the items on Roblox from that file. Run from the game folder after changing Config's products:
--   lune run tools/export_monetization.luau
local fs = require("@lune/fs")
local H = require("../tests/harness")
local Catalog = require("./monetization_catalog")

local list = Catalog.build(H.shared("Config"), H.shared("Format"))
fs.writeFile(Catalog.FILE, Catalog.encode(list))
local passes = 0
for _, e in list do
	if e.kind == "pass" then
		passes += 1
	end
end
print(`{Catalog.FILE}: {#list - passes} developer products + {passes} gamepasses`)
