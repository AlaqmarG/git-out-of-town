import { readFile } from "node:fs/promises";
import path from "node:path";
import { UPLOADS_BASE } from "@got/shared";
import { pool } from "@/lib/db";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Next writes a fresh BUILD_ID for every build, so it is a reliable "which build
 * am I" marker. CI waits for this value to CHANGE before smoke testing —
 * otherwise the suite races the rollout and tests the previous container, which
 * is exactly how a stale image once passed every check while serving the wrong
 * site.
 */
let cachedBuildId: string | null = null;

async function buildId(): Promise<string> {
  if (cachedBuildId) return cachedBuildId;
  // In the standalone output the server runs from the repo root.
  for (const p of [".next/BUILD_ID", "apps/web/.next/BUILD_ID"]) {
    try {
      cachedBuildId = (await readFile(path.join(process.cwd(), p), "utf8")).trim();
      return cachedBuildId;
    } catch {
      // try the next candidate
    }
  }
  cachedBuildId = "unknown";
  return cachedBuildId;
}

export async function GET() {
  const build = await buildId();
  try {
    await pool.query("SELECT 1");
    return Response.json({ ok: true, uploads: UPLOADS_BASE, build });
  } catch {
    return Response.json({ ok: false, build }, { status: 503 });
  }
}
