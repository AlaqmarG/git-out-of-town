import { UPLOADS_BASE } from "@got/shared";
import { pool } from "@/lib/db";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    await pool.query("SELECT 1");
    return Response.json({ ok: true, uploads: UPLOADS_BASE });
  } catch {
    return Response.json({ ok: false }, { status: 503 });
  }
}
