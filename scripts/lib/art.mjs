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
import { layoutWord, randomWord } from "./letters.mjs";

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
  [168, 92, 255], [0, 232, 198],
];

/** Draws a polyline as a continuous thick stroke of overlapping dabs. */
function drawPolyline(buf, w, h, pts, radius, r, g, b, alpha = 1, dx = 0, dy = 0) {
  for (let i = 0; i < pts.length - 1; i++) {
    const [x0, y0] = pts[i];
    const [x1, y1] = pts[i + 1];
    const dist = Math.hypot(x1 - x0, y1 - y0);
    const steps = Math.max(2, Math.ceil(dist / (radius * 0.28)));
    for (let s = 0; s <= steps; s++) {
      const t = s / steps;
      dab(buf, w, h, x0 + (x1 - x0) * t + dx, y0 + (y1 - y0) * t + dy, radius, r, g, b, alpha);
    }
  }
}

/**
 * A graffiti piece, built the way a real one is: 3D extrusion behind, hard
 * outline, colour fill, highlight glints, overspray and drips.
 *
 * The layer order is what sells it — extrusion first so it sits *behind* the
 * letters, outline before fill so the fill nests inside it.
 */
export function makeArt(size = 420) {
  const rgba = Buffer.alloc(size * size * 4);
  const word = randomWord();

  const pad = size * 0.1;
  const { strokes, height } = layoutWord(word, size - pad * 2, size - pad * 2);
  const shifted = strokes.map((s) => s.map(([x, y]) => [x + pad, y + pad]));

  const shuffled = [...PALETTE].sort(() => Math.random() - 0.5);
  const [fr, fg, fb] = shuffled[0];
  const [ar, ag, ab] = shuffled[1];

  const weight = height * 0.17;
  const outline = weight * 1.34;
  const depth = weight * 0.85;

  // 1. Extrusion — an offset dark copy giving the letters thickness.
  const ex = depth * 0.75;
  const ey = depth * 0.6;
  for (let k = 6; k >= 1; k--) {
    const f = k / 6;
    for (const s of shifted) {
      drawPolyline(rgba, size, size, s, outline * 0.95, 10, 10, 14, 1, ex * f, ey * f);
    }
  }

  // 2. A second-colour keyline just outside the outline, as most pieces have.
  for (const s of shifted) {
    drawPolyline(rgba, size, size, s, outline * 1.22, ar, ag, ab, 0.95);
  }

  // 3. Hard black outline.
  for (const s of shifted) {
    drawPolyline(rgba, size, size, s, outline, 10, 10, 14, 1);
  }

  // 4. Colour fill, darkening downward so the letters have volume.
  for (const s of shifted) {
    drawPolyline(rgba, size, size, s, weight, fr, fg, fb, 1);
  }
  for (const s of shifted) {
    const shaded = s.filter(([, y]) => y > size * 0.5);
    if (shaded.length > 1) {
      drawPolyline(rgba, size, size, shaded, weight * 0.8,
        Math.max(0, fr - 60), Math.max(0, fg - 60), Math.max(0, fb - 60), 0.45);
    }
  }

  // 5. Highlight along the upper-left of each stroke.
  for (const s of shifted) {
    drawPolyline(rgba, size, size, s, weight * 0.28,
      clamp(fr + 90, 0, 255), clamp(fg + 90, 0, 255), clamp(fb + 90, 0, 255),
      0.55, -weight * 0.3, -weight * 0.34);
  }

  // 6. Overspray mist around the whole piece.
  for (const s of shifted) {
    for (const [x, y] of s) {
      for (let i = 0; i < 6; i++) {
        const ang = rnd(0, Math.PI * 2);
        const d = outline * rnd(1.1, 2.4);
        px(rgba, size, size, Math.round(x + Math.cos(ang) * d), Math.round(y + Math.sin(ang) * d),
           fr, fg, fb, rnd(0.04, 0.16));
      }
    }
  }

  // 7. Drips from the lowest points of a few strokes.
  const drippers = shifted.filter(() => Math.random() < 0.4);
  for (const s of drippers) {
    const low = s.reduce((a, b) => (b[1] > a[1] ? b : a), s[0]);
    const len = rnd(size * 0.05, size * 0.16);
    for (let t = 0; t < len; t++) {
      const taper = weight * 0.34 * (1 - t / len);
      if (taper < 0.5) break;
      dab(rgba, size, size, low[0], low[1] + t, taper, fr, fg, fb, 0.92);
    }
    dab(rgba, size, size, low[0], low[1] + len, weight * 0.3, fr, fg, fb, 0.85);
  }

  const colours = [
    { r: fr, g: fg, b: fb },
    { r: ar, g: ag, b: ab },
  ];
  return { png: encodePng(size, size, rgba), rgba, size, colours, word, strokeCount: shifted.length };
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
