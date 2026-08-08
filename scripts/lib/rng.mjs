/**
 * One seedable random source, shared by everything that draws.
 *
 * Iterating on realism is impossible if every run produces a different piece in
 * a different place — you cannot tell whether a change helped or the dice
 * changed. `seedArt(n)` makes a whole render reproducible.
 */

export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export const R = { next: Math.random };

/** Seed the shared source, or pass nothing to go back to real randomness. */
export function seedArt(n) {
  R.next = n === undefined || n === null ? Math.random : mulberry32(n);
}

/**
 * Smooth 2-D value noise on a coarse lattice, bilinearly upsampled.
 *
 * Used for coverage variation: paint density wanders over a wall at a scale of
 * tens of centimetres, and perfectly even coverage is one of the tells.
 */
export function valueNoise(w, h, cellPx, seed) {
  const rnd = mulberry32(seed);
  const gw = Math.ceil(w / cellPx) + 2, gh = Math.ceil(h / cellPx) + 2;
  const grid = new Float32Array(gw * gh);
  for (let i = 0; i < grid.length; i++) grid[i] = rnd();
  return (x, y) => {
    const fx = x / cellPx, fy = y / cellPx;
    const x0 = Math.floor(fx), y0 = Math.floor(fy);
    const tx = fx - x0, ty = fy - y0;
    const sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty);
    const g = (gx, gy) =>
      grid[Math.min(gh - 1, Math.max(0, gy)) * gw + Math.min(gw - 1, Math.max(0, gx))];
    const a = g(x0, y0) + (g(x0 + 1, y0) - g(x0, y0)) * sx;
    const b = g(x0, y0 + 1) + (g(x0 + 1, y0 + 1) - g(x0, y0 + 1)) * sx;
    return a + (b - a) * sy;
  };
}
