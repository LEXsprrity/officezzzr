-- Uploads icons/*.png to Roblox (Open Cloud Assets API) and writes their image ids to icons/ids.json.
-- Run from the game folder (the one with default.project.json):
--
--   lune run tools/upload_icons.luau --dry-run      # lists what would be uploaded; no key, no network
--   lune run tools/upload_icons.luau                # uploads every icon whose id in ids.json is still 0
--   lune run tools/upload_icons.luau --only Shop,Index --force   # re-upload just these
--   lune run tools/upload_icons.luau --type Decal   # upload as decals and resolve their image ids
--
-- Needs, in the environment only (never in a file in the repo):
--   ROBLOX_API_KEY                     an Open Cloud API key with Assets read + write
--   ROBLOX_USER_ID or ROBLOX_GROUP_ID  who will own the uploaded images
-- Step-by-step (Portuguese): icons/COMO_SUBIR_ICONES.md. The logic lives in tools/icon_uploader.luau.
local process = require("@lune/process")
local Uploader = require("./icon_uploader")

local opts, err = Uploader.parseArgs(process.args)
if not opts then
	print(`upload_icons: {err}`)
	print("usage: lune run tools/upload_icons.luau [--dry-run] [--type Image|Decal] [--only Key1,Key2] [--force]")
	process.exit(2)
end
process.exit(if Uploader.run(opts :: Uploader.Options, Uploader.realDeps()) == 0 then 0 else 1)
