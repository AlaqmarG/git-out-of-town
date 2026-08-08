/**
 * A bold, slightly angular graffiti alphabet.
 *
 * Each glyph is a list of strokes; each stroke is a polyline in a unit box
 * (x right, y down, both 0..1). Rendered with thick round caps they read as
 * bubble/throw-up letterforms — the thing that makes a piece look like graffiti
 * rather than a scribble.
 *
 * Kept as polylines rather than a real font because we have no font rasteriser
 * available here, and letterforms only need to be recognisable at marker size.
 */

const G = {
  A: [[[0.08, 1], [0.5, 0], [0.92, 1]], [[0.24, 0.62], [0.76, 0.62]]],
  B: [[[0.14, 0], [0.14, 1]], [[0.14, 0], [0.66, 0.06], [0.74, 0.26], [0.62, 0.48], [0.14, 0.5]],
      [[0.14, 0.5], [0.7, 0.54], [0.82, 0.76], [0.68, 0.96], [0.14, 1]]],
  C: [[[0.86, 0.16], [0.6, 0], [0.28, 0.06], [0.1, 0.34], [0.1, 0.68], [0.3, 0.95], [0.62, 1], [0.88, 0.84]]],
  D: [[[0.16, 0], [0.16, 1]], [[0.16, 0], [0.62, 0.06], [0.84, 0.36], [0.84, 0.66], [0.6, 0.95], [0.16, 1]]],
  E: [[[0.84, 0.02], [0.16, 0.02], [0.16, 1], [0.84, 1]], [[0.16, 0.5], [0.68, 0.5]]],
  F: [[[0.84, 0.02], [0.16, 0.02], [0.16, 1]], [[0.16, 0.5], [0.68, 0.5]]],
  G: [[[0.86, 0.16], [0.58, 0], [0.26, 0.08], [0.1, 0.36], [0.12, 0.7], [0.34, 0.96], [0.66, 0.98], [0.86, 0.8], [0.86, 0.56], [0.54, 0.56]]],
  H: [[[0.16, 0], [0.16, 1]], [[0.84, 0], [0.84, 1]], [[0.16, 0.52], [0.84, 0.52]]],
  I: [[[0.5, 0], [0.5, 1]], [[0.24, 0.02], [0.76, 0.02]], [[0.24, 1], [0.76, 1]]],
  J: [[[0.76, 0], [0.76, 0.74], [0.58, 0.98], [0.28, 0.94], [0.16, 0.72]]],
  K: [[[0.16, 0], [0.16, 1]], [[0.84, 0], [0.16, 0.54]], [[0.36, 0.42], [0.86, 1]]],
  L: [[[0.2, 0], [0.2, 1], [0.84, 1]]],
  M: [[[0.08, 1], [0.14, 0], [0.5, 0.62], [0.86, 0], [0.92, 1]]],
  N: [[[0.14, 1], [0.14, 0], [0.86, 1], [0.86, 0]]],
  O: [[[0.5, 0], [0.16, 0.2], [0.1, 0.6], [0.34, 0.96], [0.7, 0.96], [0.9, 0.6], [0.84, 0.2], [0.5, 0]]],
  P: [[[0.16, 1], [0.16, 0], [0.68, 0.06], [0.82, 0.28], [0.68, 0.5], [0.16, 0.54]]],
  Q: [[[0.5, 0], [0.16, 0.2], [0.1, 0.6], [0.34, 0.96], [0.7, 0.96], [0.9, 0.6], [0.84, 0.2], [0.5, 0]], [[0.62, 0.72], [0.94, 1.04]]],
  R: [[[0.16, 1], [0.16, 0], [0.68, 0.06], [0.82, 0.28], [0.68, 0.5], [0.16, 0.54]], [[0.44, 0.54], [0.86, 1]]],
  S: [[[0.86, 0.14], [0.56, 0], [0.24, 0.06], [0.14, 0.28], [0.34, 0.46], [0.66, 0.54], [0.86, 0.72], [0.74, 0.94], [0.4, 1], [0.12, 0.86]]],
  T: [[[0.08, 0.02], [0.92, 0.02]], [[0.5, 0.02], [0.5, 1]]],
  U: [[[0.14, 0], [0.14, 0.7], [0.36, 0.96], [0.66, 0.96], [0.86, 0.7], [0.86, 0]]],
  V: [[[0.1, 0], [0.5, 1], [0.9, 0]]],
  W: [[[0.06, 0], [0.24, 1], [0.5, 0.36], [0.76, 1], [0.94, 0]]],
  X: [[[0.12, 0], [0.88, 1]], [[0.88, 0], [0.12, 1]]],
  Y: [[[0.12, 0], [0.5, 0.5], [0.88, 0]], [[0.5, 0.5], [0.5, 1]]],
  Z: [[[0.12, 0.02], [0.88, 0.02], [0.14, 1], [0.9, 1]]],
  0: [[[0.5, 0], [0.16, 0.24], [0.16, 0.76], [0.5, 1], [0.84, 0.76], [0.84, 0.24], [0.5, 0]]],
  1: [[[0.28, 0.2], [0.52, 0], [0.52, 1]], [[0.28, 1], [0.78, 1]]],
  2: [[[0.14, 0.2], [0.44, 0], [0.78, 0.12], [0.8, 0.4], [0.16, 1], [0.86, 1]]],
  3: [[[0.16, 0.06], [0.62, 0], [0.8, 0.2], [0.6, 0.46], [0.28, 0.48]], [[0.6, 0.46], [0.84, 0.68], [0.66, 0.96], [0.2, 0.96]]],
  4: [[[0.66, 0], [0.12, 0.66], [0.9, 0.66]], [[0.66, 0.3], [0.66, 1]]],
  5: [[[0.84, 0.02], [0.22, 0.02], [0.18, 0.44], [0.56, 0.4], [0.84, 0.6], [0.7, 0.94], [0.22, 0.98]]],
  6: [[[0.8, 0.04], [0.38, 0.1], [0.18, 0.5], [0.2, 0.84], [0.5, 1], [0.78, 0.86], [0.76, 0.6], [0.44, 0.5], [0.2, 0.6]]],
  7: [[[0.12, 0.02], [0.88, 0.02], [0.42, 1]]],
  8: [[[0.5, 0.46], [0.22, 0.3], [0.3, 0.06], [0.66, 0.04], [0.76, 0.28], [0.5, 0.46], [0.2, 0.66], [0.28, 0.94], [0.68, 0.96], [0.82, 0.7], [0.5, 0.46]]],
  9: [[[0.2, 0.96], [0.62, 0.9], [0.82, 0.5], [0.8, 0.16], [0.5, 0], [0.22, 0.14], [0.24, 0.4], [0.56, 0.5], [0.8, 0.4]]],
};

