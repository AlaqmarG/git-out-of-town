import { pool } from "@/lib/db";
import { clientIp, rateLimit } from "@/lib/ratelimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * POST /api/views — records that someone opened a piece.
 *
 * This is the "attention" half of the dashboard: what people *made* versus what
 * people actually *looked at*. Fire-and-forget from the client; a failure here
 * must never affect the viewing experience.
 */
export async function POST(req: Request) {
  // Generous: viewing is cheap and a curious user shouldn't be throttled.
  if (!rateLimit(`views:${clientIp(req)}`, 120, 2).ok) {
    return new Response(null, { status: 429 });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return new Response(null, { status: 400 });
  }

  const { pieceId, sessionId } = (body ?? {}) as { pieceId?: unknown; sessionId?: unknown };
  if (!Number.isInteger(pieceId)) return new Response(null, { status: 400 });

  try {
    await pool.query(
      `INSERT INTO views (piece_id, session_id) VALUES ($1, $2)`,
      [pieceId, typeof sessionId === "string" ? sessionId.slice(0, 64) : null],
    );
  } catch (err) {
    console.error("[views] insert failed", err);
    // Deliberately still 204 — the client does not care and must not retry.
  }
  return new Response(null, { status: 204 });
}
