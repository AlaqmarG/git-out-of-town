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

import { compositeOnScene, makeArt, makeScene } from "./lib/art.mjs";

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
console.log("Scenes: generated walls with the art baked in (see the contract in @got/shared)\n");

let ok = 0;
const failures = [];

for (let i = 0; i < COUNT; i++) {
  const art = makeArt();
  const lat = CENTRE.lat + (Math.random() - 0.5) * SPREAD;
  const lng = CENTRE.lng + (Math.random() - 0.5) * SPREAD * 1.6;
  const heading = Math.random() * 360;

  // CONTRACT: sceneImagePath must already contain the artwork (see @got/shared).
  // iOS sends the AR snapshot with the paint burned in, so seeds must match —
  // otherwise the map shows a bare wall where a piece should be.
  //
  // Compositing onto a real Street View JPEG needs a decoder we do not have here;
  // that is what the graffiti-realism work adds. Until then, seeds bake onto a
  // generated wall so the contract holds and the map is never wrong.
  const scene = compositeOnScene(makeScene(640, 480), art);
  const sceneType = "image/png";

  const fd = new FormData();
  fd.append("image", new Blob([art.png], { type: "image/png" }), "art.png");
  fd.append("scene", new Blob([scene], { type: sceneType }), "scene.png");
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
      //
      // Drain before retrying. An unread response body keeps its connection
      // checked out of undici's pool, and a throttled run does this once per
      // piece — enough pinned connections and every later fetch() fails or hangs
      // forever, so the run reports exit 0 having seeded a handful of rows.
      await res.arrayBuffer();
      const wait = Number(res.headers.get("retry-after") || 7);
      process.stdout.write(` (rate limited, ${wait}s)`);
      await new Promise((r) => setTimeout(r, wait * 1000));
      i--;
      continue;
    }
    if (!res.ok) throw new Error(`HTTP ${res.status} ${await res.text()}`);
    await res.arrayBuffer(); // same reason — the 201 body is never looked at
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
