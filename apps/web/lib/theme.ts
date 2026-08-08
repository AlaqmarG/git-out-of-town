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

export type Palette = typeof palette;

/** Where the map opens before it knows anything about the user. */
export const DEFAULT_VIEW = {
  /** Downtown Toronto — the hackathon city, and where seeding will concentrate. */
  center: [-79.3832, 43.6532] as [number, number],
  zoom: 12,
  minZoom: 1.5,
  maxZoom: 20,
};
