# Reve prompts actually used — Git Out of Town

Tool: Reve web app (`https://app.reve.com`), Free plan, no API. Album: **Spray Paint Map Pin Sticker**
(auto-named by Reve), project "Alaqmar Gandhi's Project". Session date: 2026-08-08.
Model reported by Reve: `unified-v1/prod/20260807-032434`.

All generations ran with the HOUSE RULES below pasted into **Guidelines** (the 2026 UI's replacement
for `Custom` → `Custom instructions`), so every prompt below is implicitly prefixed by it.

## Guidelines / house rules (applied to every generation)

```
House style for this project, apply to every image unless I say otherwise:

Flat vector street-art illustration. Hand-cut screenprint / spray-stencil feel, NOT 3D, NOT
photorealistic, NOT glossy. Every subject has a single uniform heavy black outline in near-black
#0a0b0f. Flat fills only - absolutely no gradients, no drop shadows, no bevels, no lens flare, no
ambient occlusion.

Use ONLY these colours as fills: spray red #ff5230, cyan #35d0e8, amber #ffb021, violet #a277ff,
lime #9be855, hot pink #ff5fa8, bone white #e9ecf4, near-black #0a0b0f. Maximum three fill colours
per subject, plus the black outline.

Texture: light spray-can overspray speckle and a 1-2px misregistered ink offset, as if screenprinted
slightly off-plate. Subtle paint drips where they read naturally.

Silhouettes must be bold, chunky and readable when shrunk to 60 pixels wide. No thin lines, no fine
detail, no small interior shapes.

Do not add any text, letters, numbers, watermarks or signatures unless I explicitly ask for text.
```

---

## 1. Style anchor — produced `stickers/pin-drip-a.png`, `stickers/pin-drip-b.png`

Settings: aspect `1:1`, count `1` (Reve returned 2 variants anyway). 4096×4096.

```
A single die-cut street-art sticker of a map pin, drawn as a fat spray-paint blob with a wet drip
running off the bottom point. Bold chunky silhouette, one uniform heavy near-black #0a0b0f outline,
flat fill in spray red #ff5230 with a bone white #e9ecf4 highlight. Light overspray speckle and a
1px cyan #35d0e8 misregistered ink offset on the left edge. Sticker sits alone, centred, on a plain
flat mid-grey background with clear separation from the background. No text. No gradients. No 3D.
Must read clearly at 60 pixels wide.
```

Result: correct first time, no re-roll. This became the de facto house style anchor.

## 2. Sticker contact sheet 1 (symbols) — produced `stickers/sheet-1-symbols.png`

Settings: aspect `1:1`, count `1`. 4096×4096. One generation = nine stickers.

Deviation from the playbook: it opens with `Match the style of my got-house reference exactly.`
No `got-house` Reference was created (see notes), so that line was replaced with
`Match the house style exactly.` which leans on the Guidelines block instead.

```
A 3x3 grid contact sheet of nine separate die-cut street-art stickers, evenly spaced, each fully
isolated with generous empty space between them, on a plain flat mid-grey background. Match the
house style exactly. Nine subjects, reading left to right, top to bottom: 1. A three-point graffiti
crown, flat amber #ffb021, slightly tilted. 2. A spray paint can seen from the side, mid-spray, flat
spray red #ff5230 body with a bone white #e9ecf4 cap. 3. A fat hand-drawn arrow curving to the
right, flat cyan #35d0e8, with one paint drip. 4. A wonky five-point throw-up star, flat amber
#ffb021. 5. A dripping heart, flat hot pink #ff5fa8, three drips off the bottom. 6. A jagged
lightning bolt, flat amber #ffb021 with a spray red #ff5230 offset shadow. 7. A single wide-open
cartoon eye with a drip running from the lower lid, flat cyan #35d0e8 iris on bone white #e9ecf4.
8. A bold exclamation mark drawn as a wildstyle graffiti tag, flat spray red #ff5230. 9. A flame,
flat spray red #ff5230 core with an amber #ffb021 tip. Every sticker has the same uniform heavy
near-black #0a0b0f outline weight. Flat fills only, no gradients, no shading, no 3D. No text
anywhere. Each silhouette must stay readable at 60 pixels wide.
```

All nine cells landed. No re-roll.

## 3. Sticker contact sheet 2 (characters) — produced `stickers/sheet-2-characters.png`

Settings: aspect `1:1`, count `1`. 4096×4096.

