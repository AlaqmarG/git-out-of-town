/**
 * The whole pipeline, end to end: coordinates in, a photograph of painted
 * graffiti out.
 *
 *   Street View still → find a plane → generate a piece sized to it
 *   → warp onto the plane → blend it into the surface → JPEG
 *
 * `paintStreetView()` is the drop-in for the art+scene pair the seeder used to
 * build separately. It still returns the transparent artwork, because the map
 * markers and the AR anchor need it; what changes is that the scene now has the
 * paint baked in, in perspective, instead of a CSS transform faking it later.
 */

import { encodePng, makeArt, makeScene } from "./art.mjs";
import { paintOnPhoto } from "./composite.mjs";
import { decodeJpeg, encodeJpeg } from "./image.mjs";
import { R, seedArt } from "./rng.mjs";
import { fetchStreetView } from "./streetview.mjs";
import { findSurface } from "./surface.mjs";

/** Per-surface tuning. Different materials fail in different ways. */
const TUNING = {
  wall: { wear: 1.0, texture: 1.15, opacity: 0.97 },
  // Tarmac is coarse and eats paint; nothing on a road stays crisp for long.
  ground: { wear: 1.25, texture: 1.35, opacity: 0.88, desaturate: 0.72 },
};

const edgeLength = (q) =>
  Math.max(...q.map((p, i) => Math.hypot(p[0] - q[(i + 1) % 4][0], p[1] - q[(i + 1) % 4][1])));

/**
 * Paint one piece onto an already-fetched JPEG. Returns null when the view has
 * no plausible surface — the caller should try a different heading rather than
 * paint something silly.
 */
export function paintPhoto(jpegBuf, { seed, word, allowGround = false } = {}) {
  seedArt(seed);
  const photo = decodeJpeg(jpegBuf);

  const surface = findSurface(photo, { rand: R.next, allowGround });
  if (!surface) return null;

  // Render the artwork larger than it will appear, so the warp is always a
  // minification: downsampling averages, upsampling just shows you the pixels.
  const artW = Math.round(Math.min(1500, Math.max(420, edgeLength(surface.quad) * 1.9)));
  const art = makeArt(artW, Math.round(artW / surface.aspect), {
    word,
    drips: surface.kind !== "ground",
  });

  if (!paintOnPhoto(photo, art, surface, TUNING[surface.kind])) return null;

  return {
    jpeg: encodeJpeg(photo, 86),
    art,
    surfaceType: surface.kind,
    quad: surface.quad,
    quality: surface.quality,
  };
}

/**
 * Fetch the view at these coordinates and paint it.
 *
 * Street View has no wall at every heading — a treed street, a car park, a
 * wall of glass — so try every bearing before giving up. `heading` is honoured
 * first, since it is the direction the piece was painted toward.
 *
 * Ground planes are deliberately never used. The geometry works, but tarmac and
 * gravel simply never look right, and a throw-up in the middle of a road is not
 * a thing that happens. Returning null and letting the caller skip the spot
 * beats producing a picture nobody believes.
 */
export async function paintStreetView(lat, lng, heading, { seed, word, tries = 6 } = {}) {
  const offsets = [0, 90, 180, 270, 45, 225];
  for (let t = 0; t < Math.min(tries, offsets.length); t++) {
    const bearing = (heading + offsets[t] + 360) % 360;
    const jpeg = await fetchStreetView(lat, lng, bearing);
    if (!jpeg) return null; // no coverage here at all
    const painted = paintPhoto(jpeg, { seed: seed === undefined ? undefined : seed + t, word });
    if (painted) return { ...painted, heading: bearing };
  }
  return null;
}

/** Last resort when there is no imagery: the old generated wall, still baked. */
export function paintGeneratedWall({ seed, word } = {}) {
  seedArt(seed);
  const scene = makeScene(640, 480);
  const jpeg = encodeJpeg({ data: scene.rgba, width: scene.w, height: scene.h }, 92);
  return (
    paintPhoto(jpeg, { seed, word }) ?? {
      jpeg: encodePng(scene.w, scene.h, scene.rgba),
      art: makeArt(420, 420),
      surfaceType: "wall",
    }
  );
}
