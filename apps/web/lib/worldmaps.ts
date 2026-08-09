import type { WorldMapRecord } from "@got/shared";
import { pool } from "@/lib/db";

/**
 * Serialized ARWorldMap scans: rows, queries, and the policy for CHAINING them
 * into versioned lineages. `WorldMapRecord` in `@got/shared` is the model.
 */

/** Flat-earth metres per degree of latitude; good to a metre at venue scale. */
const M_PER_DEG = 111320;

function mPerDegLng(lat: number): number {
  return M_PER_DEG * Math.cos((lat * Math.PI) / 180);
}

// --- chain policy -----------------------------------------------------------

export interface ScanQuality {
  lat: number;
  lng: number;
  featurePoints: number;
  anchorCount: number;
}

/** A chained map may only extend a venue, never wander to a new one. */
export const MAX_CHAIN_DRIFT_M = 250;
/** Enough headroom that ARKit's frame-to-frame jitter can't pass as progress. */
const MIN_GROWTH_RATIO = 1.05;
const MIN_GROWTH_POINTS = 50;

/**
 * Why `child` may not supersede `parent`, or null if it may.
 *
 * A chained map is supposed to be its parent plus everything the new visitor
 * walked past, and superseding is destructive — the parent stops being served.
 * So a map that is smaller, poorer or somewhere else must never take the head
 * position: a broken chain costs relocalization for every later visitor, which
 * is worse than not chaining at all.
 */
export function chainRejection(
  parent: ScanQuality & { supersededAt: Date | null },
  child: ScanQuality,
): string | null {
  if (parent.supersededAt !== null) return "parent map has already been extended by someone else";
  const latM = (parent.lat - child.lat) * M_PER_DEG;
  const lngM = (parent.lng - child.lng) * mPerDegLng(parent.lat);
  if (Math.hypot(latM, lngM) > MAX_CHAIN_DRIFT_M) return "too far from the map it claims to extend";
  // The whole point of a chain is carrying the earlier pieces forward. If ARKit
  // dropped anchors during relocalization, the map is a regression however many
  // feature points it gained.
  if (child.anchorCount < parent.anchorCount) {
    return `would drop ${parent.anchorCount - child.anchorCount} anchor(s)`;
  }
  if (child.featurePoints < parent.featurePoints) return "sparser than the map it extends";
  // A newly pinned piece is content the parent simply does not have, so it
  // earns the head position on its own. Otherwise the scan has to have grown:
  // the ratio stops a huge map ratcheting on jitter, the flat floor stops a
  // tiny one doing the same.
  if (child.anchorCount > parent.anchorCount) return null;
  if (
    child.featurePoints < parent.featurePoints * MIN_GROWTH_RATIO ||
    child.featurePoints < parent.featurePoints + MIN_GROWTH_POINTS
  ) {
    return "not meaningfully richer than the map it extends";
  }
  return null;
}

// --- schema -----------------------------------------------------------------

/** Created lazily so a deploy needs no manual migration. */
let ensured: Promise<unknown> | null = null;
export function ensureWorldMaps() {
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
    // Chaining, plus the placement guide. Every default is the truth for a row
    // that predates them: an existing map is version 1, its own root (root_id
    // NULL, read as id), has no parent, has never been superseded, and carries
    // no guide. So this needs no backfill and no downtime.
    .then(() => pool.query(`
      ALTER TABLE world_maps
        ADD COLUMN IF NOT EXISTS anchor_count integer NOT NULL DEFAULT 0,
        ADD COLUMN IF NOT EXISTS parent_id bigint REFERENCES world_maps(id) ON DELETE SET NULL,
        ADD COLUMN IF NOT EXISTS root_id bigint REFERENCES world_maps(id) ON DELETE SET NULL,
        ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1,
        ADD COLUMN IF NOT EXISTS superseded_at timestamptz,
        ADD COLUMN IF NOT EXISTS snapshot_path text,
        ADD COLUMN IF NOT EXISTS snapshot_transform jsonb`))
    // Deleting a piece cascades to its map, and Postgres then has to find every
    // row referencing it through the two self-references above.
    .then(() => pool.query(
      `CREATE INDEX IF NOT EXISTS world_maps_parent_idx ON world_maps (parent_id, root_id)`))
    // A DB blip during the first call must not poison the memo — a rejected
    // promise cached here would 500 every worldmaps request until restart.
    .catch((err) => {
      ensured = null;
      throw err;
    });
  return ensured;
}

