"use client";

import { useId, useState } from "react";
import { CHART, palette } from "@/lib/theme";

/**
 * Hand-built chart primitives.
 *
 * No chart library: these are simple enough that a dependency would cost more
 * than it saves, and it keeps full control over mark weight, spacing and the
 * hover layer.
 *
 * Colour rules followed here:
 *  - A single measure across categories is ONE hue, not a rainbow. Colour is not
 *    repeating the category label.
 *  - The pigment chart is the exception: there, the colour *is* the datum.
 *  - Text always wears text tokens, never a series colour.
 */

export function Panel({
  title,
  hint,
  children,
}: {
  title: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <section
      className="rounded-2xl p-5"
      style={{ background: palette.raised, border: `1px solid ${palette.line}` }}
    >
      <header className="mb-4">
        <h2 className="text-sm font-semibold tracking-wide" style={{ color: palette.text }}>
          {title}
        </h2>
        {hint && (
          <p className="mt-0.5 text-xs" style={{ color: palette.textMuted }}>
            {hint}
          </p>
        )}
      </header>
      {children}
    </section>
  );
}

export function StatTile({
  label,
  value,
  sub,
  live,
}: {
  label: string;
  value: string;
  sub?: string;
  live?: boolean;
}) {
  return (
    <div
      className="rounded-2xl p-5"
      style={{ background: palette.raised, border: `1px solid ${palette.line}` }}
    >
      <div className="flex items-center gap-2">
        {live && (
          <span
            className="got-live-dot inline-block h-1.5 w-1.5 rounded-full"
            style={{ background: palette.accent }}
          />
        )}
        <p className="text-xs tracking-widest uppercase" style={{ color: palette.textMuted }}>
          {label}
        </p>
      </div>
      <p
        className="mt-2 text-4xl font-semibold tabular-nums"
        style={{ color: palette.text, letterSpacing: "-0.02em" }}
      >
        {value}
      </p>
      {sub && (
        <p className="mt-1 text-xs" style={{ color: palette.textMuted }}>
          {sub}
        </p>
      )}
    </div>
  );
}

/** Empty state that is honest about *why* there is nothing, not just that there isn't. */
export function NoData({ children }: { children: React.ReactNode }) {
  return (
    <p className="py-8 text-center text-xs" style={{ color: palette.textMuted }}>
      {children}
    </p>
  );
}

/**
 * Area + line over time. One series, so no legend — the panel title names it.
 * Crosshair and tooltip on hover, per the interaction rules.
 */
export function TimeArea({
  points,
  height = 150,
}: {
  points: { hour: string; pieces: number }[];
  height?: number;
}) {
  const gid = useId();
  const [hover, setHover] = useState<number | null>(null);

  if (points.length === 0) return <NoData>No activity recorded yet.</NoData>;

  const W = 720;
  const H = height;
  const padB = 22;
  const max = Math.max(1, ...points.map((p) => p.pieces));
  const x = (i: number) => (i / Math.max(1, points.length - 1)) * W;
  const y = (v: number) => H - padB - (v / max) * (H - padB - 8);

  const line = points.map((p, i) => `${i === 0 ? "M" : "L"}${x(i)},${y(p.pieces)}`).join(" ");
  const area = `${line} L${W},${H - padB} L0,${H - padB} Z`;
  const hourOf = (iso: string) => new Date(iso).getHours();

  return (
    <div className="relative">
      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="w-full"
        role="img"
        aria-label="Pieces painted per hour over the last 24 hours"
        onMouseLeave={() => setHover(null)}
      >
        <defs>
          <linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={CHART[0]} stopOpacity="0.42" />
            <stop offset="100%" stopColor={CHART[0]} stopOpacity="0.02" />
          </linearGradient>
        </defs>

        {/* Recessive baseline only — a full grid competes with the data. */}
        <line x1="0" y1={H - padB} x2={W} y2={H - padB} stroke={palette.line} strokeWidth="1" />

        <path d={area} fill={`url(#${gid})`} />
        <path d={line} fill="none" stroke={CHART[0]} strokeWidth="2" strokeLinejoin="round" />

        {hover !== null && (
          <>
            <line
              x1={x(hover)}
              y1="0"
              x2={x(hover)}
              y2={H - padB}
              stroke={palette.textMuted}
              strokeWidth="1"
              strokeDasharray="3 3"
            />
            <circle
              cx={x(hover)}
              cy={y(points[hover]!.pieces)}
              r="4.5"
              fill={CHART[0]}
              stroke={palette.raised}
              strokeWidth="2"
            />
          </>
        )}

        {points.map((p, i) => (
          <rect
            key={p.hour}
            x={x(i) - W / points.length / 2}
            y="0"
            width={W / points.length}
            height={H - padB}
            fill="transparent"
            onMouseEnter={() => setHover(i)}
          />
        ))}

        {points.map((p, i) =>
          i % 6 === 0 ? (
            <text
              key={p.hour}
              x={x(i)}
              y={H - 6}
              fontSize="10"
              textAnchor="middle"
              fill={palette.textMuted}
            >
              {String(hourOf(p.hour)).padStart(2, "0")}:00
            </text>
          ) : null,
        )}
      </svg>

      {hover !== null && (
        <div
          className="pointer-events-none absolute -top-1 rounded-lg px-2.5 py-1.5 text-xs whitespace-nowrap"
          style={{
            left: `${(hover / Math.max(1, points.length - 1)) * 100}%`,
            transform: "translateX(-50%)",
            background: palette.ink,
            border: `1px solid ${palette.line}`,
            color: palette.text,
          }}
        >
          <strong className="tabular-nums">{points[hover]!.pieces}</strong>{" "}
          {points[hover]!.pieces === 1 ? "piece" : "pieces"} ·{" "}
          <span style={{ color: palette.textMuted }}>
            {String(hourOf(points[hover]!.hour)).padStart(2, "0")}:00
          </span>
        </div>
      )}
    </div>
  );
}

