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

// A fake Open Cloud: lists in pages of 2 (with each item's priceInformation when it has a price), creates with
// increasing ids, PATCHes prices (204), optional 429s, records every call.
function fakeRoblox({ products = [], passes = [], rateLimits = 0, failNames = [], failPatchIds = [] } = {}) {
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
			const page = list.slice(start, start + 2).map((x) => ({
				[idField]: x.id,
				name: x.name,
				...(x.price !== undefined ? { priceInformation: { defaultPriceInRobux: x.price, enabledFeatures: [] } } : {}),
				...(x.forSale !== undefined ? { isForSale: x.forSale } : {}),
			}));
			const next = start + 2 < list.length ? String(start + 2) : "";
			return reply(200, { [isPass ? "gamePasses" : "developerProducts"]: page, nextPageToken: next });
		}
		if (init.method === "PATCH") {
			const id = Number(u.pathname.split("/").pop());
			const form = init.body;
			assert.ok(form instanceof FormData, "multipart");
			const keys = [...form.keys()];
			assert.ok(keys.length > 0 && keys.every((k) => k === "price" || k === "isForSale"), `only price / isForSale are sent (${keys})`);
			const item = list.find((x) => x.id === id);
			if (!item) return reply(404, "not found");
			if (failPatchIds.includes(id)) return reply(400, `bad price, key was ${KEY}`);
			const patch = { id, pass: isPass };
			if (form.has("price")) patch.price = item.price = Number(form.get("price"));
			if (form.has("isForSale")) {
				assert.ok(["true", "false"].includes(form.get("isForSale")), "isForSale is true / false");
				patch.isForSale = item.forSale = form.get("isForSale") === "true";
			}
			state.patched = [...(state.patched ?? []), patch];
			return reply(204, "");
		}
		const form = init.body;
		assert.ok(form instanceof FormData);
		assert.equal(form.get("isForSale"), "true", "a retired item is never created");
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
	assert.deepEqual(M.parseArgs(["--universe", "12"], {}), { dryRun: false, universe: "12", help: false, updatePrices: false });
	assert.equal(M.parseArgs(["--universe", "12", "--update-prices"], {}).updatePrices, true);
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

test("listedPrice: priceInformation.defaultPriceInRobux, else unknown", () => {
	assert.equal(M.listedPrice({ priceInformation: { defaultPriceInRobux: 200 } }), 200);
	assert.equal(M.listedPrice({ priceInformation: null }), null);
	assert.equal(M.listedPrice({ priceInformation: { defaultPriceInRobux: "200" } }), null);
	assert.equal(M.listedPrice({}), null);
});

test("--update-prices: PATCHes only existing items whose price differs (or is unknown); new ones are created at the catalog price", async () => {
	const roblox = fakeRoblox({
		passes: [{ id: 2, name: "VIP", price: 399 }, { id: 3, name: "2x Luck", price: 100 }],
		products: [{ id: 50, name: "Pocket Cash", price: 40 }, { id: 51, name: "+25K Speed" }],
	});
	const d = deps(roblox, startFiles({ passes: { VIP: 2 }, products: {} }));
	const code = await M.run(["--universe", UNIVERSE, "--update-prices"], { ROBLOX_API_KEY: KEY }, d);
	assert.equal(code, 0, d.out.join("\n"));
	const patched = Object.fromEntries((roblox.patched ?? []).map((p) => [p.id, p.price]));
	assert.deepEqual(patched, { 3: 249, 51: 9 }, "2x Luck 100 -> 249, +25K Speed (price unknown) -> 9; VIP and Pocket Cash already right");
	const patches = roblox.calls.filter((c) => c.method === "PATCH");
	assert.equal(patches.length, 2);
	assert.ok(patches.some((c) => c.url === `https://apis.roblox.com/game-passes/v1/universes/${UNIVERSE}/game-passes/3`), "the game pass endpoint");
	assert.ok(
		patches.some((c) => c.url === `https://apis.roblox.com/developer-products/v2/universes/${UNIVERSE}/developer-products/51`),
		"the developer product endpoint"
	);
	assert.equal(roblox.calls.filter((c) => c.method === "POST").length, 1, "Red Trail is created (at its catalog price), not patched");
	const out = d.out.join("\n");
	assert.match(out, /Prices: 2 updated, 2 already right, 0 failed\./);
	assert.ok(!out.includes(KEY));

	// again: everything is right now, nothing is sent
	roblox.calls.length = 0;
	const again = deps(roblox, { ...d.files });
	assert.equal(await M.run(["--universe", UNIVERSE, "--update-prices"], { ROBLOX_API_KEY: KEY }, again), 0);
	assert.equal(roblox.calls.filter((c) => c.method !== "GET").length, 0);
	assert.match(again.out.join("\n"), /Prices: 0 updated, 5 already right, 0 failed\./);
});

