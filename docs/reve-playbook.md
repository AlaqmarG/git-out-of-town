# Reve Playbook — sticker pack + brand kit

Issue #5. Web app only (`https://app.reve.com`), Free plan, no API. ~60 minutes.

Everything below assumes you have never opened Reve before and are not a designer. Follow it in
order. If you run out of time at minute 30 you will still have the assets that matter.

**How to read the UI instructions.** Every button name in `code` was verified against Reve's own
help centre (August 2026). Anything I could not verify is flagged **[unverified]** — look for the
nearest equivalent rather than hunting for the exact string. See "What I could not verify" at the
bottom.

---

## 0. The one idea that makes this work

Do **not** generate 20 stickers one at a time. Generate two **contact sheets** — a single image
containing a 3×3 grid of nine stickers — and hand-cut them apart.

Three reasons, all of them worth points:

1. **Consistency is free.** Nine stickers drawn in one pass by one model share line weight,
   palette and personality automatically. Twenty separate generations do not, no matter how good
   your prompt is. This is the single biggest thing separating "a pack" from "20 unrelated AI
   images".
2. **Energy.** The Free plan gives you a small daily allowance. Two generations instead of twenty
   is the difference between finishing and running dry.
3. **It forces hand-editing.** You physically have to cut, crop and centre each one. That *is* the
   craft the judging doc is asking for, and it happens as a side effect of the workflow.

Generate individually only for the hero assets (wordmark, app icon) and for any sheet cell that
comes out wrong.

---

## 1. Setup — 5 min

1. Open `https://app.reve.com`.
2. In the **left-hand menu**, click **`+`**. This creates a new album and drops you into its chat
   interface. Click the album name at the top and choose **`Rename album`** → `Git Out of Town`.
   Everything you make lands here, which makes the export sweep at the end fast.
3. In the chat interface click **`Custom`**. You get a small menu with (verified) **`Aspect ratio`**,
   **`Count`**, **`Custom instructions`**, **`Use attachments`**.
   - **`Count`** → **`2`**. It defaults to 4. Four variants per prompt burns energy you do not have.
     Bump to 4 only for the wordmark, where you actually want options.
   - **`Aspect ratio`** → **`1:1`**. Stickers, sheets and the app icon are all square. Reve's web
     app only offers `16:9 3:2 4:3 1:1 3:4 2:3 9:16` — there is no 1.91:1, so the OG image gets
     generated at 16:9 and cropped (§6).
   - **`Custom instructions`** → paste the HOUSE RULES block below. This applies to every generation
     without you retyping it, and it is the mechanism that keeps the pack coherent.

### HOUSE RULES — paste into `Custom` → `Custom instructions`

```
House style for this project, apply to every image unless I say otherwise:

Flat vector street-art illustration. Hand-cut screenprint / spray-stencil feel, NOT 3D,
NOT photorealistic, NOT glossy. Every subject has a single uniform heavy black outline
in near-black #0a0b0f. Flat fills only — absolutely no gradients, no drop shadows, no
bevels, no lens flare, no ambient occlusion.

Use ONLY these colours as fills:
  spray red    #ff5230
  cyan         #35d0e8
  amber        #ffb021
  violet       #a277ff
  lime         #9be855
  hot pink     #ff5fa8
  bone white   #e9ecf4
  near-black   #0a0b0f
Maximum three fill colours per subject, plus the black outline.

Texture: light spray-can overspray speckle and a 1-2px misregistered ink offset, as if
screenprinted slightly off-plate. Subtle paint drips where they read naturally.

Silhouettes must be bold, chunky and readable when shrunk to 60 pixels wide. No thin
lines, no fine detail, no small interior shapes.

Do not add any text, letters, numbers, watermarks or signatures unless I explicitly ask
for text.
```

**Remember to clear or amend this** before generating the landing hero and 404, which are scenes
rather than stickers. Prompts 20–22 below say so inline.

**Time check: 5 min in.**

---

## 2. Style anchor + saved Effect — 7 min

You need one image you love before you make eighteen. This step is also where you create the two
reusable consistency mechanisms.

1. Paste **Prompt 0** (below) into the chat box and press the send arrow.
2. Look at the two results. If the line weight is thin, or it looks 3D, or it has a gradient — say
   so in plain English in the chat and send again. Reve is conversational; you do not need to
   rewrite the prompt. Good corrective phrases:
   - `Thicker, more uniform black outline. Chunkier silhouette.`
   - `Flatter. Remove all shading and gradients — pure flat colour fills.`
   - `More overspray speckle, more screenprint misregistration.`
