/**
 * Finding a paintable plane in a Street View still.
 *
 * Three stages:
 *   1. score every 8px cell on how much it looks like a flat, paintable surface
 *   2. find the best rectangle of good cells (integral image, brute-force sweep)
 *   3. recover the *plane* that rectangle lies on, and re-project a true
 *      world-space rectangle onto the image
 *
 * Stage 3 is what makes the paint sit in the scene rather than on it. It leans
 * on one fact about the imagery: the Street View static API renders a
 * rectilinear projection, so at `pitch=0` the horizon is exactly the centre row.
 * Every vanishing point of a horizontal line therefore lies on that row — which
 * turns vanishing-point estimation from a fragile 2-D fit into a 1-D one.
 */

import { boxBlur, clamp, luminance, smoothstep, sobel } from "./image.mjs";

const CELL = 8;
/** Street View car camera height, metres. Only sets scale; shape is unaffected. */
const CAM_HEIGHT = 2.5;
/** Aspect ratios a throw-up can sensibly be drawn at. */
const MIN_ASPECT = 1.5, MAX_ASPECT = 3.4;

// --- masks ------------------------------------------------------------------

/**
 * Sky — the one region that scores perfectly on every "is this a flat surface"
 * test and must never be painted.
 *
 * Two detectors, unioned, because neither alone is enough. Clear blue is
 * unmistakable from colour, so it is taken outright. Overcast white is
 * indistinguishable from a white wall by colour, so it has to be reached by a
 * flood fill from the top edge that refuses to cross a strong edge — which
 * keeps the fill on the right side of the roofline.
 */
function skyMask(img, mag) {
  const { data, width: w, height: h } = img;
  const sky = new Uint8Array(w * h);
  const skyish = (i) => {
    const r = data[i * 4], g = data[i * 4 + 1], b = data[i * 4 + 2];
    return r * 0.299 + g * 0.587 + b * 0.114 > 118 && b >= r - 6;
  };

  for (let y = 0; y < h * 0.72; y++) {
    for (let x = 0; x < w; x++) {
      const i = y * w + x;
      if (data[i * 4 + 2] > 118 && data[i * 4 + 2] - data[i * 4] > 24) sky[i] = 1; // unambiguous blue
    }
  }

  const stack = [];
  for (let x = 0; x < w; x++) if (skyish(x)) { sky[x] = 1; stack.push(x); }
  while (stack.length) {
    const i = stack.pop();
    const x = i % w, y = (i / w) | 0;
    if (y > h * 0.72) continue;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      const j = ny * w + nx;
      if (sky[j] || mag[j] > 34 || !skyish(j)) continue;
      sky[j] = 1;
      stack.push(j);
    }
  }
  return sky;
}

/** Foliage: green-dominant. High-energy and never a surface anyone paints. */
function vegMask(img) {
  const { data } = img;
  const veg = new Uint8Array(img.width * img.height);
  for (let p = 0; p < veg.length; p++) {
    const r = data[p * 4], g = data[p * 4 + 1], b = data[p * 4 + 2];
    if (g > r + 5 && g > b + 5) veg[p] = 1;
  }
  return veg;
}

/**
 * A robust colour model of what the chosen surface looks like, used to decide
 * whether a given pixel belongs to it.
 *
 * Median and MAD rather than mean and standard deviation, because the sample box
 * usually contains a drainpipe or a stain and those would drag a mean around.
 * A wide-gamut surface like brick gets a large MAD and a permissive test, which
 * is the right behaviour — brick really is that varied.
 *
 * Two jobs: keeping the perspective vote on the wall rather than on the power
 * lines crossing the sky behind it, and keeping paint off whatever stands in
 * front of the wall.
 */
export function surfaceModel(img, box) {
  const { data, width: w } = img;
  const chans = [[], [], []];
  for (let y = box[1]; y < box[3]; y += 2) {
    for (let x = box[0]; x < box[2]; x += 2) {
      const i = (y * w + x) * 4;
      for (let c = 0; c < 3; c++) chans[c].push(data[i + c]);
    }
  }
  const med = [], mad = [];
  for (let c = 0; c < 3; c++) {
    const s = chans[c].sort((a, b) => a - b);
    const m = s[s.length >> 1];
    med.push(m);
    const dev = s.map((v) => Math.abs(v - m)).sort((a, b) => a - b);
    mad.push(dev[dev.length >> 1]);
  }
  const tol = med.map((_, c) => 2.4 * mad[c] + 14);
  return {
    med,
    mad,
    member(i) {
      let d = 0;
      for (let c = 0; c < 3; c++) d = Math.max(d, Math.abs(data[i * 4 + c] - med[c]) / tol[c]);
      return 1 - smoothstep(1.0, 2.3, d);
    },
  };
}

