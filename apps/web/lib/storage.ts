import { randomUUID } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { UPLOAD_DIR } from "@/lib/db";

export const MAX_IMAGE_BYTES = 8 * 1024 * 1024;
/** Scene photos are camera frames, so they run larger than line art. */
export const MAX_SCENE_BYTES = 12 * 1024 * 1024;

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
