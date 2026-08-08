import { parseBBox } from "@got/shared";
import { reverseGeocode } from "@/lib/geocode";
import { insertPiece, listPieces, upsertSession, validateMeta } from "@/lib/pieces";
import { clientIp, rateLimit } from "@/lib/ratelimit";
import { MAX_IMAGE_BYTES, MAX_SCENE_BYTES, detectImage, saveImage } from "@/lib/storage";

// fs access + pg, so this must not run on the edge runtime.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const DEFAULT_LIMIT = 500;
const MAX_LIMIT = 2000;

function bad(status: number, error: string, extra?: Record<string, unknown>) {
  return Response.json({ error, ...extra }, { status });
}

/**
 * GET /api/pieces?bbox=west,south,east,north&since=<iso>&limit=<n>
 *
 * bbox and since are both optional: the map passes bbox, the live feed passes
 * since, and the dashboard passes neither.
 */
export async function GET(req: Request) {
  const url = new URL(req.url);

  const rawBbox = url.searchParams.get("bbox");
  let bbox = null;
  if (rawBbox) {
    bbox = parseBBox(rawBbox);
    if (!bbox) return bad(400, "bbox must be 'west,south,east,north'");
  }

  const since = url.searchParams.get("since");
  if (since && Number.isNaN(Date.parse(since))) {
    return bad(400, "since must be an ISO 8601 timestamp");
  }

  const rawLimit = url.searchParams.get("limit");
  let limit = DEFAULT_LIMIT;
  if (rawLimit) {
    const n = Number(rawLimit);
    if (!Number.isInteger(n) || n < 1 || n > MAX_LIMIT) {
      return bad(400, `limit must be an integer in [1, ${MAX_LIMIT}]`);
    }
    limit = n;
  }

  try {
    const result = await listPieces({ bbox, since, limit });
    return Response.json(result, {
      headers: { "Cache-Control": "no-store" },
    });
  } catch (err) {
    console.error("[pieces] list failed", err);
    return bad(500, "could not list pieces");
  }
}

/**
 * POST /api/pieces — multipart/form-data
 *   image: the transparent art (PNG/JPEG/WebP)
 *   scene: OPTIONAL — the camera frame with the art composited on. This is what
 *          the web shows: the actual wall it was painted on, not a stock photo.
 *   meta:  JSON, shape of CreatePieceRequest
 */
export async function POST(req: Request) {
  // 10 per burst, refilling 1 every 6s (~10/min sustained).
  const limit = rateLimit(`pieces:${clientIp(req)}`, 10, 1 / 6);
  if (!limit.ok) {
    return Response.json(
      { error: "slow down" },
      { status: 429, headers: { "Retry-After": String(limit.retryAfter) } },
    );
  }

  const contentType = req.headers.get("content-type") ?? "";
  if (!contentType.includes("multipart/form-data")) {
    return bad(415, "expected multipart/form-data with 'image' and 'meta' parts");
  }

  let form: FormData;
  try {
    form = await req.formData();
  } catch {
    return bad(400, "malformed multipart body");
  }

  const file = form.get("image");
  if (!(file instanceof File)) return bad(400, "missing 'image' part");
  if (file.size === 0) return bad(400, "'image' is empty");
  if (file.size > MAX_IMAGE_BYTES) {
    return bad(413, `image exceeds ${MAX_IMAGE_BYTES} bytes`);
  }

  const rawMeta = form.get("meta");
  if (typeof rawMeta !== "string") return bad(400, "missing 'meta' part");

  let parsed: unknown;
  try {
    parsed = JSON.parse(rawMeta);
  } catch {
    return bad(400, "'meta' is not valid JSON");
  }

  const validated = validateMeta(parsed);
  if (!validated.ok) return bad(400, validated.error);
  const meta = validated.meta;

  const buf = Buffer.from(await file.arrayBuffer());
  const ext = detectImage(buf);
  if (!ext) return bad(415, "image must be PNG, JPEG, or WebP");

  // Optional scene photo. A bad scene must never lose the contribution, so a
  // malformed one is dropped rather than failing the whole request.
  let sceneBuf: Buffer | null = null;
  let sceneExt: string | null = null;
  const scene = form.get("scene");
  if (scene instanceof File && scene.size > 0) {
    if (scene.size > MAX_SCENE_BYTES) {
      return bad(413, `scene exceeds ${MAX_SCENE_BYTES} bytes`);
    }
    const buf = Buffer.from(await scene.arrayBuffer());
    const ext = detectImage(buf);
    if (ext) {
      sceneBuf = buf;
      sceneExt = ext;
    }
  }

  try {
    // Best effort, never blocks the write — a piece without a city label is fine.
    const place = await reverseGeocode(meta.lat, meta.lng);

    await upsertSession(
      meta.sessionId,
      place.city,
      place.country,
      req.headers.get("user-agent")?.slice(0, 255) ?? null,
    );

    const rawImagePath = await saveImage(buf, ext);
    const sceneImagePath =
      sceneBuf && sceneExt ? await saveImage(sceneBuf, sceneExt) : null;
    const piece = await insertPiece(meta, rawImagePath, place, sceneImagePath);

    return Response.json(piece, { status: 201 });
  } catch (err) {
    console.error("[pieces] create failed", err);
    return bad(500, "could not save piece");
  }
}
