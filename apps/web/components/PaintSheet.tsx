"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { sessionId } from "@/lib/session";
import { SPRAY, palette } from "@/lib/theme";

/**
 * The browser contribution path.
 *
 * This is the seeding route, not the headline experience — the AR app is that.
 * Its whole job is to let someone who was handed a link put something on the
 * wall in well under a minute, on a phone, with no install and no account.
 * Every decision here is subordinate to that.
 */

type Point = { x: number; y: number };

interface Stroke {
  colour: string;
  width: number;
  points: Point[];
}

const CANVAS = 640; // exported at this size, square, transparent

export default function PaintSheet({
  centre,
  onClose,
  onPainted,
}: {
  /** Fallback position: wherever the map is looking, if GPS is refused. */
  centre: { lat: number; lng: number };
  onClose: () => void;
  onPainted: () => void;
}) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const strokes = useRef<Stroke[]>([]);
  const current = useRef<Stroke | null>(null);
  // Set on mount, not during render — Date.now() in a render body is impure.
  const startedAt = useRef<number>(0);

  const [colour, setColour] = useState<string>(SPRAY[0]);
  const [width, setWidth] = useState(18);
  const [hasArt, setHasArt] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [where, setWhere] = useState<{ lat: number; lng: number; precise: boolean }>({
    ...centre,
    precise: false,
  });

  // Ask for GPS, but never block on it — a refused prompt must not cost the
  // contribution. The map's centre is a perfectly good fallback.
  useEffect(() => {
    if (!navigator.geolocation) return;
    const id = navigator.geolocation.getCurrentPosition(
      (pos) => setWhere({ lat: pos.coords.latitude, lng: pos.coords.longitude, precise: true }),
      () => {},
      { enableHighAccuracy: true, timeout: 8000 },
    );
    return () => void id;
  }, []);

  const redraw = useCallback(() => {
    const c = canvas.current;
    if (!c) return;
    const ctx = c.getContext("2d");
    if (!ctx) return;
    ctx.clearRect(0, 0, c.width, c.height);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    for (const s of [...strokes.current, current.current].filter(Boolean) as Stroke[]) {
      if (s.points.length === 0) continue;
      ctx.strokeStyle = s.colour;
      ctx.lineWidth = s.width;
      ctx.beginPath();
      ctx.moveTo(s.points[0]!.x, s.points[0]!.y);
      for (const p of s.points.slice(1)) ctx.lineTo(p.x, p.y);
      // A single tap should still leave a dot.
      if (s.points.length === 1) ctx.lineTo(s.points[0]!.x + 0.1, s.points[0]!.y);
      ctx.stroke();
    }
  }, []);

  useEffect(() => {
    startedAt.current = Date.now();
    const c = canvas.current;
    if (!c) return;
    c.width = CANVAS;
    c.height = CANVAS;
    redraw();
  }, [redraw]);

  const toCanvas = (e: React.PointerEvent): Point => {
    const rect = e.currentTarget.getBoundingClientRect();
    return {
      x: ((e.clientX - rect.left) / rect.width) * CANVAS,
      y: ((e.clientY - rect.top) / rect.height) * CANVAS,
    };
  };

  const down = (e: React.PointerEvent) => {
    e.currentTarget.setPointerCapture(e.pointerId);
    current.current = { colour, width, points: [toCanvas(e)] };
    redraw();
  };

  const move = (e: React.PointerEvent) => {
    if (!current.current) return;
    current.current.points.push(toCanvas(e));
    redraw();
  };

  const up = () => {
    if (!current.current) return;
    strokes.current.push(current.current);
    current.current = null;
    setHasArt(true);
    redraw();
  };

  const undo = () => {
    strokes.current.pop();
    setHasArt(strokes.current.length > 0);
    redraw();
  };

  const send = async () => {
    const c = canvas.current;
    if (!c || strokes.current.length === 0) return;
    setSending(true);
    setError(null);

    const blob = await new Promise<Blob | null>((res) => c.toBlob(res, "image/png"));
    if (!blob) {
      setError("Could not read the canvas.");
      setSending(false);
      return;
    }

    // Colours are recorded in the order they were first used, which is what the
    // dashboard's pigment chart counts.
    const seen: string[] = [];
    for (const s of strokes.current) if (!seen.includes(s.colour)) seen.push(s.colour);
    const colors = seen.map((hex) => ({
      r: parseInt(hex.slice(1, 3), 16),
      g: parseInt(hex.slice(3, 5), 16),
      b: parseInt(hex.slice(5, 7), 16),
    }));

    const fd = new FormData();
    fd.append("image", blob, "art.png");
    fd.append(
      "meta",
      JSON.stringify({
        lat: where.lat,
        lng: where.lng,
        kind: "spray",
        sessionId: sessionId(),
        colors,
        strokeCount: strokes.current.length,
        durationMs: Date.now() - startedAt.current,
        client: "web",
        accuracyM: where.precise ? undefined : 250,
      }),
    );

    try {
      const res = await fetch("/api/pieces", { method: "POST", body: fd });
      if (res.status === 429) {
        setError("Too many just now — give it a few seconds.");
        setSending(false);
        return;
      }
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      onPainted();
      onClose();
    } catch {
      setError("Could not put it on the wall. Try again.");
      setSending(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex flex-col" style={{ background: palette.ink }}>
      <header className="flex items-center justify-between px-4 py-3">
        <button
          type="button"
          onClick={onClose}
          className="rounded-full px-3 py-1.5 text-xs"
          style={{ color: palette.textMuted, border: `1px solid ${palette.line}` }}
        >
          Cancel
        </button>
        <p className="text-xs" style={{ color: palette.textMuted }}>
          {where.precise ? "Using your location" : "Using the map’s centre"}
        </p>
        <button
          type="button"
          onClick={undo}
          disabled={!hasArt}
          className="rounded-full px-3 py-1.5 text-xs disabled:opacity-40"
          style={{ color: palette.textMuted, border: `1px solid ${palette.line}` }}
        >
          Undo
        </button>
      </header>

      <div className="flex flex-1 items-center justify-center px-4">
        <canvas
          ref={canvas}
          onPointerDown={down}
          onPointerMove={move}
          onPointerUp={up}
          onPointerCancel={up}
          className="w-full max-w-md rounded-2xl"
          style={{
            aspectRatio: "1 / 1",
            // A checkerboard would be noise; a flat panel reads as a wall.
            background: palette.raised,
            border: `1px solid ${palette.line}`,
            touchAction: "none", // or the browser pans instead of drawing
            cursor: "crosshair",
          }}
        />
      </div>

      {!hasArt && (
        <p className="px-6 text-center text-xs" style={{ color: palette.textMuted }}>
          Draw something. Anything.
        </p>
      )}
      {error && (
        <p className="px-6 pt-2 text-center text-xs" style={{ color: palette.accent }}>
          {error}
        </p>
      )}

      <footer className="px-4 pt-3 pb-6">
        <div className="mb-3 flex items-center justify-center gap-2.5">
          {SPRAY.map((c) => (
            <button
              key={c}
              type="button"
              aria-label={`Colour ${c}`}
              onClick={() => setColour(c)}
              className="h-9 w-9 rounded-full transition-transform"
              style={{
                background: c,
                transform: colour === c ? "scale(1.22)" : "none",
                boxShadow: colour === c ? `0 0 0 2px ${palette.text}` : `0 0 0 1px ${palette.line}`,
              }}
            />
          ))}
        </div>

        <div className="mb-4 flex items-center justify-center gap-3">
          <span className="text-[10px] tracking-widest uppercase" style={{ color: palette.textMuted }}>
            Nozzle
          </span>
          <input
            type="range"
            min={6}
            max={48}
            value={width}
            onChange={(e) => setWidth(Number(e.target.value))}
            className="w-40"
            aria-label="Brush size"
          />
        </div>

        <button
          type="button"
          onClick={() => void send()}
          disabled={!hasArt || sending}
          className="w-full rounded-2xl py-4 text-base font-semibold disabled:opacity-40"
          style={{ background: palette.accent, color: "#fff" }}
        >
          {sending ? "Putting it up…" : "Put it on the wall"}
        </button>
      </footer>
    </div>
  );
}
