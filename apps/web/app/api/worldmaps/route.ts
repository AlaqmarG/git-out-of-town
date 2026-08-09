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
    )`)
    // Scan quality, so a thin glance at one wall can be told from a real scan
    // without downloading the map. Added separately: the table predates them.
    .then(() => pool.query(`
      ALTER TABLE world_maps
        ADD COLUMN IF NOT EXISTS feature_points integer NOT NULL DEFAULT 0,
        ADD COLUMN IF NOT EXISTS extent_m double precision NOT NULL DEFAULT 0`))
    // A DB blip during the first call must not poison the memo — a rejected
    // promise cached here would 500 every worldmaps request until restart.
    .catch((err) => {
      ensured = null;
      throw err;
    });
  return ensured;
}

/**
 * GET /api/worldmaps?lat=..&lng=..&radiusM=..  — nearest scans first, so a
 * client can try to relocalize against the closest one and fall back down
 * the list.
 */
export async function GET(req: Request) {
  const url = new URL(req.url);
  // Number(null) and Number("") are both 0, so an absent or blank param must
  // be rejected before coercion — "?lng=..." alone would silently query lat=0.
  const coord = (name: string) => {
    const s = url.searchParams.get(name);
    return s ? Number(s) : NaN;
  };
  const lat = coord("lat");
  const lng = coord("lng");
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
      `SELECT w.id, w.piece_id, w.lat, w.lng, w.map_path, w.size_bytes,
              w.feature_points, w.extent_m, w.created_at
       FROM world_maps w
       -- A map outlives the piece it was saved with. Serving one whose piece is
       -- gone makes a client spend its whole relocalization budget matching a
       -- scan that can only ever restore an anchor for nothing.
       LEFT JOIN pieces p ON p.id = w.piece_id
       WHERE (w.piece_id IS NULL OR (p.id IS NOT NULL AND p.deleted_at IS NULL))
         AND w.lat BETWEEN $1 AND $2 AND w.lng BETWEEN $3 AND $4
       -- Nearest first, but a richer scan beats a marginally closer thin one:
       -- relocalization succeeds on feature density, not on proximity.
       ORDER BY (w.feature_points < 150),
                (w.lat - $5) * (w.lat - $5) + (w.lng - $6) * (w.lng - $6) ASC
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
          featurePoints: Number(row.feature_points),
          extentM: Number(row.extent_m),
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

  // Refuse before reading a byte — formData() buffers the whole body, so the
  // per-part check below can only ever be an after-the-fact complaint.
  const declared = Number(req.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > MAX_MAP_BYTES + 1024 * 1024) {
    return bad(413, `body exceeds ${MAX_MAP_BYTES} bytes`);
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

  let meta: {
    pieceId?: unknown;
    lat?: unknown;
    lng?: unknown;
    featurePoints?: unknown;
    extentM?: unknown;
  };
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
    const featurePoints = Number.isFinite(Number(meta.featurePoints))
      ? Math.max(0, Math.trunc(Number(meta.featurePoints)))
      : 0;
    const extentM = Number.isFinite(Number(meta.extentM)) ? Number(meta.extentM) : 0;
    const { rows } = await pool.query(
      `INSERT INTO world_maps (piece_id, lat, lng, map_path, size_bytes, feature_points, extent_m)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id, created_at`,
      [pieceId, lat, lng, rel, map.size, featurePoints, extentM],
    );
    return Response.json(
      {
        id: Number(rows[0].id),
        pieceId,
        lat,
        lng,
        mapPath: rel,
        sizeBytes: map.size,
        featurePoints,
        extentM,
        createdAt: (rows[0].created_at as Date).toISOString(),
      },
      { status: 201 },
    );
  } catch (err) {
    console.error("[worldmaps] save failed", err);
    return bad(500, "could not save world map");
  }
}
