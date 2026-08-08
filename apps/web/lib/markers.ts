import { type Piece, uploadUrl } from "@got/shared";
import type { LayerSpecification } from "maplibre-gl";
import { palette } from "@/lib/theme";

/**
 * Three zoom tiers, not two.
 *
 * A single threshold meant art either dominated the screen or vanished. Now the
 * map stays calm at street level (quiet pins) and only commits screen space to
 * the artwork once you are close enough for it to be the subject.
 */
export const ZOOM = {
  /** Below this: clustered density glow only. */
  pins: 13,
  /** At or above this: the framed artwork itself. */
  art: 16,
} as const;

export type Tier = "density" | "pins" | "art";

export function tierForZoom(zoom: number): Tier {
  if (zoom >= ZOOM.art) return "art";
  if (zoom >= ZOOM.pins) return "pins";
  return "density";
}

/** Rendered size of a framed piece, in CSS px. Bigger than a pin because at
 *  this zoom the artwork IS the content, not an indicator of it. */
const CARD_W = 132;
const CARD_H = 99; // 4:3, matching the captured frame

/** Dominant colour of a piece, used to tint its pin. Falls back to the accent. */
function dominant(piece: Piece): string {
  const c = piece.colors?.[0];
  return c ? `rgb(${c.r},${c.g},${c.b})` : palette.accent;
}

/**
 * Mid-zoom representation: a small uniform dot tinted with the piece's own
 * dominant colour. Reads as "something is here" without competing for attention.
 */
export function createPinElement(piece: Piece, index = 0): HTMLElement {
  const el = document.createElement("button");
  el.type = "button";
  el.className = "got-pin";
  // Staggered so a viewport of pieces arrives as a wave, not a pop.
  el.style.setProperty("--delay", `${Math.min(index * 14, 420)}ms`);
  el.setAttribute("aria-label", `Graffiti at ${piece.lat.toFixed(4)}, ${piece.lng.toFixed(4)}`);
  el.style.setProperty("--pin", dominant(piece));
  return el;
}

/**
 * Close-zoom representation: the artwork in a frame.
 *
 * The frame matters. Transparent PNGs sitting straight on the basemap read as
 * spilled paint; a backing card and border make each piece read as an object
 * someone placed.
 */
export function createArtElement(piece: Piece, index = 0): HTMLElement {
  const el = document.createElement("button");
  el.type = "button";
  el.className = "got-marker";
  el.style.setProperty("--delay", `${Math.min(index * 22, 520)}ms`);
  el.style.width = `${CARD_W}px`;
  el.style.height = `${CARD_H}px`;
  el.setAttribute("aria-label", `Graffiti at ${piece.lat.toFixed(4)}, ${piece.lng.toFixed(4)}`);

  // Seeded off the id so a piece keeps its tilt across re-renders, and a wall of
  // them looks hand-placed rather than gridded.
  el.style.setProperty("--tilt", `${((piece.id * 37) % 15) - 7}deg`);

  if (piece.sceneImagePath) {
    // The photo of the actual place is the marker, and the paint is already
    // burned into it in perspective by scripts/lib/composite.mjs. Nothing is
    // overlaid on top: that used to be a CSS 3D transform faking the angle,
    // and it read as a sticker on a photo rather than paint on a wall.
    const scene = document.createElement("img");
    scene.className = "got-marker-scene";
    scene.src = uploadUrl(piece.sceneImagePath);
    scene.alt = "";
    scene.loading = "lazy";
    scene.decoding = "async";
    scene.draggable = false;
    el.appendChild(scene);
    el.classList.add("has-scene");
  } else {
    // No photo of the place, so show the artwork plainly instead.
    const art = document.createElement("img");
    art.className = "got-marker-art bare";
    art.src = uploadUrl(piece.finalImagePath ?? piece.rawImagePath);
    art.alt = "";
    art.loading = "lazy";
    art.decoding = "async";
    art.draggable = false;
    el.appendChild(art);
  }

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

/** Circle + count layers for the clustered view. The accent is the one hot colour. */
export function densityLayerSpecs(): LayerSpecification[] {
  return [
    {
      id: DENSITY_LAYERS.glow,
      type: "circle",
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
      type: "symbol",
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
      type: "circle",
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
