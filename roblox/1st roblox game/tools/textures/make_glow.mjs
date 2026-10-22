// Writes icons/GlowRays.png: a soft white radial glow with 12 sunburst rays fading out, on a clear
// background (the premium windows tint it behind their hero art: Premium.glow). node tools/textures/make_glow.mjs
import fs from "fs";
import zlib from "zlib";
const S = 512;
const px = Buffer.alloc(S * (S * 4 + 1));
for (let y = 0; y < S; y++) {
  px[y * (S * 4 + 1)] = 0;
  for (let x = 0; x < S; x++) {
    const dx = (x + 0.5) / S - 0.5, dy = (y + 0.5) / S - 0.5;
    const r = Math.hypot(dx, dy) * 2; // 0 centre, 1 edge
    const ang = Math.atan2(dy, dx);
    const glow = Math.max(0, 1 - r / 0.75) ** 2 * 0.85;
    const ray = (Math.cos(ang * 12) * 0.5 + 0.5) ** 6; // 12 thin rays
    const rays = ray * Math.max(0, 1 - r) ** 1.5 * 0.55 * Math.min(1, r / 0.18);
    const a = Math.min(1, glow + rays);
    const i = y * (S * 4 + 1) + 1 + x * 4;
    px[i] = px[i + 1] = px[i + 2] = 255;
    px[i + 3] = Math.round(a * 255);
  }
}
const crc = (b) => { let c, t = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } let v = 0xffffffff; for (const x of b) v = t[(v ^ x) & 255] ^ (v >>> 8); return (v ^ 0xffffffff) >>> 0; };
const chunk = (type, data) => { const l = Buffer.alloc(4); l.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(S, 0); ihdr.writeUInt32BE(S, 4); ihdr[8] = 8; ihdr[9] = 6;
const png = Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(px)), chunk("IEND", Buffer.alloc(0))]);
fs.writeFileSync(process.argv[2] || "icons/GlowRays.png", png);
