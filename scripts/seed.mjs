#!/usr/bin/env node
/**
 * Seeds placeholder graffiti around Stackt Market so the map has something to render.
 *
 * Each piece is a real Street View still with the artwork composited into it in
 * perspective — see scripts/lib/README.md. The transparent PNG still goes up as
 * `image`, because the AR anchor and the bare marker need it, but the scene is
 * now the finished picture rather than a backdrop for a CSS overlay.
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

import { paintGeneratedWall, paintStreetView } from "./lib/graffiti.mjs";
import { hasKey } from "./lib/streetview.mjs";

const BASE = (process.env.SEED_URL || process.env.SITE_URL || "http://localhost:3000").replace(/\/$/, "");
const COUNT = Number(process.env.SEED_COUNT || 25);

// Stackt Market, Bathurst & Front — the venue. Matches DEFAULT_VIEW in
// apps/web/lib/theme.ts. Tight spread so pieces land on the surrounding blocks
// rather than scattering across the city.
const CENTRE = { lat: 43.6413, lng: -79.4042 };
const SPREAD = 0.0032; // ~350m


// --- seeding ----------------------------------------------------------------

console.log(`\nSeeding ${COUNT} placeholder pieces → ${BASE}`);
console.log(hasKey ? "Street View: key present\n" : "Street View: no key, using generated walls\n");

let ok = 0;
const failures = [];

// Only a minority of spots have a paintable wall in any direction — most are
// trees, parked cars or glass. Allow several attempts per piece, each at fresh
// coordinates, rather than lowering the bar for what counts as a wall.
const MAX_ATTEMPTS = COUNT * 8;

let attempts = 0;
let skipped = 0;

for (let i = 0; i < COUNT; i++) {
  let piece = null;
  let lat, lng, heading;

  while (!piece && attempts < MAX_ATTEMPTS) {
    attempts++;
    lat = CENTRE.lat + (Math.random() - 0.5) * SPREAD;
    lng = CENTRE.lng + (Math.random() - 0.5) * SPREAD * 1.6;
    heading = Math.random() * 360;
    piece = await paintStreetView(lat, lng, heading);
    if (!piece) skipped++;
  }
  // Ran out of budget looking for real walls: fall back to a generated one.
  if (!piece) piece = paintGeneratedWall();

  const { art, jpeg } = piece;
  if (piece.heading !== undefined) heading = piece.heading;

  const fd = new FormData();
  fd.append("image", new Blob([art.png], { type: "image/png" }), "art.png");
  fd.append("scene", new Blob([jpeg], { type: "image/jpeg" }), "scene.jpg");
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
      surfaceType: piece.surfaceType,
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

console.log(`\n\n${ok}/${COUNT} seeded (${skipped} spots skipped for want of a wall).`);
if (failures.length) {
  console.error(`${failures.length} failed. First: ${failures[0]}`);
  process.exit(1);
}
console.log(`\nRemove later with:  DELETE FROM pieces WHERE session_id LIKE 'seed-%';\n`);
