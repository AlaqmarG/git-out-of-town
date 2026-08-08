"use client";

import { type Piece, uploadUrl } from "@got/shared";
import { palette } from "@/lib/theme";

function when(iso: string): string {
  const mins = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.round(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.round(hrs / 24)}d ago`;
}

export default function PieceDetail({
  piece,
  onClose,
}: {
  piece: Piece | null;
  onClose: () => void;
}) {
  if (!piece) return null;

  return (
    <div
      className="absolute right-4 bottom-24 left-4 mx-auto max-w-sm rounded-2xl p-4 sm:left-auto"
      style={{ background: "rgba(17,17,22,0.94)", border: `1px solid ${palette.building}` }}
    >
      <div className="flex gap-3">
        {/* Deliberately a plain <img>: these are user uploads served straight off
            the volume by nginx. Routing them through next/image would put image
            bytes back through Node, which is exactly what we avoid. */}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={uploadUrl(piece.finalImagePath ?? piece.rawImagePath)}
          alt=""
          width={72}
          height={72}
          className="shrink-0 rounded-lg"
          style={{ background: palette.ink }}
        />
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold" style={{ color: palette.text }}>
            {piece.kind === "sticker" ? "Sticker" : "Spray"}
            {piece.city ? ` · ${piece.city}` : ""}
          </p>
          <p className="mt-0.5 text-xs" style={{ color: palette.textMuted }}>
            {when(piece.createdAt)}
            {piece.strokeCount ? ` · ${piece.strokeCount} strokes` : ""}
            {piece.client === "ios" ? " · painted in AR" : ""}
          </p>
          {piece.colors && piece.colors.length > 0 && (
            <div className="mt-2 flex gap-1">
              {piece.colors.slice(0, 6).map((c, i) => (
                <span
                  key={i}
                  className="h-3 w-3 rounded-full"
                  style={{ background: `rgb(${c.r},${c.g},${c.b})` }}
                />
              ))}
            </div>
          )}
        </div>
        <button
          type="button"
          onClick={onClose}
          aria-label="Close"
          className="h-6 w-6 shrink-0 rounded-full text-sm leading-none"
          style={{ color: palette.textMuted }}
        >
          ×
        </button>
      </div>
    </div>
  );
}
