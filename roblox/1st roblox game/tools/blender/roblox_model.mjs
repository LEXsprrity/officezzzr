// Puts a Blender model on Roblox and brings it back as a .rbxm, with no Studio step:
//   node tools/blender/roblox_model.mjs <model.fbx> <name> <out.rbxm>
// 1. uploads the FBX (textures embedded) as a Model owned by the LeBandit Games group through Open Cloud
//    (POST assets/v1/assets, then polls the operation until it is done);
// 2. downloads what Roblox made of it (asset-delivery-api: MeshParts with their uploaded meshes and textures)
//    into out.rbxm, ready for tools/build_pumpkyra.luau (or any finishing script) and the assets folder.
// The API key comes from ROBLOX_API_KEY (never printed, never written anywhere). It needs Assets read+write and
// Legacy Assets (asset delivery) read.
import fs from 'fs';

const GROUP_ID = '48006453';
const key = process.env.ROBLOX_API_KEY;
const [file, name, out] = process.argv.slice(2);
if (!key || !file || !name || !out) {
	console.error('usage: ROBLOX_API_KEY=... node tools/blender/roblox_model.mjs <model.fbx> <name> <out.rbxm>');
	process.exit(1);
}

const form = new FormData();
form.append('request', JSON.stringify({
	assetType: 'Model', displayName: name, description: `Steal a Seed - ${name}`,
	creationContext: { creator: { groupId: GROUP_ID } },
}));
form.append('fileContent', new Blob([fs.readFileSync(file)], { type: 'model/fbx' }), `${name}.fbx`);
const created = await fetch('https://apis.roblox.com/assets/v1/assets', { method: 'POST', headers: { 'x-api-key': key }, body: form });
const op = await created.json();
if (!created.ok) throw new Error(`upload failed (${created.status}): ${JSON.stringify(op)}`);

let assetId = null;
for (let i = 0; i < 60 && !assetId; i++) {
	await new Promise((r) => setTimeout(r, 3000));
	const res = await (await fetch(`https://apis.roblox.com/assets/v1/${op.path}`, { headers: { 'x-api-key': key } })).json();
	if (res.done) {
		if (!res.response) throw new Error(`upload rejected: ${JSON.stringify(res)}`);
		assetId = res.response.assetId;
		console.log(`uploaded ${name}: asset ${assetId} (${res.response.moderationResult?.moderationState})`);
	}
}
if (!assetId) throw new Error(`still processing: ${op.path}`);

const where = await (await fetch(`https://apis.roblox.com/asset-delivery-api/v1/assetId/${assetId}`, { headers: { 'x-api-key': key } })).json();
if (!where.location) throw new Error(`download failed: ${JSON.stringify(where)}`);
const bytes = Buffer.from(await (await fetch(where.location)).arrayBuffer());
fs.writeFileSync(out, bytes);
console.log(`saved ${out} (${bytes.length} bytes)`);