test("--update-prices: without the flag no price is touched; a failed PATCH is reported (redacted) and exits 1", async () => {
	const roblox = fakeRoblox({ passes: [{ id: 3, name: "2x Luck", price: 100 }], products: [{ id: 50, name: "Pocket Cash", price: 1 }], failPatchIds: [50] });
	const plain = deps(roblox, startFiles(null));
	await M.run(["--universe", UNIVERSE], { ROBLOX_API_KEY: KEY }, plain);
	assert.equal(roblox.calls.filter((c) => c.method === "PATCH").length, 0, "no flag, no PATCH");
	const d = deps(roblox, { ...plain.files });
	const code = await M.run(["--universe", UNIVERSE, "--update-prices"], { ROBLOX_API_KEY: KEY }, d);
	assert.equal(code, 1);
	const out = d.out.join("\n");
	assert.match(out, /FAILED price product Money24K: price update failed: HTTP 400/);
	assert.ok(!out.includes(KEY), "the key is redacted");
	assert.equal(roblox.passes.find((x) => x.id === 3).price, 249, "the others still went through");
});

test("--update-prices --dry-run: says what would change, sends nothing, needs no key", async () => {
	const roblox = fakeRoblox();
	const d = deps(roblox, startFiles({ passes: { VIP: 8 } }));
	assert.equal(await M.run(["--dry-run", "--update-prices"], {}, d), 0);
	assert.equal(roblox.calls.length, 0);
	assert.match(d.out.join("\n"), /price would be set to R\$ 399/);
});

// Retired items (catalog "isForSale": false; owner 2026-10-15: the Lotus Wyrm pack): kept on Roblox, off sale.
const retired = (key, name, price) => ({ ...entry(key, "product", name, price), isForSale: false });
const RETIRED_CATALOG = [
	{ ...entry("Speed25K", "product", "+25K Speed", 9), isForSale: true },
	retired("PackSpirit", "Lotus Wyrm Pack", 300),
	retired("PackSpirit10", "Lotus Wyrm Pack x10", 2299),
	retired("PackOld", "Old Pack", 50),
];
const retiredFiles = (ids) => ({ [M.CATALOG_FILE]: JSON.stringify(RETIRED_CATALOG), [M.IDS_FILE]: M.encodeIds(M.normalizeIds(ids)) });

test("changes: price where it differs, isForSale false for retired (unless known off sale), true for a sold one known off sale", () => {
	const sold = entry("A", "product", "A", 10);
	const gone = { ...sold, isForSale: false };
	assert.deepEqual(M.changes(sold, { price: 10, forSale: true }), {});
	assert.deepEqual(M.changes(sold, { price: 10, forSale: null }), {}, "a sold item with an unknown sale state is left alone");
	assert.deepEqual(M.changes(sold, { price: 9, forSale: null }), { price: 10 });
	assert.deepEqual(M.changes(sold, { price: 10, forSale: false }), { isForSale: true }, "brought back: put on sale again");
	assert.deepEqual(M.changes(gone, { price: 10, forSale: true }), { isForSale: false });
	assert.deepEqual(M.changes(gone, { price: 10, forSale: null }), { isForSale: false }, "unknown: taken off sale to be sure");
	assert.deepEqual(M.changes(gone, { price: 10, forSale: false }), {}, "already off sale");
	assert.deepEqual(M.changes(gone, { price: 7, forSale: true }), { price: 10, isForSale: false }, "both in one PATCH");
	assert.deepEqual(M.changes(gone, undefined), { price: 10, isForSale: false });
	assert.deepEqual(M.changes(sold, { name: sold.name, price: 10, forSale: true }), {}, "same name: left alone");
	assert.deepEqual(M.changes(sold, { name: "Old Name", price: 10, forSale: true }), { name: sold.name }, "renamed in the catalog");
	assert.equal(M.forSale({}), true, "no isForSale field: sold");
	assert.equal(M.listedForSale({ isForSale: false }), false);
	assert.equal(M.listedForSale({ isForSale: "false" }), null);
	assert.equal(M.listedForSale({}), null);
});

