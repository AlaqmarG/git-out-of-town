import type {
  BBox,
  Client,
  CreatePieceRequest,
  Piece,
  PieceKind,
  Rgb,
  SurfaceType,
} from "@got/shared";
import { pool } from "@/lib/db";

const COLS = `
  id, lat, lng, heading, accuracy_m, raw_image_path, final_image_path, scene_image_path,
  kind, sticker_id, colors, stroke_count, duration_ms, city, country,
  client, surface_type, distance_m, device_pitch, used_geo_anchor, has_lidar,
  altitude_m, placement_transform, created_at
`;

interface Row {
  id: string | number;
  lat: number;
  lng: number;
  heading: number | null;
  accuracy_m: number | null;
  raw_image_path: string;
  final_image_path: string | null;
  scene_image_path: string | null;
  kind: string;
  sticker_id: string | null;
  colors: Rgb[] | null;
  stroke_count: number | null;
  duration_ms: number | null;
  city: string | null;
  country: string | null;
  client: string;
  surface_type: string | null;
  distance_m: number | null;
  device_pitch: number | null;
  used_geo_anchor: boolean;
  has_lidar: boolean | null;
  altitude_m: number | null;
  placement_transform: number[] | null;
  created_at: Date;
}

function toPiece(r: Row): Piece {
  return {
    // pg returns bigint as string to avoid precision loss; ids are small enough to narrow.
    id: Number(r.id),
    lat: r.lat,
    lng: r.lng,
    heading: r.heading,
    accuracyM: r.accuracy_m,
    rawImagePath: r.raw_image_path,
    finalImagePath: r.final_image_path,
    sceneImagePath: r.scene_image_path,
    kind: r.kind as PieceKind,
    stickerId: r.sticker_id,
    colors: r.colors,
    strokeCount: r.stroke_count,
    durationMs: r.duration_ms,
    city: r.city,
    country: r.country,
    client: r.client as Client,
    surfaceType: r.surface_type as SurfaceType | null,
    distanceM: r.distance_m,
    devicePitch: r.device_pitch,
    usedGeoAnchor: r.used_geo_anchor,
    hasLidar: r.has_lidar,
    altitudeM: r.altitude_m,
    placementTransform: r.placement_transform,
    createdAt: r.created_at.toISOString(),
  };
}

export async function upsertSession(
  id: string,
  city: string | null,
  country: string | null,
  device: string | null,
): Promise<void> {
  await pool.query(
    `INSERT INTO sessions (id, city, country, device) VALUES ($1, $2, $3, $4)
     ON CONFLICT (id) DO NOTHING`,
    [id, city, country, device],
  );
}

export async function insertPiece(
  meta: CreatePieceRequest,
  rawImagePath: string,
  place: { city: string | null; country: string | null },
  sceneImagePath: string | null = null,
): Promise<Piece> {
  const { rows } = await pool.query<Row>(
    `INSERT INTO pieces (
       lat, lng, heading, accuracy_m, raw_image_path, kind, sticker_id, colors,
       stroke_count, duration_ms, city, country, session_id,
       client, surface_type, distance_m, device_pitch, used_geo_anchor, has_lidar,
       scene_image_path, altitude_m, placement_transform
     ) VALUES (
       $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22
     ) RETURNING ${COLS}`,
    [
      meta.lat,
      meta.lng,
      meta.heading ?? null,
      meta.accuracyM ?? null,
      rawImagePath,
      meta.kind,
      meta.stickerId ?? null,
      meta.colors ? JSON.stringify(meta.colors) : null,
      meta.strokeCount ?? null,
      meta.durationMs ?? null,
      place.city,
      place.country,
      meta.sessionId,
      meta.client ?? "web",
      meta.surfaceType ?? null,
      meta.distanceM ?? null,
      meta.devicePitch ?? null,
      meta.usedGeoAnchor ?? false,
      meta.hasLidar ?? null,
      sceneImagePath,
      meta.altitudeM ?? null,
      meta.placementTransform ? JSON.stringify(meta.placementTransform) : null,
    ],
  );
  return toPiece(rows[0]!);
}

export interface ListOptions {
  bbox?: BBox | null;
  since?: string | null;
  limit: number;
}

export async function listPieces(opts: ListOptions): Promise<{ pieces: Piece[]; total: number }> {
  const where: string[] = ["deleted_at IS NULL"];
  const params: unknown[] = [];

  if (opts.bbox) {
    const { west, south, east, north } = opts.bbox;
    params.push(south, north, west, east);
    where.push(`lat BETWEEN $${params.length - 3} AND $${params.length - 2}`);
    where.push(`lng BETWEEN $${params.length - 1} AND $${params.length}`);
  }
  if (opts.since) {
    params.push(opts.since);
    where.push(`created_at > $${params.length}`);
  }

  const clause = where.join(" AND ");
  params.push(opts.limit);

  const [list, count] = await Promise.all([
    pool.query<Row>(
      `SELECT ${COLS} FROM pieces WHERE ${clause}
       ORDER BY created_at DESC LIMIT $${params.length}`,
      params,
    ),
    pool.query<{ count: string }>(
      `SELECT count(*)::text AS count FROM pieces WHERE ${clause}`,
      params.slice(0, -1),
    ),
  ]);

  return { pieces: list.rows.map(toPiece), total: Number(count.rows[0]!.count) };
}

// --- validation -------------------------------------------------------------

const KINDS: readonly PieceKind[] = ["spray", "sticker"];
const SURFACES: readonly SurfaceType[] = [
  "wall", "floor", "ceiling", "table", "seat", "door", "window", "none",
];

