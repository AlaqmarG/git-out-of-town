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

import { encodePng, makeArt, makeScene } from "./lib/art.mjs";
import { fetchStreetView, hasKey } from "./lib/streetview.mjs";

const BASE = (process.env.SEED_URL || process.env.SITE_URL || "http://localhost:3000").replace(/\/$/, "");
const COUNT = Number(process.env.SEED_COUNT || 25);

// Stackt Market, Bathurst & Front — the venue. Matches DEFAULT_VIEW in
// apps/web/lib/theme.ts. Tight spread so pieces land on the surrounding blocks
// rather than scattering across the city.
const CENTRE = { lat: 43.6413, lng: -79.4042 };
const SPREAD = 0.0032; // ~350m

// Weighted toward walls, which is where graffiti actually goes.
const SURFACES = ["wall", "wall", "wall", "wall", "wall", "door", "floor", "window"];

// --- seeding ----------------------------------------------------------------

console.log(`\nSeeding ${COUNT} placeholder pieces → ${BASE}`);
console.log(hasKey ? "Street View: key present\n" : "Street View: no key, using generated walls\n");

let ok = 0;
const failures = [];

for (let i = 0; i < COUNT; i++) {
  const art = makeArt();
  const lat = CENTRE.lat + (Math.random() - 0.5) * SPREAD;
  const lng = CENTRE.lng + (Math.random() - 0.5) * SPREAD * 1.6;
  const heading = Math.random() * 360;

  // Prefer a real photo of that spot facing the painted direction. The art is
  // NOT burned in — the web overlays it, which keeps it crisp and means we never
  // have to decode a JPEG here.
  const sv = await fetchStreetView(lat, lng, heading);
  const scene = sv ?? encodePng(640, 480, makeScene(640, 480).rgba);
  const sceneType = sv ? "image/jpeg" : "image/png";

  const fd = new FormData();
  fd.append("image", new Blob([art.png], { type: "image/png" }), "art.png");
  fd.append("scene", new Blob([scene], { type: sceneType }), sv ? "scene.jpg" : "scene.png");
  fd.append(
    "meta",
    JSON.stringify({
      lat,
      lng,
      heading,
      kind: Math.random() > 0.4 ? "spray" : "sticker",
      sessionId: `seed-${Date.now()}-${i}`,
      colors: art.colours,
      strokeCount: 2 + Math.floor(Math.random() * 20),
      durationMs: 3000 + Math.floor(Math.random() * 25000),
      client: "web",
      // Drives the perspective projection on the web (lib/surface.ts). Mostly
      // walls, as real graffiti is.
      surfaceType: SURFACES[Math.floor(Math.random() * SURFACES.length)],
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
