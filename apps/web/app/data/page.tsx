import Link from "next/link";
import type { Stats } from "@/lib/stats";
import { getStats } from "@/lib/stats";
import DataLive from "@/components/DataLive";
import { palette } from "@/lib/theme";

// Every number is queried at request time. Nothing here is precomputed, cached
// or hardcoded — the dashboard has to be true at the moment someone looks at it.
export const dynamic = "force-dynamic";
export const revalidate = 0;

export default async function DataPage() {
  let stats: Stats | null = null;
  let error: string | null = null;

  try {
    stats = await getStats();
  } catch {
    error = "Could not reach the database.";
  }

  return (
    <main className="min-h-dvh px-5 py-8 sm:px-8" style={{ background: palette.ink }}>
      <div className="mx-auto max-w-5xl">
        <header className="mb-8 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1
              className="text-3xl font-semibold tracking-tight"
              style={{ color: palette.text, letterSpacing: "-0.02em" }}
            >
              What the wall knows
            </h1>
            <p className="mt-1 text-sm" style={{ color: palette.textMuted }}>
              Every figure is a live query. Nothing here is precomputed.
            </p>
          </div>
          <Link
            href="/"
            className="rounded-full px-4 py-2 text-xs tracking-wide transition-colors"
            style={{
              border: `1px solid ${palette.line}`,
              color: palette.text,
              background: palette.raised,
            }}
          >
            ← Back to the map
          </Link>
        </header>

        {error || !stats ? (
          <p
            className="rounded-2xl p-6 text-sm"
            style={{ background: palette.raised, border: `1px solid ${palette.line}`, color: palette.textMuted }}
          >
            {error ?? "No data."}
          </p>
        ) : (
          <DataLive initial={stats} />
        )}
      </div>
    </main>
  );
}