3. When one is right, do the two things that make it reusable:

   **(a) Save it as a named Reference.** References are Reve's mechanism for "make new things look
   like this thing". Per Reve's docs they carry *style, character and composition* across
   generations. Add the winning image to a Reference named **`got-house`** with a description like
   `Git Out of Town sticker house style: flat screenprint street art, heavy black outline, six-colour
   spray palette`. You manage these from the **`Reference`** tab in the **Work panel** (select a
   Reference → **`Edit`** top right → **`Save`**). **[unverified: the exact click path for *creating*
   a new Reference from a generated image — it is roughly "select the image → add to a Reference", or
   upload the downloaded PNG into a new Reference from the Reference tab. Reve's help article on
   References only documents the *edit* path in text; the create path is in their video.]**

   Once `got-house` exists, prepend to any later prompt:
   `Match the style of my got-house reference exactly.`

   **(b) Save an Effect preset.** Open the image in **Editor** view, click **`Add Effect`**, and pick
   from the built-in categories **`Texture`**, **`Light`**, **`Color`**. Stack these three, adjust the
   sliders, then **`Apply`**:
   - a **Texture** effect — grain / halftone / paper, dialled to roughly 25–40%. This is your print
     texture.
   - a **Color** effect — push contrast up and saturation *down slightly*, so the six spray colours
     stay punchy but do not glow.
   - optionally a second **Texture** pass at ~15% for edge wear.

   Save the stack as a custom effect named **`got-print`**. Reve's docs: custom effects are saved by
   giving them a name, and reappear under **`Add effect`** → **`Saved`** tab. Applying `got-print` to
   every asset at the end is what makes the pack, the wordmark and the hero image feel like one
   object. **[unverified: whether custom-effect saving is available on the Free plan. If the save
   option is greyed out, fall back to writing the same three sliders down on paper and re-applying
   them by hand — tedious but identical output.]**

Also save a second Effect, **`got-wear`**, at roughly double the texture strength. You will use it
only on the 404 and empty state so those read as more beaten-up than the stickers.

**Time check: 12 min in.**

### Prompt 0 — style anchor (this is also sticker #1)

```
A single die-cut street-art sticker of a map pin, drawn as a fat spray-paint blob with a
wet drip running off the bottom point. Bold chunky silhouette, one uniform heavy
near-black #0a0b0f outline, flat fill in spray red #ff5230 with a bone white #e9ecf4
highlight. Light overspray speckle and a 1px cyan #35d0e8 misregistered ink offset on
the left edge. Sticker sits alone, centred, on a plain flat mid-grey background with
clear separation from the background. No text. No gradients. No 3D. Must read clearly
at 60 pixels wide.
```

---

## 3. The sticker sheets — 10 min

Two prompts, eighteen stickers. Paste **Prompt A**, then **Prompt B**. Each is one generation.

### Prompt A — symbols sheet (9 stickers)

```
Match the style of my got-house reference exactly.

A 3x3 grid contact sheet of nine separate die-cut street-art stickers, evenly spaced,
each fully isolated with generous empty space between them, on a plain flat mid-grey
background. Nine subjects, reading left to right, top to bottom:

1. A three-point graffiti crown, flat amber #ffb021, slightly tilted.
2. A spray paint can seen from the side, mid-spray, flat spray red #ff5230 body with a
   bone white #e9ecf4 cap.
3. A fat hand-drawn arrow curving to the right, flat cyan #35d0e8, with one paint drip.
4. A wonky five-point throw-up star, flat amber #ffb021.
5. A dripping heart, flat hot pink #ff5fa8, three drips off the bottom.
6. A jagged lightning bolt, flat amber #ffb021 with a spray red #ff5230 offset shadow.
7. A single wide-open cartoon eye with a drip running from the lower lid, flat cyan
   #35d0e8 iris on bone white #e9ecf4.
8. A bold exclamation mark drawn as a wildstyle graffiti tag, flat spray red #ff5230.
9. A flame, flat spray red #ff5230 core with an amber #ffb021 tip.

Every sticker has the same uniform heavy near-black #0a0b0f outline weight. Flat fills
only, no gradients, no shading, no 3D. No text anywhere. Each silhouette must stay
readable at 60 pixels wide.
```

### Prompt B — characters and objects sheet (9 stickers)

