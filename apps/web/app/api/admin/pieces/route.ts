import { timingSafeEqual } from "node:crypto";
import { pool } from "@/lib/db";
import { clientIp, rateLimit } from "@/lib/ratelimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Moderation. This is public user-generated content, so there must be a way to
 * take something down from a phone, in seconds, without SSH.
 *
 * Deletes are SOFT — `deleted_at` is set and every read already filters on it.
 * A hard delete would destroy the row and its image with no way back, and the
 * likeliest use of this button is a panicked tap during judging.
 */

function authorised(req: Request): boolean {
  const secret = process.env.ADMIN_DELETE_SECRET;
  // Refuse rather than allow-all if the secret was never configured.
  if (!secret) return false;

  const header = req.headers.get("x-admin-secret") ?? "";
  const a = Buffer.from(header);
  const b = Buffer.from(secret);
  // Length check first: timingSafeEqual throws on a length mismatch.
  return a.length === b.length && timingSafeEqual(a, b);
}

/** GET — recent pieces INCLUDING deleted ones, so removals can be undone. */
export async function GET(req: Request) {
  if (!authorised(req)) {
    return Response.json({ error: "unauthorised" }, { status: 401 });
  }
  const { rows } = await pool.query(
    `SELECT id, lat, lng, raw_image_path, final_image_path, scene_image_path,
            city, created_at, deleted_at
     FROM pieces ORDER BY created_at DESC LIMIT 120`,
  );
  return Response.json({
    pieces: rows.map((r) => ({
      id: Number(r.id),
      lat: r.lat,
      lng: r.lng,
      art: r.final_image_path ?? r.raw_image_path,
      scene: r.scene_image_path,
      city: r.city,
      createdAt: (r.created_at as Date).toISOString(),
      deleted: r.deleted_at !== null,
    })),
  });
}

/** DELETE /api/admin/pieces  { id } — or { ids: [] } to clear several at once. */
export async function DELETE(req: Request) {
  // Deliberately tight: this endpoint is a brute-force target.
  if (!rateLimit(`admin:${clientIp(req)}`, 20, 0.5).ok) {
    return Response.json({ error: "slow down" }, { status: 429 });
  }
  if (!authorised(req)) {
    return Response.json({ error: "unauthorised" }, { status: 401 });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "expected JSON" }, { status: 400 });
  }

  const { id, ids } = (body ?? {}) as { id?: unknown; ids?: unknown };
  const list = Array.isArray(ids) ? ids : id !== undefined ? [id] : [];
  const clean = list.filter((n): n is number => Number.isInteger(n));

  if (clean.length === 0) {
    return Response.json({ error: "expected an integer id or ids[]" }, { status: 400 });
  }
  if (clean.length > 200) {
    return Response.json({ error: "at most 200 at a time" }, { status: 400 });
  }

  try {
    const { rowCount } = await pool.query(
      `UPDATE pieces SET deleted_at = now()
       WHERE id = ANY($1::bigint[]) AND deleted_at IS NULL`,
      [clean],
    );
    return Response.json({ deleted: rowCount ?? 0 });
  } catch (err) {
    console.error("[admin] delete failed", err);
    return Response.json({ error: "could not delete" }, { status: 500 });
  }
}

/** POST — restore, because a soft delete is worthless without an undo. */
export async function POST(req: Request) {
  if (!authorised(req)) {
    return Response.json({ error: "unauthorised" }, { status: 401 });
  }
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "expected JSON" }, { status: 400 });
  }
  const { id } = (body ?? {}) as { id?: unknown };
  if (!Number.isInteger(id)) {
    return Response.json({ error: "expected an integer id" }, { status: 400 });
  }
  const { rowCount } = await pool.query(
    `UPDATE pieces SET deleted_at = NULL WHERE id = $1`,
    [id],
  );
  return Response.json({ restored: rowCount ?? 0 });
}
