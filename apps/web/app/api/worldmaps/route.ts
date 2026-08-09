import { pool } from "@/lib/db";
import { clientIp, rateLimit } from "@/lib/ratelimit";
import { saveBlob } from "@/lib/storage";

// fs access + pg, so this must not run on the edge runtime.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Compressed ARWorldMaps run 1–10 MB; leave generous headroom. */
const MAX_MAP_BYTES = 32 * 1024 * 1024;

function bad(status: number, error: string) {
  return Response.json({ error }, { status });
}

/**
 * Visual relocalization data. The poster scans their surroundings; the
 * serialized ARWorldMap lets a returning device match camera features against
 * that scan and recover centimetre-level pose — GPS only picks WHICH map to
 * load. Created lazily so a deploy needs no manual migration.
 */
let ensured: Promise<unknown> | null = null;
function ensureTable() {
  ensured ??= pool.query(`
    CREATE TABLE IF NOT EXISTS world_maps (
      id bigserial PRIMARY KEY,
      piece_id bigint REFERENCES pieces(id) ON DELETE CASCADE,
      lat double precision NOT NULL,
      lng double precision NOT NULL,
      map_path text NOT NULL,
      size_bytes bigint NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now()
    )`);
  return ensured;
}

/**
 * GET /api/worldmaps?lat=..&lng=..&radiusM=..  — nearest scans first, so a
 * client can try to relocalize against the closest one and fall back down
 * the list.
 */
export async function GET(req: Request) {
  const url = new URL(req.url);
  const lat = Number(url.searchParams.get("lat"));
  const lng = Number(url.searchParams.get("lng"));
  const radiusM = Number(url.searchParams.get("radiusM") ?? 100);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return bad(400, "lat and lng are required");
  }
  const r = Math.min(Math.max(radiusM, 1), 2000);

  try {
    await ensureTable();
    // Small table, small radius: a degree-box prefilter + exact ordering in SQL
    // beats bringing in PostGIS for this.
    const latDelta = r / 111320;
    const lngDelta = r / (111320 * Math.cos((lat * Math.PI) / 180) || 1);
    const { rows } = await pool.query(
      `SELECT id, piece_id, lat, lng, map_path, size_bytes, created_at
       FROM world_maps
       WHERE lat BETWEEN $1 AND $2 AND lng BETWEEN $3 AND $4
       ORDER BY (lat - $5) * (lat - $5) + (lng - $6) * (lng - $6) ASC
       LIMIT 5`,
      [lat - latDelta, lat + latDelta, lng - lngDelta, lng + lngDelta, lat, lng],
    );
    return Response.json(
      {
        maps: rows.map((row) => ({
          id: Number(row.id),
          pieceId: row.piece_id === null ? null : Number(row.piece_id),
          lat: row.lat,
          lng: row.lng,
          mapPath: row.map_path,
          sizeBytes: Number(row.size_bytes),
          createdAt: (row.created_at as Date).toISOString(),
        })),
      },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (err) {
    console.error("[worldmaps] list failed", err);
    return bad(500, "could not list world maps");
  }
}

/**
 * POST /api/worldmaps — multipart: `map` (compressed ARWorldMap blob) +
 * `meta` (JSON: { pieceId, lat, lng }). Returns 201 with the row.
 */
export async function POST(req: Request) {
  if (!rateLimit(`worldmap:${clientIp(req)}`, 10, 0.2).ok) {
    return bad(429, "slow down");
  }

  let form: FormData;
  try {
    form = await req.formData();
  } catch {
    return bad(400, "expected multipart/form-data");
  }

  const map = form.get("map");
  if (!(map instanceof File)) return bad(400, "missing 'map' file part");
  if (map.size === 0 || map.size > MAX_MAP_BYTES) {
    return bad(413, `map must be 1..${MAX_MAP_BYTES} bytes`);
  }

  let meta: { pieceId?: unknown; lat?: unknown; lng?: unknown };
  try {
    meta = JSON.parse(String(form.get("meta") ?? ""));
  } catch {
    return bad(400, "missing or invalid 'meta' JSON part");
  }
  const lat = Number(meta.lat);
  const lng = Number(meta.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return bad(400, "meta.lat and meta.lng are required");
  }
  const pieceId = Number.isInteger(meta.pieceId) ? Number(meta.pieceId) : null;

  try {
    await ensureTable();
    const rel = await saveBlob(Buffer.from(await map.arrayBuffer()), "armap");
    const { rows } = await pool.query(
      `INSERT INTO world_maps (piece_id, lat, lng, map_path, size_bytes)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, created_at`,
      [pieceId, lat, lng, rel, map.size],
    );
    return Response.json(
      {
        id: Number(rows[0].id),
        pieceId,
        lat,
        lng,
        mapPath: rel,
        sizeBytes: map.size,
        createdAt: (rows[0].created_at as Date).toISOString(),
      },
      { status: 201 },
    );
  } catch (err) {
    console.error("[worldmaps] save failed", err);
    return bad(500, "could not save world map");
  }
}