```
Match the style of my got-house reference exactly.

A 3x3 grid contact sheet of nine separate die-cut street-art character stickers, evenly
spaced, each fully isolated with generous empty space between them, on a plain flat
mid-grey background. Nine subjects, reading left to right, top to bottom:

1. A one-eyed blob monster with stubby arms and a wide grin, flat lime #9be855.
2. A city pigeon wearing a hoodie, chunky and cartoonish, flat violet #a277ff.
3. A raccoon head, front on, mischievous, flat bone white #e9ecf4 with a near-black
   #0a0b0f mask and cyan #35d0e8 eyes.
4. A simplified cartoon skull, flat bone white #e9ecf4 with spray red #ff5230 eye
   sockets, one gold tooth in amber #ffb021.
5. A friendly ghost blob with a smirk, flat hot pink #ff5fa8.
6. A boombox seen straight on, flat lime #9be855 with near-black speakers.
7. A paint roller mid-stroke leaving a thick band of paint, flat cyan #35d0e8.
8. A speech bubble shaped like an irregular paint splat, flat violet #a277ff, empty
   inside.
9. Three wifi signal arcs drawn as spray-paint strokes with drips, flat cyan #35d0e8.

Every sticker has the same uniform heavy near-black #0a0b0f outline weight. Flat fills
only, no gradients, no shading, no 3D. No text anywhere. Each silhouette must stay
readable at 60 pixels wide.
```

### If a cell comes out wrong

Do not regenerate the whole sheet. Two options, cheapest first:

- **Editor → `Select objects`** — pick the bad sticker and edit its object-level prompt, then
  **`Apply`**. Verified path: open in **Editor**, choose **`Select objects`** from the tool menu
  above the chat box.
- **Editor → `Spotlight`** — drag over the bad cell, describe the fix, **`Apply`** (bottom right).

Only if both fail, regenerate that one sticker on its own using its line from the sheet prompt,
prefixed with `Match the style of my got-house reference exactly.` and followed by
`Single sticker, centred, on a plain flat mid-grey background.`

**Time check: 22 min in.**

---

## 4. The wordmark — 5 min

Reve's in-image text rendering is its standout capability. Set **`Count`** → **`4`** for this one and
**`Aspect ratio`** → **`16:9`**. Pick the best of four; text is the one place where variants pay for
themselves.

### Prompt 1 — primary wordmark

```
Ignore my custom instructions about avoiding text — this image is text.

A graffiti logotype reading exactly "GIT OUT OF TOWN" on four stacked lines:
GIT / OUT OF / TOWN. Hand-painted street-art lettering: fat, confident, slightly uneven
marker-and-spray letterforms with a heavy uniform near-black #0a0b0f outline and flat
bone white #e9ecf4 fill. One spray red #ff5230 misregistered offset sitting 4 pixels
down and left behind the whole word. A few controlled paint drips falling from the
bottoms of the letters. Light overspray speckle.

Spelling must be exactly GIT OUT OF TOWN — check every letter. No extra words, no
tagline, no artist signature, no background scenery. Plain flat mid-grey background.
The lockup must stay legible when shrunk to 200 pixels wide.
```

**Check the spelling character by character** before you accept it. This is the number one way AI
wordmarks fail and the number one thing a judge will spot.

If the letterforms are right but a letter is malformed, fix it with **Editor → `Spotlight`** over
that letter rather than regenerating.

### Prompt 2 — one-line wordmark variant (nav bar / OG use)

```
Ignore my custom instructions about avoiding text — this image is text.

The same graffiti logotype reading exactly "GIT OUT OF TOWN" but set on ONE horizontal
line, more compressed and condensed, built for a narrow website header strip. Heavy
uniform near-black #0a0b0f outline, flat bone white #e9ecf4 fill, spray red #ff5230
offset behind. Minimal drips. Plain flat mid-grey background. Legible at 300 pixels
wide. Spelling must be exactly GIT OUT OF TOWN.
```

**Time check: 27 min in.**

---

## 5. App icon — 3 min

`Aspect ratio` → `1:1`, `Count` → `2`.

### Prompt 3 — app icon

```
An app icon. A single fat spray-paint map pin, front on, dead centre, filling most of
the frame, flat spray red #ff5230 with a heavy near-black #0a0b0f outline and one wet
drip running off the bottom point. Behind it, a flat near-black #0a0b0f background with
a very subtle darker #15171e concrete texture and two faint cyan #35d0e8 spray marks in
the corners. Bold, simple, high contrast. No text. No gradients. Must remain instantly
recognisable at 40 pixels.
```

The favicon is **not a separate generation** — crop this one down and export at 32px. If the pin
does not survive 32px, delete the corner spray marks in your editor rather than reprompting.

