// tools/create_monetization.mjs with a fake Roblox (no network, no key). Run from the game folder:
//   node --test tests/monetization.test.mjs
// tests/monetization.spec.luau runs it as part of `lune run tests/run.luau`.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import * as M from "../tools/create_monetization.mjs";

const KEY = "test-key-SECRET-1234567890";
const UNIVERSE = "4242";

const entry = (key, kind, name, price = 10) => ({ key, kind, name, description: `${name}!`, price, image: "icons/Speed.png" });
const CATALOG = [
	entry("VIP", "pass", "VIP", 399),
	entry("DoubleLuck", "pass", "2x Luck", 249),
	entry("Speed25K", "product", "+25K Speed", 9),
	entry("Money24K", "product", "Pocket Cash", 40),
	entry("TrailRed", "product", "Red Trail", 100),
];

// A fake Open Cloud: lists in pages of 2, creates with increasing ids, optional 429s, records every call.
function fakeRoblox({ products = [], passes = [], rateLimits = 0, failNames = [] } = {}) {
	const state = { products: [...products], passes: [...passes], calls: [], nextId: 9000, rateLimits };
	const reply = (status, body, headers = {}) => ({
		status,
		ok: status >= 200 && status < 300,
		headers: { get: (h) => headers[h.toLowerCase()] ?? null },
		text: async () => (typeof body === "string" ? body : JSON.stringify(body)),
	});
	state.fetch = async (url, init) => {
		state.calls.push({ url, method: init.method, headers: init.headers });
		assert.equal(init.headers["x-api-key"], KEY);
		if (state.rateLimits > 0) {
			state.rateLimits--;
			return reply(429, "slow down", { "retry-after": "1" });
		}
		const u = new URL(url);
		const isPass = u.pathname.includes("/game-passes/");
		const list = isPass ? state.passes : state.products;
		const idField = isPass ? "gamePassId" : "productId";
		assert.ok(u.pathname.includes(`/universes/${UNIVERSE}/`));
		if (init.method === "GET") {
			assert.ok(u.pathname.endsWith("/creator"));
			const start = Number(u.searchParams.get("pageToken") || 0);
			const page = list.slice(start, start + 2).map((x) => ({ [idField]: x.id, name: x.name }));
			const next = start + 2 < list.length ? String(start + 2) : "";
			return reply(200, { [isPass ? "gamePasses" : "developerProducts"]: page, nextPageToken: next });
		}
		const form = init.body;
		assert.ok(form instanceof FormData);
		assert.equal(form.get("isForSale"), "true");
		assert.ok(Number(form.get("price")) > 0);
		assert.ok(form.get("imageFile") instanceof Blob);
		if (failNames.includes(form.get("name"))) return reply(400, `bad name, key was ${KEY}`);
		const item = { id: state.nextId++, name: form.get("name"), price: Number(form.get("price")) };
		list.push(item);
		return reply(200, { [idField]: item.id, name: item.name });
	};
	return state;
}

function deps(roblox, files) {
	const out = [];
	return {
		out,
		files,
		fetch: roblox.fetch,
		sleep: async () => {},
		print: (s) => out.push(s),
		readFile: async (path, enc) => {
			if (path.endsWith(".png")) return Buffer.from([0x89, 0x50, 0x4e, 0x47]);
			if (!(path in files)) throw new Error("ENOENT");
			return files[path];
		},
		writeFile: async (path, text) => {
			files[path] = text;
		},
	};
}

const startFiles = (ids) => ({
	[M.CATALOG_FILE]: JSON.stringify(CATALOG),
	...(ids ? { [M.IDS_FILE]: M.encodeIds(M.normalizeIds(ids)) } : {}),
});
const idsOf = (d) => JSON.parse(d.files[M.IDS_FILE]);

