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
  id, lat, lng, heading, accuracy_m, raw_image_path, final_image_path,
  kind, sticker_id, colors, stroke_count, duration_ms, city, country,
  client, surface_type, distance_m, device_pitch, used_geo_anchor, has_lidar,
  created_at
`;

interface Row {
  id: string | number;
  lat: number;
  lng: number;
  heading: number | null;
  accuracy_m: number | null;
  raw_image_path: string;
  final_image_path: string | null;
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
): Promise<Piece> {
  const { rows } = await pool.query<Row>(
    `INSERT INTO pieces (
       lat, lng, heading, accuracy_m, raw_image_path, kind, sticker_id, colors,
       stroke_count, duration_ms, city, country, session_id,
       client, surface_type, distance_m, device_pitch, used_geo_anchor, has_lidar
     ) VALUES (
       $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19
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

/** Returns the validated request, or a human-readable reason it was rejected. */
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

  const heading = num(m.heading);
  if (heading !== undefined && (heading < 0 || heading >= 360)) {
    return { ok: false, error: "heading must be in [0, 360)" };
  }

  const surfaceType = m.surfaceType;
  if (surfaceType !== undefined && (typeof surfaceType !== "string" || !SURFACES.includes(surfaceType as SurfaceType))) {
    return { ok: false, error: `surfaceType must be one of ${SURFACES.join(", ")}` };
  }

  const client = m.client;
  if (client !== undefined && client !== "ios" && client !== "web") {
    return { ok: false, error: "client must be 'ios' or 'web'" };
  }

  const stickerId = m.stickerId;
  if (stickerId !== undefined && (typeof stickerId !== "string" || stickerId.length > 64)) {
    return { ok: false, error: "stickerId must be a string of at most 64 chars" };
  }

  return {
    ok: true,
    meta: {
      lat,
      lng,
      kind: kind as PieceKind,
      sessionId,
      heading,
      accuracyM: num(m.accuracyM),
      stickerId: stickerId as string | undefined,
      colors: colors(m.colors),
      strokeCount: num(m.strokeCount),
      durationMs: num(m.durationMs),
      client: client as Client | undefined,
      surfaceType: surfaceType as SurfaceType | undefined,
      distanceM: num(m.distanceM),
      devicePitch: num(m.devicePitch),
      usedGeoAnchor: typeof m.usedGeoAnchor === "boolean" ? m.usedGeoAnchor : undefined,
      hasLidar: typeof m.hasLidar === "boolean" ? m.hasLidar : undefined,
    },
  };
}
