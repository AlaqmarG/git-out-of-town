import { describe, expect, it } from "vitest";
import type { Piece, SurfaceType } from "@got/shared";
import { projectionCss, projectionFor } from "./surface";

const piece = (id: number, surfaceType: SurfaceType | null = null): Piece => ({
  id, lat: 43.6, lng: -79.4, heading: null, accuracyM: null,
  rawImagePath: "a/b.png", finalImagePath: null, sceneImagePath: "c/d.jpg",
  kind: "spray", stickerId: null, colors: null, strokeCount: null, durationMs: null,
  city: null, country: null, createdAt: new Date().toISOString(),
  client: "ios", surfaceType, distanceM: null, devicePitch: null,
  usedGeoAnchor: false, hasLidar: null, altitudeM: null, placementTransform: null,
});

describe("projectionFor", () => {
  it("is deterministic — a piece never jitters between renders", () => {
    // The angles are seeded off the id precisely so re-rendering is stable.
    expect(projectionFor(piece(42, "wall"))).toEqual(projectionFor(piece(42, "wall")));
  });

  it("gives different pieces different angles", () => {
    const a = projectionFor(piece(1, "wall")).transform;
    const b = projectionFor(piece(2, "wall")).transform;
    expect(a).not.toBe(b);
  });

  it("rakes ground surfaces far harder than walls", () => {
    const rotX = (t: string) => Math.abs(Number(/rotateX\((-?[\d.]+)deg\)/.exec(t)?.[1] ?? 0));
    expect(rotX(projectionFor(piece(3, "floor")).transform))
      .toBeGreaterThan(rotX(projectionFor(piece(3, "wall")).transform));
  });

  it("falls back to the wall treatment for unknown or missing surfaces", () => {
    const wall = projectionFor(piece(9, "wall"));
    for (const s of [null, "none"] as const) {
      expect(projectionFor(piece(9, s)).blend).toBe(wall.blend);
    }
  });

  it.each(["wall", "floor", "ceiling", "table", "seat", "door", "window", "none", null] as const)(
    "produces a usable projection for %s",
    (surface) => {
      const p = projectionFor(piece(5, surface));
      expect(p.transform).toMatch(/perspective\(/);
      // Paint on a rough surface is never fully opaque, or the texture is lost.
      expect(p.opacity).toBeGreaterThan(0.5);
      expect(p.opacity).toBeLessThan(1);
      expect(["multiply", "hard-light"]).toContain(p.blend);
    },
  );
});

describe("projectionCss", () => {
  it("serialises to inline style declarations", () => {
    const css = projectionCss(piece(11, "wall"));
    expect(css).toMatch(/transform:.*perspective/);
    expect(css).toMatch(/mix-blend-mode:/);
    expect(css).toMatch(/opacity:/);
  });
});
