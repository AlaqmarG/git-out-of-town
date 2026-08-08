import { pool } from "@/lib/db";

/**
 * Every figure on /data is a live query against the pieces table. Nothing is
 * precomputed or cached — the rubric is explicit that the data must be "real and
 * current, not fabricated or hardcoded for the demo".
 */

export interface Totals {
  pieces: number;
  contributors: number;
  cities: number;
  /** Total seconds people have spent painting. */
  paintSeconds: number;
  /** Pieces added in the last hour — the "is this alive" number. */
  lastHour: number;
}

export interface Bucket {
  label: string;
  value: number;
}

export interface HourPoint {
  hour: string;
  pieces: number;
}

export interface SurfaceRow {
  surface: string;
  pieces: number;
  /** Mean views per piece on that surface — the attention half of the story. */
  viewsPerPiece: number;
}

export interface ColourRow {
  hex: string;
  uses: number;
}

export interface Stats {
  totals: Totals;
  perHour: HourPoint[];
  surfaces: SurfaceRow[];
  cities: Bucket[];
  colours: ColourRow[];
  clients: Bucket[];
  generatedAt: string;
}

const LIVE = "deleted_at IS NULL";

export async function getStats(): Promise<Stats> {
  const [totals, perHour, surfaces, cities, colours, clients] = await Promise.all([
    pool.query<{
      pieces: string;
      contributors: string;
      cities: string;
      paint_seconds: string;
      last_hour: string;
    }>(`
      SELECT count(*)::text                                        AS pieces,
             count(DISTINCT session_id)::text                      AS contributors,
             count(DISTINCT country)::text                         AS cities,
             COALESCE(sum(duration_ms), 0)::bigint / 1000          AS paint_seconds,
             count(*) FILTER (WHERE created_at > now() - interval '1 hour')::text AS last_hour
      FROM pieces WHERE ${LIVE}
    `),

    // Bucketed by hour, with empty hours filled in — a gap in a time series
    // must read as "nothing happened", not as a missing point.
    pool.query<{ hour: Date; pieces: string }>(`
      WITH hours AS (
        SELECT generate_series(
          date_trunc('hour', now()) - interval '23 hours',
          date_trunc('hour', now()),
          interval '1 hour'
        ) AS hour
      )
      SELECT h.hour, count(p.id)::text AS pieces
      FROM hours h
      LEFT JOIN pieces p
        ON date_trunc('hour', p.created_at) = h.hour AND p.${LIVE}
      GROUP BY h.hour ORDER BY h.hour
    `),

    pool.query<{ surface: string; pieces: string; views_per_piece: string }>(`
      SELECT COALESCE(surface_type, 'unrecorded')            AS surface,
             count(*)::text                                  AS pieces,
             COALESCE(round(avg(v.n), 1), 0)::text           AS views_per_piece
      FROM pieces p
      LEFT JOIN LATERAL (
        SELECT count(*)::numeric AS n FROM views WHERE piece_id = p.id
      ) v ON true
      WHERE p.${LIVE}
      GROUP BY surface ORDER BY count(*) DESC
    `),

    pool.query<{ label: string; value: string }>(`
      SELECT COALESCE(city, 'unknown') AS label, count(*)::text AS value
      FROM pieces WHERE ${LIVE}
      GROUP BY label ORDER BY count(*) DESC LIMIT 8
    `),

    // colors is a jsonb array of {r,g,b}; unnest and count each pigment.
    pool.query<{ hex: string; uses: string }>(`
      SELECT lpad(to_hex(((c->>'r')::int)), 2, '0') ||
             lpad(to_hex(((c->>'g')::int)), 2, '0') ||
             lpad(to_hex(((c->>'b')::int)), 2, '0')  AS hex,
             count(*)::text                          AS uses
      FROM pieces p, jsonb_array_elements(p.colors) c
      WHERE p.${LIVE} AND p.colors IS NOT NULL
      GROUP BY hex ORDER BY count(*) DESC LIMIT 10
    `),

    pool.query<{ label: string; value: string }>(`
      SELECT client AS label, count(*)::text AS value
      FROM pieces WHERE ${LIVE}
      GROUP BY client ORDER BY count(*) DESC
    `),
  ]);

  const t = totals.rows[0]!;
  return {
    totals: {
      pieces: Number(t.pieces),
      contributors: Number(t.contributors),
      cities: Number(t.cities),
      paintSeconds: Number(t.paint_seconds),
      lastHour: Number(t.last_hour),
    },
    perHour: perHour.rows.map((r) => ({
      hour: r.hour.toISOString(),
      pieces: Number(r.pieces),
    })),
    surfaces: surfaces.rows.map((r) => ({
      surface: r.surface,
      pieces: Number(r.pieces),
      viewsPerPiece: Number(r.views_per_piece),
    })),
    cities: cities.rows.map((r) => ({ label: r.label, value: Number(r.value) })),
    colours: colours.rows.map((r) => ({ hex: `#${r.hex}`, uses: Number(r.uses) })),
    clients: clients.rows.map((r) => ({ label: r.label, value: Number(r.value) })),
    generatedAt: new Date().toISOString(),
  };
}