> **If you are at 30 minutes and have to stop: stop here.** You have the pack, the wordmark and the
> icon. Skip to §6 and §7, ship those, and treat §8 as optional.

---

## 6. Getting files out — 8 min

### Transparency

Verified path: open the image in the **Editor** and click **`Remove BG`** in the **upper right**.
Reve isolates the subject on a transparent background and **saves a new transparent version into the
same album**, leaving your original intact.

- Run `Remove BG` on **each contact sheet as a whole**. All nine stickers become free-floating
  cutouts in one operation; you cut them apart afterwards. This is why the prompts insist on
  "generous empty space between them" and a plain background — Reve's own docs warn background
  removal needs a clear subject.
- Run it on the wordmark too.
- Do **not** run it on the app icon, hero, 404 or OG image — those want their dark background.

### Download

Select the image and click the **download** button; on desktop it lands in your downloads folder.
**Reve downloads PNG only**, which is exactly what you want — transparency survives.

### Resolution and aspect ratio

Reve's help centre gives standard resolution as ~1.5 megapixels: **1:1 → 1024×1024**, 16:9 →
1536×864, 3:2 → 1536×1024. A 3×3 sheet at 1024² therefore yields stickers around **340px square**.
That is fine — they display at 60px in the picker and rarely above 256px on the map. If one hero
sticker looks soft at full size, tell Reve `upscale this image` in chat before cutting.

**[unverified / contradictory: a different Reve help article claims "Reve automatically generates
all images in 4K by default". The resolution table above is more specific and more recent-looking,
so plan for 1024² and be pleasantly surprised if you get more. Check the actual pixel dimensions of
your first download before you commit to a cutting grid.]**

Target sizes to export at:

| Asset | Generate at | Export as |
|---|---|---|
| Sticker (each) | from 1:1 sheet | 512×512 PNG, transparent |
| Wordmark | 16:9 | ~1600px wide PNG, transparent |
| App icon (iOS) | 1:1 | 1024×1024 PNG, **opaque** (iOS rejects alpha in app icons) |
| Favicon | crop of app icon | 32×32 ICO + 180×180 PNG |
| Landing hero | 16:9 | 2400×1350 PNG or JPG |
| Empty state | 1:1 | 800×800 PNG, transparent |
| 404 | 3:2 | 1600×1067 PNG |
| OG image | 16:9 | crop to **1200×630** |

### Cutting the sheets

Use **Photopea** (`photopea.com`, free, browser, no install, reads PSD and PNG) or macOS Preview.
Per sticker: rectangular-marquee the cutout → `Image → Crop` → trim transparent edges → resize the
longest side to 512 → export PNG. Roughly 20 seconds each once you have a rhythm.

Name them kebab-case, matching the sheet order:

```
pin-drip  crown  spray-can  arrow  star  heart  bolt  eye  bang  flame
blob  pigeon  raccoon  skull  ghost  boombox  roller  splat  signal
```

### Where the files go

**Web** — `apps/web/public/stickers/<name>.png`, served at `/stickers/<name>.png`.

Brand assets use Next.js App Router file conventions, so no config is needed — drop the file in
`apps/web/app/` with the reserved name and Next wires up the tag:

```
apps/web/app/favicon.ico            32x32 (a favicon.ico already exists — replace it)
apps/web/app/icon.png               512x512
apps/web/app/apple-icon.png         180x180
apps/web/app/opengraph-image.png    1200x630
apps/web/public/brand/wordmark.png
apps/web/public/brand/wordmark-inline.png
apps/web/public/brand/empty-state.png
apps/web/public/brand/404.png
apps/web/public/brand/hero.png
```

**iOS** — `apps/ios/ios/Assets.xcassets/`. It currently holds only `AppIcon.appiconset` and
`AccentColor.colorset`.

- App icon: open `Assets.xcassets` in Xcode, select `AppIcon`, drag the **1024×1024 opaque** PNG
  into the single well. Do not hand-edit `Contents.json`.
- Stickers: in Xcode, right-click in the asset catalog → **New Folder** → name it `Stickers`, then
  drag all 19 PNGs in at once. Xcode creates one image set per file with the filename as the asset
  name, so `pin-drip.png` becomes `Image("pin-drip")` in SwiftUI. Set each set's **Render As** to
  *Original Image* — the default *Template* mode would flatten your colours to a single tint, which
  would silently destroy the entire pack.
- Keep the asset names byte-identical to the web filenames so `packages/shared` can carry one
  sticker id that resolves in both clients.

