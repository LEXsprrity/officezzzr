// Creates every gamepass and developer product of monetization/catalog.json on Roblox (Open Cloud) and
// writes their ids into monetization/ids.json (Config reads them from there). Safe to run again: items
// that already have an id, or that already exist in the experience with the same name, are never created
// twice. Step-by-step (Portuguese): monetization/LEIA-ME.md. Run from the game folder:
//
//   node tools/create_monetization.mjs --dry-run                 # what would be created; no key, no network
//   node tools/create_monetization.mjs --universe <universeId>   # creates the missing ones
//
// The API key is read ONLY from the environment variable ROBLOX_API_KEY (Open Cloud key with Developer
// Products read + write and Game Passes read + write for this experience). It is never printed, written or
// taken as an argument. The universe id can also come from ROBLOX_UNIVERSE_ID.
import { readFile, writeFile } from "node:fs/promises";
import { basename } from "node:path";
import { pathToFileURL } from "node:url";

export const CATALOG_FILE = "monetization/catalog.json";
export const IDS_FILE = "monetization/ids.json";
const API = "https://apis.roblox.com";

// Per kind: where ids.json keeps it, the Open Cloud collection and the id field of its responses.
export const KINDS = {
	product: {
		section: "products",
		label: "developer product",
		base: (u) => `${API}/developer-products/v2/universes/${u}/developer-products`,
		listPath: "/creator",
		listField: "developerProducts",
		idField: "productId",
	},
	pass: {
		section: "passes",
		label: "gamepass",
		base: (u) => `${API}/game-passes/v1/universes/${u}/game-passes`,
		listPath: "/creator",
		listField: "gamePasses",
		idField: "gamePassId",
	},
};

const USAGE = "usage: node tools/create_monetization.mjs [--dry-run] [--universe <universeId>]";

// Command line -> { dryRun, universe } or { error }. Unknown arguments are refused without echoing them
// (one could be a pasted key).
export function parseArgs(argv, env) {
	const opts = { dryRun: false, universe: env.ROBLOX_UNIVERSE_ID || null, help: false };
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (a === "--dry-run") opts.dryRun = true;
		else if (a === "--help" || a === "-h") opts.help = true;
		else if (a === "--universe") {
			opts.universe = argv[++i] ?? "";
		} else if (a.startsWith("--universe=")) {
			opts.universe = a.slice("--universe=".length);
		} else {
			return { error: `unknown argument #${i + 1}${a.startsWith("--") && a.length < 32 ? ` (${a.split("=")[0]})` : ""}` };
		}
	}
	if (opts.universe !== null && !/^\d+$/.test(opts.universe)) {
		return { error: "--universe must be the experience's numeric universe id" };
	}
	if (!opts.dryRun && !opts.help && !opts.universe) {
		return { error: "pass --universe <universeId> (or set ROBLOX_UNIVERSE_ID)" };
	}
	return opts;
}

const validId = (id) => (Number.isSafeInteger(id) && id > 0 ? id : 0);

// ids.json (any shape, or null) -> { passes: { key: id }, products: { key: id } } with only valid ids.
export function normalizeIds(raw) {
	const out = { passes: {}, products: {} };
	for (const section of ["passes", "products"]) {
		const t = raw && typeof raw === "object" ? raw[section] : null;
		if (t && typeof t === "object") {
			for (const [k, v] of Object.entries(t)) out[section][k] = validId(v);
		}
	}
	return out;
}

// The text ids.json is kept in: sorted keys, 2-space indent (tools/monetization_catalog.luau encodeIds
// writes the same).
export function encodeIds(ids) {
	const sorted = (t) => Object.fromEntries(Object.keys(t).sort().map((k) => [k, t[k]]));
	return JSON.stringify({ passes: sorted(ids.passes), products: sorted(ids.products) }, null, 2) + "\n";
}

// Every catalog key gets a slot (0 until created); keys no longer in the catalog are kept as they are.
export function withCatalogKeys(ids, catalog) {
	const out = { passes: { ...ids.passes }, products: { ...ids.products } };
	for (const e of catalog) {
		const t = out[KINDS[e.kind].section];
		if (!(e.key in t)) t[e.key] = 0;
	}
	return out;
}

const nameKey = (s) => String(s ?? "").trim().toLowerCase();

