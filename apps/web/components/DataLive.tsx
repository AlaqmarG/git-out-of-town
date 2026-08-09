"use client";

import { useEffect, useState } from "react";
import { BarList, NoData, Panel, PigmentBars, StatTile, TimeArea } from "@/components/charts";
import type { Stats } from "@/lib/stats";
import { CHART, palette } from "@/lib/theme";

function duration(seconds: number): string {
  if (seconds < 60) return `${seconds}s`;
  const mins = Math.round(seconds / 60);
  if (mins < 60) return `${mins} min`;
  return `${(mins / 60).toFixed(1)} hrs`;
}

/**
 * The dashboard refreshes itself so the numbers move while someone is watching
 * it — which is the difference between a report and a live instrument.
 */
export default function DataLive({ initial }: { initial: Stats }) {
  const [stats, setStats] = useState(initial);
  const [flash, setFlash] = useState(false);
  const [showTable, setShowTable] = useState(false);

  useEffect(() => {
    let alive = true;
    const tick = async () => {
      try {
        const res = await fetch("/api/stats", { cache: "no-store" });
        if (!res.ok || !alive) return;
        const next = (await res.json()) as Stats;
        setStats((prev) => {
          if (next.totals.pieces !== prev.totals.pieces) {
            setFlash(true);
            setTimeout(() => setFlash(false), 900);
          }
          return next;
        });
      } catch {
        // A dropped poll is not worth surfacing; the next one will catch up.
      }
    };
    const id = setInterval(tick, 5000);
    return () => {
      alive = false;
      clearInterval(id);
    };
  }, []);

  const { totals, perHour, surfaces, cities, colours, clients, durations } = stats;
  // A single-client split says nothing. Only worth showing once both exist.
  const showClients = clients.length > 1;
  const anyViews = surfaces.some((s) => s.viewsPerPiece > 0);

  return (
    <div className="flex flex-col gap-5">
      <section className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <div style={{ transition: "transform 300ms", transform: flash ? "scale(1.03)" : "none" }}>
          <StatTile
            label="Pieces"
            value={totals.pieces.toLocaleString()}
            sub={`${totals.lastHour} in the last hour`}
            live
          />
        </div>
        <StatTile
          label="Contributors"
          value={totals.contributors.toLocaleString()}
          sub="distinct sessions"
        />
        <StatTile
          label="Time spent painting"
          value={duration(totals.paintSeconds)}
          sub="summed across everyone"
        />
        <StatTile
          label="Countries"
          value={totals.countries.toLocaleString()}
          sub="reverse-geocoded from GPS"
        />
      </section>

      <Panel
        title="When the wall gets painted"
        hint="Pieces per hour, last 24 hours. Hover for a count."
      >
        <TimeArea points={perHour} />
      </Panel>

      <div className="grid gap-5 lg:grid-cols-2">
        <Panel
          title="What the world gets painted on"
          hint="From ARKit's surface classification. Only a native AR client can record this."
        >
          <BarList
            rows={surfaces.map((s) => ({
              label: s.surface,
              value: s.pieces,
              note: anyViews ? `${s.viewsPerPiece} views/piece` : undefined,
            }))}
            unit="pieces"
          />
          {!anyViews && (
            <p className="mt-3 text-xs" style={{ color: palette.textMuted }}>
              Attention data appears here once pieces start being opened.
            </p>
          )}
        </Panel>

        <Panel title="Where it comes from" hint="Reverse-geocoded from the coordinates people painted at.">
          <BarList
            rows={cities.map((c) => ({ label: c.label, value: c.value }))}
            unit="pieces"
            colour={CHART[1]}
          />
        </Panel>
      </div>

      <div className="grid gap-5 lg:grid-cols-[2fr_1fr]">
        <Panel title="The colours people reach for" hint="Every pigment used, counted across every piece.">
          <PigmentBars rows={colours} />
        </Panel>

        <Panel
          title={showClients ? "How they painted it" : "How long a piece takes"}
          hint={
            showClients
              ? "Native AR versus the browser."
              : "Time from first stroke to placing it on the wall."
          }
        >
          {showClients ? (
            <BarList
              rows={clients.map((c) => ({
                label: c.label === "ios" ? "in AR (iOS)" : "browser",
                value: c.value,
              }))}
              unit="pieces"
              colour={CHART[3]}
            />
          ) : durations.every((d) => d.pieces === 0) ? (
            <NoData>No contributions yet.</NoData>
          ) : (
            <BarList
              rows={durations.map((d) => ({ label: d.label, value: d.pieces }))}
              unit="pieces"
              colour={CHART[3]}
            />
          )}
        </Panel>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 pt-1 pb-8">
        <p className="text-xs" style={{ color: palette.textMuted }}>
          Updated {new Date(stats.generatedAt).toLocaleTimeString()} · refreshes every 5s
        </p>
        <button
          type="button"
          onClick={() => setShowTable((v) => !v)}
          className="rounded-full px-3 py-1.5 text-xs"
          style={{ border: `1px solid ${palette.line}`, color: palette.textMuted }}
        >
          {showTable ? "Hide" : "Show"} the numbers
        </button>
      </div>

      {/* A table view so nothing is conveyed by colour or shape alone. */}
      {showTable && (
        <div className="overflow-x-auto pb-10">
          <table className="w-full text-left text-xs" style={{ color: palette.textMuted }}>
            <caption className="sr-only">All dashboard figures as a table</caption>
            <thead>
              <tr style={{ color: palette.text }}>
                <th className="py-2 pr-6">Measure</th>
                <th className="py-2 pr-6">Key</th>
                <th className="py-2">Value</th>
              </tr>
            </thead>
            <tbody>
              {surfaces.map((s) => (
                <tr key={`s-${s.surface}`} style={{ borderTop: `1px solid ${palette.line}` }}>
                  <td className="py-1.5 pr-6">Surface</td>
                  <td className="py-1.5 pr-6 capitalize">{s.surface}</td>
                  <td className="py-1.5 tabular-nums">{s.pieces}</td>
                </tr>
              ))}
              {cities.map((c) => (
                <tr key={`c-${c.label}`} style={{ borderTop: `1px solid ${palette.line}` }}>
                  <td className="py-1.5 pr-6">City</td>
                  <td className="py-1.5 pr-6">{c.label}</td>
                  <td className="py-1.5 tabular-nums">{c.value}</td>
                </tr>
              ))}
              {colours.map((c) => (
                <tr key={`p-${c.hex}`} style={{ borderTop: `1px solid ${palette.line}` }}>
                  <td className="py-1.5 pr-6">Pigment</td>
                  <td className="py-1.5 pr-6 font-mono">{c.hex}</td>
                  <td className="py-1.5 tabular-nums">{c.uses}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
