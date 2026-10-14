-- Uploads icons/*.png to Roblox through the Open Cloud Assets API and writes their image ids to
-- icons/ids.json (which Rojo turns into Shared.IconIds -> Config.ICONS). The CLI is
-- tools/upload_icons.luau; this module holds the logic so the tests can drive it with a fake network.
--
-- API (https://create.roblox.com/docs/cloud/guides/usage-assets):
--   POST https://apis.roblox.com/assets/v1/assets, header x-api-key, multipart/form-data with
--     request      JSON { assetType, displayName, description, creationContext = { creator = { userId | groupId } } }
--     fileContent  the PNG (image/png)
--   -> { path = "operations/<id>", ... }; poll GET https://apis.roblox.com/assets/v1/operations/<id> until
--      done = true, then response.assetId is the new asset.
-- Asset type: "Image" by default. The docs list Image and Decal as separate upload types with the same
-- formats, and an Image asset's id is what ImageLabel.Image takes (rbxassetid://<id>). A *Decal* asset is a
-- wrapper whose id is NOT the image's id: an ImageLabel given a decal id shows nothing in game. So with
-- `--type Decal` (or if Roblox ever answers with a decal), the image id is resolved from the decal itself:
-- GET https://apis.roblox.com/asset-delivery-api/v1/assetId/<decalId> (x-api-key) -> { location }, download
-- that file (the decal as a Roblox model) and read the image id in its Texture. If that fails, the decal id
-- is kept in icons/uploads.json and ids.json keeps 0 for that icon (see icons/COMO_SUBIR_ICONES.md).
--
-- The API key is read ONLY from the ROBLOX_API_KEY environment variable and is never printed or written.
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

local Uploader = {}

Uploader.ICON_DIR = "icons"
Uploader.IDS_FILE = "icons/ids.json"
Uploader.UPLOADS_FILE = "icons/uploads.json"
Uploader.CREATE_URL = "https://apis.roblox.com/assets/v1/assets"
Uploader.OPERATION_URL = "https://apis.roblox.com/assets/v1/operations/"
Uploader.DELIVERY_URL = "https://apis.roblox.com/asset-delivery-api/v1/assetId/"
Uploader.CREDIT = "Icon from the Free Icon Pack by @gvesster."

export type Options = {
	dryRun: boolean,
	assetType: string, -- "Image" (default) or "Decal"
	force: boolean, -- re-upload icons that already have an id
	only: { string }?, -- just these keys
}

export type Deps = {
	request: (req: { [string]: any }) -> { ok: boolean, statusCode: number, statusMessage: string, headers: { [string]: string }, body: string },
	env: { [string]: string? },
	print: (string) -> (),
	wait: (number) -> (),
	readDir: (string) -> { string },
	readFile: (string) -> string,
	writeFile: (string, string) -> (),
	isFile: (string) -> boolean,
}

function Uploader.realDeps(): Deps
	return {
		request = net.request :: any,
		env = process.env :: any,
		print = print,
		wait = function(s)
			task.wait(s)
		end,
		readDir = fs.readDir,
		readFile = fs.readFile,
		writeFile = fs.writeFile,
		isFile = fs.isFile,
	}
end

-- Command-line arguments -> Options (or nil and an error message).
function Uploader.parseArgs(args: { string }): (Options?, string?)
	local opts: Options = { dryRun = false, assetType = "Image", force = false, only = nil }
	local i = 1
	while i <= #args do
		local a = args[i]
		if a == "--dry-run" then
			opts.dryRun = true
		elseif a == "--force" then
			opts.force = true
		elseif a == "--type" then
			i += 1
			local t = args[i]
			if t ~= "Image" and t ~= "Decal" then
				return nil, `--type must be Image or Decal (got {t or "nothing"})`
			end
			opts.assetType = t :: string
		elseif a == "--only" then
			i += 1
			if not args[i] then
				return nil, "--only needs a comma-separated list of icon names, e.g. --only Shop,Index"
			end
			opts.only = string.split(args[i], ",")
		else
			return nil, `unknown argument {a}`
		end
		i += 1
	end
	return opts, nil
end

-- The icons to upload: every icons/<Key>.png, sorted by key.
function Uploader.listIcons(deps: Deps): { { key: string, path: string } }
	local list = {}
	for _, entry in deps.readDir(Uploader.ICON_DIR) do
		local key = string.match(entry, "^(.+)%.png$")
		if key then
			table.insert(list, { key = key, path = `{Uploader.ICON_DIR}/{entry}` })
		end
	end
	table.sort(list, function(a, b)
		return a.key < b.key
	end)
	return list
end

-- icons/ids.json as { Key = id }.
function Uploader.readIds(deps: Deps): { [string]: number }
	local ids = {}
	if deps.isFile(Uploader.IDS_FILE) then
		for key, id in serde.decode("json", deps.readFile(Uploader.IDS_FILE)) do
			ids[key] = if type(id) == "number" then id else 0
		end
	end
	return ids
end

-- Stable, diff-friendly JSON: one "Key": id per line, keys sorted.
function Uploader.encodeIds(ids: { [string]: number }): string
	local keys = {}
	for key in ids do
		table.insert(keys, key)
	end
	table.sort(keys)
	local lines = {}
	for i, key in keys do
		table.insert(lines, string.format('  "%s": %d%s', key, ids[key], if i < #keys then "," else ""))
	end
	return "{\n" .. table.concat(lines, "\n") .. "\n}\n"
end

-- The creator from ROBLOX_USER_ID or ROBLOX_GROUP_ID: (creator table, description) or (nil, error).
function Uploader.creator(env: { [string]: string? }): ({ [string]: string }?, string)
	local user, group = env.ROBLOX_USER_ID, env.ROBLOX_GROUP_ID
	if user and user ~= "" and group and group ~= "" then
		return nil, "set only one of ROBLOX_USER_ID and ROBLOX_GROUP_ID"
	elseif user and string.match(user, "^%d+$") then
		return { userId = user }, `user {user}`
	elseif group and string.match(group, "^%d+$") then
		return { groupId = group }, `group {group}`
	end
	return nil, "set ROBLOX_USER_ID (your numeric user id) or ROBLOX_GROUP_ID (the group's id) to who will own the icons"
end

function Uploader.requestJson(key: string, assetType: string, creator: { [string]: string }): string
	return serde.encode("json", {
		assetType = assetType,
		displayName = `StealASeed_{key}`,
		description = `Steal a Seed UI icon "{key}". {Uploader.CREDIT}`,
		creationContext = { creator = creator },
	})
end

-- multipart/form-data body with the `request` JSON and the PNG as `fileContent`. Returns (body, boundary).
function Uploader.multipart(requestJson: string, fileName: string, png: string): (string, string)
	local n = 0
	local boundary
	repeat -- a boundary that appears nowhere in the parts
		n += 1
		boundary = string.format("StealASeedIcon%08x%d", math.random(0, 0x7fffffff), n)
	until not string.find(png, boundary, 1, true) and not string.find(requestJson, boundary, 1, true)
	local body = table.concat({
		`--{boundary}\r\n`,
		'Content-Disposition: form-data; name="request"\r\n',
		"Content-Type: application/json\r\n\r\n",
		requestJson,
		`\r\n--{boundary}\r\n`,
		`Content-Disposition: form-data; name="fileContent"; filename="{fileName}"\r\n`,
		"Content-Type: image/png\r\n\r\n",
		png,
		`\r\n--{boundary}--\r\n`,
	})
	return body, boundary
end

-- The image id inside a downloaded decal (a Roblox model file, XML or binary): its Texture content.
function Uploader.imageIdFromDecal(file: string): string?
	if string.sub(file, 1, 2) == "\x1f\x8b" then
		local ok, raw = pcall(serde.decompress, "gzip", file)
		if ok then
			file = raw
		end
	end
	local ok, roots = pcall(roblox.deserializeModel, file)
	if ok then
		for _, root in roots do
			local decals = root:GetDescendants()
			table.insert(decals, root)
			for _, d in decals do
				if d:IsA("Decal") then
					local okTexture, texture = pcall(function()
						return d.Texture
					end)
					local id = okTexture and string.match(tostring(texture), "(%d+)%s*$")
					if id then
						return id
					end
				end
			end
		end
	end
	-- XML fallback: <Content name="Texture"><url>http://www.roblox.com/asset/?id=123</url></Content>
	local texture = string.match(file, '<Content name="Texture">(.-)</Content>') or file
	return string.match(texture, "[?&]id=(%d+)") or string.match(texture, "rbxassetid://(%d+)")
end

local function decodeBody(res): any
	local ok, data = pcall(serde.decode, "json", res.body)
	return if ok then data else nil
end

-- One HTTP call with retries for rate limits (429) and server errors (5xx).
local function call(deps: Deps, req: { [string]: any }, what: string)
	local delay = 2
	for attempt = 1, 6 do
		local ok, res = pcall(deps.request, req)
		if ok and res.statusCode ~= 429 and res.statusCode < 500 then
			return res
		end
		if attempt == 6 then
			if ok then
				return res
			end
			error(`{what}: network error: {res}`)
		end
		local retryAfter = ok and tonumber(res.headers and (res.headers["retry-after"] or res.headers["Retry-After"]))
		deps.print(`  {what}: {if ok then `HTTP {res.statusCode}` else "network error"}, retrying in {retryAfter or delay}s`)
		deps.wait(retryAfter or delay)
		delay = math.min(delay * 2, 30)
	end
	error("unreachable")
end

local function failure(res, what: string): string
	local body = string.sub(res.body or "", 1, 300) -- error bodies hold the message, never the key
	return `{what} failed: HTTP {res.statusCode} {res.statusMessage or ""} {body}`
end

-- Waits for an asset operation; returns its `response` ({ assetId, assetType, ... }).
local function waitOperation(deps: Deps, apiKey: string, first: any, key: string): { [string]: any }
	local op = first
	local id = op.operationId or (type(op.path) == "string" and string.match(op.path, "operations/([^/]+)$"))
	local delay = 1
	for _ = 1, 40 do
		if op.done then
			if op.error then
				error(`{key}: upload rejected: {serde.encode("json", op.error)}`)
			end
			if type(op.response) ~= "table" or not op.response.assetId then
				error(`{key}: operation finished without an assetId: {serde.encode("json", op)}`)
			end
			return op.response
		end
		if not id then
			error(`{key}: no operation id in the answer: {serde.encode("json", op)}`)
		end
		deps.wait(delay)
		delay = math.min(delay + 1, 5)
		local res = call(deps, { url = Uploader.OPERATION_URL .. id, method = "GET", headers = { ["x-api-key"] = apiKey } }, `{key} status`)
		if not res.ok then
			error(failure(res, `{key}: checking the upload`))
		end
		op = decodeBody(res) or {}
	end
	error(`{key}: the upload was still processing after a few minutes; run the uploader again later`)
end

-- A decal's image id, through Open Cloud asset delivery. Returns (imageId?, problem?).
function Uploader.resolveDecal(deps: Deps, apiKey: string, decalId: string): (string?, string?)
	local res = call(deps, { url = Uploader.DELIVERY_URL .. decalId, method = "GET", headers = { ["x-api-key"] = apiKey } }, `decal {decalId}`)
	if not res.ok then
		return nil, failure(res, "asset delivery")
	end
	local location = (decodeBody(res) or {}).location
	if type(location) ~= "string" then
		return nil, "asset delivery gave no download location"
	end
	local file = call(deps, { url = location, method = "GET", headers = { ["Accept-Encoding"] = "gzip" } }, `decal {decalId} download`)
	if not file.ok then
		return nil, failure(file, "downloading the decal")
	end
	local imageId = Uploader.imageIdFromDecal(file.body)
	if not imageId then
		return nil, "no image id inside the decal"
	end
	return imageId, nil
end

local function isDecal(assetType: any): boolean
	return type(assetType) == "string" and string.find(string.lower(assetType), "decal", 1, true) ~= nil
end

-- Uploads (or with dryRun, lists) the icons. Returns the number of failures.
function Uploader.run(opts: Options, deps: Deps): number
	local icons = Uploader.listIcons(deps)
	local ids = Uploader.readIds(deps)
	local todo = {}
	for _, icon in icons do
		if ids[icon.key] == nil then
			ids[icon.key] = 0
		end
		local wanted = opts.only == nil or table.find(opts.only :: { string }, icon.key) ~= nil
		if wanted and (opts.force or ids[icon.key] == 0) then
			table.insert(todo, icon)
		end
	end
	local creator, who = Uploader.creator(deps.env)

	if opts.dryRun then
		deps.print(`DRY RUN: nothing is uploaded and no API key is needed. {#icons} icons in {Uploader.ICON_DIR}/, {#todo} to upload as {opts.assetType} assets{if creator then ` owned by {who}` else ""}:`)
		for _, icon in todo do
			local size = #deps.readFile(icon.path)
			deps.print(`  would upload {icon.path} ({size} bytes) as "StealASeed_{icon.key}" -> ids.json "{icon.key}"`)
		end
		for _, icon in icons do
			if not table.find(todo, icon) then
				deps.print(`  skip {icon.path}: ids.json already has {ids[icon.key]} (use --force to upload again)`)
			end
		end
		if not creator then
			deps.print(`Note for the real run: {who}.`)
		end
		return 0
	end

	local apiKey = deps.env.ROBLOX_API_KEY
	if not apiKey or apiKey == "" then
		deps.print("ROBLOX_API_KEY is not set. Create an Open Cloud API key with Assets read + write (see icons/COMO_SUBIR_ICONES.md) and set it in this terminal only.")
		return 1
	end
	if not creator then
		deps.print(`Can't upload: {who}.`)
		return 1
	end

	local uploads = {}
	if deps.isFile(Uploader.UPLOADS_FILE) then
		local ok, data = pcall(serde.decode, "json", deps.readFile(Uploader.UPLOADS_FILE))
		uploads = if ok and type(data) == "table" then data else {}
	end
	local function save()
		deps.writeFile(Uploader.IDS_FILE, Uploader.encodeIds(ids))
		deps.writeFile(Uploader.UPLOADS_FILE, serde.encode("json", uploads, true) .. "\n")
	end

	deps.print(`Uploading {#todo} icons as {opts.assetType} assets owned by {who}...`)
	local failures = 0
	for _, icon in todo do
		local ok, err = pcall(function()
			local body, boundary = Uploader.multipart(Uploader.requestJson(icon.key, opts.assetType, creator :: any), icon.key .. ".png", deps.readFile(icon.path))
			local res = call(deps, {
				url = Uploader.CREATE_URL,
				method = "POST",
				headers = { ["x-api-key"] = apiKey, ["Content-Type"] = `multipart/form-data; boundary={boundary}` },
				body = body,
			}, icon.key)
			if not res.ok then
				error(failure(res, `{icon.key}: upload`))
			end
			local result = waitOperation(deps, apiKey :: string, decodeBody(res) or {}, icon.key)
			local assetId = tostring(result.assetId)
			local record = { assetId = assetId, assetType = result.assetType, imageId = nil :: string? }
			uploads[icon.key] = record
			if isDecal(result.assetType) or opts.assetType == "Decal" then
				local imageId, problem = Uploader.resolveDecal(deps, apiKey :: string, assetId)
				if not imageId then
					save()
					error(`{icon.key}: uploaded as decal {assetId}, but its image id couldn't be read ({problem}). ids.json keeps 0; see icons/COMO_SUBIR_ICONES.md to get the image id in Studio`)
				end
				record.imageId = imageId
			else
				record.imageId = assetId
			end
			ids[icon.key] = tonumber(record.imageId) :: number
			save()
			deps.print(`  {icon.key}: image {record.imageId}{if record.imageId ~= assetId then ` (decal {assetId})` else ""}`)
		end)
		if not ok then
			failures += 1
			deps.print(`  FAILED {err}`)
		end
	end
	deps.print(if failures == 0 then `Done: {Uploader.IDS_FILE} updated. Rebuild with Rojo (or let rojo serve sync) to see the icons.`
		else `{failures} icon(s) failed; the others are saved in {Uploader.IDS_FILE}. Fix the problem and run again: icons that already have an id are skipped.`)
	return failures
end

return Uploader