// --- cell scoring -----------------------------------------------------------

/**
 * Local edge orientation by structure tensor. Per-pixel Sobel angles are far too
 * noisy to vote with; smoothing the tensor (not the gradients — those cancel)
 * gives a stable orientation plus a coherence score that says whether there is
 * a line here at all, or just texture.
 */
export function structureTensor(grad, w, h, r = 2) {
  const { gx, gy } = grad;
  const xx = new Float32Array(w * h), yy = new Float32Array(w * h), xy = new Float32Array(w * h);
  for (let i = 0; i < xx.length; i++) {
    xx[i] = gx[i] * gx[i];
    yy[i] = gy[i] * gy[i];
    xy[i] = gx[i] * gy[i];
  }
  return { xx: boxBlur(xx, w, h, r), yy: boxBlur(yy, w, h, r), xy: boxBlur(xy, w, h, r) };
}

/**
 * Per-pixel strength of *vertical* lines.
 *
 * With a level camera, only a vertical plane can show vertical lines — a ground
 * plane's seams all converge on the horizon instead. Door jambs, downpipes,
 * window reveals and pilasters are therefore the cleanest evidence that a smooth
 * grey rectangle is a wall and not a stretch of pavement.
 */
function verticalLines(tensor, w, h) {
  const out = new Float32Array(w * h);
  for (let i = 0; i < out.length; i++) {
    const jxx = tensor.xx[i], jyy = tensor.yy[i], jxy = tensor.xy[i];
    const tr = jxx + jyy;
    if (tr < 900) continue;
    const disc = Math.sqrt((jxx - jyy) ** 2 + 4 * jxy * jxy);
    const coh = disc / tr;
    if (coh < 0.55) continue;
    // Gradient horizontal ⇒ the line it sits on is vertical.
    if (Math.abs(Math.cos(0.5 * Math.atan2(2 * jxy, jxx - jyy))) < 0.9) continue;
    out[i] = coh;
  }
  return out;
}

/**
 * How paintable is each cell?
 *
 * The discriminator that matters is *coarse* flatness, not fine flatness. Brick
 * is full of fine detail but is perfectly flat once you blur it; a car, a window
 * or a hedge is not. So the dominant term is the variance of a blurred
 * luminance, with fine gradient energy only a tiebreaker.
 */
function scoreCells(img, fields) {
  const { width: w, height: h } = img;
  const { lum, mag, sky, veg, smooth, vert } = fields;
  const gw = Math.floor(w / CELL), gh = Math.floor(h / CELL);
  const wall = new Float32Array(gw * gh);
  const ground = new Float32Array(gw * gh);
  const horizon = h / 2;

  for (let cy = 0; cy < gh; cy++) {
    for (let cx = 0; cx < gw; cx++) {
      let n = 0, sLum = 0, sMag = 0, sSky = 0, sVeg = 0, sSm = 0, sSm2 = 0, sSat = 0, sVert = 0;
      for (let y = cy * CELL; y < (cy + 1) * CELL; y++) {
        for (let x = cx * CELL; x < (cx + 1) * CELL; x++) {
          const i = y * w + x;
          const r = img.data[i * 4], g = img.data[i * 4 + 1], b = img.data[i * 4 + 2];
          const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
          n++;
          sLum += lum[i];
          sMag += mag[i];
          sSky += sky[i];
          sVeg += veg[i];
          sSm += smooth[i];
          sSm2 += smooth[i] * smooth[i];
          sSat += mx > 8 ? (mx - mn) / mx : 0;
          sVert += vert[i];
        }
      }
      const meanLum = sLum / n;
      const meanMag = sMag / n;
      const sat = sSat / n;
      const coarseSd = Math.sqrt(Math.max(0, sSm2 / n - (sSm / n) ** 2));

      // Flatness dominates; fine texture is only a tiebreaker.
      let q = Math.exp(-((coarseSd / 9) ** 2)) * (0.55 + 0.45 * Math.exp(-meanMag / 70));
      // But a *completely* featureless patch is sky, glass or blown highlight —
      // never a surface. Every real material has some grain at this scale.
      q *= smoothstep(2.5, 7, meanMag);
      q *= 1 - smoothstep(0.02, 0.22, sSky / n);
      q *= 1 - smoothstep(0.05, 0.42, sVeg / n);
      q *= smoothstep(28, 62, meanLum) * (1 - smoothstep(232, 251, meanLum));

      const y0 = cy * CELL;
      // Tarmac and concrete slabs are flat, even and irresistible to the
      // scorer, and painting them as if they were vertical is the worst failure
      // this module can make. Below the horizon, grey, and with no vertical
      // lines anywhere nearby is the signature — dock it hard.
      const groundish =
        smoothstep(horizon + 15, horizon + 75, y0) *
        (1 - smoothstep(0.16, 0.38, sat)) *
        (1 - smoothstep(0.012, 0.06, sVert / n));

      wall[cy * gw + cx] =
        q * (1 - 0.9 * groundish) *
        smoothstep(-0.04, 0.06, y0 / h) * (1 - smoothstep(0.86, 0.99, y0 / h));
      ground[cy * gw + cx] =
        q * smoothstep(horizon + 4, horizon + 40, y0) * (1 - smoothstep(0.22, 0.45, sat));
    }
  }
  return { wall, ground, gw, gh };
}

