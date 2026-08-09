import { readFile } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";
import { UPLOAD_DIR, ensureSchema, pool } from "@/lib/db";
import { deleteImage, detectImage, saveImage } from "@/lib/storage";

/**
 * THE transformation: a crude finger-scribble goes in, a polished graffiti
 * throw-up comes out, anchored to the same spot. Runs after the piece is
 * already saved — the raw art shows immediately and swaps when this lands,
 * so a slow or dead Replicate can never lose a contribution.
 *
 *   upscale (small art only) → restyle → isolate → final_image_path
 *                                              ↳ weather → weathered_image_path
 *
 * Every stage is optional in the sense that matters: whatever fails, the piece
 * keeps the best image it already has. None of this is ever on the AR path.
 */

const REPLICATE = "https://api.replicate.com/v1";

/**
 * Restyle model is google/nano-banana: reve/remix hard-fails server-side
 * (E001) on every input — verified 2026-08-09 with a 64px synthetic image.
 * nano-banana in turn refuses large inputs (identical art: 1024px data URI
 * fails, 512px succeeds), hence the downscale/flatten below.
 */
const STYLE_PROMPT =
  "Redraw this drawing as a polished street-art style piece: bold black " +
  "outlines, vivid spray-paint fills, subtle paint drips. Keep the shapes, " +
  "layout and colours recognisable. Plain solid white background, nothing " +
  "else in the image.";

const RESTYLE_PX = 512;

/**
 * The web map's second copy of the piece: the same art as if it had spent years
 * on the wall. Never rendered in AR — see `weatherPiece`.
 */
const WEATHER_PROMPT =
  "Age this graffiti as if it has been on a wall outdoors for years: paint " +
  "runs and drips streaking downward, sun-faded patchy colour, grime and dust " +
  "settled into the texture, chipped and worn edges. Keep the same shapes, " +
  "layout and colours recognisable. Plain solid white background, nothing " +
  "else in the image.";

/** An undrained body holds its socket open; every early return has to eat one. */
async function drain(res: Response): Promise<void> {
  await res.arrayBuffer().catch(() => {});
}

/**
 * `version` is required for community models — only official models (reve/*)
 * expose the model-scoped predictions endpoint; everything else 404s there
 * and must go through /predictions with a pinned version.
 */
async function runModel(model: string, input: Record<string, unknown>, version?: string): Promise<string> {
  const token = process.env.REPLICATE_API_TOKEN;
  if (!token) throw new Error("REPLICATE_API_TOKEN not configured");

  const url = version ? `${REPLICATE}/predictions` : `${REPLICATE}/models/${model}/predictions`;
  const request = {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      Prefer: "wait=60",
    },
    body: JSON.stringify(version ? { version, input } : { input }),
  };
  let res = await fetch(url, request);
  if (res.status === 429) {
    // Fresh accounts burst-limit quickly; one spaced retry rides it out.
    await drain(res);
    await new Promise((resolve) => setTimeout(resolve, 12000));
    res = await fetch(url, request);
  }
  let prediction = await res.json();
  if (!res.ok) {
    throw new Error(`${model}: HTTP ${res.status} ${prediction?.detail ?? ""}`);
  }
  for (let i = 0; i < 30 && ["starting", "processing"].includes(prediction.status); i++) {
    await new Promise((resolve) => setTimeout(resolve, 2000));
    const poll = await fetch(prediction.urls.get, {
      headers: { Authorization: `Bearer ${token}` },
    });
    prediction = await poll.json();
  }
  if (prediction.status !== "succeeded") {
    throw new Error(`${model}: ${prediction.status} ${prediction.error ?? ""}`);
  }
  const output = Array.isArray(prediction.output) ? prediction.output[0] : prediction.output;
  if (typeof output !== "string") throw new Error(`${model}: no output URL`);
  return output;
}

/** Fetches a finished prediction's image, draining the body if it isn't one. */
async function download(url: string): Promise<Buffer> {
  const res = await fetch(url);
  if (!res.ok) {
    await drain(res);
    throw new Error(`download: HTTP ${res.status}`);
  }
  return Buffer.from(await res.arrayBuffer());
}

/**
 * Scale to ask the upscaler for, or null to leave the art alone.
 *
 * Under RESTYLE_PX the restyle is being fed fewer pixels than it can use and
 * every soft edge survives into the finished piece; at or above it an upscale
 * only costs money and softens line art that was already fine.
 */
export function upscaleFactor(width: number, height: number): number | null {
  const longest = Math.max(width, height);
  if (longest <= 0 || longest >= RESTYLE_PX) return null;
  return Math.min(4, Math.ceil(RESTYLE_PX / longest));
}

/**
 * Sharpens small art before it reaches the restyle. Fails soft by design: a
 * dead, slow or rate-limited upscaler returns the original bytes, so the only
 * cost of a failure is the picture the piece would have had anyway.
 */
