/**
 * Visual tokens — the single source of truth for colour.
 *
 * Design intent
 * -------------
 * The artwork is loud and multicoloured, so the interface is almost monochrome:
 * a cool, blue-shifted neutral ramp (concrete at night, not generic dashboard
 * grey) with exactly one saturated accent. Anything competing with the graffiti
 * for attention is wrong.
 *
 * Contrast is tuned to survive a projector. An earlier pass was several steps
 * darker and vanished on anything but a good display — the pitch is judged on a
 * projected screen, so legibility beats moodiness.
 *
 * Charts draw from SPRAY, the same pigments the artwork is painted with, so the
 * data visualisation and the art read as one system.
 */

export const palette = {
  /** Page and map background. Blue-black rather than neutral black. */
  ink: "#0a0b0f",
  /** Land mass. */
  surface: "#15171e",
  /** Panels and cards that sit above the map. */
  raised: "#1c1f28",
  /** Hairlines and borders. */
  line: "#272b36",

  /** Water — darker than land, so coastlines read without a hard edge. */
  water: "#05060d",
  park: "#121a17",
  building: "#232733",
  roadMinor: "#31363f",
  roadMajor: "#4e5462",
  boundary: "#3a3f4c",

  label: "#848b9c",
  labelBright: "#b6bccb",
  /** Halo behind labels so they stay legible over any fill. */
  labelHalo: "#07080c",

  /** Spray-can red. The only saturated colour in the interface. */
  accent: "#ff5230",
  accentDim: "#7c2716",
  /** For hovers and glows built from the accent. */
  accentSoft: "rgba(255, 82, 48, 0.24)",

  text: "#e9ecf4",
  textMuted: "#8a90a0",
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