function integral(field, gw, gh) {
  const I = new Float64Array((gw + 1) * (gh + 1));
  for (let y = 0; y < gh; y++) {
    let row = 0;
    for (let x = 0; x < gw; x++) {
      row += field[y * gw + x];
      I[(y + 1) * (gw + 1) + x + 1] = I[y * (gw + 1) + x + 1] + row;
    }
  }
  return I;
}

const rectSum = (I, gw, x0, y0, x1, y1) =>
  I[y1 * (gw + 1) + x1] - I[y0 * (gw + 1) + x1] - I[y1 * (gw + 1) + x0] + I[y0 * (gw + 1) + x0];

/**
 * Best rectangle of good cells.
 *
 * The balance between "clean" and "big" is the whole game here. Quality is
 * cubed so a patch with a window in it never wins, but area carries a high
 * exponent because a small immaculate patch is the wrong answer: graffiti fills
 * a wall, and a postage stamp of paint in the middle of a garage door looks
 * exactly like what it is — an algorithm being timid.
 */
function bestRect(field, gw, gh, w, h, kind, aspect) {
  const I = integral(field, gw, gh);
  const bad = new Float32Array(field.length);
  for (let i = 0; i < field.length; i++) bad[i] = field[i] < 0.35 ? 1 : 0;
  const Ibad = integral(bad, gw, gh);

  let best = null;
  const widths = kind === "ground" ? [0.72, 0.58, 0.44] : [0.74, 0.6, 0.47, 0.36];
  // Boxes near the artwork's own aspect, so fitting it in wastes little of the
  // surface we worked to find.
  const aspects = [0.7, 1, 1.45].map((k) => aspect * k);

  for (const relW of widths) {
    const cw = Math.round((relW * w) / CELL);
    for (const asp of aspects) {
      const ch = Math.round((relW * w) / asp / CELL);
      if (cw < 6 || ch < 4 || cw > gw || ch > gh) continue;
      for (let y = 0; y + ch <= gh; y += 2) {
        for (let x = 0; x + cw <= gw; x += 2) {
          const cells = cw * ch;
          if (rectSum(Ibad, gw, x, y, x + cw, y + ch) / cells > 0.1) continue;
          const meanQ = rectSum(I, gw, x, y, x + cw, y + ch) / cells;
          if (meanQ < 0.42) continue;

          const yc = ((y + ch / 2) * CELL) / h;
          const xc = ((x + cw / 2) * CELL) / w;
          // Walls: paint goes where a hand reaches. Ground: near the camera.
          const place =
            kind === "ground"
              ? 0.5 + 0.5 * smoothstep(0.6, 0.95, yc)
              : (1 - 0.85 * Math.abs(yc - 0.56)) * (1 - 0.3 * Math.abs(xc - 0.5));

          const score = meanQ ** 3 * (cw * ch) ** 0.8 * place;
          if (!best || score > best.score) {
            best = { score, meanQ, box: [x * CELL, y * CELL, (x + cw) * CELL, (y + ch) * CELL] };
          }
        }
      }
    }
  }
  return best;
}

// --- vanishing point --------------------------------------------------------

