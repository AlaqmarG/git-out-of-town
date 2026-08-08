/**
 * API contract shared by every client (web today, iOS next).
 * Schema of record is `db/init.sql` — keep these in sync with it.
 */

export type PieceKind = "spray" | "sticker";

export type Client = "ios" | "web";

/**
 * ARKit `ARMeshClassification`. Only the iOS client with LiDAR can produce this —
 * it is the basis of the "what surfaces does the world get painted on?" insight.
 */
export type SurfaceType =
  | "wall"
  | "floor"
  | "ceiling"
  | "table"
  | "seat"
  | "door"
  | "window"
  | "none";

export interface Rgb {
  r: number;
  g: number;
  b: number;
}

/** A single piece of graffiti pinned to a place and a direction. */
export interface Piece {
  id: number;
  lat: number;
  lng: number;
  /** Compass bearing the phone faced, degrees clockwise from true north. */
  heading: number | null;
  accuracyM: number | null;
  /** Path under /uploads — the untransformed scribble. Always present. */
  rawImagePath: string;
  /** Path under /uploads — the Reve-transformed piece. Null until it lands. */
  finalImagePath: string | null;
  /**
   * Path under /uploads — the camera frame at the moment of painting.
   *
   * ⚠️ CONTRACT: this image ALREADY CONTAINS THE ARTWORK. It is the AR view as
   * the painter saw it, so the art is burned in. Clients must render it alone —
   * overlaying `rawImagePath` on top draws the piece twice.
   *
   * Null when a contribution was made without a camera (the browser path), in
   * which case clients show the bare artwork instead.
   */
  sceneImagePath: string | null;
  kind: PieceKind;
  stickerId: string | null;
  colors: Rgb[] | null;
  strokeCount: number | null;
  durationMs: number | null;
  city: string | null;
  country: string | null;
  createdAt: string;

  // --- native AR only; null from web clients ---
  client: Client;
  surfaceType: SurfaceType | null;
  /** Camera-to-anchor distance in metres at placement time. */
  distanceM: number | null;
  /** Device pitch in degrees; negative means aimed downward. */
  devicePitch: number | null;
  /** True when placed with ARGeoAnchor rather than the GPS-bearing fallback. */
  usedGeoAnchor: boolean;
  hasLidar: boolean | null;
  /** Metres above mean sea level — the ARGeoAnchor altitude. Null when unknown. */
  altitudeM: number | null;
  /**
   * The piece's placement, as a 4x4 transform (row-major, 16 floats) expressed in
   * a north-up (ENU) frame with its origin at the piece's lat/lng/altitude. Lets a
   * viewer reconstruct the exact orientation/surface-relative placement.
   */
  placementTransform: number[] | null;
}

/** POST /api/pieces — multipart; `image` is the PNG, this is the JSON `meta` part. */
export interface CreatePieceRequest {
  lat: number;
  lng: number;
  heading?: number;
  accuracyM?: number;
  kind: PieceKind;
  stickerId?: string;
  colors?: Rgb[];
  strokeCount?: number;
  durationMs?: number;
  sessionId: string;

  // --- native AR only ---
  client?: Client;
  surfaceType?: SurfaceType;
  distanceM?: number;
  devicePitch?: number;
  usedGeoAnchor?: boolean;
  hasLidar?: boolean;
  altitudeM?: number;
  placementTransform?: number[];
}

/** GET /api/pieces?bbox=west,south,east,north */
export interface BBox {
  west: number;
  south: number;
  east: number;
  north: number;
}

export interface PiecesResponse {
  pieces: Piece[];
  total: number;
}

/** Payload pushed over SSE when someone paints. */
export interface NewPieceEvent {
  id: number;
  lat: number;
  lng: number;
  city: string | null;
}

export const UPLOADS_BASE = "/uploads";

export function uploadUrl(path: string): string {
  return `${UPLOADS_BASE}/${path.replace(/^\/+/, "")}`;
}

export function parseBBox(raw: string): BBox | null {
  const parts = raw.split(",");
  if (parts.length !== 4) return null;

  // Number("") is 0, not NaN — so blank parts must be rejected explicitly or
  // "1,2,3," would parse as a valid box with north = 0.
  const p = parts.map((s) => (s.trim() === "" ? Number.NaN : Number(s)));
  if (p.some((n) => !Number.isFinite(n))) return null;

  const [west, south, east, north] = p as [number, number, number, number];
  if (west < -180 || west > 180 || east < -180 || east > 180) return null;
  if (south < -90 || south > 90 || north < -90 || north > 90) return null;
  if (south > north) return null;

  return { west, south, east, north };
}
