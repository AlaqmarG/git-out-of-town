/**
 * The small raster toolkit the compositor needs: JPEG in/out and the three
 * filters everything else is built from — luminance, box blur, Sobel.
 *
 * `jpeg-js` is the one image dependency in the repo. It is pure JS on purpose:
 * `sharp` is a native build and a deployment liability on the ARM VPS.
 *
 * Images are `{ data: Buffer RGBA8, width, height }` throughout. Scalar fields
 * (luminance, blur, gradients) are `Float32Array` of width*height.
 */

import jpeg from "jpeg-js";

export const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);

/** Hermite ramp from 0 at `a` to 1 at `b`. */
export function smoothstep(a, b, x) {
  const t = clamp((x - a) / (b - a || 1e-6), 0, 1);
  return t * t * (3 - 2 * t);
}

/** Deterministic RNG — iteration on realism is impossible if every run differs. */
export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function decodeJpeg(buf) {
  const raw = jpeg.decode(buf, { useTArray: true, formatAsRGBA: true });
  return {
    data: Buffer.from(raw.data.buffer, raw.data.byteOffset, raw.data.length),
    width: raw.width,
    height: raw.height,
  };
}

export function encodeJpeg(img, quality = 86) {
  return Buffer.from(jpeg.encode({ data: img.data, width: img.width, height: img.height }, quality).data);
}

export function cloneImage(img) {
  return { data: Buffer.from(img.data), width: img.width, height: img.height };
}

export function luminance(img) {
  const { data } = img;
  const out = new Float32Array(img.width * img.height);
  for (let p = 0, i = 0; p < out.length; p++, i += 4) {
    out[p] = data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114;
  }
  return out;
}

function blurH(src, dst, w, h, r) {
  const norm = 1 / (2 * r + 1);
  for (let y = 0; y < h; y++) {
    const row = y * w;
    let sum = 0;
    for (let i = -r; i <= r; i++) sum += src[row + clamp(i, 0, w - 1)];
    for (let x = 0; x < w; x++) {
      dst[row + x] = sum * norm;
      sum += src[row + clamp(x + r + 1, 0, w - 1)] - src[row + clamp(x - r, 0, w - 1)];
    }
  }
}

function blurV(src, dst, w, h, r) {
  const norm = 1 / (2 * r + 1);
  for (let x = 0; x < w; x++) {
    let sum = 0;
    for (let i = -r; i <= r; i++) sum += src[clamp(i, 0, h - 1) * w + x];
    for (let y = 0; y < h; y++) {
      dst[y * w + x] = sum * norm;
      sum += src[clamp(y + r + 1, 0, h - 1) * w + x] - src[clamp(y - r, 0, h - 1) * w + x];
    }
  }
}

/** Separable box blur; two passes read as Gaussian enough for our purposes. */
export function boxBlur(src, w, h, r, passes = 2) {
  if (r < 1) return Float32Array.from(src);
  let a = Float32Array.from(src);
  let b = new Float32Array(w * h);
  for (let p = 0; p < passes; p++) {
    blurH(a, b, w, h, r);
    blurV(b, a, w, h, r);
  }
  return a;
}

/** Sobel gradients. `mag` is the magnitude; `gx`/`gy` give the edge normal. */
export function sobel(lum, w, h) {
  const gx = new Float32Array(w * h);
  const gy = new Float32Array(w * h);
  const mag = new Float32Array(w * h);
  const at = (x, y) => lum[clamp(y, 0, h - 1) * w + clamp(x, 0, w - 1)];
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const tl = at(x - 1, y - 1), tc = at(x, y - 1), tr = at(x + 1, y - 1);
      const ml = at(x - 1, y), mr = at(x + 1, y);
      const bl = at(x - 1, y + 1), bc = at(x, y + 1), br = at(x + 1, y + 1);
      const dx = tr + 2 * mr + br - (tl + 2 * ml + bl);
      const dy = bl + 2 * bc + br - (tl + 2 * tc + tr);
      const i = y * w + x;
      gx[i] = dx;
      gy[i] = dy;
      mag[i] = Math.hypot(dx, dy);
    }
  }
  return { gx, gy, mag };
}

/** Bilinear sample of an RGBA buffer. Returns [r,g,b,a]; out of bounds is transparent. */
export function sampleRgba(buf, w, h, x, y, out) {
  const x0 = Math.floor(x), y0 = Math.floor(y);
  if (x0 < 0 || y0 < 0 || x0 >= w - 1 || y0 >= h - 1) {
    out[0] = out[1] = out[2] = out[3] = 0;
    return out;
  }
  const fx = x - x0, fy = y - y0;
  const i00 = (y0 * w + x0) * 4, i10 = i00 + 4, i01 = i00 + w * 4, i11 = i01 + 4;
  const w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy), w01 = (1 - fx) * fy, w11 = fx * fy;
  for (let c = 0; c < 4; c++) {
    out[c] = buf[i00 + c] * w00 + buf[i10 + c] * w10 + buf[i01 + c] * w01 + buf[i11 + c] * w11;
  }
  return out;
}
