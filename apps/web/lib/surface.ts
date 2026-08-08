import type { Piece } from "@got/shared";

/**
 * How a piece sits on the thing it was painted on.
 *
 * In AR the artwork is a quad anchored to a real surface, so it is seen in
 * perspective — foreshortened on a wall you are not square to, raked hard on the
 * ground. Rendering it as a flat sticker is the single biggest reason a preview
 * reads as "pasted" rather than "painted".
 *
 * We approximate that with a CSS 3D transform chosen from `surfaceType`, plus a
 * blend mode so the surface texture shows *through* the paint.
 */

export interface Projection {
  /** CSS transform for the artwork layer. */
  transform: string;
  /** Blend mode so brick, mortar and shadow read through the paint. */
  blend: string;
  /** Paint is never perfectly opaque on a rough surface. */
  opacity: number;
}

/** Stable pseudo-random in [-1, 1] from an id, so a piece never jitters between renders. */
function seeded(id: number, salt: number): number {
  const x = Math.sin(id * 12.9898 + salt * 78.233) * 43758.5453;
  return (x - Math.floor(x)) * 2 - 1;
}

export function projectionFor(piece: Piece): Projection {
  const yaw = seeded(piece.id, 1);
  const roll = seeded(piece.id, 3);

  switch (piece.surfaceType) {
    case "floor":
      // Looking down at the ground: rake hard away from the viewer.
      return {
        transform: `perspective(600px) rotateX(58deg) rotateZ(${roll * 12}deg) scale(1.05)`,
        blend: "multiply",
        opacity: 0.92,
      };
    case "ceiling":
      return {
        transform: `perspective(600px) rotateX(-52deg) rotateZ(${roll * 10}deg)`,
        blend: "multiply",
        opacity: 0.88,
      };
    case "table":
    case "seat":
      return {
        transform: `perspective(700px) rotateX(46deg) rotateZ(${roll * 14}deg)`,
        blend: "multiply",
        opacity: 0.9,
      };
    case "door":
    case "window":
      return {
        transform: `perspective(900px) rotateY(${yaw * 14}deg) rotateZ(${roll * 2}deg)`,
        blend: "hard-light",
        opacity: 0.95,
      };
    case "wall":
    case "none":
    case null:
    case undefined:
    default:
      // A wall you are rarely square to: a modest yaw reads as depth without
      // making the letters illegible.
      return {
        transform: `perspective(900px) rotateY(${yaw * 17}deg) rotateX(${roll * 4}deg) rotateZ(${roll * 3}deg)`,
        blend: "hard-light",
        opacity: 0.94,
      };
  }
}

/** Inline style string for a plain DOM element (markers are not React). */
export function projectionCss(piece: Piece): string {
  const p = projectionFor(piece);
  return `transform:${p.transform};mix-blend-mode:${p.blend};opacity:${p.opacity};`;
}
