import { randomUUID } from "node:crypto";
import { mkdir, unlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { UPLOAD_DIR } from "@/lib/db";

export const MAX_IMAGE_BYTES = 8 * 1024 * 1024;
/** Scene photos are camera frames, so they run larger than line art. */
export const MAX_SCENE_BYTES = 12 * 1024 * 1024;
/**
 * Ceiling on the whole multipart body, checked from Content-Length before any
 * of it is read. The per-part limits above can only be enforced once
 * `formData()` has buffered everything into memory, which is far too late to be
 * a defence — by then an attacker has already had us allocate the lot.
 */
export const MAX_BODY_BYTES = MAX_IMAGE_BYTES + MAX_SCENE_BYTES + 1024 * 1024;

/** Compressed ARWorldMaps run 1–10 MB; leave generous headroom. */
export const MAX_MAP_BYTES = 32 * 1024 * 1024;
/**
 * The placement guide that rides along with a world map. Deliberately tiny: the
 * map is already megabytes and the guide only has to be recognisable — the
 * client sends a 640px JPEG, tens of KB.
 */
export const MAX_SNAPSHOT_BYTES = 512 * 1024;
export const MAX_WORLDMAP_BODY_BYTES = MAX_MAP_BYTES + MAX_SNAPSHOT_BYTES + 1024 * 1024;

const SIGNATURES: { ext: string; test: (b: Buffer) => boolean }[] = [
  { ext: "png", test: (b) => b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) },
  { ext: "jpg", test: (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff },
  { ext: "webp", test: (b) => b.subarray(0, 4).toString() === "RIFF" && b.subarray(8, 12).toString() === "WEBP" },
];

/**
 * Sniff the actual bytes rather than trusting the declared Content-Type — a
 * client can claim anything, and this is public UGC.
 */
export function detectImage(buf: Buffer): string | null {
  if (buf.length < 12) return null;
  return SIGNATURES.find((s) => s.test(buf))?.ext ?? null;
}

/**
 * An optional image part, or null when it is absent, empty, oversized or not an
 * image. Never throws: callers use this for decorations that must not be able
 * to fail the upload they ride along with.
 */
export async function readImagePart(
  form: FormData,
  name: string,
  maxBytes: number,
): Promise<{ buf: Buffer; ext: string } | null> {
  const part = form.get(name);
  if (!(part instanceof File) || part.size === 0 || part.size > maxBytes) return null;
  const buf = Buffer.from(await part.arrayBuffer());
  const ext = detectImage(buf);
  return ext ? { buf, ext } : null;
}

/**
 * Writes into a 2-char shard so one directory doesn't accumulate every file.
 * Returns the path relative to UPLOAD_DIR, which is what goes in the database
 * and what nginx serves under /uploads/.
 */
export async function saveImage(buf: Buffer, ext: string): Promise<string> {
  const id = randomUUID();
  const rel = path.join(id.slice(0, 2), `${id}.${ext}`);
  const abs = path.join(UPLOAD_DIR, rel);
  await mkdir(path.dirname(abs), { recursive: true });
  await writeFile(abs, buf);
  return rel;
}

/** Undo a `saveImage` whose database row never landed, so a failed write
 *  doesn't leave an image nothing will ever reference. */
export async function deleteImage(rel: string): Promise<void> {
  await unlink(path.join(UPLOAD_DIR, rel)).catch(() => {});
}

/** Same sharded layout for opaque blobs (ARWorldMap scans) — no sniffing. */
export const saveBlob = saveImage;