```
A 3x3 grid contact sheet of nine separate die-cut street-art character stickers, evenly spaced, each
fully isolated with generous empty space between them, on a plain flat mid-grey background. Match
the house style exactly, same heavy outline weight as the previous sheet. Nine subjects, reading
left to right, top to bottom: 1. A one-eyed blob monster with stubby arms and a wide grin, flat lime
#9be855. 2. A city pigeon wearing a hoodie, chunky and cartoonish, flat violet #a277ff. 3. A raccoon
head, front on, mischievous, flat bone white #e9ecf4 with a near-black #0a0b0f mask and cyan #35d0e8
eyes. 4. A simplified cartoon skull, flat bone white #e9ecf4 with spray red #ff5230 eye sockets, one
gold tooth in amber #ffb021. 5. A friendly ghost blob with a smirk, flat hot pink #ff5fa8. 6. A
boombox seen straight on, flat lime #9be855 with near-black speakers. 7. A paint roller mid-stroke
leaving a thick band of paint, flat cyan #35d0e8. 8. A speech bubble shaped like an irregular paint
splat, flat violet #a277ff, empty inside. 9. Three wifi signal arcs drawn as spray-paint strokes
with drips, flat cyan #35d0e8. Every sticker has the same uniform heavy near-black #0a0b0f outline
weight. Flat fills only, no gradients, no shading, no 3D. No text anywhere. Each silhouette must
stay readable at 60 pixels wide.
```

All nine cells landed. No re-roll. Two cells drifted from the brief: the pigeon's hoodie did not
render, and cell 8 came out as a plain paint splat rather than a splat-shaped speech bubble.

## 4. Wordmark — produced `brand/wordmark-a.png`, `brand/wordmark-b.png`

Settings: aspect `16:9`, count `2`. 5376×3072.

Deviation: the playbook says "four stacked lines: GIT / OUT OF / TOWN", which is three lines. Changed
to "three stacked lines" so the instruction is not self-contradictory.

```
Ignore my custom instructions about avoiding text - this image is text. A graffiti logotype reading
exactly "GIT OUT OF TOWN" on three stacked lines: GIT / OUT OF / TOWN. Hand-painted street-art
lettering: fat, confident, slightly uneven marker-and-spray letterforms with a heavy uniform
near-black #0a0b0f outline and flat bone white #e9ecf4 fill. One spray red #ff5230 misregistered
offset sitting 4 pixels down and left behind the whole word. A few controlled paint drips falling
from the bottoms of the letters. Light overspray speckle. Spelling must be exactly GIT OUT OF TOWN -
check every letter. No extra words, no tagline, no artist signature, no background scenery. Plain
flat mid-grey background. The lockup must stay legible when shrunk to 200 pixels wide.
```

Both variants spell GIT OUT OF TOWN correctly, checked letter by letter. No re-roll.
`wordmark-a.png` has a soft red halo behind the letters; `wordmark-b.png` has the harder
misregistered red offset the brief asked for.

**Playbook Prompt 2 (one-line nav-bar wordmark) was NOT run.**

## 5. App icon — produced `brand/app-icon-a.png`, `brand/app-icon-b.png`

Settings: aspect `1:1`, count `2`. 4096×4096.

```
An app icon. A single fat spray-paint map pin, front on, dead centre, filling most of the frame,
flat spray red #ff5230 with a heavy near-black #0a0b0f outline and one wet drip running off the
bottom point. Behind it, a flat near-black #0a0b0f background with a very subtle darker #15171e
concrete texture and two faint cyan #35d0e8 spray marks in the corners. Bold, simple, high contrast.
No text. No gradients. Must remain instantly recognisable at 40 pixels.
```

No re-roll.

---

## Not run this session

Playbook Prompt 2 (one-line wordmark), Prompt 4 (landing hero), Prompt 5 (empty state),
Prompt 6 (404), Prompt 7 (OG image). Energy was still available; these were deferred rather than
blocked.

## Notes for anyone repeating this

- The 2026 Reve UI has no `Remove BG` control and no `Custom` menu. The equivalents are the
  **Guidelines** panel (sliders icon, top right of the Create panel) and an **Add effect** panel
  (image icon in the bottom toolbar) offering Textures / Light / Color presets plus `Saved`.
- No `got-house` Reference and no `got-print` saved Effect were created. The `...` menu on an image
  does offer **Add to reference**, so the Reference path exists if you want it later.
- `Count` resets to `Auto` between generations — re-set it each time or you may get 4 images.
- Output resolution is far higher than the playbook estimated: **4096×4096** for 1:1 and
  **5376×3072** for 16:9, not ~1024². A 3×3 sheet therefore yields stickers around 1300px square,
  so there is plenty of headroom for 512px exports.
- Reve rewrites hex codes into `<color hex="ff5230"/>` tags internally, which is why colour
  adherence was good but not exact — still hand-correct to the palette.
