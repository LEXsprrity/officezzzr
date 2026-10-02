-- Puts the models from assets/ into map/World.rbxm, keeping every hand edit: each map piece that is still
-- built from code and whose slot now has a model is replaced where it stands (moved or rotated pieces keep
-- their spot). With --all, pieces that already came from assets/ are replaced too (after re-exporting a
-- model). The server does the same at start, so this is what makes them show in Studio edit mode.
-- Run from the game folder:
--   lune run tools/apply_assets.luau [--all]
local process = require("@lune/process")
local MapTool = require("./map_tool")

local ok, message = MapTool.applyAssets(process.args, MapTool.PATH)
print(message)
process.exit(if ok then 0 else 1)