/**
 * Where the near-horizontal lines around `box` converge, along the horizon.
 *
 * Every oriented pixel implies its own vanishing point: a line through (x,y)
 * whose normal is at angle φ meets the horizon at `x + (y − cy)·tanφ`. So rather
 * than extracting lines and intersecting them, vote for that value directly —
 * a one-dimensional Hough in vanishing-point space.
 *
 * Two details make it work. Votes are weighted by |cosφ|, which is the precision
 * of the estimate: a perfectly horizontal edge says nothing about where the
 * vanishing point is, and correctly contributes nothing. And the axis is
 * compressed through `atan`, so "at infinity" is a finite bin at each end —
 * a frontal wall produces a clean peak there instead of a smeared tail.
 *
 * Returns null for a frontal wall, which is the honest answer, not a failure.
 */
function vanishingX(fields, w, h, box, model) {
  const { tensor, sky } = fields;
  const cx = w / 2, cy = h / 2;
  // Generous margin: a blank wall's own coursing may be too faint to vote, and
  // the roofline and window heads that do carry the perspective sit outside it.
  const bw = box[2] - box[0], bh = box[3] - box[1];
  const x0 = Math.max(0, Math.floor(box[0] - bw * 0.7));
  const x1 = Math.min(w, Math.ceil(box[2] + bw * 0.7));
  const y0 = Math.max(0, Math.floor(box[1] - bh));
  const y1 = Math.min(h, Math.ceil(box[3] + bh));

  const NB = 141;
  const SCALE = 1.5 * w;
  const bins = new Float64Array(NB); // splatted, for peak finding
  const mass = new Float64Array(NB); // exact-bin weight, for the refined mean
  const sums = new Float64Array(NB); // exact-bin weight × u
  let total = 0;

  for (let y = y0; y < y1; y++) {
    // Near the horizon every line reports its own x; no information, and it
    // would just pull the estimate toward the region centre.
    if (Math.abs(y - cy) < 20) continue;
    for (let x = x0; x < x1; x++) {
      const i = y * w + x;
      // Overhead cables are strong, near-horizontal, and converge nowhere
      // useful; so is the building across the street. Vote only from pixels
      // that look like the surface we picked. The sky test is deliberately
      // un-dilated: a roofline pixel is a wall pixel, and the roofline is
      // usually the strongest perspective cue in the frame.
      if (sky[i]) continue;
      const belongs = model.member(i);
      if (belongs < 0.35) continue;

      const jxx = tensor.xx[i], jyy = tensor.yy[i], jxy = tensor.xy[i];
      const tr = jxx + jyy;
      if (tr < 900) continue;
      const disc = Math.sqrt((jxx - jyy) ** 2 + 4 * jxy * jxy);
      const coh = disc / tr;
      if (coh < 0.55) continue;

      const phi = 0.5 * Math.atan2(2 * jxy, jxx - jyy); // gradient orientation, mod π
      const nx = Math.cos(phi), ny = Math.sin(phi);
      if (Math.abs(ny) < 0.82) continue; // line not near-horizontal

      const vx = x + ((y - cy) * ny) / nx;
      const u = Math.atan((vx - cx) / SCALE);
      const b = clamp(Math.round((u / Math.PI + 0.5) * (NB - 1)), 0, NB - 1);
      const weight = Math.sqrt(disc) * coh * Math.abs(nx) * belongs;
      // Triangular splat absorbs bin quantisation.
      bins[b] += weight;
      if (b > 0) bins[b - 1] += weight * 0.5;
      if (b < NB - 1) bins[b + 1] += weight * 0.5;
      mass[b] += weight;
      sums[b] += weight * u;
      total += weight;
    }
  }
  if (total < 400) return null;

  let best = 0;
  for (let b = 0; b < NB; b++) if (bins[b] > bins[best]) best = b;
  // Peaks at the extremes mean "no finite vanishing point": a frontal surface.
  if (best < NB * 0.09 || best > NB * 0.91) return null;

  // A real plane makes a sharp mode. A jumble of unrelated edges does not.
  let m = 0, mu = 0;
  for (let b = Math.max(0, best - 2); b <= Math.min(NB - 1, best + 2); b++) {
    m += mass[b];
    mu += sums[b];
  }
  if (m < total * 0.16) return null;

  const vx = cx + SCALE * Math.tan(clamp(mu / m, -1.5, 1.5));
  if (!Number.isFinite(vx)) return null;

  // A planar face cannot contain its own vanishing point — it would fold there.
  const margin = w * 0.12;
  if (vx > box[0] - margin && vx < box[2] + margin) return null;
  const dNear = Math.max(Math.abs(vx - box[0]), Math.abs(vx - box[2]));
  const dFar = Math.min(Math.abs(vx - box[0]), Math.abs(vx - box[2]));
  // Reject rakes so steep that the far end is a smear: any small error in the
  // estimate blows up, and the artwork stops being legible anyway.
  if (dFar / dNear < 0.26) return null;
  // And a taper this slight is inside the estimator's own noise. Frontal is the
  // safer reading: a wrong small rake is more obvious than no rake at all.
  if (dFar / dNear > 0.87) return null;

  return clamp(vx, -14 * w, 15 * w);
}