test("--update-prices: retired items are PATCHed isForSale=false (same endpoints), never created; a second run sends nothing", async () => {
	const roblox = fakeRoblox({
		products: [
			{ id: 51, name: "+25K Speed", price: 9, forSale: true },
			{ id: 3718769580, name: "Lotus Wyrm Pack", price: 300, forSale: true },
			{ id: 3718799418, name: "Lotus Wyrm Pack x10", price: 2000 }, // (sale state not listed)
		],
	});
	const d = deps(roblox, retiredFiles({ products: { Speed25K: 51, PackSpirit: 3718769580, PackSpirit10: 3718799418 } }));
	const code = await M.run(["--universe", UNIVERSE, "--update-prices"], { ROBLOX_API_KEY: KEY }, d);
	assert.equal(code, 0, d.out.join("\n"));
	const patched = Object.fromEntries((roblox.patched ?? []).map((p) => [p.id, p]));
	assert.deepEqual(Object.keys(patched).sort(), ["3718769580", "3718799418"], "only the retired ones");
	assert.deepEqual(patched[3718769580], { id: 3718769580, pass: false, isForSale: false }, "off sale, price untouched");
	assert.deepEqual(patched[3718799418], { id: 3718799418, pass: false, price: 2299, isForSale: false }, "price and off sale in one PATCH");
	const patches = roblox.calls.filter((c) => c.method === "PATCH");
	assert.equal(patches.length, 2);
	assert.ok(patches.every((c) => c.url.startsWith(`https://apis.roblox.com/developer-products/v2/universes/${UNIVERSE}/developer-products/`)), "the developer product endpoint");
	assert.equal(roblox.calls.filter((c) => c.method === "POST").length, 0, "the retired Old Pack (no id, not on Roblox) is never created");
	const out = d.out.join("\n");
	assert.match(out, /sale product PackSpirit: taken off sale \(retired\)/);
	assert.match(out, /PackOld .* skipped +retired: not created/);
	assert.match(out, /0 created, 3 existing, 0 failed, 1 retired \(not created\)\./);
	assert.match(out, /Prices: 2 updated, 1 already right, 0 failed\. 2 retired taken off sale\./);
	assert.ok(!out.includes(KEY));
	assert.equal(idsOf(d).products.PackOld, 0, "its ids.json slot stays 0");
	assert.equal(idsOf(d).products.PackSpirit, 3718769580, "the retired ids are kept (receipts still grant)");

	roblox.calls.length = 0;
	const again = deps(roblox, { ...d.files });
	assert.equal(await M.run(["--universe", UNIVERSE, "--update-prices"], { ROBLOX_API_KEY: KEY }, again), 0);
	assert.equal(roblox.calls.filter((c) => c.method !== "GET").length, 0, "already off sale: nothing sent");
	assert.match(again.out.join("\n"), /Prices: 0 updated, 3 already right, 0 failed\./);
});

test("--update-prices: a retired item brought back (isForSale true again) is put on sale; without the flag nothing is patched", async () => {
	const roblox = fakeRoblox({ products: [{ id: 70, name: "Lotus Wyrm Pack", price: 300, forSale: false }] });
	const files = { [M.CATALOG_FILE]: JSON.stringify([{ ...entry("PackSpirit", "product", "Lotus Wyrm Pack", 300), isForSale: true }]), [M.IDS_FILE]: M.encodeIds(M.normalizeIds({ products: { PackSpirit: 70 } })) };
	const plain = deps(roblox, { ...files });
	assert.equal(await M.run(["--universe", UNIVERSE], { ROBLOX_API_KEY: KEY }, plain), 0);
	assert.equal(roblox.calls.filter((c) => c.method === "PATCH").length, 0, "no flag, no PATCH");
	const d = deps(roblox, { ...files });
	assert.equal(await M.run(["--universe", UNIVERSE, "--update-prices"], { ROBLOX_API_KEY: KEY }, d), 0);
	assert.deepEqual(roblox.patched, [{ id: 70, pass: false, isForSale: true }]);
	assert.match(d.out.join("\n"), /sale product PackSpirit: put on sale/);
});

test("--update-prices: a failed off-sale PATCH is reported (redacted) and exits 1; --dry-run says it would take them off sale", async () => {
	const roblox = fakeRoblox({ products: [{ id: 80, name: "Lotus Wyrm Pack", price: 300, forSale: true }], failPatchIds: [80] });
	const files = retiredFiles({ products: { PackSpirit: 80 } });
	const d = deps(roblox, { ...files });
	assert.equal(await M.run(["--universe", UNIVERSE, "--update-prices"], { ROBLOX_API_KEY: KEY }, d), 1);
	const out = d.out.join("\n");
	assert.match(out, /FAILED sale product PackSpirit: sale update failed: HTTP 400/);
	assert.ok(!out.includes(KEY), "the key is redacted");

	const dry = deps(fakeRoblox(), { ...files });
	assert.equal(await M.run(["--dry-run", "--update-prices"], {}, dry), 0);
	const dryOut = dry.out.join("\n");
	assert.match(dryOut, /PackSpirit .*would be taken off sale \(retired\)/);
	assert.match(dryOut, /PackOld .* skipped +retired: not created/);
});

test("catalog.json: the retired Lotus Wyrm packs are off sale, every other item for sale", () => {
	const catalog = JSON.parse(readFileSync(M.CATALOG_FILE, "utf8"));
	for (const e of catalog) {
		assert.equal(typeof e.isForSale, "boolean", `${e.key} says isForSale`);
		assert.equal(e.isForSale, !["PackSpirit", "PackSpirit10"].includes(e.key), e.key);
	}
});