export async function upscaleIfSmall(raw: Buffer): Promise<Buffer> {
  try {
    const { width = 0, height = 0 } = await sharp(raw).metadata();
    const scale = upscaleFactor(width, height);
    if (!scale) return raw;

    const png = await sharp(raw).flatten({ background: "#ffffff" }).png().toBuffer();
    const out = await download(
      await runModel(
        "nightmareai/real-esrgan",
        { image: `data:image/png;base64,${png.toString("base64")}`, scale },
        "f121d640bd286e1fdc67f9799164c1d5be36ff74576ee11c803ae5b665dd46aa",
      ),
    );
    if (!detectImage(out)) throw new Error("upscale result is not an image");
    return out;
  } catch (err) {
    console.warn("[transform] upscale skipped", err);
    return raw;
  }
}

async function prepare(art: Buffer): Promise<string> {
  const prepared = await sharp(art)
    .flatten({ background: "#ffffff" })
    .resize(RESTYLE_PX, RESTYLE_PX, { fit: "inside", withoutEnlargement: true })
    .png()
    .toBuffer();
  return `data:image/png;base64,${prepared.toString("base64")}`;
}

/**
 * One nano-banana pass over a piece's art, stored under /uploads. The model's
 * output is opaque, so it is cut back out — paint on a wall, not a pasted
 * rectangle.
 */
async function repaint(art: Buffer, prompt: string): Promise<string> {
  const painted = await runModel("google/nano-banana", {
    prompt,
    image_input: [await prepare(art)],
    output_format: "png",
  });
  const isolated = await runModel(
    "851-labs/background-remover",
    { image: painted, format: "png" },
    "a029dff38972b5fda4ec5d75d7d1cd25aeff621d2cf4946a41055d7db66b80bc",
  );
  const buf = await download(isolated);
  const ext = detectImage(buf);
  if (!ext) throw new Error("transform result is not an image");
  return saveImage(buf, ext);
}

/**
 * Records a finished pass, unless a concurrent one already claimed the piece —
 * in which case the file it produced is nothing's, and goes.
 */
async function claim(
  id: number,
  // A union, not a string: this one is interpolated into the statement.
  column: "final_image_path" | "weathered_image_path",
  rel: string,
): Promise<string | null> {
  const updated = await pool.query(
    `UPDATE pieces SET ${column} = $2 WHERE id = $1 AND ${column} IS NULL`,
    [id, rel],
  );
  if ((updated.rowCount ?? 0) > 0) return rel;
  await deleteImage(rel);
  return null;
}

/** Double-submits happen (retries, impatient taps); only run each pass once. */
const inFlight = new Set<string>();

/**
 * Transforms one piece's raw art and records final_image_path.
 * Returns the new path, or null when there was nothing to do.
 */
export async function transformPiece(id: number): Promise<string | null> {
  const key = `style:${id}`;
  if (inFlight.has(key)) return null;
  inFlight.add(key);
  try {
    const { rows } = await pool.query(
      `SELECT raw_image_path, kind FROM pieces
       WHERE id = $1 AND deleted_at IS NULL AND final_image_path IS NULL`,
      [id],
    );
    // Stickers are already art-directed; restyle only hand-drawn pieces.
    if (rows.length === 0 || rows[0].kind !== "spray") return null;

    const raw = await readFile(path.join(UPLOAD_DIR, rows[0].raw_image_path));
    if (!detectImage(raw)) return null;

    return claim(id, "final_image_path", await repaint(await upscaleIfSmall(raw), STYLE_PROMPT));
  } finally {
    inFlight.delete(key);
  }
}

/**
 * The aged copy: the piece as if it had been weathering on that wall for years.
 *
 * ⚠️ WEB MAP ONLY, and deliberately so. AR geometry and blending stay local at
 * 60fps on device, so nothing here is ever on the AR path — iOS renders
 * `finalImagePath ?? rawImagePath` and never reads this column.
 *
 * Ages the finished piece, never the raw scribble: without that guard a
 * Replicate outage during the restyle would leave an aged scribble that then
 * outranks the polished art forever, since the map prefers the weathered copy.
 * That also keeps this off stickers, which are never restyled.
 */
export async function weatherPiece(id: number): Promise<string | null> {
  const key = `weather:${id}`;
  if (inFlight.has(key)) return null;
  inFlight.add(key);
  try {
    await ensureSchema();
    const { rows } = await pool.query<{ art: string }>(
      `SELECT final_image_path AS art FROM pieces
       WHERE id = $1 AND deleted_at IS NULL
         AND final_image_path IS NOT NULL AND weathered_image_path IS NULL`,
      [id],
    );
    if (rows.length === 0) return null;

    const art = await readFile(path.join(UPLOAD_DIR, rows[0]!.art));
    if (!detectImage(art)) return null;

    return claim(id, "weathered_image_path", await repaint(art, WEATHER_PROMPT));
  } finally {
    inFlight.delete(key);
  }
}
