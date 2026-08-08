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

  // The scene is the camera frame with the art burned in — the actual wall.
  // Without one (web contributions, older rows) fall back to the bare art.
  const hero = piece.sceneImagePath ?? piece.finalImagePath ?? piece.rawImagePath;
  const hasScene = Boolean(piece.sceneImagePath);

  return (
    <div
      className="absolute right-3 bottom-3 left-3 mx-auto max-w-md overflow-hidden rounded-2xl sm:left-auto"
      style={{
        background: "rgba(14,14,18,0.96)",
        border: `1px solid ${palette.building}`,
        boxShadow: "0 12px 40px rgba(0,0,0,0.6)",
      }}
    >
      <div className="relative">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={uploadUrl(hero)}
          alt=""
          className="block w-full"
          style={{
            aspectRatio: "4 / 3",
            objectFit: hasScene ? "cover" : "contain",
            background: palette.ink,
          }}
        />

        {hasScene && (
          <span
            className="absolute top-2 left-2 rounded-full px-2 py-1 text-[10px] tracking-widest uppercase"
            style={{ background: "rgba(0,0,0,0.6)", color: palette.textMuted }}
          >
            On the wall
          </span>
        )}

        <button
          type="button"
          onClick={onClose}
          aria-label="Close"
          className="absolute top-2 right-2 grid h-7 w-7 place-items-center rounded-full text-sm"
          style={{ background: "rgba(0,0,0,0.6)", color: palette.text }}
        >
          ×
        </button>
      </div>

      <div className="flex items-center gap-3 px-4 py-3">
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold" style={{ color: palette.text }}>
            {piece.kind === "sticker" ? "Sticker" : "Spray"}
            {piece.city ? ` · ${piece.city}` : ""}
          </p>
          <p className="mt-0.5 text-xs" style={{ color: palette.textMuted }}>
            {when(piece.createdAt)}
            {piece.strokeCount ? ` · ${piece.strokeCount} strokes` : ""}
            {piece.client === "ios" ? " · painted in AR" : ""}
            {piece.surfaceType ? ` · on a ${piece.surfaceType}` : ""}
          </p>
        </div>

        {piece.colors && piece.colors.length > 0 && (
          <div className="flex shrink-0 gap-1">
            {piece.colors.slice(0, 6).map((c, i) => (
              <span
                key={i}
                className="h-3.5 w-3.5 rounded-full"
                style={{ background: `rgb(${c.r},${c.g},${c.b})` }}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