// --- rows -------------------------------------------------------------------

/**
 * root_id stays NULL on a root — an INSERT cannot reference the id it is still
 * generating — so every read resolves it to the row's own id. That is also what
 * makes the migration backfill-free: every pre-chaining row is its own root.
 */
const COLS = `
  w.id, w.piece_id, w.lat, w.lng, w.map_path, w.size_bytes, w.feature_points,
  w.extent_m, w.anchor_count, w.parent_id, COALESCE(w.root_id, w.id) AS root_id,
  w.version, w.snapshot_path, w.snapshot_transform, w.created_at
`;

interface Row {
  id: string | number;
  piece_id: string | number | null;
  lat: number;
  lng: number;
  map_path: string;
  size_bytes: string | number;
  feature_points: number;
  extent_m: number;
  anchor_count: number;
  parent_id: string | number | null;
  root_id: string | number;
  version: number;
  snapshot_path: string | null;
  snapshot_transform: number[] | null;
  created_at: Date;
}

function toWorldMap(r: Row): WorldMapRecord {
  return {
    // pg returns bigint as string to avoid precision loss; ids are small enough to narrow.
    id: Number(r.id),
    pieceId: r.piece_id === null ? null : Number(r.piece_id),
    lat: r.lat,
    lng: r.lng,
    mapPath: r.map_path,
    sizeBytes: Number(r.size_bytes),
    featurePoints: r.feature_points,
    extentM: r.extent_m,
    anchorCount: r.anchor_count,
    parentId: r.parent_id === null ? null : Number(r.parent_id),
    rootId: Number(r.root_id),
    version: r.version,
    snapshotPath: r.snapshot_path,
    snapshotTransform: r.snapshot_transform,
    createdAt: r.created_at.toISOString(),
  };
}

// --- queries ----------------------------------------------------------------

/** Nearby heads, nearest first, so a client can try the closest and fall back. */
export async function listNearby(lat: number, lng: number, radiusM: number): Promise<WorldMapRecord[]> {
  // Small table, small radius: a degree-box prefilter + exact ordering in SQL
  // beats bringing in PostGIS for this.
  const latDelta = radiusM / M_PER_DEG;
  const lngDelta = radiusM / (mPerDegLng(lat) || 1);
  const { rows } = await pool.query<Row>(
    `SELECT ${COLS}
     FROM world_maps w
     -- A map outlives the piece it was saved with. Serving one whose piece is
     -- gone makes a client spend its whole relocalization budget matching a
     -- scan that can only ever restore an anchor for nothing.
     LEFT JOIN pieces p ON p.id = w.piece_id
     WHERE (w.piece_id IS NULL OR (p.id IS NOT NULL AND p.deleted_at IS NULL))
       -- Heads only. An extended version contains everything its parent did, so
       -- offering the parent too would only spend a client's relocalization
       -- budget on a strictly thinner scan.
       AND w.superseded_at IS NULL
       AND w.lat BETWEEN $1 AND $2 AND w.lng BETWEEN $3 AND $4
     -- Nearest first, but a richer scan beats a marginally closer thin one:
     -- relocalization succeeds on feature density, not on proximity.
     ORDER BY (w.feature_points < 150),
              (w.lat - $5) * (w.lat - $5) + (w.lng - $6) * (w.lng - $6) ASC
     LIMIT 5`,
    [lat - latDelta, lat + latDelta, lng - lngDelta, lng + lngDelta, lat, lng],
  );
  return rows.map(toWorldMap);
}

