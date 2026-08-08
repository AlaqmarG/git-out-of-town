/**
 * Burning artwork onto a photograph so it reads as paint rather than a decal.
 *
 * Order matters. Geometry first — warp the art onto the plane's quad — then a
 * short stack of appearance passes, each fixing one specific tell:
 *
 *   membership  paint must not cross the pole, car or plant in front of the wall
 *   wear        spray misses the recesses; mortar lines stay bare
 *   texture     the surface's own detail multiplies through the paint
 *   light       paint takes the wall's exposure and the scene's illuminant
 *   grain       the paint carries the same sensor noise as the photo
 *
 * Of these, wear does the most work. A perfect homography with even coverage
 * still looks pasted on; uneven coverage that respects the mortar reads as paint
 * even when the perspective is only roughly right.
 */

import { boxBlur, clamp, luminance, sampleRgba, smoothstep } from "./image.mjs";
import { valueNoise } from "./rng.mjs";

// --- homography -------------------------------------------------------------

/** Solve A·x = b by Gauss-Jordan elimination with partial pivoting. */
function solve(A, b, n) {
  for (let col = 0; col < n; col++) {
    let piv = col;
    for (let r = col + 1; r < n; r++) if (Math.abs(A[r][col]) > Math.abs(A[piv][col])) piv = r;
    if (Math.abs(A[piv][col]) < 1e-12) return null;
    [A[col], A[piv]] = [A[piv], A[col]];
    [b[col], b[piv]] = [b[piv], b[col]];
    for (let r = 0; r < n; r++) {
      if (r === col) continue;
      const f = A[r][col] / A[col][col];
      for (let c = col; c < n; c++) A[r][c] -= f * A[col][c];
      b[r] -= f * b[col];
    }
  }
  return b.map((v, i) => v / A[i][i]);
}

/**
 * The 3×3 mapping taking each `from[i]` to `to[i]`.
 *
 * Callers build it in the destination→source direction on purpose:
 * forward-mapping the artwork would leave holes wherever the quad is magnified.
 * Walking destination pixels and pulling from the source cannot.
 */
export function homography(from, to) {
  const A = [], b = [];
  for (let i = 0; i < 4; i++) {
    const [X, Y] = from[i], [x, y] = to[i];
    A.push([X, Y, 1, 0, 0, 0, -X * x, -Y * x]); b.push(x);
    A.push([0, 0, 0, X, Y, 1, -X * y, -Y * y]); b.push(y);
  }
  const h = solve(A, b, 8);
  return h ? [...h, 1] : null;
}

const apply = (h, x, y) => {
  const d = h[6] * x + h[7] * y + 1;
  return [(h[0] * x + h[1] * y + h[2]) / d, (h[3] * x + h[4] * y + h[5]) / d, d];
};

// --- the composite ----------------------------------------------------------

const DEFAULTS = {
  /** How hard recesses reject paint. 1 = mortar joints stay almost bare. */
  wear: 1.0,
  /** How much of the surface's fine detail multiplies through the paint. */
  texture: 1.15,
  /** Pull of the scene's illuminant colour on the paint. */
  tint: 0.45,
  /** Paint is never as vivid as the swatch once it is on a wall in daylight. */
  desaturate: 0.82,
  /** Overall coverage. Below 1 the wall reads through everywhere. */
  opacity: 0.97,
  grain: 1.0,
};

/**
 * Paint `art` onto `photo` across `surface.quad`, in place. Returns false if the
 * quad is degenerate.
 *
 * `art` is `{ rgba, width, height }` with premultiplied-ish RGB — that is what
 * the dab renderer produces, and dividing the interpolated colour by the
 * interpolated alpha recovers straight colour without a dark fringe at the soft
 * spray edges.
 */
