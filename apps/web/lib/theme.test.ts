import { describe, expect, it } from "vitest";
import { CHART, HEAT, SPRAY, palette } from "./theme";

/**
 * These encode the rules the palette validator enforces, so CHART cannot be
 * hand-edited back out of the band it was computed into. The first attempt at
 * this palette FAILED the lightness check (all six were L 0.67–0.85 against a
 * 0.48–0.67 dark band); this test is what stops that regressing silently.
 */

const srgbToLinear = (c: number) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);

function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace("#", "");
  return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16) / 255) as [number, number, number];
}

/** OKLab lightness (Ottosson). */
function oklabL([r, g, b]: [number, number, number]): number {
  const R = srgbToLinear(r);
  const G = srgbToLinear(g);
  const B = srgbToLinear(b);
  const l = Math.cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B);
  const m = Math.cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B);
  const s = Math.cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B);
  return 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
}

const relLuminance = ([r, g, b]: [number, number, number]) =>
  0.2126 * srgbToLinear(r) + 0.7152 * srgbToLinear(g) + 0.0722 * srgbToLinear(b);

function contrast(a: string, b: string): number {
  const la = relLuminance(hexToRgb(a));
  const lb = relLuminance(hexToRgb(b));
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

const HEX = /^#[0-9a-f]{6}$/;

describe("CHART scale", () => {
  it("is all well-formed hex", () => {
    for (const c of CHART) expect(c).toMatch(HEX);
  });

  it("sits inside the OKLCH dark-mode lightness band (0.48–0.67)", () => {
    for (const c of CHART) {
      const L = oklabL(hexToRgb(c));
      expect(L, `${c} has L=${L.toFixed(3)}`).toBeGreaterThanOrEqual(0.48);
      expect(L, `${c} has L=${L.toFixed(3)}`).toBeLessThanOrEqual(0.67);
    }
  });

  it("clears 3:1 contrast against every surface it is drawn on", () => {
    for (const c of CHART) {
      for (const surface of [palette.ink, palette.raised]) {
        expect(contrast(c, surface), `${c} on ${surface}`).toBeGreaterThanOrEqual(3);
      }
    }
  });

  it("has no duplicate hues", () => {
    expect(new Set(CHART).size).toBe(CHART.length);
  });

  it("keeps red and green non-adjacent for colour-blind readers", () => {
    // Slot order is deliberate: red at 0, lime at 4, so the first pairs a reader
    // has to separate are never the hard ones.
    expect(CHART.indexOf("#63ac00") - CHART.indexOf("#eb3d19")).toBeGreaterThan(1);
  });
});

describe("HEAT ramp", () => {
  it("increases monotonically in lightness — a sequential ramp must be ordered", () => {
    const ls = HEAT.map((c) => oklabL(hexToRgb(c)));
    for (let i = 1; i < ls.length; i++) {
      expect(ls[i], `step ${i} (${HEAT[i]}) is not lighter than ${HEAT[i - 1]}`).toBeGreaterThan(
        ls[i - 1]!,
      );
    }
  });
});

describe("palette", () => {
  it("keeps body text well clear of WCAG AA on the page background", () => {
    expect(contrast(palette.text, palette.ink)).toBeGreaterThanOrEqual(4.5);
  });

  it("keeps muted text legible on both surfaces", () => {
    expect(contrast(palette.textMuted, palette.ink)).toBeGreaterThanOrEqual(3);
    expect(contrast(palette.textMuted, palette.raised)).toBeGreaterThanOrEqual(3);
  });

  it("has exactly as many spray pigments as chart slots", () => {
    // The art and the charts are meant to be the same system.
    expect(SPRAY.length).toBe(CHART.length);
  });
});