**Time check: 35 min in** (or ~43 if you did the full run).

---

## 7. Hand-edit checklist — 8 min

This is the part the rubric is actually scoring. Do all of it; none of it takes long.

1. **Crop tight.** Every cutout should have its ink touching the canvas edge on at least two sides.
   A centred subject floating in transparent margin is the classic AI-export tell, and it is also
   why stickers look tiny in a 60px picker cell. *(Highest value per second spent.)*
2. **Recolour to our exact hexes.** Reve will drift — you will get `#f4552f` where you asked for
   `#ff5230`. In Photopea: `Image → Adjustments → Replace Color`, eyedrop the fill, set the result
   to the exact palette hex. Do this for all 19. When the stickers, the map accent and the charts
   share literally the same six values, the app reads as designed rather than assembled.
3. **Composite at least three.** Put the crown on the raccoon. Put the pin through the heart. Stack
   the bolt behind the boombox. Two-layer paste, five seconds each — and now demonstrably no single
   generation produced that asset.
4. **Break the symmetry.** Rotate each sticker 3–8° at random, and nudge one interior element
   off-centre. Perfect axial alignment is a machine signature; real stickers are slapped on crooked.
5. **Add wear.** A 5–8% monochrome noise layer over each sticker, plus a 1px erosion on the outline
   so the edge is not mathematically smooth. If `got-print` already did this in Reve, skip it — do
   not double up or they turn to mush.
6. **Purge stray marks.** Sheets often smuggle in a half-letter, a signature squiggle, or a
   fragment of a neighbouring cell. Erase them. A judge zooming in on a phantom glyph is a
   preventable loss.
7. **Contact-sheet your own work.** Lay all 19 finished PNGs on one canvas at 60px and look at it.
   Anything that turns to mush, that is too dark against `#0a0b0f`, or that has visibly thinner
   outlines than its neighbours — fix or drop it. Twelve stickers that read is a better pack than
   twenty where six are illegible, and the issue's floor is 12.
8. **Set the map marker.** Whichever sticker ends up as the default map pin should be re-exported
   with a subtle `#ff5230` outer glow so it separates from `#0a0b0f`. That is one edit that will
   appear in every demo screenshot.

---

## 8. Remaining brand assets — 12 min

These are lower value than the pack. Do them only with time left over. Set **`Count`** → **`2`** and
change the aspect ratio per asset.

### Prompt 4 — landing hero (`16:9`)

```
Override my custom instructions for this image: this is a rendered scene, not a flat
sticker.

A night-time city alley wall shot straight on, near-black #0a0b0f concrete with subtle
#15171e texture, lit only by a cold streetlight from the left. Painted across the wall
in bright graffiti: a fat spray-paint map pin in #ff5230 with a wet drip, a cyan #35d0e8
arrow, and an amber #ffb021 three-point crown. The paint is the only saturated thing in
the frame — everything else is desaturated near-monochrome blue-black. Empty space in
the left third for a headline. Shallow perspective, no people, no readable text
anywhere.
```

Then in **Editor**, apply your saved **`got-print`** effect so it belongs to the same family. Place
the wordmark PNG over the empty left third in Photopea — do not ask Reve to put the text in the
scene; composited-by-hand text is both more accurate and more obviously deliberate.

### Prompt 5 — empty state (`1:1`, transparent)

```
A single die-cut street-art sticker: a spray can lying on its side, empty, with a small
puff of dust and one sad drip. Flat bone white #e9ecf4 body with spray red #ff5230
label, heavy uniform near-black #0a0b0f outline. Slightly melancholy but still cheeky.
Plain flat mid-grey background, isolated subject, no text. Must read at 200 pixels.
```

Run `Remove BG`. Pair it in the UI with typed copy like `Nothing painted here yet.` — set that in
your own type, not in the image.

### Prompt 6 — 404 (`3:2`)

```
Override my custom instructions for this image: this is a rendered scene.

A peeling, half-torn street poster on a near-black #0a0b0f concrete wall, shot straight
on. The poster is bone white #e9ecf4 and mostly ripped away, with only fragments of
spray red #ff5230 paint left on it. Damp, weathered, torn edges, staple marks, a little
overspray. Near-monochrome blue-black scene, the red is the only saturated colour.
Centre of the frame is empty wall so text can be placed there later. No readable text in
the image.
```

Apply the heavier **`got-wear`** effect. Composite `404` and your message in your own type.

### Prompt 7 — OG image (`16:9`, crop to 1200×630)

