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

// --- masks ------------------------------------------------------------------

/**
 * Sky, by flood fill from the top edge. A colour test alone paints white walls
 * as sky under an overcast sky; requiring connectivity to the top *and* refusing
 * to cross a strong edge keeps the fill on the right side of the roofline.
 */
function skyMask(img, mag) {
  const { data, width: w, height: h } = img;
  const sky = new Uint8Array(w * h);
  const skyish = (i) => {
    const r = data[i * 4], g = data[i * 4 + 1], b = data[i * 4 + 2];
    const lum = r * 0.299 + g * 0.587 + b * 0.114;
    return lum > 135 && b >= r - 6;
  };
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

// --- cell scoring -----------------------------------------------------------

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
  const { lum, mag, sky, veg, smooth } = fields;
  const gw = Math.floor(w / CELL), gh = Math.floor(h / CELL);
  const wall = new Float32Array(gw * gh);
  const ground = new Float32Array(gw * gh);
  const horizon = h / 2;

  for (let cy = 0; cy < gh; cy++) {
    for (let cx = 0; cx < gw; cx++) {
      let n = 0, sLum = 0, sMag = 0, sSky = 0, sVeg = 0, sSm = 0, sSm2 = 0, sSat = 0;
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
        }
      }
      const meanLum = sLum / n;
      const meanMag = sMag / n;
      const sat = sSat / n;
      const coarseSd = Math.sqrt(Math.max(0, sSm2 / n - (sSm / n) ** 2));

      // Flatness dominates; fine texture is only a tiebreaker.
      let q = Math.exp(-((coarseSd / 9) ** 2)) * (0.55 + 0.45 * Math.exp(-meanMag / 70));
      q *= 1 - smoothstep(0.02, 0.22, sSky / n);
      q *= 1 - smoothstep(0.05, 0.42, sVeg / n);
      q *= smoothstep(28, 62, meanLum) * (1 - smoothstep(232, 251, meanLum));

      const y0 = cy * CELL;
      // A wall lives above the ground line and below the roofline.
      wall[cy * gw + cx] = q * smoothstep(-0.04, 0.06, y0 / h) * (1 - smoothstep(0.86, 0.99, y0 / h));
      // Ground is below the horizon, unsaturated, and not blindingly bright.
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
 * Best rectangle of good cells. Scored on mean quality cubed times sqrt(area) —
 * quality has to dominate or the sweep just returns the biggest patch of sky-
 * adjacent nothing, but a tiny perfect patch is no use either.
 */
function bestRect(field, gw, gh, w, h, kind) {
  const I = integral(field, gw, gh);
  const bad = new Float32Array(field.length);
  for (let i = 0; i < field.length; i++) bad[i] = field[i] < 0.35 ? 1 : 0;
  const Ibad = integral(bad, gw, gh);

  let best = null;
  const widths = kind === "ground" ? [0.66, 0.52, 0.4] : [0.58, 0.46, 0.36, 0.28];
  const aspects = kind === "ground" ? [1.5, 2.0, 2.6] : [1.7, 2.2, 2.9, 3.6];

  for (const relW of widths) {
    const cw = Math.round((relW * w) / CELL);
    for (const aspect of aspects) {
      const ch = Math.round((relW * w) / aspect / CELL);
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

          const score = meanQ ** 3 * Math.sqrt(cw * ch) * place;
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
 * Where the near-horizontal lines inside `box` converge, along the horizon.
 *
 * A small Hough over edge pixels whose normal is near-vertical (so the line is
 * near-horizontal), then a least-squares intersection constrained to the horizon
 * row, refined once with residual reweighting to shake off a stray building face.
 *
 * Returns the x of the vanishing point, or null when the lines are parallel —
 * which is the honest answer for a wall you are square to.
 */
function vanishingX(fields, w, h, box) {
  const { gx, gy, mag } = fields;
  const cy = h / 2;
  const pad = 0.25;
  const bw = box[2] - box[0], bh = box[3] - box[1];
  const x0 = Math.max(0, Math.floor(box[0] - bw * pad));
  const x1 = Math.min(w, Math.ceil(box[2] + bw * pad));
  const y0 = Math.max(0, Math.floor(box[1] - bh * pad));
  const y1 = Math.min(h, Math.ceil(box[3] + bh * pad));

  const NA = 71; // normal angle 55°..125°, 1° bins
  const A0 = (55 * Math.PI) / 180, A1 = (125 * Math.PI) / 180;
  const RHO = 2;
  const rhoMax = Math.ceil(Math.hypot(w, h) / RHO) + 2;
  const acc = new Float32Array(NA * (2 * rhoMax + 1));

  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      const i = y * w + x;
      if (mag[i] < 55) continue;
      let a = Math.atan2(gy[i], gx[i]);
      if (a < 0) a += Math.PI;
      if (a < A0 || a > A1) continue;
      const ai = Math.min(NA - 1, Math.round(((a - A0) / (A1 - A0)) * (NA - 1)));
      const ang = A0 + (ai / (NA - 1)) * (A1 - A0);
      const rho = Math.round((x * Math.cos(ang) + y * Math.sin(ang)) / RHO);
      acc[ai * (2 * rhoMax + 1) + rho + rhoMax] += mag[i];
    }
  }

  // Peak picking with crude non-max suppression.
  const lines = [];
  let peak = 0;
  for (const v of acc) if (v > peak) peak = v;
  if (peak <= 0) return null;
  for (let ai = 0; ai < NA; ai++) {
    for (let ri = 1; ri < 2 * rhoMax; ri++) {
      const v = acc[ai * (2 * rhoMax + 1) + ri];
      if (v < peak * 0.28) continue;
      if (v < acc[ai * (2 * rhoMax + 1) + ri - 1] || v < acc[ai * (2 * rhoMax + 1) + ri + 1]) continue;
      const ang = A0 + (ai / (NA - 1)) * (A1 - A0);
      lines.push({ nx: Math.cos(ang), ny: Math.sin(ang), rho: (ri - rhoMax) * RHO, w: v });
    }
  }
  if (lines.length < 3) return null;

  // vx minimising Σ w (nx·vx + ny·cy − ρ)², then one reweighted pass.
  let vx = null;
  let weights = lines.map((l) => l.w);
  for (let iter = 0; iter < 2; iter++) {
    let num = 0, den = 0;
    lines.forEach((l, i) => {
      num += weights[i] * l.nx * (l.rho - l.ny * cy);
      den += weights[i] * l.nx * l.nx;
    });
    const total = lines.reduce((s, l, i) => s + weights[i], 0);
    // Near-zero slant mass means the lines really are parallel: no finite VP.
    if (den < total * 0.004) return null;
    vx = num / den;
    weights = lines.map((l, i) => {
      const r = Math.abs(l.nx * vx + l.ny * cy - l.rho);
      return l.w / (1 + (r / 24) ** 2);
    });
  }

  // A VP inside or beside the region is a misfit, not a wall raking away.
  const cxBox = (box[0] + box[2]) / 2;
  if (!Number.isFinite(vx) || Math.abs(vx - cxBox) < w * 0.55) return null;
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
  const a = clamp(vx === null ? Infinity : vx - cx, -40 * w, 40 * w);
  const dir = norm([a, 0, f]);
  const n = norm([-f, 0, a]);
  // Keep the plane in front of the camera.
  const D = n[2] > 0 ? 10 : -10;
  const axisU = a >= 0 ? dir : [-dir[0], -dir[1], -dir[2]];
  return makePlane({ n: D > 0 ? n : [-n[0], -n[1], -n[2]], D: Math.abs(D), axisU, axisV: [0, 1, 0], f, cx, cy });
}

function groundPlane(vx, w, h, f) {
  const cx = w / 2, cy = h / 2;
  const a = vx === null ? 0 : clamp(vx - cx, -6 * w, 6 * w);
  const away = norm([a, 0, f]);
  const across = norm([-f, 0, a]);
  return makePlane({
    n: [0, 1, 0],
    D: CAM_HEIGHT,
    axisU: across[0] >= 0 ? across : [-across[0], -across[1], -across[2]],
    axisV: [-away[0], -away[1], -away[2]], // art's "down" is toward the camera
    f, cx, cy,
  });
}

/**
 * Turn the found box into a quad by measuring it *on the plane*, fitting a
 * rectangle of the artwork's aspect inside it, and projecting that back.
 */
function quadFromBox(plane, box, aspect, w, h) {
  const corners = [
    [box[0], box[1]], [box[2], box[1]], [box[2], box[3]], [box[0], box[3]],
  ].map(([x, y]) => plane.unproject(x, y));
  if (corners.some((c) => c === null)) return null;

  const us = corners.map((c) => c[0]), vs = corners.map((c) => c[1]);
  const u0 = Math.min(...us), u1 = Math.max(...us);
  const v0 = Math.min(...vs), v1 = Math.max(...vs);
  const uc = (u0 + u1) / 2, vc = (v0 + v1) / 2;

  // Fit the art's aspect inside the measured rectangle.
  let du = u1 - u0, dv = v1 - v0;
  if (du / dv > aspect) du = dv * aspect;
  else dv = du / aspect;

  const quad = [
    plane.project(uc - du / 2, vc - dv / 2),
    plane.project(uc + du / 2, vc - dv / 2),
    plane.project(uc + du / 2, vc + dv / 2),
    plane.project(uc - du / 2, vc + dv / 2),
  ];
  if (quad.some((p) => p === null)) return null;
  // Reject anything that wandered far off frame or collapsed.
  const xs = quad.map((p) => p[0]), ys = quad.map((p) => p[1]);
  if (Math.min(...xs) < -w * 0.4 || Math.max(...xs) > w * 1.4) return null;
  if (Math.min(...ys) < -h * 0.4 || Math.max(...ys) > h * 1.4) return null;
  if (Math.max(...xs) - Math.min(...xs) < w * 0.1) return null;
  return quad;
}

// --- entry point ------------------------------------------------------------

/**
 * Locate a paintable surface. Returns null when the view has nothing plausible —
 * a treed street, a car park, a wall of glass — and the caller should try
 * another heading rather than paint something silly.
 */
export function findSurface(img, { aspect = 2.2, fov = 80, prefer = "auto" } = {}) {
  const { width: w, height: h } = img;
  const f = w / 2 / Math.tan((fov * Math.PI) / 360);

  const lum = luminance(img);
  const grad = sobel(lum, w, h);
  const fields = {
    lum,
    ...grad,
    smooth: boxBlur(lum, w, h, 4),
    sky: skyMask(img, grad.mag),
    veg: vegMask(img),
  };

  const cells = scoreCells(img, fields);
  const options = [];
  for (const kind of prefer === "auto" ? ["wall", "ground"] : [prefer]) {
    const rect = bestRect(cells[kind], cells.gw, cells.gh, w, h, kind);
    if (rect) options.push({ kind, ...rect });
  }
  if (!options.length) return null;

  // Walls read better than ground at almost any angle; only prefer ground when
  // it is clearly the stronger find.
  options.sort((a, b) => b.score * (b.kind === "wall" ? 1.35 : 1) - a.score * (a.kind === "wall" ? 1.35 : 1));

  for (const opt of options) {
    const vx = vanishingX(fields, w, h, opt.box);
    const plane = opt.kind === "ground" ? groundPlane(vx, w, h, f) : wallPlane(vx, w, h, f);
    const quad = quadFromBox(plane, opt.box, aspect, w, h);
    if (quad) return { kind: opt.kind, quad, box: opt.box, vanishX: vx, quality: opt.meanQ, fields };
  }
  return null;
}
