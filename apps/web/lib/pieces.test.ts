import { describe, expect, it } from "vitest";
import { validateMeta } from "./pieces";

const valid = {
  lat: 43.6426,
  lng: -79.3871,
  kind: "spray",
  sessionId: "testsession-0001",
};

function reason(raw: unknown): string {
  const r = validateMeta(raw);
  return r.ok ? "" : r.error;
}

describe("validateMeta", () => {
  it("accepts a minimal valid payload", () => {
    const r = validateMeta(valid);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.meta.lat).toBe(43.6426);
      expect(r.meta.kind).toBe("spray");
      // Absent optionals must be undefined, not null — they become SQL NULL downstream.
      expect(r.meta.heading).toBeUndefined();
    }
  });

  it("defaults nothing it wasn't given", () => {
    const r = validateMeta(valid);
    if (!r.ok) throw new Error(r.error);
    expect(r.meta.client).toBeUndefined();
    expect(r.meta.usedGeoAnchor).toBeUndefined();
  });

  it.each([
    ["not an object", null],
    ["missing lat", { ...valid, lat: undefined }],
    ["lat too high", { ...valid, lat: 90.1 }],
    ["lat too low", { ...valid, lat: -90.1 }],
    ["lng too high", { ...valid, lng: 180.1 }],
    ["lat NaN", { ...valid, lat: Number.NaN }],
    ["lat as string", { ...valid, lat: "43.6" }],
    ["unknown kind", { ...valid, kind: "laser" }],
    ["sessionId too short", { ...valid, sessionId: "abc" }],
    ["sessionId too long", { ...valid, sessionId: "x".repeat(65) }],
    ["heading negative", { ...valid, heading: -1 }],
    ["heading 360", { ...valid, heading: 360 }],
    ["unknown surfaceType", { ...valid, surfaceType: "lava" }],
    ["unknown client", { ...valid, client: "android" }],
    ["stickerId too long", { ...valid, stickerId: "x".repeat(65) }],
  ])("rejects %s", (_label, input) => {
    expect(validateMeta(input).ok).toBe(false);
  });

  it("accepts boundary values", () => {
    expect(validateMeta({ ...valid, lat: 90, lng: 180 }).ok).toBe(true);
    expect(validateMeta({ ...valid, lat: -90, lng: -180 }).ok).toBe(true);
    expect(validateMeta({ ...valid, heading: 0 }).ok).toBe(true);
    expect(validateMeta({ ...valid, heading: 359.9 }).ok).toBe(true);
  });

  it("names the offending field so clients can act on it", () => {
    expect(reason({ ...valid, lat: 999 })).toMatch(/lat/);
    expect(reason({ ...valid, kind: "laser" })).toMatch(/kind/);
    expect(reason({ ...valid, surfaceType: "lava" })).toMatch(/surfaceType/);
  });

  describe("colors", () => {
    it("accepts well-formed rgb", () => {
      const r = validateMeta({ ...valid, colors: [{ r: 255, g: 0, b: 128 }] });
      expect(r.ok).toBe(true);
      if (r.ok) expect(r.meta.colors).toEqual([{ r: 255, g: 0, b: 128 }]);
    });

    // Malformed colours are dropped rather than rejected — a piece is still
    // worth saving even if its palette metadata is junk.
    it.each([
      ["out of range", [{ r: 256, g: 0, b: 0 }]],
      ["non-integer", [{ r: 1.5, g: 0, b: 0 }]],
      ["missing channel", [{ r: 1, g: 2 }]],
      ["not an array", "red"],
      ["empty array", []],
      ["too many", Array.from({ length: 17 }, () => ({ r: 1, g: 1, b: 1 }))],
    ])("drops %s", (_label, colors) => {
      const r = validateMeta({ ...valid, colors });
      expect(r.ok).toBe(true);
      if (r.ok) expect(r.meta.colors).toBeUndefined();
    });
  });

  describe("native AR fields", () => {
    it("round-trips a full iOS payload", () => {
      const r = validateMeta({
        ...valid,
        client: "ios",
        surfaceType: "wall",
        distanceM: 2.4,
        devicePitch: -8.5,
        usedGeoAnchor: true,
        hasLidar: true,
      });
      expect(r.ok).toBe(true);
      if (!r.ok) return;
      expect(r.meta.client).toBe("ios");
      expect(r.meta.surfaceType).toBe("wall");
      expect(r.meta.distanceM).toBe(2.4);
      expect(r.meta.devicePitch).toBe(-8.5);
      expect(r.meta.usedGeoAnchor).toBe(true);
      expect(r.meta.hasLidar).toBe(true);
    });

    it("ignores non-boolean flags rather than failing the write", () => {
      const r = validateMeta({ ...valid, usedGeoAnchor: "yes", hasLidar: 1 });
      expect(r.ok).toBe(true);
      if (!r.ok) return;
      expect(r.meta.usedGeoAnchor).toBeUndefined();
      expect(r.meta.hasLidar).toBeUndefined();
    });

    it("accepts every documented surface type", () => {
      for (const s of ["wall", "floor", "ceiling", "table", "seat", "door", "window", "none"]) {
        expect(validateMeta({ ...valid, surfaceType: s }).ok).toBe(true);
      }
    });
  });
});
