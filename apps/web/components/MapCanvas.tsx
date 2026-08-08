"use client";

import type { Piece, PiecesResponse } from "@got/shared";
import type { GeoJSONSource, Map as MapLibreMap, Marker } from "maplibre-gl";
import { useCallback, useEffect, useRef, useState } from "react";
import "maplibre-gl/dist/maplibre-gl.css";
import PieceDetail from "@/components/PieceDetail";
import { buildMapStyle } from "@/lib/map-style";
import {
  DENSITY_LAYERS,
  MARKER_MIN_ZOOM,
  createMarkerElement,
  densityLayerSpecs,
  toGeoJson,
} from "@/lib/markers";
import { DEFAULT_VIEW, palette } from "@/lib/theme";

export default function MapCanvas() {
  const container = useRef<HTMLDivElement>(null);
  const map = useRef<MapLibreMap | null>(null);
  const maplibre = useRef<typeof import("maplibre-gl") | null>(null);

  const [ready, setReady] = useState(false);
  const [total, setTotal] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<Piece | null>(null);

  const pieces = useRef<Piece[]>([]);
  const markers = useRef(new Map<number, Marker>());
  // Latest-wins: panning fast would otherwise let a slow early response
  // overwrite the results for where the user actually ended up.
  const inflight = useRef<AbortController | null>(null);
  const revealTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const resizeObs = useRef<ResizeObserver | null>(null);

  /**
   * Reconciles DOM markers against the viewport. Only pieces in view, and only
   * above MARKER_MIN_ZOOM — below that the clustered density glow takes over,
   * because hundreds of DOM nodes at city zoom is unreadable and slow.
   */
  const syncMarkers = useCallback(() => {
    const m = map.current;
    const gl = maplibre.current;
    if (!m || !gl) return;

    const showArt = m.getZoom() >= MARKER_MIN_ZOOM;
    const bounds = m.getBounds();
    const wanted = new Set<number>();

    if (showArt) {
      for (const piece of pieces.current) {
        if (!bounds.contains([piece.lng, piece.lat])) continue;
        wanted.add(piece.id);
        if (markers.current.has(piece.id)) continue;

        const el = createMarkerElement(piece);
        el.addEventListener("click", (ev) => {
          ev.stopPropagation();
          setSelected(piece);
        });
        markers.current.set(
          piece.id,
          new gl.Marker({ element: el, anchor: "center" })
            .setLngLat([piece.lng, piece.lat])
            .addTo(m),
        );
      }
    }

    for (const [id, marker] of markers.current) {
      if (!wanted.has(id)) {
        marker.remove();
        markers.current.delete(id);
      }
    }

    // The density layer is the inverse of the art view.
    for (const id of [DENSITY_LAYERS.glow, DENSITY_LAYERS.count, DENSITY_LAYERS.single]) {
      if (m.getLayer(id)) {
        m.setLayoutProperty(id, "visibility", showArt ? "none" : "visible");
      }
    }
  }, []);

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

        pieces.current = body.pieces;
        setTotal(body.total);
        setError(null);

        const src = m.getSource(DENSITY_LAYERS.source) as GeoJSONSource | undefined;
        src?.setData(toGeoJson(body.pieces));
        syncMarkers();
      } catch (err) {
        if ((err as Error).name === "AbortError") return;
        setError("Could not reach the wall. Retrying as you move.");
      }
    },
    [syncMarkers],
  );

  useEffect(() => {
    if (!container.current || map.current) return;
    let cancelled = false;

    (async () => {
      // maplibre-gl touches `window` at import time, so it cannot be imported
      // at module scope in a server-rendered tree.
      const gl = await import("maplibre-gl");
      if (cancelled || !container.current) return;
      maplibre.current = gl;

      const m = new gl.Map({
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

      // OSM data is ODbL — attribution is required, not optional. Kept, but
      // collapsed to a small "i" that expands on click (see globals.css).
      m.addControl(new gl.AttributionControl({ compact: true }), "bottom-right");
      m.addControl(new gl.NavigationControl({ showCompass: false }), "bottom-right");
      m.addControl(
        new gl.GeolocateControl({
          positionOptions: { enableHighAccuracy: true },
          trackUserLocation: true,
        }),
        "bottom-right",
      );

      // A malformed style makes `load` never fire and throws nothing.
      m.on("error", (e) => {
        console.error("[map]", e.error?.message ?? e);
        setError("The map style failed to load.");
      });

      const reveal = () => {
        if (cancelled) return;
        setReady(true);
        void load(m);
      };

      m.on("load", () => {
        if (cancelled) return;
        m.addSource(DENSITY_LAYERS.source, {
          type: "geojson",
          data: { type: "FeatureCollection", features: [] },
          cluster: true,
          clusterRadius: 60,
          clusterMaxZoom: MARKER_MIN_ZOOM,
        });
        for (const spec of densityLayerSpecs()) {
          m.addLayer(spec);
        }
        reveal();
      });

      // `load` can fail to fire if any part of the style stalls. Never let that
      // leave the user staring at a blank overlay — reveal the map regardless.
      revealTimerRef.current = setTimeout(reveal, 4000);
      m.once("load", () => clearTimeout(revealTimerRef.current));

      m.on("moveend", () => void load(m));
      m.on("zoomend", syncMarkers);
      m.on("click", () => setSelected(null));

      const ro = new ResizeObserver(() => m.resize());
      ro.observe(container.current);
      resizeObs.current = ro;

      map.current = m;
    })();

    // Captured now: by cleanup time `markers.current` may point at a different Map.
    const liveMarkers = markers.current;

    return () => {
      cancelled = true;
      clearTimeout(revealTimerRef.current);
      resizeObs.current?.disconnect();
      inflight.current?.abort();
      for (const marker of liveMarkers.values()) marker.remove();
      liveMarkers.clear();
      map.current?.remove();
      map.current = null;
    };
  }, [load, syncMarkers]);

  return (
    <div className="relative h-dvh w-full" style={{ background: palette.ink }}>
      {/* Inline positioning is deliberate: maplibre-gl.css sets
          `.maplibregl-map { position: relative }` on this element, which overrides
          the Tailwind `absolute` utility and collapses it to height 0. */}
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
            <p className="text-2xl font-semibold tracking-tight" style={{ color: palette.text }}>
              Nothing painted here yet.
            </p>
            <p className="mt-2 text-sm" style={{ color: palette.textMuted }}>
              Be the first to leave something on this corner.
            </p>
          </div>
        </div>
      )}

      {ready && total !== null && total > 0 && (
        <div
          className="pointer-events-none absolute top-4 left-4 rounded-full px-3 py-1.5 text-xs tracking-wide"
          style={{ background: "rgba(11,11,13,0.72)", color: palette.textMuted }}
        >
          <span style={{ color: palette.text, fontWeight: 600 }}>{total}</span>{" "}
          {total === 1 ? "piece" : "pieces"} here
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

      <PieceDetail piece={selected} onClose={() => setSelected(null)} />
    </div>
  );
}