// --- plane geometry ---------------------------------------------------------

const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const norm = (v) => {
  const m = Math.hypot(v[0], v[1], v[2]);
  return [v[0] / m, v[1] / m, v[2] / m];
};

/**
 * A plane in camera space (x right, y down, z forward) plus the two in-plane
 * axes the artwork's u/v map to. `project`/`unproject` are exact inverses, so a
 * rectangle in (u,v) is a genuine world rectangle however hard the perspective.
 */
function makePlane({ n, D, axisU, axisV, f, cx, cy }) {
  const P0 = [n[0] * D, n[1] * D, n[2] * D];
  return {
    axisU, axisV,
    /** Image point → plane coordinates, or null if the ray misses the plane. */
    unproject(px, py) {
      const d = [px - cx, py - cy, f];
      const nd = dot(n, d);
      if (nd < 1e-4) return null;
      const t = D / nd;
      const P = [d[0] * t - P0[0], d[1] * t - P0[1], d[2] * t - P0[2]];
      return [dot(P, axisU), dot(P, axisV)];
    },
    /** Plane coordinates → image point, or null if behind the camera. */
    project(u, v) {
      const P = [
        P0[0] + u * axisU[0] + v * axisV[0],
        P0[1] + u * axisU[1] + v * axisV[1],
        P0[2] + u * axisU[2] + v * axisV[2],
      ];
      if (P[2] < 1e-3) return null;
      return [cx + (f * P[0]) / P[2], cy + (f * P[1]) / P[2]];
    },
  };
}

function wallPlane(vx, w, h, f) {
  const cx = w / 2, cy = h / 2;
  // A vanishing point at (vx, cy) means the wall runs along (vx−cx, 0, f).
  // Cap it: beyond this the wall is effectively fronto-parallel anyway.
  const a = vx === null ? 40 * w : clamp(vx - cx, -40 * w, 40 * w);
  const dir = norm([a, 0, f]);
  let n = norm([-f, 0, a]);
  if (n[2] < 0) n = [-n[0], -n[1], -n[2]]; // keep the plane in front of us
  return makePlane({ n, D: 10, axisU: [...dir], axisV: [0, 1, 0], f, cx, cy });
}

function groundPlane(vx, w, h, f) {
  const cx = w / 2, cy = h / 2;
  const a = vx === null ? 0 : clamp(vx - cx, -6 * w, 6 * w);
  const away = norm([a, 0, f]);
  const across = norm([-f, 0, a]);
  return makePlane({
    n: [0, 1, 0],
    D: CAM_HEIGHT,
    axisU: [...across],
    axisV: [-away[0], -away[1], -away[2]], // the art's "down" is toward the camera
    f, cx, cy,
  });
}

/**
 * Point the plane's u axis right and its v axis down *in the image*, so the
 * artwork never lands mirrored or upside down.
 */
function orient(plane, box) {
  const mid = plane.unproject((box[0] + box[2]) / 2, (box[1] + box[3]) / 2);
  if (!mid) return false;
  const here = plane.project(mid[0], mid[1]);
  const right = plane.project(mid[0] + 0.05, mid[1]);
  const down = plane.project(mid[0], mid[1] + 0.05);
  if (!here || !right || !down) return false;
  if (right[0] < here[0]) for (let i = 0; i < 3; i++) plane.axisU[i] *= -1;
  if (down[1] < here[1]) for (let i = 0; i < 3; i++) plane.axisV[i] *= -1;
  return true;
}

/**
 * Turn the found box into a quad by measuring it *on the plane* and projecting
 * a world rectangle back. Returns the quad and the rectangle's true world
 * aspect, so the artwork can be drawn to fit rather than letterboxed into it.
 *
 * The subtlety: a rectangle in the image is a *trapezoid* on a raked plane, and
 * its far end covers far more ground than its near end. Taking the bounding box
 * of that trapezoid produces a world rectangle several times larger than the
 * region we vetted, which then reprojects halfway across the frame. So take the
 * inscribed rectangle instead — every corner max'd or min'd inward — and the
 * artwork is guaranteed to stay on the surface we actually checked.
 */