export function paintOnPhoto(photo, art, surface, options = {}) {
  const o = { ...DEFAULTS, ...options };
  const { data, width: w, height: h } = photo;
  const { quad, model } = surface;

  const H = homography(quad, [[0, 0], [art.width, 0], [art.width, art.height], [0, art.height]]);
  if (!H) return false;
  // Points on the far side of the plane's horizon satisfy the same algebra but
  // are behind the camera; the sign of the denominator is what separates them.
  const sign = Math.sign(apply(H, (quad[0][0] + quad[2][0]) / 2, (quad[0][1] + quad[2][1]) / 2)[2]);

  const x0 = Math.max(0, Math.floor(Math.min(...quad.map((p) => p[0]))) - 2);
  const x1 = Math.min(w, Math.ceil(Math.max(...quad.map((p) => p[0]))) + 2);
  const y0 = Math.max(0, Math.floor(Math.min(...quad.map((p) => p[1]))) - 2);
  const y1 = Math.min(h, Math.ceil(Math.max(...quad.map((p) => p[1]))) + 2);
  const bw = x1 - x0, bh = y1 - y0;
  if (bw < 8 || bh < 8) return false;

  // --- warp ---------------------------------------------------------------
  // 2×2 supersampling. The artwork is rendered larger than the quad, so every
  // destination pixel is a minification; point sampling would alias the
  // letterforms into a shimmer.
  const wa = new Float32Array(bw * bh);
  const wc = new Float32Array(bw * bh * 3);
  const px = new Float32Array(4);
  for (let y = 0; y < bh; y++) {
    for (let x = 0; x < bw; x++) {
      let sa = 0, sr = 0, sg = 0, sb = 0;
      for (const [dx, dy] of [[0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]]) {
        const [u, v, d] = apply(H, x0 + x + dx, y0 + y + dy);
        if (Math.sign(d) !== sign) continue;
        sampleRgba(art.rgba, art.width, art.height, u, v, px);
        sa += px[3]; sr += px[0]; sg += px[1]; sb += px[2];
      }
      const i = y * bw + x;
      wa[i] = sa / 4 / 255;
      wc[i * 3] = sr / 4; wc[i * 3 + 1] = sg / 4; wc[i * 3 + 2] = sb / 4;
    }
  }

  // Real spray has no crisp boundary. A touch of blur on the warped alpha is
  // the cheapest convincing version of that, and it hides resampling
  // stairsteps. Kept light and scaled to the piece: a fixed one-pixel blur is
  // invisible on a wall-sized throw-up and turns a small one to mush.
  const soft = boxBlur(wa, bw, bh, 1, 1);
  const k = clamp(bw / 900, 0.16, 0.45);
  for (let i = 0; i < wa.length; i++) wa[i] += (soft[i] - wa[i]) * k;

  // --- read the surface ---------------------------------------------------
  const lum = surface.fields?.lum ?? luminance(photo);
  const lumBlur = boxBlur(lum, w, h, 9);    // large-scale illumination
  const lumFine = boxBlur(lum, w, h, 1, 1); // for the noise estimate

  let n = 0, sLum = 0, sR = 0, sG = 0, sB = 0;
  const detail = [], hf = [];
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      if (wa[(y - y0) * bw + (x - x0)] < 0.02) continue;
      const i = y * w + x;
      n++;
      sLum += lumBlur[i];
      sR += data[i * 4]; sG += data[i * 4 + 1]; sB += data[i * 4 + 2];
      detail.push(Math.abs(lum[i] - lumBlur[i]));
      hf.push(Math.abs(lum[i] - lumFine[i]));
    }
  }
  if (n < 64) return false;

  const meanLum = Math.max(12, sLum / n);
  const illum = [sR / n / meanLum, sG / n / meanLum, sB / n / meanLum];
  detail.sort((a, b) => a - b);
  hf.sort((a, b) => a - b);
  // Median absolute deviation: robust to the one dark window in the region.
  const sdDetail = Math.max(3, detail[detail.length >> 1] * 1.4826);
  const sigma = clamp(hf[hf.length >> 1] * 1.2, 0.6, 6) * o.grain;

  // Coverage wanders across a wall; a can does not lay down an even film.
  const patch = valueNoise(bw, bh, 26, 0x51ed);
  const speck = valueNoise(bw, bh, 4, 0x9a3f);

  // --- paint --------------------------------------------------------------
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      const kx = x - x0, ky = y - y0;
      const q = ky * bw + kx;
      let a = wa[q];
      if (a < 0.004) continue;
      const i = y * w + x;

      // 1. Membership. Whatever stands in front of the wall stays unpainted;
      //    a tag running across a lamp post is an instant giveaway.
      a *= model.member(i);
      if (a < 0.004) continue;

      const L = lum[i];
      const Lb = Math.max(6, lumBlur[i]);
      const relief = (L - Lb) / sdDetail; // −1 deep in a mortar joint, +1 on a proud brick

      // 2. Coverage wear. The single most valuable pass. Spray travels in a
      //    straight line and simply does not reach into a recess, so the
      //    surface's own dark lines stay dark straight through the paint.
      a *= 1 - o.wear * 0.94 * (1 - smoothstep(-1.2, 0.1, relief));
      //    Plus slow variation in how much paint landed where.
      a *= 0.8 + 0.34 * patch(kx, ky);
      //    …and a fine dither, strongest where coverage is already thin.
      a *= 1 - 0.5 * (1 - a) * speck(kx, ky);
      a *= o.opacity;
      if (a < 0.004) continue;

      // 3. Colour. Start from the artwork's straight colour.
      const wi = q * 3;
      const inv = 1 / Math.max(wa[q], 0.05);
      let r = wc[wi] * inv, g = wc[wi + 1] * inv, b = wc[wi + 2] * inv;

      //    Texture through the paint: the wall's fine detail modulates it, so
      //    mortar, bumps and grime keep reading under the colour.
      const mod = clamp(1 + o.texture * ((L - Lb) / Math.max(Lb, 26)), 0.35, 1.9);
      //    Exposure: paint is lit by whatever is lighting this bit of wall.
      const f = mod * clamp(Lb / 168, 0.4, 1.3);
      r *= f * (1 + o.tint * (illum[0] - 1));
      g *= f * (1 + o.tint * (illum[1] - 1));
      b *= f * (1 + o.tint * (illum[2] - 1));

      //    Nothing in a street photograph is as saturated as a paint swatch.
      const grey = r * 0.299 + g * 0.587 + b * 0.114;
      r = grey + (r - grey) * o.desaturate;
      g = grey + (g - grey) * o.desaturate;
      b = grey + (b - grey) * o.desaturate;

      // 4. Composite, then match the photograph's own grain — clean paint over
      //    noisy brick separates out immediately to the eye.
      const nz = (speck(kx, ky) - 0.5) * 2 * sigma * a;
      const j = i * 4;
      data[j] = clamp(r * a + data[j] * (1 - a) + nz, 0, 255);
      data[j + 1] = clamp(g * a + data[j + 1] * (1 - a) + nz, 0, 255);
      data[j + 2] = clamp(b * a + data[j + 2] * (1 - a) + nz, 0, 255);
    }
  }
  return true;
}