test("parseArgs: universe from flag or env, never a key argument", () => {
	assert.deepEqual(M.parseArgs(["--universe", "12"], {}), { dryRun: false, universe: "12", help: false });
	assert.equal(M.parseArgs([], { ROBLOX_UNIVERSE_ID: "34" }).universe, "34");
	assert.equal(M.parseArgs(["--dry-run"], {}).dryRun, true);
	assert.match(M.parseArgs([], {}).error, /--universe/);
	assert.match(M.parseArgs(["--universe", "abc"], {}).error, /numeric/);
	const e = M.parseArgs(["--universe", "1", KEY], {}).error;
	assert.ok(e && !e.includes(KEY), "an unknown argument is refused without echoing it");
	assert.ok(!M.parseArgs([`--api-key=${KEY}`], {}).error.includes(KEY));
});

test("ids.json: normalize keeps whole positive ids, encode is sorted and stable", () => {
	const ids = M.normalizeIds({ passes: { VIP: 5, B: -1, C: 1.5, D: "7" }, products: { Z: 3, A: 0 }, junk: 1 });
	assert.deepEqual(ids, { passes: { VIP: 5, B: 0, C: 0, D: 0 }, products: { Z: 3, A: 0 } });
	assert.deepEqual(M.normalizeIds(null), { passes: {}, products: {} });
	assert.equal(M.encodeIds(ids), '{\n  "passes": {\n    "B": 0,\n    "C": 0,\n    "D": 0,\n    "VIP": 5\n  },\n  "products": {\n    "A": 0,\n    "Z": 3\n  }\n}\n');
	// The committed file is in this exact format (the Lune side writes the same, tests/monetization.spec).
	const committed = readFileSync(M.IDS_FILE, "utf8").replace(/\r/g, "");
	assert.equal(M.encodeIds(M.normalizeIds(JSON.parse(committed))), committed);
});

test("plan: ids.json first, then same name on Roblox (oldest wins), else create", () => {
	const ids = M.withCatalogKeys(M.normalizeIds({ passes: { VIP: 77 }, products: { Gone: 5 } }), CATALOG);
	assert.equal(ids.products.Gone, 5, "keys not in the catalog are kept");
	assert.equal(ids.products.Speed25K, 0);
	const existing = {
		pass: [{ id: 77, name: "VIP" }, { id: 12, name: " 2X LUCK " }, { id: 11, name: "2x luck" }],
		product: [{ id: 30, name: "Pocket Cash" }, { id: 31, name: "+25K Speed (old)" }],
	};
	const rows = M.plan(CATALOG, ids, existing);
	const by = Object.fromEntries(rows.map((r) => [r.entry.key, r]));
	assert.deepEqual([by.VIP.status, by.VIP.id], ["existing", 77]);
	assert.deepEqual([by.DoubleLuck.status, by.DoubleLuck.id], ["existing", 11]);
	assert.deepEqual([by.Money24K.status, by.Money24K.id], ["existing", 30]);
	assert.equal(by.Speed25K.status, "create");
	assert.equal(by.TrailRed.status, "create");
	// A known id the universe doesn't have is never re-created.
	const wrong = M.plan(CATALOG, M.normalizeIds({ passes: { VIP: 999 } }), existing);
	assert.equal(wrong[0].status, "failed");
	assert.match(wrong[0].note, /wrong --universe/);
	// Dry run (no listing): ids.json only.
	assert.equal(M.plan(CATALOG, ids, null)[0].status, "existing");
	assert.equal(M.plan(CATALOG, ids, null)[1].status, "create");
	// mergeIds takes existing + created, never failed.
	const merged = M.mergeIds(ids, [...rows, { entry: CATALOG[4], status: "failed", id: 5 }]);
	assert.deepEqual(merged.passes, { VIP: 77, DoubleLuck: 11 });
	assert.deepEqual(merged.products, { Gone: 5, Speed25K: 0, Money24K: 30, TrailRed: 0 });
});

