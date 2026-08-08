import { getStats } from "@/lib/stats";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const stats = await getStats();
    return Response.json(stats, { headers: { "Cache-Control": "no-store" } });
  } catch (err) {
    console.error("[stats] failed", err);
    return Response.json({ error: "could not compute stats" }, { status: 500 });
  }
}
