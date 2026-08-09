import { readFile } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";
import { UPLOAD_DIR, pool } from "@/lib/db";
import { detectImage, saveImage } from "@/lib/storage";

/**
 * THE transformation: a crude finger-scribble goes in, a polished graffiti
 * throw-up comes out, anchored to the same spot. Runs after the piece is
 * already saved — the raw art shows immediately and swaps when this lands,
 * so a slow or dead Replicate can never lose a contribution.
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

/** Double-submits happen (retries, impatient taps); only transform once. */
const inFlight = new Set<number>();

/**
 * Transforms one piece's raw art and records final_image_path.
 * Returns the new path, or null when there was nothing to do.
 */
export async function transformPiece(id: number): Promise<string | null> {
  if (inFlight.has(id)) return null;
  inFlight.add(id);
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
    // ≤512px, alpha flattened to white — both verified requirements of the model.
    const prepared = await sharp(raw)
      .flatten({ background: "#ffffff" })
      .resize(512, 512, { fit: "inside", withoutEnlargement: true })
      .png()
      .toBuffer();
    const dataUri = `data:image/png;base64,${prepared.toString("base64")}`;

    const styled = await runModel("google/nano-banana", {
      prompt: STYLE_PROMPT,
      image_input: [dataUri],
      output_format: "png",
    });
    // The styled output is opaque; cut it back out so it reads as paint on a
    // wall in AR rather than a pasted rectangle.
    const isolated = await runModel(
      "851-labs/background-remover",
      { image: styled, format: "png" },
      "a029dff38972b5fda4ec5d75d7d1cd25aeff621d2cf4946a41055d7db66b80bc",
    );

    const download = await fetch(isolated);
    if (!download.ok) throw new Error(`download: HTTP ${download.status}`);
    const buf = Buffer.from(await download.arrayBuffer());
    const outExt = detectImage(buf);
    if (!outExt) throw new Error("transform result is not an image");

    const rel = await saveImage(buf, outExt);
    // Guard against a concurrent transform of the same piece having won.
    const updated = await pool.query(
      `UPDATE pieces SET final_image_path = $2
       WHERE id = $1 AND final_image_path IS NULL`,
      [id, rel],
    );
    return (updated.rowCount ?? 0) > 0 ? rel : null;
  } finally {
    inFlight.delete(id);
  }
}