test("run: lists every page, creates only the missing ones, writes ids, second run creates nothing", async () => {
	const roblox = fakeRoblox({
		passes: [{ id: 1, name: "Other" }, { id: 2, name: "Other 2" }, { id: 3, name: "2x Luck" }],
		products: [{ id: 50, name: "Pocket Cash" }],
	});
	const d = deps(roblox, startFiles({ passes: { VIP: 2 }, products: {} }));
	const code = await M.run(["--universe", UNIVERSE], { ROBLOX_API_KEY: KEY }, d);
	assert.equal(code, 0, d.out.join("\n"));
	const ids = idsOf(d);
	assert.deepEqual(ids.passes, { DoubleLuck: 3, VIP: 2 });
	assert.equal(ids.products.Money24K, 50);
	assert.ok(ids.products.Speed25K >= 9000 && ids.products.TrailRed >= 9000);
	assert.equal(roblox.calls.filter((c) => c.method === "POST").length, 2);
	assert.equal(roblox.calls.filter((c) => c.method === "GET" && c.url.includes("game-passes")).length, 2, "two pages of passes");
	assert.ok(!d.out.join("\n").includes(KEY), "the key is never printed");
	assert.match(d.out.join("\n"), /2 created, 3 existing, 0 failed/);

	const again = deps(roblox, { ...d.files });
	roblox.calls.length = 0;
	assert.equal(await M.run(["--universe", UNIVERSE], { ROBLOX_API_KEY: KEY }, again), 0);
	assert.equal(roblox.calls.filter((c) => c.method === "POST").length, 0, "nothing is created twice");
	assert.deepEqual(idsOf(again), ids);
});

test("run: lost ids.json still finds everything by name", async () => {
	const roblox = fakeRoblox();
	const first = deps(roblox, startFiles(null));
	assert.equal(await M.run(["--universe", UNIVERSE], { ROBLOX_API_KEY: KEY }, first), 0);
	assert.equal(roblox.calls.filter((c) => c.method === "POST").length, CATALOG.length);
	const fresh = deps(roblox, startFiles(null));
	roblox.calls.length = 0;
	assert.equal(await M.run(["--universe", UNIVERSE], { ROBLOX_API_KEY: KEY }, fresh), 0);
	assert.equal(roblox.calls.filter((c) => c.method === "POST").length, 0);
	assert.deepEqual(idsOf(fresh), idsOf(first));
});

test("run: 429 is retried; a failed create is reported (redacted) and the rest still go through", async () => {
	const roblox = fakeRoblox({ rateLimits: 3, failNames: ["Red Trail"] });
	const d = deps(roblox, startFiles(null));
	const code = await M.run(["--universe", UNIVERSE], { ROBLOX_API_KEY: KEY }, d);
	assert.equal(code, 1, "a failure makes the exit code 1");
	const out = d.out.join("\n");
	assert.match(out, /FAILED product TrailRed: HTTP 400/);
	assert.ok(!out.includes(KEY), "the key is redacted from error bodies");
	assert.match(out, /4 created, 0 existing, 1 failed/);
	assert.equal(idsOf(d).products.TrailRed, 0);
	assert.ok(idsOf(d).products.Money24K > 0);
});

test("run: gives up after repeated 429s without creating anything", async () => {
	const roblox = fakeRoblox({ rateLimits: 1000 });
	const d = deps(roblox, startFiles(null));
	assert.equal(await M.run(["--universe", UNIVERSE], { ROBLOX_API_KEY: KEY }, d), 1);
	assert.match(d.out.join("\n"), /could not list.*HTTP 429 after 6 tries/);
	assert.equal(d.files[M.IDS_FILE], undefined, "nothing written");
});

test("run: dry run needs no key and makes no calls; no key = refuse", async () => {
	const roblox = fakeRoblox();
	const d = deps(roblox, startFiles({ passes: { VIP: 8 } }));
	assert.equal(await M.run(["--dry-run"], {}, d), 0);
	assert.equal(roblox.calls.length, 0);
	assert.match(d.out.join("\n"), /DRY RUN: nothing is sent to Roblox\. 4 of 5/);
	const nokey = deps(roblox, startFiles(null));
	assert.equal(await M.run(["--universe", UNIVERSE], {}, nokey), 2);
	assert.equal(roblox.calls.length, 0);
});
