import { type Piece, uploadUrl } from "@got/shared";
import type { LayerSpecification } from "maplibre-gl";
import { palette } from "@/lib/theme";

/**
 * Below this zoom we draw a density glow instead of individual art. Hundreds of
 * DOM markers at city zoom is both unreadable and slow.
 */
export const MARKER_MIN_ZOOM = 14;

/** Rendered size in CSS px. Sticker-sized: readable, not dominating the map. */
const SIZE = 56;

/**
 * Each piece is rendered as its own artwork — never a pin. Zoomed in, the map
 * becomes a collage of what people actually painted, which is the whole point.
 */
export function createMarkerElement(piece: Piece): HTMLElement {
  const el = document.createElement("button");
  el.type = "button";
  el.className = "got-marker";
  el.setAttribute("aria-label", `Graffiti at ${piece.lat.toFixed(4)}, ${piece.lng.toFixed(4)}`);

  const img = document.createElement("img");
  // Show the finished piece once the transformation lands, else the raw scribble.
  img.src = uploadUrl(piece.finalImagePath ?? piece.rawImagePath);
  img.alt = "";
  img.loading = "lazy";
  img.decoding = "async";
  img.draggable = false;
  img.width = SIZE;
  img.height = SIZE;

  el.appendChild(img);

  // Slight random rotation so a wall of pieces looks hand-placed, not gridded.
  // Seeded off the id so it stays put across re-renders.
  const tilt = ((piece.id * 37) % 21) - 10;
  el.style.setProperty("--tilt", `${tilt}deg`);

  return el;
}

/** GeoJSON for the low-zoom density layer. */
export function toGeoJson(pieces: Piece[]): GeoJSON.FeatureCollection<GeoJSON.Point> {
  return {
    type: "FeatureCollection",
    features: pieces.map((p) => ({
      type: "Feature",
      geometry: { type: "Point", coordinates: [p.lng, p.lat] },
      properties: { id: p.id },
    })),
  };
}

export const DENSITY_LAYERS = {
  source: "pieces-density",
  glow: "pieces-glow",
  count: "pieces-count",
  single: "pieces-single",
} as const;

/** Circle + count layers for the clustered view. Uses the accent as the one hot colour. */
export function densityLayerSpecs(): LayerSpecification[] {
  return [
    {
      id: DENSITY_LAYERS.glow,
      type: "circle" as const,
      source: DENSITY_LAYERS.source,
      filter: ["has", "point_count"],
      paint: {
        "circle-color": palette.accent,
        "circle-opacity": 0.22,
        "circle-blur": 0.6,
        "circle-radius": ["interpolate", ["linear"], ["get", "point_count"], 1, 18, 25, 46, 100, 70],
      },
    },
    {
      id: DENSITY_LAYERS.count,
      type: "symbol" as const,
      source: DENSITY_LAYERS.source,
      filter: ["has", "point_count"],
      layout: {
        "text-field": ["get", "point_count_abbreviated"],
        "text-font": ["Noto Sans Bold"],
        "text-size": 13,
      },
      paint: { "text-color": palette.text },
    },
    {
      // Unclustered singles at low zoom: a dot, so a lone piece is still findable.
      id: DENSITY_LAYERS.single,
      type: "circle" as const,
      source: DENSITY_LAYERS.source,
      filter: ["!", ["has", "point_count"]],
      paint: {
        "circle-color": palette.accent,
        "circle-opacity": 0.75,
        "circle-radius": 5,
        "circle-blur": 0.3,
      },
    },
  ];
}