/**
 * Horizontal bars for a single measure across categories. One hue — the label
 * already carries identity, so colouring each bar differently would be decoration.
 */
export function BarList({
  rows,
  unit,
  colour = CHART[0],
}: {
  rows: { label: string; value: number; note?: string }[];
  unit: string;
  colour?: string;
}) {
  const [hover, setHover] = useState<string | null>(null);
  if (rows.length === 0) return <NoData>Nothing recorded yet.</NoData>;
  const max = Math.max(1, ...rows.map((r) => r.value));

  return (
    <ul className="flex flex-col gap-2.5">
      {rows.map((r) => (
        <li
          key={r.label}
          className="grid grid-cols-[7.5rem_1fr_auto] items-center gap-3"
          onMouseEnter={() => setHover(r.label)}
          onMouseLeave={() => setHover(null)}
        >
          <span className="truncate text-xs capitalize" style={{ color: palette.textMuted }}>
            {r.label}
          </span>
          <span
            className="relative block h-3 overflow-hidden rounded-sm"
            style={{ background: palette.line }}
          >
            <span
              className="absolute inset-y-0 left-0 rounded-r-[4px] transition-[width] duration-500"
              style={{
                width: `${(r.value / max) * 100}%`,
                background: colour,
                opacity: hover && hover !== r.label ? 0.45 : 1,
              }}
            />
          </span>
          <span className="text-xs tabular-nums" style={{ color: palette.text }}>
            {r.value}
            <span style={{ color: palette.textMuted }}> {unit}</span>
            {r.note && <span style={{ color: palette.textMuted }}> · {r.note}</span>}
          </span>
        </li>
      ))}
    </ul>
  );
}

/**
 * Pigment usage. The one place colour is data rather than decoration: each bar
 * is painted in the pigment it represents, with a ring so pale colours stay
 * visible against the surface.
 */
export function PigmentBars({ rows }: { rows: { hex: string; uses: number }[] }) {
  if (rows.length === 0) return <NoData>No colour data yet.</NoData>;
  const max = Math.max(1, ...rows.map((r) => r.uses));

  return (
    <div className="flex items-end gap-2" style={{ height: 140 }}>
      {rows.map((r) => (
        <div key={r.hex} className="flex flex-1 flex-col items-center gap-2" title={`${r.hex} · ${r.uses} uses`}>
          <span
            className="w-full rounded-t-[4px] transition-[height] duration-500"
            style={{
              height: `${Math.max(4, (r.uses / max) * 104)}px`,
              background: r.hex,
              boxShadow: `0 0 0 1px ${palette.line}`,
            }}
          />
          <span className="text-[10px] tabular-nums" style={{ color: palette.textMuted }}>
            {r.uses}
          </span>
        </div>
      ))}
    </div>
  );
}