function quadFromBox(plane, box, w, h, rand) {
  if (!orient(plane, box)) return null;
  const c = [
    [box[0], box[1]], [box[2], box[1]], [box[2], box[3]], [box[0], box[3]],
  ].map(([x, y]) => plane.unproject(x, y));
  if (c.some((p) => p === null)) return null;
  const [tl, tr, br, bl] = c;

  const u0 = Math.max(tl[0], bl[0]), u1 = Math.min(tr[0], br[0]);
  const v0 = Math.max(tl[1], tr[1]), v1 = Math.min(bl[1], br[1]);
  if (u1 - u0 < 1e-3 || v1 - v0 < 1e-3) return null;

  // Nobody paints flush to the edges of a wall, and dead-centre placement is
  // its own tell. Leave a margin and drift inside it.
  let du = (u1 - u0) * 0.9, dv = (v1 - v0) * 0.9;
  const aspect = clamp(du / dv, MIN_ASPECT, MAX_ASPECT);
  if (du / dv > aspect) du = dv * aspect;
  else dv = du / aspect;

  const slackU = (u1 - u0 - du) / 2, slackV = (v1 - v0 - dv) / 2;
  const uc = (u0 + u1) / 2 + slackU * (rand() * 2 - 1) * 0.8;
  const vc = (v0 + v1) / 2 + slackV * (rand() * 2 - 1) * 0.8;

  const quad = [
    plane.project(uc - du / 2, vc - dv / 2),
    plane.project(uc + du / 2, vc - dv / 2),
    plane.project(uc + du / 2, vc + dv / 2),
    plane.project(uc - du / 2, vc + dv / 2),
  ];
  if (quad.some((p) => p === null)) return null;

  const xs = quad.map((p) => p[0]), ys = quad.map((p) => p[1]);
  if (Math.max(...xs) - Math.min(...xs) < w * 0.1) return null;
  if (Math.max(...ys) - Math.min(...ys) < h * 0.05) return null;
  if (Math.min(...xs) < -w * 0.15 || Math.max(...xs) > w * 1.15) return null;
  if (Math.min(...ys) < -h * 0.15 || Math.max(...ys) > h * 1.15) return null;
  return { quad, aspect };
}

// --- entry point ------------------------------------------------------------

/**
 * Locate a paintable surface. Returns null when the view has nothing plausible —
 * a treed street, a car park, a wall of glass — and the caller should try
 * another heading rather than paint something silly.
 */
export function findSurface(img, { fov = 80, prefer = "auto", rand = Math.random } = {}) {
  const nominalAspect = 2.2; // only shapes the candidate boxes; the quad measures its own
  const { width: w, height: h } = img;
  const f = w / 2 / Math.tan((fov * Math.PI) / 360);

  const lum = luminance(img);
  const grad = sobel(lum, w, h);
  const tensor = structureTensor(grad, w, h);
  const fields = {
    lum,
    ...grad,
    tensor,
    // Blurred wide so a smooth patch of wall inherits the evidence from the
    // door frame beside it.
    vert: boxBlur(verticalLines(tensor, w, h), w, h, 14, 1),
    smooth: boxBlur(lum, w, h, 4),
    sky: skyMask(img, grad.mag),
    veg: vegMask(img),
  };

  const cells = scoreCells(img, fields);
  const options = [];
  for (const kind of prefer === "auto" ? ["wall", "ground"] : [prefer]) {
    const rect = bestRect(cells[kind], cells.gw, cells.gh, w, h, kind, nominalAspect);
    if (rect) options.push({ kind, ...rect });
  }
  if (!options.length) return null;

  // Walls read better than ground at almost any angle, and are where graffiti
  // actually goes; only fall to the ground when it is much the stronger find.
  const bias = (o) => o.score * (o.kind === "wall" ? 2.0 : 1);
  options.sort((a, b) => bias(b) - bias(a));

  for (const opt of options) {
    const model = surfaceModel(img, opt.box);
    const vx = vanishingX(fields, w, h, opt.box, model);
    const plane = opt.kind === "ground" ? groundPlane(vx, w, h, f) : wallPlane(vx, w, h, f);
    const fit = quadFromBox(plane, opt.box, w, h, rand);
    if (fit) {
      return {
        kind: opt.kind, ...fit,
        box: opt.box, vanishX: vx, quality: opt.meanQ, model, fields,
      };
    }
  }
  return null;
}
