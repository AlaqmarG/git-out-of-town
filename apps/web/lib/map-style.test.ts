import { describe, expect, it } from "vitest";
import { buildMapStyle } from "./map-style";
import { palette } from "./theme";

const style = buildMapStyle();

/** Source-layers the OpenFreeMap `planet` tileset actually publishes. */
const AVAILABLE_SOURCE_LAYERS = new Set([
  "aerodrome_label", "aeroway", "boundary", "building", "housenumber",
  "landcover", "landuse", "mountain_peak", "park", "place", "poi",
  "transportation", "transportation_name", "water", "water_name", "waterway",
]);

/**
 * Legacy filters — `["in", "class", "a", "b"]` — were removed in MapLibre v6 and
 * are deprecated in v5. Using one makes the style fail to parse, the `load` event
 * never fires, and NOTHING is thrown. That cost real debugging time once; this
 * test exists so it can't happen twice.
 *
 * The tell: the second element of a comparison filter is a bare string rather
 * than an expression array like ["get", "class"].
 */
const COMPARISON_OPS = new Set(["==", "!=", ">", ">=", "<", "<=", "in", "!in"]);

function usesLegacyFilter(filter: unknown): boolean {
  if (!Array.isArray(filter)) return false;
  const [op, operand] = filter as [unknown, unknown];
  if (typeof op === "string" && COMPARISON_OPS.has(op) && typeof operand === "string") {
    return true;
  }
  return (filter as unknown[]).some(usesLegacyFilter);
}

describe("buildMapStyle", () => {
  it("is a valid v8 style with a vector source", () => {
    expect(style.version).toBe(8);
    expect(style.sources.openmaptiles).toMatchObject({ type: "vector" });
    expect(style.glyphs).toBeTruthy();
  });

  it("declares every source its layers reference", () => {
    const declared = new Set(Object.keys(style.sources));
    for (const layer of style.layers) {
      if ("source" in layer && layer.source) {
        expect(declared, `layer '${layer.id}' references an undeclared source`).toContain(
          layer.source,
        );
      }
    }
  });

  it("only references source-layers the tileset publishes", () => {
    for (const layer of style.layers) {
      const sl = (layer as { "source-layer"?: string })["source-layer"];
      if (sl) {
        expect(AVAILABLE_SOURCE_LAYERS, `layer '${layer.id}'`).toContain(sl);
      }
    }
  });

  it("uses no legacy filter syntax", () => {
    const offenders = style.layers
      .filter((l) => usesLegacyFilter((l as { filter?: unknown }).filter))
      .map((l) => l.id);
    expect(offenders).toEqual([]);
  });

  it("gives every layer a unique id", () => {
    const ids = style.layers.map((l) => l.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("paints the background before anything else", () => {
    expect(style.layers[0]!.type).toBe("background");
  });

  it("draws water beneath roads, so coastlines never cover streets", () => {
    const order = style.layers.map((l) => l.id);
    expect(order.indexOf("water")).toBeLessThan(order.indexOf("road-major"));
  });

  it("draws labels last so nothing occludes them", () => {
    const lastNonSymbol = style.layers.map((l) => l.type).lastIndexOf("symbol");
    expect(lastNonSymbol).toBe(style.layers.length - 1);
  });

  it("takes its colours from the palette, not hardcoded values", () => {
    const bg = style.layers[0] as { paint?: Record<string, unknown> };
    expect(bg.paint?.["background-color"]).toBe(palette.ink);
  });

  it("is rebuilt per call, so a caller cannot mutate shared state", () => {
    const a = buildMapStyle();
    const b = buildMapStyle();
    expect(a).not.toBe(b);
    expect(a.layers).not.toBe(b.layers);
  });

  it("honours an overridden palette", () => {
    const custom = buildMapStyle({ ...palette, ink: "#ff0000" });
    const bg = custom.layers[0] as { paint?: Record<string, unknown> };
    expect(bg.paint?.["background-color"]).toBe("#ff0000");
  });
});