/**
 * Whether `parentId` may be extended, checked BEFORE the caller writes megabytes
 * to disk. Race-free despite being a separate statement: a row's quality columns
 * never change after insert, and `superseded_at` — the one that does — is
 * re-checked atomically by the claiming UPDATE in `insertWorldMap`.
 */
export async function chainRejectionFor(parentId: number, child: ScanQuality): Promise<string | null> {
  const { rows } = await pool.query(
    `SELECT lat, lng, feature_points, anchor_count, superseded_at FROM world_maps WHERE id = $1`,
    [parentId],
  );
  if (rows.length === 0) return "no such map to extend";
  return chainRejection(
    {
      lat: rows[0].lat,
      lng: rows[0].lng,
      featurePoints: rows[0].feature_points,
      anchorCount: rows[0].anchor_count,
      supersededAt: rows[0].superseded_at,
    },
    child,
  );
}

export interface NewWorldMap extends ScanQuality {
  pieceId: number | null;
  /** Set to chain: this map extends `parentId` and supersedes it. */
  parentId: number | null;
  mapPath: string;
  sizeBytes: number;
  extentM: number;
  snapshotPath: string | null;
  snapshotTransform: number[] | null;
}

const INSERT_COLS = `piece_id, lat, lng, map_path, size_bytes, feature_points, extent_m,
                     anchor_count, snapshot_path, snapshot_transform`;

function values(m: NewWorldMap, pieceId: number | null) {
  return [
    pieceId, m.lat, m.lng, m.mapPath, m.sizeBytes, m.featurePoints, m.extentM,
    m.anchorCount, m.snapshotPath, m.snapshotTransform ? JSON.stringify(m.snapshotTransform) : null,
  ];
}

/**
 * Stores a scan — as the next version of `parentId`, or as a new venue.
 *
 * Returns null only when a chain lost its race and there is no piece to save:
 * `landAsRoot` says a scan carrying a fresh piece anchor must land regardless,
 * because that anchor is the only record of where the piece went.
 */
export async function insertWorldMap(m: NewWorldMap, landAsRoot: boolean): Promise<WorldMapRecord | null> {
  if (m.parentId !== null) {
    // One statement, so the supersede and the insert cannot be interleaved: the
    // second of two devices extending the same parent updates zero rows, then
    // inserts zero rows, and leaves the winner's map untouched.
    const { rows } = await pool.query<Row>(
      `WITH claimed AS (
         UPDATE world_maps SET superseded_at = now()
         WHERE id = $11 AND superseded_at IS NULL
         RETURNING id, COALESCE(root_id, id) AS root_id, version,
                   snapshot_path, snapshot_transform
       )
       INSERT INTO world_maps AS w (${INSERT_COLS}, parent_id, root_id, version)
       -- Inherit the guide when this version brings none: a visitor who only
       -- walked around has no view worth standing in, and losing the painter's
       -- would make every later relocalization blind. Image and pose inherit
       -- together — a pose from one photo against another is worse than none.
       SELECT $1, $2, $3, $4, $5, $6, $7, $8,
              COALESCE($9::text, claimed.snapshot_path),
              CASE WHEN $9::text IS NULL THEN claimed.snapshot_transform ELSE $10::jsonb END,
              claimed.id, claimed.root_id, claimed.version + 1
       FROM claimed
       RETURNING ${COLS}`,
      // A chained map carries many pieces' anchors, so tying it to one piece
      // would let a single deletion hide the whole venue's best scan.
      [...values(m, null), m.parentId],
    );
    if (rows[0]) return toWorldMap(rows[0]);
    if (!landAsRoot) return null;
  }

  const { rows } = await pool.query<Row>(
    `INSERT INTO world_maps AS w (${INSERT_COLS})
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
     RETURNING ${COLS}`,
    values(m, m.pieceId),
  );
  return toWorldMap(rows[0]!);
}
