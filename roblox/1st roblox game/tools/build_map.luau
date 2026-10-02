-- REGENERATES the map from code into map/World.rbxm (Rojo puts it at Workspace.World). That file is the
-- hand-editable map the game uses, so this refuses to replace it unless run with --force, which DISCARDS
-- every hand edit in it. Run from the game folder:
--   lune run tools/build_map.luau --force
-- To put new models from assets/ into the current map while keeping hand edits, use
-- tools/apply_assets.luau instead.
local process = require("@lune/process")
local MapTool = require("./map_tool")

local ok, message = MapTool.regenerate(process.args, MapTool.PATH)
print(message)
process.exit(if ok then 0 else 1)
