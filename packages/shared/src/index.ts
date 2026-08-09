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
   * Path under /uploads — the same piece aged: drips, fading, grime. Generated
   * server-side after the piece is already stored, so it is null until it lands
   * and stays null if the model fails.
   *
   * ⚠️ WEB MAP ONLY. The AR path must stay local and never wait on a model, so
   * iOS renders `finalImagePath ?? rawImagePath` and ignores this.
   */
  weatheredImagePath: string | null;
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
   * The piece's placement, as a 4x4 transform (16 floats) expressed in a
   * north-up (ENU) frame with its origin at the piece's lat/lng/altitude. Lets a
   * viewer reconstruct the exact orientation/surface-relative placement.
   *
   * ⚠️ COLUMN-major — `[m00,m01,m02,m03, m10,…]` is column 0 then column 1, which
   * is simd/`simd_float4x4` order, not the row-major order a textbook implies.
   * That is what `flatten()`/`unflatten()` in `apps/ios/ios/ARPaintView.swift`
   * write and read, and they are the only code that has ever produced or consumed
   * this field. Transposing it in a new client would silently mirror every piece.
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

/**
 * A serialized ARWorldMap scan — a venue's visual fingerprint.
 *
 * Maps CHAIN. A device that relocalizes against a map keeps extending that same
 * map as its owner walks, then re-uploads it as the next VERSION of the same
 * lineage (`parentId` → the map it extends). The server supersedes the parent,
 * so a venue converges on one thickening map instead of many thin ones, and
 * `GET` only ever serves heads (`supersededAt === null`).
 *
 * GET /api/worldmaps?lat&lng&radiusM lists nearby heads, nearest first.
 * POST /api/worldmaps is multipart: `map` (compressed blob), an optional
 * `snapshot` (small JPEG placement guide) and `meta`
 * (`CreateWorldMapRequest`). Both files are served under /uploads/.
 */
export interface WorldMapRecord {
  id: number;
  /**
   * The piece this scan was saved with — null on a chained version, which
   * carries many pieces' anchors and must not be hidden when any one of them
   * is deleted.
   */
  pieceId: number | null;
  lat: number;
  lng: number;
  mapPath: string;
  sizeBytes: number;
  /** ARKit rawFeaturePoints count at save time — scan richness. */
  featurePoints: number;
  /** Longest side of the scanned extent, metres. */
  extentM: number;
  /** Piece anchors carried by the map, deduped by piece. Never shrinks along a chain. */
  anchorCount: number;
  /**
   * Path under /uploads — a downscaled JPEG of the scene from where the painter
   * stood. A viewer sees it ghosted over their live camera and physically
   * matches the view, which is Apple's own advice for turning relocalization
   * from a blind feature search into a targeted one. Inherited by a chained
   * version that does not send its own, so extending a venue never costs it
   * the guide.
   *
   * Null on scans saved before this existed; relocalization then runs unguided,
   * exactly as it always did.
   */
  snapshotPath: string | null;
  /**
   * Camera pose the snapshot was shot from — 16 floats, COLUMN-major, the same
   * simd order as `Piece.placementTransform`. Null when there is no snapshot.
   */
  snapshotTransform: number[] | null;
  /** The map this one extends. Null on the first scan of a venue. */
  parentId: number | null;
  /** The lineage's first map — the venue's identity. Equals `id` for a root. */
  rootId: number;
  /** Position in the chain; 1 for a root. */
  version: number;
  createdAt: string;
}

/** POST /api/worldmaps — the JSON `meta` part alongside the `map` blob. */
export interface CreateWorldMapRequest {
  lat: number;
  lng: number;
  pieceId?: number;
  featurePoints?: number;
  extentM?: number;
  anchorCount?: number;
  /** Pose of the `snapshot` part — 16 floats, column-major. Ignored without one. */
  snapshotTransform?: number[];
  /**
   * Set to chain: this map was built by relocalizing against `parentId` and
   * walking further, so it contains everything that map did and more. The
   * server rejects the chain (409) if the parent is already superseded or the
   * new map is not measurably better.
   */
  parentId?: number;
}

/** Payload pushed over SSE when someone paints. */
export interface NewPieceEvent {
  id: number;
  lat: number;
  lng: number;
  city: string | null;
}

export const UPLOADS_BASE = "/uploads";

/**
 * Which of a piece's images a web viewer should show, best first. The aged copy
 * wins on the map because the map is the world as it has weathered; iOS
 * deliberately stops at `finalImagePath` so AR never waits on a model.
 */
export function pieceArt(p: Piece): string {
  return p.weatheredImagePath ?? p.finalImagePath ?? p.rawImagePath;
}

export function uploadUrl(path: string): string {
  return `${UPLOADS_BASE}/${path.replace(/^\/+/, "")}`;
}

/**
 * A 4x4 COLUMN-major transform as it crosses the network: 16 finite numbers.
 * Both `Piece.placementTransform` and `WorldMapRecord.snapshotTransform` are
 * this shape, written by `flatten()` in `apps/ios/ios/ARPaintView.swift`.
 */
export function isTransform16(v: unknown): v is number[] {
  return (
    Array.isArray(v) &&
    v.length === 16 &&
    v.every((n) => typeof n === "number" && Number.isFinite(n))
  );
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
