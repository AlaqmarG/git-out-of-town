"use client";

import type { Piece, PiecesResponse } from "@got/shared";
import type { Map as MapLibreMap } from "maplibre-gl";
import { useCallback, useEffect, useRef, useState } from "react";
import "maplibre-gl/dist/maplibre-gl.css";
import { buildMapStyle } from "@/lib/map-style";
import { DEFAULT_VIEW, palette } from "@/lib/theme";

interface Props {
  /** Fires whenever the visible pieces change, so #13 can render markers. */
  onPiecesChange?: (pieces: Piece[]) => void;
}

export default function MapCanvas({ onPiecesChange }: Props) {
  const container = useRef<HTMLDivElement>(null);
  const map = useRef<MapLibreMap | null>(null);
  const [ready, setReady] = useState(false);
  const [total, setTotal] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Latest-wins: panning fast would otherwise let a slow early response
  // overwrite the results for where the user actually ended up.
  const inflight = useRef<AbortController | null>(null);
  const revealTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const resizeObs = useRef<ResizeObserver | null>(null);

  const load = useCallback(
    async (m: MapLibreMap) => {
      const b = m.getBounds();
      const bbox = [b.getWest(), b.getSouth(), b.getEast(), b.getNorth()]
        .map((n) => n.toFixed(5))
        .join(",");

      inflight.current?.abort();
      const ctrl = new AbortController();
      inflight.current = ctrl;

      try {
        const res = await fetch(`/api/pieces?bbox=${bbox}&limit=2000`, { signal: ctrl.signal });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const body = (await res.json()) as PiecesResponse;
        setTotal(body.total);
        setError(null);
        onPiecesChange?.(body.pieces);
      } catch (err) {
        if ((err as Error).name === "AbortError") return;
        setError("Could not reach the wall. Retrying as you move.");
      }
    },
    [onPiecesChange],
  );

  useEffect(() => {
    if (!container.current || map.current) return;
    let cancelled = false;

    (async () => {
      // maplibre-gl touches `window` at import time, so it cannot be imported
      // at module scope in a server-rendered tree.
      const maplibregl = await import("maplibre-gl");
      if (cancelled || !container.current) return;

      const m = new maplibregl.Map({
        container: container.current,
        style: buildMapStyle(),
        center: DEFAULT_VIEW.center,
        zoom: DEFAULT_VIEW.zoom,
        minZoom: DEFAULT_VIEW.minZoom,
        maxZoom: DEFAULT_VIEW.maxZoom,
        attributionControl: false,
        // The art is the content; tilting makes flat images hard to read.
        pitchWithRotate: false,
        dragRotate: false,
      });

      m.addControl(
        new maplibregl.AttributionControl({ compact: true, customAttribution: "© OpenStreetMap" }),
        "bottom-right",
      );
      m.addControl(new maplibregl.NavigationControl({ showCompass: false }), "bottom-right");
      m.addControl(
        new maplibregl.GeolocateControl({
          positionOptions: { enableHighAccuracy: true },
          trackUserLocation: true,
        }),
        "bottom-right",
      );

      // A malformed style makes `load` never fire and throws nothing — without this
      // the UI just sits on the loading state forever.
      m.on("error", (e) => {
        console.error("[map]", e.error?.message ?? e);
        setError("The map style failed to load.");
      });

      const reveal = () => {
        if (cancelled) return;
        setReady(true);
        void load(m);
      };
      m.on("load", reveal);
      // `load` can fail to fire if any part of the style stalls. Never let that
      // leave the user staring at a blank overlay — reveal the map regardless.
      const ro = new ResizeObserver(() => m.resize());
      ro.observe(container.current);
      resizeObs.current = ro;

      revealTimerRef.current = setTimeout(reveal, 4000);
      m.once("load", () => clearTimeout(revealTimerRef.current));
      m.on("moveend", () => void load(m));

      map.current = m;
    })();

    return () => {
      cancelled = true;
      clearTimeout(revealTimerRef.current);
      resizeObs.current?.disconnect();
      inflight.current?.abort();
      map.current?.remove();
      map.current = null;
    };
  }, [load]);

  return (
    <div className="relative h-dvh w-full" style={{ background: palette.ink }}>
      {/* Inline positioning is deliberate: maplibre-gl.css sets
          `.maplibregl-map { position: relative }` on this element, which overrides the
          Tailwind `absolute` utility and collapses it to height 0. */}
      <div ref={container} style={{ position: "absolute", inset: 0 }} />

      {!ready && (
        <div
          className="pointer-events-none absolute inset-0 grid place-items-center"
          style={{ background: palette.ink }}
        >
          <p className="text-sm tracking-widest uppercase" style={{ color: palette.textMuted }}>
            Finding the wall…
          </p>
        </div>
      )}

      {ready && total === 0 && (
        <div className="pointer-events-none absolute inset-0 grid place-items-center px-6">
          <div className="max-w-sm text-center">
            <p
              className="text-2xl font-semibold tracking-tight"
              style={{ color: palette.text }}
            >
              Nothing painted here yet.
            </p>
            <p className="mt-2 text-sm" style={{ color: palette.textMuted }}>
              Be the first to leave something on this corner.
            </p>
          </div>
        </div>
      )}

      {error && (
        <div
          className="absolute top-4 left-1/2 -translate-x-1/2 rounded-full px-4 py-2 text-xs"
          style={{ background: palette.accentDim, color: palette.text }}
        >
          {error}
        </div>
      )}
    </div>
  );
}
