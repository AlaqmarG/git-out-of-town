"use client";

import { type Piece, uploadUrl } from "@got/shared";
import { useEffect } from "react";
import { palette } from "@/lib/theme";

function when(iso: string): string {
  const mins = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.round(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.round(hrs / 24)}d ago`;
}

/**
 * Opening a piece is the moment this project is about, so it takes over the
 * screen rather than sitting in a corner. The artwork is the subject; the map
 * recedes behind a blur.
 */
export default function PieceDetail({
  piece,
  onClose,
}: {
  piece: Piece | null;
  onClose: () => void;
}) {
  useEffect(() => {
    if (!piece) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [piece, onClose]);

  if (!piece) return null;

  const hasScene = Boolean(piece.sceneImagePath);
  const art = piece.finalImagePath ?? piece.rawImagePath;

  return (
    <div
      className="got-lightbox fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-8"
      style={{ background: "rgba(6,6,9,0.82)", backdropFilter: "blur(14px)" }}
      onClick={onClose}
      role="dialog"
      aria-modal="true"
    >
      <div
        className="got-lightbox-panel relative w-full max-w-3xl overflow-hidden rounded-3xl"
        style={{ border: `1px solid ${palette.building}`, boxShadow: "0 30px 90px rgba(0,0,0,0.7)" }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="relative" style={{ aspectRatio: "4 / 3", background: palette.ink }}>
          {hasScene && (
            /* eslint-disable-next-line @next/next/no-img-element */
            <img
              src={uploadUrl(piece.sceneImagePath!)}
              alt="The place this was painted"
              className="absolute inset-0 h-full w-full object-cover"
            />
          )}

          {/* The scene photo already contains the art (it's the AR view snapshot),
              so only overlay the art when there is no scene photo. */}
          {!hasScene && (
            /* eslint-disable-next-line @next/next/no-img-element */
            <img
              src={uploadUrl(art)}
              alt=""
              className="absolute inset-0 m-auto"
              style={{ width: "76%" }}
            />
          )}

          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="absolute top-3 right-3 grid h-9 w-9 place-items-center rounded-full text-lg transition-transform hover:scale-110"
            style={{ background: "rgba(0,0,0,0.55)", color: palette.text, backdropFilter: "blur(6px)" }}
          >
            ×
          </button>

          {hasScene && (
            <span
              className="absolute top-3 left-3 rounded-full px-2.5 py-1 text-[10px] tracking-widest uppercase"
              style={{
                background: "rgba(0,0,0,0.55)",
                color: palette.textMuted,
                backdropFilter: "blur(6px)",
              }}
            >
              {piece.surfaceType && piece.surfaceType !== "none"
                ? `on a ${piece.surfaceType}`
                : "on the wall"}
            </span>
          )}
        </div>

        <div
          className="flex items-center gap-4 px-5 py-4"
          style={{ background: "rgba(14,14,18,0.96)" }}
        >
          <div className="min-w-0 flex-1">
            <p className="truncate text-base font-semibold" style={{ color: palette.text }}>
              {piece.kind === "sticker" ? "Sticker" : "Spray"}
              {piece.city ? ` · ${piece.city}` : ""}
            </p>
            <p className="mt-1 text-xs" style={{ color: palette.textMuted }}>
              {when(piece.createdAt)}
              {piece.strokeCount ? ` · ${piece.strokeCount} strokes` : ""}
              {piece.durationMs ? ` · ${Math.round(piece.durationMs / 1000)}s to paint` : ""}
              {piece.client === "ios" ? " · painted in AR" : ""}
            </p>
          </div>

          {piece.colors && piece.colors.length > 0 && (
            <div className="flex shrink-0 gap-1.5">
              {piece.colors.slice(0, 6).map((c, i) => (
                <span
                  key={i}
                  className="h-4 w-4 rounded-full"
                  style={{
                    background: `rgb(${c.r},${c.g},${c.b})`,
                    boxShadow: "0 0 0 1px rgba(255,255,255,0.15)",
                  }}
                />
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
