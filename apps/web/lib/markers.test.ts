import { describe, expect, it } from "vitest";
import type { Piece } from "@got/shared";
import { ZOOM, tierForZoom, toGeoJson } from "./markers";

const piece = (over: Partial<Piece> = {}): Piece => ({
  id: 1, lat: 43.6413, lng: -79.4042, heading: 90, accuracyM: 5,
  rawImagePath: "ab/x.png", finalImagePath: null, weatheredImagePath: null, sceneImagePath: null,
  kind: "spray", stickerId: null, colors: null, strokeCount: 4, durationMs: 9000,
  city: "Toronto", country: "Canada", createdAt: new Date().toISOString(),
  client: "web", surfaceType: null, distanceM: null, devicePitch: null,
  usedGeoAnchor: false, hasLidar: null, altitudeM: null, placementTransform: null, ...over,
});

describe("tierForZoom", () => {
  it("maps each band to its representation", () => {
    expect(tierForZoom(0)).toBe("density");
    expect(tierForZoom(ZOOM.pins - 0.01)).toBe("density");
    expect(tierForZoom(ZOOM.pins)).toBe("pins");
    expect(tierForZoom(ZOOM.art - 0.01)).toBe("pins");
    expect(tierForZoom(ZOOM.art)).toBe("art");
    expect(tierForZoom(22)).toBe("art");
  });

  it("has no gap or overlap between the tiers", () => {
    // Every zoom resolves to exactly one tier — a gap would blank the map.
    for (let z = 0; z <= 22; z += 0.25) {
      expect(["density", "pins", "art"]).toContain(tierForZoom(z));
    }
  });

  it("orders the thresholds sensibly", () => {
    expect(ZOOM.pins).toBeLessThan(ZOOM.art);
  });
});

describe("toGeoJson", () => {
  it("emits GeoJSON with lng,lat order", () => {
    // Reversing these is the classic mapping bug — pieces land in the ocean.
    const fc = toGeoJson([piece({ id: 7, lat: 43.6, lng: -79.4 })]);
    expect(fc.type).toBe("FeatureCollection");
    expect(fc.features[0]!.geometry.coordinates).toEqual([-79.4, 43.6]);
    expect(fc.features[0]!.properties).toEqual({ id: 7 });
  });

  it("handles an empty list", () => {
    expect(toGeoJson([]).features).toEqual([]);
  });

  it("preserves every piece", () => {
    const pieces = Array.from({ length: 40 }, (_, i) => piece({ id: i }));
    expect(toGeoJson(pieces).features).toHaveLength(40);
  });
});
