-- Every script compiles at every optimization level. Studio compiles without optimizations (-O0), where
-- a script's top-level locals each keep a register: past 200 the script fails to compile and never runs
-- (that is how the whole HUD once went missing while -O1/-O2 builds still compiled fine).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local H = require("./harness")

local files: { string } = {}
local function collect(dir: string)
	for _, entry in fs.readDir(dir) do
		if string.match(entry, "%.luau$") then
			table.insert(files, dir .. "/" .. entry)
		elseif fs.isDir(dir .. "/" .. entry) then -- sub-folders too (src/server/Zones)
			collect(dir .. "/" .. entry)
		end
	end
end
for _, dir in { "src/client", "src/server", "src/shared" } do
	collect(dir)
end
table.sort(files)

H.test("every script compiles at -O0, -O1 and -O2", function()
	H.ok(#files > 20, `{#files} scripts found`)
	for _, file in files do
		local source = fs.readFile(file)
		for level = 0, 2 do
			local ok, err = pcall(luau.compile, source, { optimizationLevel = level })
			H.ok(ok, `{file} at -O{level}: {err}`)
		end
	end
end)

H.test("the HUD keeps headroom under the 200-register limit at -O0", function()
	-- 15 more top-level locals must still fit, so the next feature doesn't silently break the HUD again.
	local extra = {}
	for i = 1, 15 do
		table.insert(extra, `local headroom{i} = {i}`)
	end
	for i = 1, 15 do
		table.insert(extra, `print(headroom{i})`)
	end
	local source = fs.readFile("src/client/HUD.client.luau") .. "\n" .. table.concat(extra, "\n")
	local ok, err = pcall(luau.compile, source, { optimizationLevel = 0 })
	H.ok(ok, `HUD with 15 more locals at -O0: {err}`)
end)
