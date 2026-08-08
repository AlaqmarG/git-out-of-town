/**
 * Procedural art for seeding. No dependencies, no network.
 *
 * Produces two things per piece:
 *   makeArt()   — transparent graffiti (AR anchor, map marker)
 *   makeScene() — a wall photo to composite it onto (the web preview)
 *
 * These stand in for real contributions until the iOS camera path (#25/#29) and
 * the Reve transformation (#18) land. Nothing here is meant to survive to judging.
 */

import { deflateSync } from "node:zlib";

// --- PNG encoding -----------------------------------------------------------

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

export function encodePng(width, height, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  const stride = width * 4 + 1;
  const raw = Buffer.alloc(height * stride);
  for (let y = 0; y < height; y++) {
    raw[y * stride] = 0; // filter: none
    rgba.copy(raw, y * stride + 1, y * width * 4, (y + 1) * width * 4);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw, { level: 6 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// --- helpers ----------------------------------------------------------------

const rnd = (a, b) => a + Math.random() * (b - a);
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

function px(buf, w, h, x, y, r, g, b, a = 1) {
  if (x < 0 || y < 0 || x >= w || y >= h || a <= 0) return;
  const i = (y * w + x) * 4;
  const inv = 1 - a;
  buf[i] = r * a + buf[i] * inv;
  buf[i + 1] = g * a + buf[i + 1] * inv;
  buf[i + 2] = b * a + buf[i + 2] * inv;
  buf[i + 3] = Math.min(255, buf[i + 3] + 255 * a);
}

/** Soft round dab — the basis of a spray stroke. */
function dab(buf, w, h, cx, cy, radius, r, g, b, alpha = 1) {
  const rad = Math.ceil(radius);
  for (let dy = -rad; dy <= rad; dy++) {
    for (let dx = -rad; dx <= rad; dx++) {
      const d = Math.hypot(dx, dy);
      if (d > radius) continue;
      // Soft falloff at the rim, like overspray.
      const a = alpha * clamp(1 - (d / radius) ** 2.2, 0, 1);
      px(buf, w, h, Math.round(cx + dx), Math.round(cy + dy), r, g, b, a);
    }
  }
}

const PALETTE = [
  [255, 77, 46], [255, 196, 0], [46, 190, 255],
  [124, 240, 60], [255, 60, 170], [245, 245, 250],
];

/**
 * One flowing stroke: dark outline underneath, bright fill on top, a highlight
 * pass, overspray speckle, and a couple of drips. Roughly how a real tag is built.
 */
function stroke(buf, w, h, colour) {
  const [r, g, b] = colour;
  const pts = [];
  const width = rnd(h * 0.05, h * 0.09);
  const steps = Math.round(rnd(190, 300));

  // Start on the left of a central band and sweep rightward, so strokes overlap
  // into a single piece instead of scattering.
  let x = rnd(w * 0.1, w * 0.3);
  let y = rnd(h * 0.3, h * 0.7);
  let angle = rnd(-0.6, 0.6);
  let curl = rnd(-0.05, 0.05);

  for (let i = 0; i < steps; i++) {
    // Slow, continuous turning gives flowing curves; the occasional kick adds
    // the sharp direction changes a real tag has.
    curl += rnd(-0.012, 0.012);
    curl = clamp(curl, -0.09, 0.09);
    if (Math.random() < 0.02) curl = -curl * 1.8;
    angle += curl;

    const speed = 2.9;
    x += Math.cos(angle) * speed + 0.55; // bias rightward
    y += Math.sin(angle) * speed;

    // Bounce off the margins rather than clamping flat against them.
    if (x < width || x > w - width) { angle = Math.PI - angle; x = clamp(x, width, w - width); }
    if (y < width || y > h - width) { angle = -angle; y = clamp(y, width, h - width); }

    pts.push([x, y]);
  }

  // Outline first, so the fill sits inside it.
  for (const [pxx, pyy] of pts) dab(buf, w, h, pxx, pyy, width * 0.62, 12, 12, 16, 0.85);
  for (const [pxx, pyy] of pts) dab(buf, w, h, pxx, pyy, width * 0.44, r, g, b, 0.95);
  // Highlight offset up-left, as if lit from that side.
  for (const [pxx, pyy] of pts) {
    dab(buf, w, h, pxx - width * 0.1, pyy - width * 0.12, width * 0.16,
        clamp(r + 70, 0, 255), clamp(g + 70, 0, 255), clamp(b + 70, 0, 255), 0.5);
  }

  // Overspray: fine mist around the line.
  for (let i = 0; i < steps * 5; i++) {
    const [sx, sy] = pts[Math.floor(Math.random() * pts.length)];
    const ang = rnd(0, Math.PI * 2);
    const dist = width * rnd(0.5, 1.8);
    px(buf, w, h, Math.round(sx + Math.cos(ang) * dist), Math.round(sy + Math.sin(ang) * dist),
       r, g, b, rnd(0.05, 0.3));
  }

  // Drips from a few low points.
  for (let d = 0; d < Math.round(rnd(1, 4)); d++) {
    const [dx, dy] = pts[Math.floor(rnd(pts.length * 0.3, pts.length))];
    const len = rnd(h * 0.05, h * 0.22);
    for (let t = 0; t < len; t++) {
      const taper = width * 0.2 * (1 - t / len);
      if (taper < 0.4) break;
      dab(buf, w, h, dx, dy + t, taper, r, g, b, 0.9);
    }
  }

  return { r, g, b };
}

/** Transparent graffiti art. Returns the PNG and the palette actually used. */
export function makeArt(size = 320) {
  const rgba = Buffer.alloc(size * size * 4);
  const colours = [];
  const n = Math.round(rnd(2, 5));
  const shuffled = [...PALETTE].sort(() => Math.random() - 0.5);
  for (let i = 0; i < n; i++) {
    const c = shuffled[i % shuffled.length];
    stroke(rgba, size, size, c);
    colours.push({ r: c[0], g: c[1], b: c[2] });
  }
  return { png: encodePng(size, size, rgba), rgba, size, colours };
}

/** A plausible wall: brick or concrete, directional light, grain, vignette. */
export function makeScene(w = 640, h = 480) {
  const rgba = Buffer.alloc(w * h * 4);
  const brick = Math.random() > 0.45;

  const base = brick ? [104, 68, 58] : [128, 126, 122];
  const brickH = h / rnd(11, 16);
  const brickW = brickH * rnd(2.1, 2.6);

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      let [r, g, b] = base;

      if (brick) {
        const row = Math.floor(y / brickH);
        const offset = (row % 2) * (brickW / 2);
        const bx = (x + offset) % brickW;
        const by = y % brickH;
        // Deterministic per-brick tint so each block differs.
        const seed = Math.sin(row * 12.9898 + Math.floor((x + offset) / brickW) * 78.233) * 43758.5453;
        const jitter = (seed - Math.floor(seed) - 0.5) * 34;
        r += jitter; g += jitter * 0.8; b += jitter * 0.7;
        if (bx < 3 || by < 3) { r = 148; g = 144; b = 138; } // mortar
      } else {
        const blotch = Math.sin(x * 0.013) * Math.cos(y * 0.017) * 12;
        r += blotch; g += blotch; b += blotch;
      }

      // Quantised so the PNG still compresses; pure per-pixel noise ballooned
      // these to ~750KB each.
      const grain = (Math.round(Math.random() * 3) - 1.5) * 6;
      // Light from upper-left, falling off across the surface.
      const light = 1.16 - (x / w) * 0.2 - (y / h) * 0.22;
      // Vignette.
      const vx = (x / w - 0.5) * 2;
      const vy = (y / h - 0.5) * 2;
      const vig = 1 - Math.hypot(vx, vy) * 0.28;

      const i = (y * w + x) * 4;
      rgba[i] = clamp((r + grain) * light * vig, 0, 255);
      rgba[i + 1] = clamp((g + grain) * light * vig, 0, 255);
      rgba[i + 2] = clamp((b + grain) * light * vig, 0, 255);
      rgba[i + 3] = 255;
    }
  }
  return { rgba, w, h };
}

/** Burns transparent art onto a scene, centred with a little random placement. */
export function compositeOnScene(scene, art) {
  const { rgba: dst, w, h } = scene;
  const scale = (h * rnd(0.5, 0.72)) / art.size;
  const outW = Math.round(art.size * scale);
  const ox = Math.round((w - outW) / 2 + rnd(-w * 0.09, w * 0.09));
  const oy = Math.round((h - outW) / 2 + rnd(-h * 0.08, h * 0.08));

  for (let y = 0; y < outW; y++) {
    for (let x = 0; x < outW; x++) {
      const sx = Math.min(art.size - 1, Math.floor(x / scale));
      const sy = Math.min(art.size - 1, Math.floor(y / scale));
      const si = (sy * art.size + sx) * 4;
      const a = art.rgba[si + 3] / 255;
      if (a <= 0.01) continue;
      const dx = ox + x;
      const dy = oy + y;
      if (dx < 0 || dy < 0 || dx >= w || dy >= h) continue;
      const di = (dy * w + dx) * 4;
      // Slightly under 1 so the wall texture reads through the paint.
      const eff = a * 0.94;
      dst[di] = art.rgba[si] * eff + dst[di] * (1 - eff);
      dst[di + 1] = art.rgba[si + 1] * eff + dst[di + 1] * (1 - eff);
      dst[di + 2] = art.rgba[si + 2] * eff + dst[di + 2] * (1 - eff);
    }
  }
  return encodePng(w, h, dst);
}