// What to do with each catalog entry, given ids.json and (unless dry-run: null) what the universe already
// has: { product: [{ id, name }], pass: [{ id, name }] }. Returns one row per entry:
//   existing  id known (ids.json, or an item with the same name in the universe): nothing to create
//   create    to be created
//   failed    ids.json has an id the universe doesn't have (wrong universe?): left alone, never re-created
export function plan(catalog, ids, existing) {
	const byName = {};
	const byId = {};
	for (const kind of Object.keys(KINDS)) {
		byName[kind] = new Map();
		byId[kind] = new Set();
		for (const item of existing?.[kind] ?? []) {
			byId[kind].add(item.id);
			const n = nameKey(item.name);
			// Same name twice on Roblox: keep the oldest (lowest id).
			if (!byName[kind].has(n) || item.id < byName[kind].get(n)) byName[kind].set(n, item.id);
		}
	}
	const seen = new Set();
	return catalog.map((e) => {
		const kind = KINDS[e.kind];
		if (!kind) return { entry: e, status: "failed", id: 0, note: `unknown kind "${e.kind}"` };
		if (seen.has(`${e.kind}:${e.key}`)) return { entry: e, status: "failed", id: 0, note: "key listed twice in catalog" };
		seen.add(`${e.kind}:${e.key}`);
		const known = validId(ids[kind.section]?.[e.key]);
		if (known) {
			if (existing && !byId[e.kind].has(known)) {
				return { entry: e, status: "failed", id: known, note: `id ${known} from ids.json is not a ${kind.label} of this universe (wrong --universe? set it to 0 to create it again)` };
			}
			return { entry: e, status: "existing", id: known, note: "id in ids.json" };
		}
		const found = existing ? byName[e.kind].get(nameKey(e.name)) : undefined;
		if (found) return { entry: e, status: "existing", id: found, note: "found by name on Roblox" };
		return { entry: e, status: "create", id: 0, note: "" };
	});
}

// Puts the ids of the rows (existing or created) into ids (a new object).
export function mergeIds(ids, rows) {
	const out = { passes: { ...ids.passes }, products: { ...ids.products } };
	for (const r of rows) {
		if ((r.status === "existing" || r.status === "created") && validId(r.id)) {
			out[KINDS[r.entry.kind].section][r.entry.key] = r.id;
		}
	}
	return out;
}

// The summary table.
export function table(rows) {
	const head = ["key", "kind", "name", "price", "id", "status", "note"];
	const cells = rows.map((r) => [r.entry.key, r.entry.kind, r.entry.name, `R$ ${r.entry.price}`, r.id ? String(r.id) : "-", r.status, r.note || ""]);
	const widths = head.map((h, i) => Math.max(h.length, ...cells.map((c) => c[i].length)));
	const line = (c) => c.map((x, i) => (i === c.length - 1 ? x : x.padEnd(widths[i]))).join("  ").trimEnd();
	return [line(head), line(widths.map((w) => "-".repeat(w))), ...cells.map(line)].join("\n");
}