```
Override my custom instructions for this image: this is a rendered scene.

A wide night-time establishing shot of a dark city skyline in near-monochrome blue-black
#0a0b0f and #15171e, viewed slightly from above like a map tilting into a horizon.
Scattered across it, a handful of glowing spray-paint marks in #ff5230, #35d0e8 and
#ffb021 sitting on the buildings like pins on a map — small, sparse, deliberate. Wide
cinematic composition with clear empty space in the lower third. No text, no people, no
logos.
```

Crop 16:9 → **1200×630** (trim equally top and bottom), composite the one-line wordmark from Prompt
2 into the lower third, save as `apps/web/app/opengraph-image.png`.

**Time check: ~60 min.**

---

## Time budget at a glance

| # | Step | Min | Cumulative | Drop if short? |
|---|---|---|---|---|
| 1 | Setup: album, Count, aspect ratio, HOUSE RULES | 5 | 5 | No |
| 2 | Style anchor + `got-house` reference + `got-print` effect | 7 | 12 | No |
| 3 | Two sticker sheets (18 stickers) | 10 | 22 | No |
| 4 | Wordmark ×2 | 5 | 27 | No |
| 5 | App icon | 3 | 30 | No |
| 6 | Remove BG, download, cut, file into repo | 8 | 38 | No |
| 7 | Hand-edit checklist | 8 | 46 | Items 1–3 never |
| 8 | Hero / empty state / 404 / OG | 12 | 58 | **Yes — all four** |

**If you must stop at 30 minutes**, you have 18 stickers, a wordmark and an app icon still sitting
in Reve. Spend the next 8 minutes on §6 and 4 minutes on hand-edit items 1, 2 and 3 only. That is a
shippable, coherent, defensibly hand-crafted identity.

---

## Consistency mechanisms — the short version

Four layers, cheapest first. Use all four; they compound.

| Mechanism | Where | What it locks |
|---|---|---|
| **HOUSE RULES** in `Custom` → `Custom instructions` | applies to every generation, no retyping | palette, flatness, outline weight, "no text" |
| **Contact sheets** | one generation = nine stickers | line weight and personality, for free |
| **`got-house` Reference** | `Reference` tab in the Work panel | style carried into later one-off generations |
| **`got-print` saved Effect** | `Add Effect` → `Saved` | final grain/contrast pass, applied identically to all |

Then the manual layer: hand-edit item 2 (recolour to exact hexes) is what pins everything to
`apps/web/lib/theme.ts`, so the stickers, the map, the UI accent and the `/data` charts are literally
the same six values. Say that sentence out loud in the demo.

---

## What I could not verify

Honest list. Everything else in this document came from Reve's own help centre.

1. **Creating a new Reference from a generated image.** Reve documents editing an existing Reference
   (`Reference` tab → select → `Edit` → `Save`) in text, but the creation flow is only shown in an
   embedded video I could not watch. Expect it to be near the paperclip / attachment area or a
   `+ New reference` in the Reference tab.
2. **Free-plan energy allowance.** Reve publishes only "an introductory allocation of creative
   energy and a daily refresh thereafter" with no number. Third-party reviews guess ~20 generations
   per day; treat that as a rumour. This is why `Count` → `2` and the contact-sheet approach matter.
   Check your remaining energy in the **Account** tab before starting.
3. **Whether saving custom Effects and References is gated to paid plans.** Not documented either
   way. If a save button is greyed out, fall back to writing the slider values down.
4. **Resolution.** Two Reve help articles contradict each other — one gives a table topping out at
   ~1.5MP, another says "all images in 4K by default". Verify against your first actual download.
5. **The exact `Remove BG` behaviour on a multi-subject contact sheet.** Reve's docs warn it "needs
   a clear subject". Nine well-separated stickers on flat grey should be fine, but if it keeps only
   one, fall back to cutting the sheet into nine PNGs first and running `Remove BG` per sticker —
   costs more time, same result.
6. **The download button's exact icon and position.** Documented as "select any image and click the
   download button"; the position is not specified. Look top-right near `Share`.
7. **"Direct prompt mode."** Reve's chat article links to an article on a more literal,
   non-conversational prompt mode which I could not find. If you spot that toggle, turn it on — the
   prompts above are written as literal specs, not conversation, and will behave better with prompt
   rewriting disabled.
8. **Whether the 2026 single-panel UI redesign has reached this account.** All button names above
   come from current help-centre articles, but if the layout looks different from the descriptions,
   trust what is on your screen.
