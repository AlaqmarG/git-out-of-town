import { type CreateWorldMapRequest, isTransform16 } from "@got/shared";
import { int32 } from "@/lib/pieces";
import { clientIp, rateLimit } from "@/lib/ratelimit";
import {
  deleteImage,
  MAX_MAP_BYTES,
  MAX_SNAPSHOT_BYTES,
  MAX_WORLDMAP_BODY_BYTES,
  readImagePart,
  saveBlob,
  saveImage,
} from "@/lib/storage";
import { chainRejectionFor, ensureWorldMaps, insertWorldMap, listNearby } from "@/lib/worldmaps";

// fs access + pg, so this must not run on the edge runtime.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function bad(status: number, error: string) {
  return Response.json({ error }, { status });
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

  try {
    await ensureWorldMaps();
    const maps = await listNearby(lat, lng, Math.min(Math.max(radiusM, 1), 2000));
    return Response.json({ maps }, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    console.error("[worldmaps] list failed", err);
    return bad(500, "could not list world maps");
  }
}

/**
 * POST /api/worldmaps — multipart: `map` (compressed ARWorldMap blob), an
 * OPTIONAL `snapshot` (small JPEG placement guide) and `meta`
 * (`CreateWorldMapRequest`). Returns 201 with the row.
 *
 * With `meta.parentId` this is a chained version of that map. It supersedes its
 * parent atomically, so of two devices extending the same map only the first
 * wins. A scan carrying a fresh `pieceId` lands as a new venue rather than 409
 * when it loses — that anchor is the only record of where the piece went.
 */
export async function POST(req: Request) {
  if (!rateLimit(`worldmap:${clientIp(req)}`, 10, 0.2).ok) {
    return bad(429, "slow down");
  }

  // Refuse before reading a byte — formData() buffers the whole body, so the
  // per-part checks below can only ever be an after-the-fact complaint.
  const declared = Number(req.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > MAX_WORLDMAP_BODY_BYTES) {
    return bad(413, `body exceeds ${MAX_WORLDMAP_BODY_BYTES} bytes`);
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

  let meta: Partial<Record<keyof CreateWorldMapRequest, unknown>>;
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
  const quality = {
    lat,
    lng,
    featurePoints: int32(meta.featurePoints) ?? 0,
    anchorCount: int32(meta.anchorCount) ?? 0,
  };
  const pieceId = Number.isInteger(meta.pieceId) ? Number(meta.pieceId) : null;
  let parentId = Number.isInteger(meta.parentId) ? Number(meta.parentId) : null;

  // Optional placement guide. The map is the valuable half of this upload, so
  // an unusable guide is dropped, never fatal.
  const snapshot = await readImagePart(form, "snapshot", MAX_SNAPSHOT_BYTES);
  const snapshotTransform = snapshot && isTransform16(meta.snapshotTransform)
    ? meta.snapshotTransform
    : null;

  const written: string[] = [];
  try {
    await ensureWorldMaps();

    // Check the parent before writing megabytes to disk for a chain that will
    // be refused. A post whose chain is refused still has to land, so it falls
    // back to a new venue instead of a 409.
    if (parentId !== null) {
      const why = await chainRejectionFor(parentId, quality);
      if (why && pieceId === null) return bad(409, why);
      if (why) parentId = null;
    }

    const mapPath = await saveBlob(Buffer.from(await map.arrayBuffer()), "armap");
    written.push(mapPath);
    const snapshotPath = snapshot ? await saveImage(snapshot.buf, snapshot.ext) : null;
    if (snapshotPath) written.push(snapshotPath);

    const record = await insertWorldMap(
      {
        ...quality,
        pieceId,
        parentId,
        mapPath,
        sizeBytes: map.size,
        extentM: Number.isFinite(Number(meta.extentM)) ? Number(meta.extentM) : 0,
        snapshotPath,
        snapshotTransform,
      },
      pieceId !== null,
    );
    if (!record) {
      await Promise.all(written.map((p) => deleteImage(p)));
      return bad(409, "parent map has already been extended by someone else");
    }
    return Response.json(record, { status: 201 });
  } catch (err) {
    // Never leave a blob nothing references — these are megabytes each.
    await Promise.all(written.map((p) => deleteImage(p)));
    console.error("[worldmaps] save failed", err);
    return bad(500, "could not save world map");
  }
}