// Never let the key reach the screen, even inside an error message.
const redact = (text, key) => (key ? String(text).split(key).join("***") : String(text));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// One API call, retried on 429 (rate limit) and 5xx with backoff (Retry-After when given).
export async function call(deps, url, init, attempts = 6) {
	let wait = 1000;
	for (let attempt = 1; ; attempt++) {
		let res;
		try {
			res = await deps.fetch(url, { ...init, body: init.body ? init.body() : undefined });
		} catch (err) {
			if (attempt >= attempts) throw new Error(`network error: ${err.message}`);
			await deps.sleep(wait);
			wait = Math.min(wait * 2, 30000);
			continue;
		}
		if (res.status === 429 || res.status >= 500) {
			if (attempt >= attempts) throw new Error(`HTTP ${res.status} after ${attempts} tries: ${(await res.text()).slice(0, 300)}`);
			const after = Number(res.headers?.get?.("retry-after"));
			await deps.sleep(Number.isFinite(after) && after > 0 ? Math.min(after * 1000, 60000) : wait);
			wait = Math.min(wait * 2, 30000);
			continue;
		}
		const text = await res.text();
		if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 300)}`);
		return text ? JSON.parse(text) : {};
	}
}

// Everything of one kind in the universe: [{ id, name }].
export async function listAll(deps, kindName, universe, apiKey) {
	const kind = KINDS[kindName];
	const out = [];
	let token = "";
	for (let page = 0; page < 200; page++) {
		const url = `${kind.base(universe)}${kind.listPath}?pageSize=50${token ? `&pageToken=${encodeURIComponent(token)}` : ""}`;
		const body = await call(deps, url, { method: "GET", headers: { "x-api-key": apiKey } });
		for (const item of body[kind.listField] ?? []) {
			const id = validId(Number(item[kind.idField]));
			if (id) out.push({ id, name: item.name });
		}
		token = body.nextPageToken;
		if (!token) return out;
	}
	throw new Error(`listing ${kind.label}s: too many pages`);
}

// Creates one catalog entry; returns its new id.
export async function create(deps, entry, universe, apiKey) {
	const kind = KINDS[entry.kind];
	const image = await deps.readFile(entry.image);
	const body = () => {
		const form = new FormData();
		form.append("name", entry.name);
		form.append("description", entry.description);
		form.append("isForSale", "true");
		form.append("price", String(entry.price));
		form.append("imageFile", new Blob([image], { type: "image/png" }), basename(entry.image));
		return form;
	};
	const res = await call(deps, kind.base(universe), { method: "POST", headers: { "x-api-key": apiKey }, body });
	const id = validId(Number(res[kind.idField]));
	if (!id) throw new Error(`no ${kind.idField} in the response`);
	return id;
}

export async function run(argv, env, deps) {
	const opts = parseArgs(argv, env);
	if (opts.error || opts.help) {
		deps.print(opts.error ? `create_monetization: ${opts.error}\n${USAGE}` : USAGE);
		return opts.error ? 2 : 0;
	}
	const catalog = JSON.parse(await deps.readFile(CATALOG_FILE, "utf8"));
	let rawIds = null;
	try {
		rawIds = JSON.parse(await deps.readFile(IDS_FILE, "utf8"));
	} catch {
		rawIds = null; // no file yet: everything is 0
	}
	let ids = withCatalogKeys(normalizeIds(rawIds), catalog);

	if (opts.dryRun) {
		const rows = plan(catalog, ids, null);
		for (const r of rows) if (r.status === "create") r.note = "would be created (unless one with this name exists)";
		deps.print(`DRY RUN: nothing is sent to Roblox. ${rows.filter((r) => r.status === "create").length} of ${rows.length} items have no id in ${IDS_FILE} yet.\n`);
		deps.print(table(rows));
		return 0;
	}

	const apiKey = env.ROBLOX_API_KEY;
	if (!apiKey) {
		deps.print("create_monetization: set the ROBLOX_API_KEY environment variable first (monetization/LEIA-ME.md)");
		return 2;
	}
	const save = async () => deps.writeFile(IDS_FILE, encodeIds(ids));

	let rows;
	try {
		deps.print(`Universe ${opts.universe}: reading the existing developer products and gamepasses...`);
		const existing = {
			product: await listAll(deps, "product", opts.universe, apiKey),
			pass: await listAll(deps, "pass", opts.universe, apiKey),
		};
		deps.print(`found ${existing.product.length} developer products and ${existing.pass.length} gamepasses.\n`);
		rows = plan(catalog, ids, existing);
	} catch (err) {
		deps.print(`create_monetization: could not list the universe's items, nothing was created: ${redact(err.message, apiKey)}`);
		return 1;
	}
	ids = mergeIds(ids, rows);
	await save();

	for (const r of rows) {
		if (r.status !== "create") continue;
		try {
			r.id = await create(deps, r.entry, opts.universe, apiKey);
			r.status = "created";
			ids = mergeIds(ids, [r]);
			await save(); // after every item, so a crash halfway keeps what was made
			deps.print(`created ${r.entry.kind} ${r.entry.key} -> ${r.id}`);
		} catch (err) {
			r.status = "failed";
			r.note = redact(err.message, apiKey);
			deps.print(`FAILED ${r.entry.kind} ${r.entry.key}: ${r.note}`);
		}
	}

	deps.print("\n" + table(rows));
	const count = (s) => rows.filter((r) => r.status === s).length;
	deps.print(`\n${count("created")} created, ${count("existing")} existing, ${count("failed")} failed. Ids written to ${IDS_FILE}.`);
	return count("failed") > 0 ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	const deps = {
		fetch: globalThis.fetch,
		readFile,
		writeFile: (path, text) => writeFile(path, text, "utf8"),
		sleep,
		print: (s) => console.log(s),
	};
	run(process.argv.slice(2), process.env, deps).then(
		(code) => process.exit(code),
		(err) => {
			console.error(`create_monetization: ${redact(err.message, process.env.ROBLOX_API_KEY)}`);
			process.exit(1);
		}
	);
}