function num(v: unknown): number | undefined {
  return typeof v === "number" && Number.isFinite(v) ? v : undefined;
}

/**
 * An absent optional field and an explicit `null` mean the same thing to us.
 * Swift's JSONEncoder omits nil, but nothing in the contract requires that, and
 * a client that spells it out must not be rejected.
 */
function given(v: unknown): boolean {
  return v !== undefined && v !== null;
}

/** Optional measurements are pulled into range rather than refused. */
function clamped(v: unknown, lo: number, hi: number): number | undefined {
  const n = num(v);
  return n === undefined ? undefined : Math.min(hi, Math.max(lo, n));
}

/**
 * INTEGER columns. Rounded and clamped rather than validated: a float here used
 * to reach Postgres and come back as an opaque 500.
 */
function int32(v: unknown, hi = 2147483647): number | undefined {
  const n = clamped(v, 0, hi);
  return n === undefined ? undefined : Math.round(n);
}

/** A bearing wraps: 365° is 5°, not a lost contribution. */
function bearing(v: unknown): number | undefined {
  const n = num(v);
  return n === undefined ? undefined : ((n % 360) + 360) % 360;
}

/** One of `allowed`, or nothing. An unrecognised value is dropped, never fatal. */
function oneOf<T extends string>(v: unknown, allowed: readonly T[]): T | undefined {
  return typeof v === "string" && allowed.includes(v as T) ? (v as T) : undefined;
}

/** A malformed palette is dropped, never fatal — losing the piece would be worse. */
function colors(v: unknown): Rgb[] | undefined {
  if (!Array.isArray(v) || v.length === 0 || v.length > 16) return undefined;
  const out: Rgb[] = [];
  for (const c of v) {
    if (typeof c !== "object" || c === null) return undefined;
    const { r, g, b } = c as Record<string, unknown>;
    const ok = [r, g, b].every(
      (n) => typeof n === "number" && Number.isInteger(n) && n >= 0 && n <= 255,
    );
    if (!ok) return undefined;
    out.push({ r: r as number, g: g as number, b: b as number });
  }
  return out;
}

/**
 * Returns the validated request, or a human-readable reason it was rejected.
 *
 * Only the fields a piece cannot exist without are fatal: lat, lng, kind,
 * sessionId, and the shape of placementTransform if one was sent. Everything
 * else is decorative — a heading, a duration, a palette — and is clamped or
 * dropped rather than refused.
 *
 * The reason is that a 400 here destroys the contribution: the painting is
 * already made, the client shows a failure, and retrying sends the same bad
 * field forever. Losing a piece because its altimeter read 99999 is a far worse
 * outcome than storing it without an altitude. This mirrors what the route
 * already does with a malformed scene photo.
 */
export function validateMeta(raw: unknown): { ok: true; meta: CreatePieceRequest } | { ok: false; error: string } {
  if (typeof raw !== "object" || raw === null) return { ok: false, error: "meta must be an object" };
  const m = raw as Record<string, unknown>;

  const lat = num(m.lat);
  const lng = num(m.lng);
  if (lat === undefined || lat < -90 || lat > 90) return { ok: false, error: "lat must be a number in [-90, 90]" };
  if (lng === undefined || lng < -180 || lng > 180) return { ok: false, error: "lng must be a number in [-180, 180]" };

  const kind = m.kind;
  if (typeof kind !== "string" || !KINDS.includes(kind as PieceKind)) {
    return { ok: false, error: `kind must be one of ${KINDS.join(", ")}` };
  }

  const sessionId = m.sessionId;
  if (typeof sessionId !== "string" || sessionId.length < 8 || sessionId.length > 64) {
    return { ok: false, error: "sessionId must be a string of 8-64 chars" };
  }

  // The placement matrix is the one optional field that is still fatal when
  // malformed: a wrong-length one silently mis-anchors the piece in AR, and the
  // client can only be sending it as a bug.
  const placementTransform = given(m.placementTransform) ? m.placementTransform : undefined;
  if (
    placementTransform !== undefined &&
    (!Array.isArray(placementTransform) ||
      placementTransform.length !== 16 ||
      placementTransform.some((n) => typeof n !== "number" || !Number.isFinite(n)))
  ) {
    return { ok: false, error: "placementTransform must be a 16-number column-major 4x4" };
  }

  return {
    ok: true,
    meta: {
      lat,
      lng,
      kind: kind as PieceKind,
      sessionId,
      // Everything below is decorative: clamped, wrapped or dropped, never fatal.
      heading: bearing(m.heading),
      accuracyM: clamped(m.accuracyM, 0, 100_000),
      stickerId:
        typeof m.stickerId === "string" && m.stickerId.length <= 64 ? m.stickerId : undefined,
      colors: colors(m.colors),
      strokeCount: int32(m.strokeCount, 100_000),
      durationMs: int32(m.durationMs),
      client: oneOf<Client>(m.client, ["ios", "web"]),
      surfaceType: oneOf<SurfaceType>(m.surfaceType, SURFACES),
      distanceM: clamped(m.distanceM, 0, 10_000),
      devicePitch: clamped(m.devicePitch, -180, 180),
      usedGeoAnchor: typeof m.usedGeoAnchor === "boolean" ? m.usedGeoAnchor : undefined,
      hasLidar: typeof m.hasLidar === "boolean" ? m.hasLidar : undefined,
      altitudeM: clamped(m.altitudeM, -500, 10_000),
      placementTransform: placementTransform as number[] | undefined,
    },
  };
}
