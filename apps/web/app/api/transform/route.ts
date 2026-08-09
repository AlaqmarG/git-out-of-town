import { after } from "next/server";
import { clientIp, rateLimit } from "@/lib/ratelimit";
import { transformPiece, weatherPiece } from "@/lib/transform";

// fs access + pg, so this must not run on the edge runtime.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * POST /api/transform { id } — restyle a piece's raw art via Replicate, then
 * kick off the web map's weathered variant. Fired-and-forgotten by the iOS
 * client right after a successful post; idempotent, so calling it again for
 * the same piece is harmless.
 */
export async function POST(req: Request) {
  // Each call can cost Replicate credits; keep the bucket tight.
  if (!rateLimit(`transform:${clientIp(req)}`, 6, 0.1).ok) {
    return Response.json({ error: "slow down" }, { status: 429 });
  }

  let id: unknown;
  try {
    ({ id } = await req.json());
  } catch {
    return Response.json({ error: "expected JSON" }, { status: 400 });
  }
  if (!Number.isInteger(id)) {
    return Response.json({ error: "expected an integer id" }, { status: 400 });
  }

  try {
    const finalImagePath = await transformPiece(id as number);
    // Runs once the response is out: the aged copy only decorates the web map,
    // so nobody waits on it and a failure is a log line.
    after(() =>
      weatherPiece(id as number).catch((err) => console.error("[weather] failed", err)),
    );
    return Response.json({ finalImagePath });
  } catch (err) {
    console.error("[transform] failed", err);
    return Response.json({ error: "transform failed" }, { status: 502 });
  }
}
