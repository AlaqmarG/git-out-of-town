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

import { boxBlur, clamp, luminance, open, sampleRgba, smoothstep } from "./image.mjs";
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

  // --- read the surface at three scales -----------------------------------
  //
  // Which scale each pass reads from is the difference between paint and
  // coloured glass. Texture and wear must see *fine* detail only — mortar
  // joints, grit, grime. Given a wide reference they also pick up window
  // reveals and door frames, and printing a whole window through the paint is
  // what makes a piece look transparent rather than opaque. Illumination is the
  // opposite: it must see only the broad sweep of sun and shade, or the paint
  // gets darkened twice by the same mortar joint.
  const lum = surface.fields?.lum ?? luminance(photo);
  const lumFine = boxBlur(lum, w, h, 1, 1);  // denoised, for the wear input
  const lumLocal = boxBlur(lum, w, h, 5);    // local reference: detail is what beats this
  const lumShade = boxBlur(lum, w, h, 22);   // the illumination field alone

  let n = 0, sLum = 0, sR = 0, sG = 0, sB = 0;
  const hf = [];
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      if (wa[(y - y0) * bw + (x - x0)] < 0.02) continue;
      const i = y * w + x;
      n++;
      sLum += lumShade[i];
      sR += data[i * 4]; sG += data[i * 4 + 1]; sB += data[i * 4 + 2];
      hf.push(Math.abs(lum[i] - lumFine[i]));
    }
  }
  if (n < 64) return false;

  const meanLum = Math.max(12, sLum / n);
  const illum = [sR / n / meanLum, sG / n / meanLum, sB / n / meanLum];
  // Median absolute deviation: robust to the one dark window in the region.
  hf.sort((a, b) => a - b);
  const sigma = clamp(hf[hf.length >> 1] * 1.4826, 0.5, 6) * o.grain;

  // Coverage wanders across a wall; a can does not lay down an even film.
  const patch = valueNoise(bw, bh, 26, 0x51ed);
  const speck = valueNoise(bw, bh, 4, 0x9a3f);

  // --- what must stay unpainted -------------------------------------------
  //
  // The colour model flags anything that does not look like the surface, which
  // catches the lamp post in front of the wall — but also the window frames
  // *on* it, and punching those through the paint makes the piece look like
  // coloured glass. Two guards. Opening deletes anything thinner than a few
  // pixels, so frame lines and cable runs go while poles and cars survive. And
  // the mask only gets full authority on a surface the model actually fits: on
  // a box straddling brick and plywood its verdicts are mostly noise.
  const reject = new Float32Array(bw * bh);
  for (let y = 0; y < bh; y++) {
    for (let x = 0; x < bw; x++) reject[y * bw + x] = 1 - model.member((y + y0) * w + x + x0);
  }
  const occluder = open(reject, bw, bh, 2);
  const authority = 0.25 + 0.75 * smoothstep(0.5, 0.85, model.homogeneity ?? 1);

  // --- paint --------------------------------------------------------------
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      const kx = x - x0, ky = y - y0;
      const q = ky * bw + kx;
      let a = wa[q];
      if (a < 0.004) continue;
      const i = y * w + x;

      // 1. Occlusion. Whatever stands in front of the wall stays unpainted;
      //    a tag running across a lamp post is an instant giveaway.
      a *= 1 - authority * occluder[q];
      if (a < 0.004) continue;

      const L = lum[i];
      const Lloc = Math.max(6, lumLocal[i]);

      // 2. Coverage wear. The single most valuable pass. Spray travels in a
      //    straight line and simply does not reach into a recess, so the
      //    surface's own dark lines stay dark straight through the paint.
      //
      //    `shade` is how much darker this pixel is than its surroundings, as a
      //    fraction of the local brightness — a physical quantity, not a
      //    normalised one. That distinction matters: dividing by the region's
      //    own variance turns JPEG noise on a smooth roller shutter into ±2
      //    swings and punches holes through the paint at random. Measured
      //    against local brightness, a mortar joint reads ≈ −1.5, a shutter's
      //    shallow groove ≈ −0.7, and sensor noise ≈ −0.05 and is ignored.
      //    Taken from the denoised luminance for the same reason.
      const shade = (lumFine[i] - Lloc) / Math.max(Lloc * 0.17, 6);
      a *= 1 - o.wear * 0.9 * (1 - smoothstep(-1.5, -0.15, shade));
      //    Plus slow variation in how much paint landed where.
      a *= 0.8 + 0.34 * patch(kx, ky);
      //    …and a fine dither, strongest where coverage is already thin.
      a *= 1 - 0.3 * (1 - a) * speck(kx, ky);
      a *= o.opacity;
      if (a < 0.004) continue;

      // 3. Colour. Start from the artwork's straight colour.
      const wi = q * 3;
      const inv = 1 / Math.max(wa[q], 0.05);
      let r = wc[wi] * inv, g = wc[wi + 1] * inv, b = wc[wi + 2] * inv;

      //    Texture through the paint: the wall's fine detail modulates it, so
      //    mortar, bumps and grime keep reading under the colour. Deliberately
      //    taken from the *raw* luminance, noise and all — that carries the
      //    photograph's own grain onto the paint, perfectly correlated with the
      //    surrounding pixels in a way added noise can never be.
      //    Through a soft knee, not a hard clamp: mortar (≈20% modulation)
      //    passes almost linearly, while anything much stronger saturates.
      //    Opaque paint hides structure; it does not hide grain.
      const KNEE = 0.26;
      const mod = 1 + o.texture * KNEE * Math.tanh((L - Lloc) / Math.max(Lloc, 26) / KNEE);
      //    Exposure: paint is lit by whatever is lighting this bit of wall.
      const f = mod * clamp(lumShade[i] / 168, 0.4, 1.3);
      r *= f * (1 + o.tint * (illum[0] - 1));
      g *= f * (1 + o.tint * (illum[1] - 1));
      b *= f * (1 + o.tint * (illum[2] - 1));

      //    Nothing in a street photograph is as saturated as a paint swatch.
      const grey = r * 0.299 + g * 0.587 + b * 0.114;
      r = grey + (r - grey) * o.desaturate;
      g = grey + (g - grey) * o.desaturate;
      b = grey + (b - grey) * o.desaturate;

      // 4. Composite, with a little extra grain for the flat fills where the
      //    texture pass clamps out. Clean paint over noisy brick separates
      //    immediately to the eye.
      const nz = (speck(kx, ky) - 0.5) * sigma * a;
      const j = i * 4;
      data[j] = clamp(r * a + data[j] * (1 - a) + nz, 0, 255);
      data[j + 1] = clamp(g * a + data[j + 1] * (1 - a) + nz, 0, 255);
      data[j + 2] = clamp(b * a + data[j + 2] * (1 - a) + nz, 0, 255);
    }
  }
  return true;
}