/** Words that read like tags — short, punchy, mostly local. */
export const WORDS = [
  "STACKT", "TDOT", "6IX", "GOT", "WALL", "FRESH", "KING", "BOLD", "CREW",
  "RIOT", "NEON", "DUSK", "HALT", "VOID", "ECHO", "RUST", "ZINE", "FLUX",
];

export function randomWord() {
  return WORDS[Math.floor(Math.random() * WORDS.length)];
}

/**
 * Lays a word out across a canvas box, returning absolute polylines.
 * Letters overlap slightly and sit on a gentle arc — real tags are rarely level.
 */
export function layoutWord(word, boxW, boxH, { overlap = 0.14, arc = 0.1 } = {}) {
  const chars = [...word.toUpperCase()].filter((c) => G[c]);
  if (chars.length === 0) return { strokes: [], height: 0 };

  const advance = 1 - overlap;
  const totalUnits = chars.length * advance + overlap;
  // Fit width, but never so tall it overflows the box.
  const unit = Math.min(boxW / totalUnits, boxH / 1.5);
  const glyphH = unit * 1.25;

  const startX = (boxW - unit * totalUnits) / 2;
  const baseY = (boxH - glyphH) / 2;

  const strokes = [];
  chars.forEach((c, i) => {
    const ox = startX + i * unit * advance;
    // Arc + per-letter jitter so it never looks typeset.
    const t = chars.length === 1 ? 0 : i / (chars.length - 1) - 0.5;
    const oy = baseY + t * t * arc * glyphH * 4 - arc * glyphH + (Math.random() - 0.5) * glyphH * 0.08;
    const tilt = (Math.random() - 0.5) * 0.14;

    for (const stroke of G[c]) {
      strokes.push(
        stroke.map(([x, y]) => {
          // Shear each glyph slightly for that leaning graffiti stance.
          const sx = x + (0.5 - y) * tilt;
          return [ox + sx * unit, oy + y * glyphH];
        }),
      );
    }
  });

  return { strokes, height: glyphH };
}
