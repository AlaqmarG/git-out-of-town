#!/usr/bin/env node
/**
 * Seeds placeholder graffiti around Stackt Market so the map has something to render.
 *
 *   npm run seed                                  # 25 pieces around Toronto, localhost
 *   SEED_URL=https://… SEED_COUNT=40 npm run seed
 *
 * These are generated scribbles, NOT real contributions. They exist so #13
 * (art as markers) can be built and reviewed. Delete them before judging —
 * "the data is real and current, not fabricated" is an explicit rubric line:
 *
 *   DELETE FROM pieces WHERE session_id LIKE 'seed-%';
 */

import { deflateSync } from "node:zlib";

const BASE = (process.env.SEED_URL || process.env.SITE_URL || "http://localhost:3000").replace(/\/$/, "");
const COUNT = Number(process.env.SEED_COUNT || 25);

// Stackt Market, Bathurst & Front — the venue. Matches DEFAULT_VIEW in
// apps/web/lib/theme.ts. Tight spread so pieces land on the surrounding blocks
// rather than scattering across the city.
const CENTRE = { lat: 43.6413, lng: -79.4042 };
const SPREAD = 0.0032; // ~350m


const PALETTE = [
  [255, 77, 46], [255, 209, 46], [46, 204, 255],
  [124, 255, 46], [255, 46, 178], [255, 255, 255],
];

// --- minimal PNG encoder (no dependencies) ---------------------------------

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});

function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

function encodePng(width, height, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;   // bit depth
  ihdr[9] = 6;   // colour type: RGBA
  // Each scanline is prefixed with its filter byte (0 = none).
  const raw = Buffer.alloc(height * (width * 4 + 1));
  for (let y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0;
    rgba.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

/** A few fat random strokes on transparent background — reads as a scribble at marker size. */
function scribble(size = 96) {
  const rgba = Buffer.alloc(size * size * 4); // transparent
  const strokes = 2 + Math.floor(Math.random() * 3);
  const colours = [];

  for (let s = 0; s < strokes; s++) {
    const [r, g, b] = PALETTE[Math.floor(Math.random() * PALETTE.length)];
    colours.push({ r, g, b });
    let x = Math.random() * size;
    let y = Math.random() * size;
    let ax = (Math.random() - 0.5) * 6;
    let ay = (Math.random() - 0.5) * 6;
    const radius = 3 + Math.random() * 4;

    for (let step = 0; step < 90; step++) {
      ax += (Math.random() - 0.5) * 2;
      ay += (Math.random() - 0.5) * 2;
      x = Math.max(radius, Math.min(size - radius, x + ax));
      y = Math.max(radius, Math.min(size - radius, y + ay));

      for (let dy = -radius; dy <= radius; dy++) {
        for (let dx = -radius; dx <= radius; dx++) {
          if (dx * dx + dy * dy > radius * radius) continue;
          const px = Math.round(x + dx);
          const py = Math.round(y + dy);
          if (px < 0 || py < 0 || px >= size || py >= size) continue;
          const i = (py * size + px) * 4;
          rgba[i] = r; rgba[i + 1] = g; rgba[i + 2] = b; rgba[i + 3] = 255;
        }
      }
    }
  }
  return { png: encodePng(size, size, rgba), colours };
}

// --- seeding ----------------------------------------------------------------

console.log(`\nSeeding ${COUNT} placeholder pieces → ${BASE}\n`);

let ok = 0;
const failures = [];

for (let i = 0; i < COUNT; i++) {
  const { png, colours } = scribble();
  const fd = new FormData();
  fd.append("image", new Blob([png], { type: "image/png" }), "seed.png");
  fd.append(
    "meta",
    JSON.stringify({
      lat: CENTRE.lat + (Math.random() - 0.5) * SPREAD,
      lng: CENTRE.lng + (Math.random() - 0.5) * SPREAD * 1.6,
      heading: Math.random() * 360,
      kind: Math.random() > 0.4 ? "spray" : "sticker",
      sessionId: `seed-${Date.now()}-${i}`,
      colors: colours,
      strokeCount: 2 + Math.floor(Math.random() * 20),
      durationMs: 3000 + Math.floor(Math.random() * 25000),
      client: "web",
    }),
  );

  try {
    const res = await fetch(`${BASE}/api/pieces`, { method: "POST", body: fd });
    if (res.status === 429) {
      // The API allows a burst then refills 1 per 6s. Wait it out rather than fail.
      const wait = Number(res.headers.get("retry-after") || 7);
      process.stdout.write(` (rate limited, ${wait}s)`);
      await new Promise((r) => setTimeout(r, wait * 1000));
      i--;
      continue;
    }
    if (!res.ok) throw new Error(`HTTP ${res.status} ${await res.text()}`);
    ok++;
    process.stdout.write(".");
  } catch (err) {
    failures.push(err.message);
    process.stdout.write("x");
  }
}

console.log(`\n\n${ok}/${COUNT} seeded.`);
if (failures.length) {
  console.error(`${failures.length} failed. First: ${failures[0]}`);
  process.exit(1);
}
console.log(`\nRemove later with:  DELETE FROM pieces WHERE session_id LIKE 'seed-%';\n`);
