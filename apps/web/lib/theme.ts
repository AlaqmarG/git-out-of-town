/**
 * Visual tokens — the single source of truth for colour.
 *
 * Contrast note: these are tuned to survive a projector. The first pass was
 * several steps darker and vanished entirely when not viewed on a good display —
 * the pitch is judged on a projected screen, so legibility wins over moodiness.
 *
 * The Reve-made brand art (#5/#6) does not exist yet. When it lands, replace the
 * values here and the whole app follows: map, UI, markers. Do not hardcode
 * colours anywhere else.
 */

export const palette = {
  /** Page and map background. Near-black so the art is the only bright thing. */
  ink: "#0b0b0d",
  /** Land mass. */
  surface: "#17171c",
  /** Water — darker than land, so coastlines read without a hard line. */
  water: "#05060e",
  park: "#131c15",
  building: "#22222a",
  roadMinor: "#30303a",
  roadMajor: "#4d4d5c",
  boundary: "#3a3a48",

  label: "#83838f",
  labelBright: "#b4b4c2",
  /** Halo behind labels so they stay legible over any fill. */
  labelHalo: "#08080a",

  /** Spray-can orange. The one saturated colour in the system. */
  accent: "#ff4d2e",
  accentDim: "#7a2417",

  text: "#e8e8ec",
  textMuted: "#8b8b98",
} as const;

/**
 * The shape, not the literal values — `palette` is `as const`, so deriving the
 * type directly would pin each key to its exact hex string and make overrides
 * (tests, a future light theme) impossible.
 */
export type Palette = Record<keyof typeof palette, string>;

/**
 * The spray-can palette. These are the pigments the artwork is generated with,
 * and the categorical scale every chart uses — so a colour means the same thing
 * whether it appears on a wall or in the dashboard.
 *
 * Ordered so the first four stay distinguishable under the common forms of
 * colour blindness: red/green are never adjacent.
 */
export const SPRAY = [
  "#ff5230", // red
  "#35d0e8", // cyan
  "#ffb021", // amber
  "#a277ff", // violet
  "#9be855", // lime
  "#ff5fa8", // pink
] as const;

/**
 * The chart scale. Same hues as SPRAY, stepped down into the OKLCH lightness
 * band that survives a dark surface (L 0.48–0.67). Verified with the palette
 * validator: lightness band, chroma floor, CVD separation, normal-vision floor
 * and contrast all pass. Do not hand-edit these without re-running it.
 */
export const CHART = [
  "#eb3d19", // red
  "#00a6bd", // cyan
  "#c57900", // amber
  "#8659de", // violet
  "#63ac00", // lime
  "#d63786", // pink
] as const;

/** Sequential ramp for density and heat, cold to hot. */
export const HEAT = [
  "#1c1f28",
  "#4a2a2c",
  "#8a3524",
  "#c8451f",
  "#ff5230",
  "#ffb021",
] as const;

/** Where the map opens before it knows anything about the user. */
export const DEFAULT_VIEW = {
  /**
   * Stackt Market, Bathurst & Front — the hackathon venue. Opening here means
   * judges land on the densest part of the wall instead of an empty city.
   */
  center: [-79.4042, 43.6413] as [number, number],
  zoom: 16,
  minZoom: 1.5,
  maxZoom: 20,
};
