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
    ["placementTransform of the wrong length", { ...valid, placementTransform: [1, 2, 3] }],
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
    expect(reason({ ...valid, sessionId: "abc" })).toMatch(/sessionId/);
  });

  /**
   * The painting already exists by the time this runs. Refusing it over a field
   * nothing depends on loses it for good — the client cannot fix an altimeter
   * and retry. So decorative fields degrade instead of failing.
   */
  describe("decorative fields degrade instead of failing", () => {
    it.each([
      ["altitudeM far too high", "altitudeM", 99999, 10000],
      ["altitudeM far too low", "altitudeM", -9999, -500],
      ["a negative accuracyM", "accuracyM", -5, 0],
      ["an absurd distanceM", "distanceM", 1e9, 10000],
      ["devicePitch past vertical", "devicePitch", -400, -180],
    ])("clamps %s", (_label, field, value, expected) => {
      const r = validateMeta({ ...valid, [field]: value });
      expect(r.ok).toBe(true);
      if (!r.ok) return;
      expect(r.meta[field as keyof typeof r.meta]).toBe(expected);
    });

    it.each([
      ["365 degrees", 365, 5],
      ["exactly 360", 360, 0],
      ["a negative bearing", -90, 270],
    ])("wraps a heading of %s", (_label, value, expected) => {
      const r = validateMeta({ ...valid, heading: value });
      expect(r.ok).toBe(true);
      if (r.ok) expect(r.meta.heading).toBe(expected);
    });

    it.each([
      ["an unknown surfaceType", "surfaceType", "lava"],
      ["an unknown client", "client", "android"],
      ["an oversized stickerId", "stickerId", "x".repeat(65)],
      ["a non-numeric heading", "heading", "north"],
    ])("drops %s", (_label, field, value) => {
      const r = validateMeta({ ...valid, [field]: value });
      expect(r.ok).toBe(true);
      if (r.ok) expect(r.meta[field as keyof typeof r.meta]).toBeUndefined();
    });
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

    it("takes the placement transform as 16 finite numbers", () => {
      const m = Array.from({ length: 16 }, (_, i) => i / 3);
      const r = validateMeta({ ...valid, placementTransform: m });
      expect(r.ok).toBe(true);
      expect(validateMeta({ ...valid, placementTransform: m.slice(1) }).ok).toBe(false);
      expect(reason({ ...valid, placementTransform: m.slice(1) })).toContain("column-major");
    });
  });

  // Swift omits nil, but nothing in the contract says a client must. Spelling an
  // optional out as null used to be a 400.
  describe("explicit null", () => {
    it.each([
      "heading", "accuracyM", "stickerId", "surfaceType", "client", "hasLidar",
      "usedGeoAnchor", "distanceM", "devicePitch", "altitudeM", "colors",
      "strokeCount", "durationMs", "placementTransform",
    ])("treats a null %s as absent", (field) => {
      const r = validateMeta({ ...valid, [field]: null });
      expect(r.ok).toBe(true);
      if (!r.ok) return;
      expect(r.meta[field as keyof typeof r.meta]).toBeUndefined();
    });
  });

  // These land in INTEGER columns. Reaching Postgres as a float or an overflow
  // came back as an opaque 500 the client could do nothing with.
  describe("integer columns", () => {
    it.each([
      ["a float durationMs", "durationMs", 12345.67, 12346],
      ["a float strokeCount", "strokeCount", 3.5, 4],
      ["a durationMs past int4", "durationMs", 9e12, 2147483647],
      ["a negative strokeCount", "strokeCount", -3, 0],
    ])("rounds and clamps %s", (_label, field, value, expected) => {
      const r = validateMeta({ ...valid, [field]: value });
      expect(r.ok).toBe(true);
      if (!r.ok) return;
      expect(r.meta[field as keyof typeof r.meta]).toBe(expected);
    });

    it("keeps whole numbers exactly", () => {
      const r = validateMeta({ ...valid, strokeCount: 12, durationMs: 45_000 });
      expect(r.ok).toBe(true);
      if (!r.ok) return;
      expect(r.meta.strokeCount).toBe(12);
      expect(r.meta.durationMs).toBe(45_000);
    });

    it("drops a NaN rather than storing one", () => {
      const r = validateMeta({ ...valid, strokeCount: Number.NaN });
      expect(r.ok).toBe(true);
      if (r.ok) expect(r.meta.strokeCount).toBeUndefined();
    });
  });
});
