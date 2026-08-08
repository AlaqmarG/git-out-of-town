/**
 * Real Street View imagery for seeding, with a procedural fallback.
 *
 * Requires the *Street View Static API* to be enabled on the Google Cloud project
 * (not just a valid key) and billing linked. When it is unavailable — not enabled,
 * over quota, or simply no coverage at those coordinates — callers fall back to a
 * generated wall so seeding never fails.
 */

import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const KEY = process.env.GOOGLE_MAPS_API_KEY || process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY || "";
const META = "https://maps.googleapis.com/maps/api/streetview/metadata";
const IMG = "https://maps.googleapis.com/maps/api/streetview";

// Every fetch is billed, and iterating on the compositor means fetching the
// same handful of views hundreds of times. Cache on disk, keyed by the request.
const CACHE = process.env.SV_CACHE_DIR || ".cache/streetview";

let warned = false;

/**
 * Returns JPEG bytes for the view at these coordinates, or null.
 * `heading` is the compass bearing the piece was painted toward, so the photo
 * looks the way the painter was facing.
 */
export async function fetchStreetView(
  lat, lng, heading,
  { width = 640, height = 480, pitch = 0, fov = 80 } = {},
) {
  if (!KEY) return null;

  const loc = `${lat},${lng}`;
  const query = `${loc}|${Math.round(heading)}|${width}x${height}|${pitch}|${fov}`;
  const hit = join(CACHE, `${createHash("sha1").update(query).digest("hex").slice(0, 16)}.jpg`);
  try {
    return readFileSync(hit);
  } catch {
    /* not cached yet */
  }

  try {
    // Metadata is free and tells us whether imagery exists before we pay for a pixel.
    const meta = await fetch(`${META}?location=${loc}&key=${KEY}`, {
      signal: AbortSignal.timeout(10_000),
    }).then((r) => r.json());

    if (meta.status !== "OK") {
      if (!warned) {
        warned = true;
        const why = meta.error_message ?? meta.status;
        console.warn(`\n  Street View unavailable (${why}) — falling back to generated walls.`);
      }
      return null;
    }

    const res = await fetch(
      `${IMG}?size=${width}x${height}&location=${loc}&heading=${Math.round(heading)}&pitch=${pitch}&fov=${fov}&key=${KEY}`,
      { signal: AbortSignal.timeout(15_000) },
    );
    if (!res.ok) return null;

    const buf = Buffer.from(await res.arrayBuffer());
    // A JPEG starts FFD8FF; an error page does not.
    if (buf[0] !== 0xff || buf[1] !== 0xd8) return null;

    mkdirSync(CACHE, { recursive: true });
    writeFileSync(hit, buf);
    return buf;
  } catch {
    return null;
  }
}

export const hasKey = Boolean(KEY);
