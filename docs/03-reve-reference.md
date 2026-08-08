# Reve API Reference

> Verified 2026-08-08 by extracting the live docs source from `api.reve.com` (the docs site is a
> client-rendered SPA, so the numbers below come from the shipped JS chunks, not from blog posts).
> Primary sources: `api.reve.com/console/docs`, `github.com/reve-ai/reve-sdk`.

**Strategy, deadlines, and what to build live in `START-HERE.md`.** This file is pure API lookup.

## 1. Access, auth, cost, limits

### Getting a key
> **Currently gated.** The console reports the API is closed to new users, and no "Enable API"
> section appears on a Free-plan account. Steps 1–2 only work with sponsor-provided access.

1. `https://app.reve.com/account` → scroll to bottom → **"Enable API"** → accept ToS → add credits.
2. Keys live at `https://api.reve.com/console/keys`. Tokens look like `papi.xxxxx`.
3. Env var: `REVE_API_TOKEN` (SDK) / `REVE_API_KEY` (docs examples). Header: `Authorization: Bearer papi.…`
4. If you can't see the keys page, you're in the wrong **organization** — switch it in the bottom-left nav menu.
5. Keys support **IP restrictions** and a **per-key budget** — set a budget cap before you go public
   or a bot will drain your credits.

### Pricing (credits, and approx USD)

| Operation | Credits | ≈ USD | Notes |
|---|---:|---:|---|
| `v1/image/create` | 18 | $0.024 | 1 prompt → 1 image. **Cheapest full generation.** |
| `v1/image/edit` | 30 | $0.040 | |
| `v1/image/remix` | 30 | $0.040 | 1–6 images + prompt |
| `v1 edit` @ `latest-fast` | **5** | **$0.007** | 6× cheaper — use for public free-tier |
| `v1 remix` @ `latest-fast` | **5** | **$0.007** | ditto |
| `v2/image/create` | 150 | $0.20 | image **+ layout** |
| `v2/image/extract_layout` | 80 | $0.11 | image → layout |
| `v2/image/create_layout` | 80 | $0.11 | prompt/refs/commands → layout |
| `v2/image/render_layout` | 80 | $0.11 | layout → image + layout |
| `postprocessing: upscale` | variable (≥2) | ~$0.002/MP | |
| `postprocessing: remove_background` | variable (≥2) | ~$0.002/MP | |
| `postprocessing: effect` | 3 | $0.004 | |
| `postprocessing: fit_image` | **0** | **free** | resize/thumbnail at no cost |
| `test_time_scaling` | multiples of base | — | quality dial |

> Budget math for a public demo: at v1-fast (5 credits) you get ~200 generations per $1.40.
> At v2 create (150 credits) you get ~7. **Design your public loop around v1/fast, and use v2
> layout endpoints for the "shared artifact" spine that runs less often.**

### Rate limits (critical for a public site)
- **1750 API credits per minute, per key.** → ~97 v1-creates/min, ~350 fast-edits/min, but only
  **~11 v2-creates/min**.
- Account-level basic tier: **10 images/min, 200/hour, 2000/day**, applied independently.
- **Mitigation:** issue multiple API keys (each has its own credit-rate bucket), queue writes,
  and cache aggressively. Ship a visible "you're #N in the queue" UI — it reads as a feature.

### Latency (this will bite you)
- v2 image generation / render: **40–80 s**. v2 layout ops: **10–40 s**. v1: much faster.
- Set HTTP client / proxy / serverless timeouts to **≥120 s**. Vercel/Netlify default function
  timeouts are shorter — **use the `async` flow (§3.11) or a worker**, or v2 will fail in prod.
- A short client timeout is *not* a cancellation — the server finishes and **you are still billed**.

### Ownership
You own what you generate, commercial use allowed. You're responsible for infringement/legality.
(Relevant because your output is public UGC — put a line in your ToS.)

---

## 2. Endpoint map

| Method | Endpoint | In → Out |
|---|---|---|
| POST | `/v2/image/create` | prompt + ordered refs → **image + layout** |
| POST | `/v2/image/extract_layout` | image (+ optional prompt) → **layout** |
| POST | `/v2/image/create_layout` | prompt / refs / **commands** → **layout** |
| POST | `/v2/image/render_layout` | layout + refs → **image + layout** |
| POST | `/v2/image/reconcile_layout` | original_layout + edited_layout → **repaired layout** |
| GET | `/v2/image/response?request_id=…` | async result poll |
| POST | `/v1/image/create` | prompt → image (cheap, fast) |
| POST | `/v1/image/edit` | image + instruction → image |
| POST | `/v1/image/remix` | 1–6 images + prompt → image |
| GET | `/v1/image/effect` | list saved + builtin effect presets |
| GET | postprocessor list (via web SDK `listPostprocessors`) | per-op credit costs |

**Note:** v1 `edit`/`remix` have been folded into v2 `create` — in v2 there is no separate base-image
field, you just put the image first in `references` and all refs are frames `0..N-1`.

### Parameters worth knowing

**v2 `create`**: `prompt` (≤4000 chars, required), `references[]` (≤8, each exactly one of
`data` or `ref`), `aspect_ratio` (default `auto`), `postprocessing[]`, `version`, `async`.

**v1 `create`**: `prompt` (≤2560, auto-enhanced by the model), `aspect_ratio` (default `3:2`),
`version` (`latest` | `reve-create@20250915`).

**v1 `remix`**: `prompt`, `reference_images[]` (1–6), `aspect_ratio`, `version`
(`latest` | `latest-fast` | `reve-remix-fast@20251030` | `reve-remix@20250915`).

**v1 `edit`**: `edit_instruction`, `reference_image`, `aspect_ratio` (defaults to the input's),
`version` (`latest` | `latest-fast` | `reve-edit-fast@20251030` | `reve-edit@20250915`).

### Aspect ratios
- **v2 (17 + auto):** `4:1 3:1 21:9 2:1 17:9 16:9 3:2 4:3 5:4 1:1 4:5 3:4 2:3 9:16 1:2 1:3 1:4`, plus `auto`.
- **v1 (7 only):** `16:9 3:2 4:3 1:1 3:4 2:3 9:16`.
- `4:1` / `1:4` are great for a scrolling "tapestry" strip artifact.

### Input image limits
Formats in: **WEBP, JPEG, PNG, GIF, TIFF, AVIF**. Per image: ≤40 MB and ≤33,554,432 px, neither
dimension >8192. Per request across all images: ≤50,331,648 px and ≤100 MB decoded.

### Response formats
`Accept: application/json` (default; base64 PNG + metadata fields) or `image/png` | `image/jpeg` |
`image/webp` (raw bytes, metadata moves to headers). **Use `image/webp` for speed** — skips base64's
33% bloat.

### Response headers (free per-request telemetry)
`X-Reve-Request-Id`, `X-Reve-Credits-Used`, `X-Reve-Credits-Remaining`, `X-Reve-Version`,
`X-Reve-Content-Violation`, `X-Reve-Error-Code`.

### Status codes
200 ok · 400 bad request · 401 unauthorized · 402 **insufficient credits** · 404 · 422 unprocessable ·
429 rate limit · 500. **A content-policy violation returns 200 with `content_violation: true` and an
empty image** — you must check the flag, not the status code. Non-negotiable for public UGC.

---

## 3. The niche features (the actual goldmine)

### 3.1 `<frame>N</frame>` — reference images by index, inline in the prompt (v2)
```
"Put the character from <frame>0</frame> into the room from <frame>1</frame>, holding <frame>2</frame>"
```
v1 `remix` uses the older `<img>0</img>` syntax. This is real compositional control in plain text —
you can build a "combine these three contributions" feature with a template string.
**Use it for:** merging N user contributions into one frame with explicit roles.

### 3.2 `reference:@<name>` — named, persistent project references
`{ "ref": "reference:@mascot" }` pulls a named asset from your Reve project. Set up your mascot /
logotype / house background *once in the Reve app*, then every API call gets **perfect character and
brand consistency for free**, with zero bytes re-sent.
**Use it for:** a recurring character that appears in every user's contribution — the visual thread
that makes a thousand separate contributions read as one artifact. This is the Reve-track winner.

### 3.3 `id:<uuid>` — chain off a previous generation without re-uploading
`{ "ref": "id:<uuid>" }` points at a stored image *or a previous generation* in your project.
**Use it for:** each contribution builds directly on the last one — the literal "growing artifact"
mechanic, with no image storage on your side.

### 3.4 The free `layout` object (⭐ the big one)
Every `v2/create` and `render_layout` response includes a `layout`:
```json
{
  "prompt": "a person at a cafe",
  "width": 2048, "height": 1536,
  "regions": [{
    "label": "person",
    "prompt": "a woman in a red coat",
    "bbox": { "x0": 0.1, "y0": 0.1, "x1": 0.6, "y1": 0.9 },
    "color_palette": [{ "r": 242, "g": 115, "b": 83 }],
    "parent": null,
    "region_type": "coarse_detail",
    "image_index": 0, "image_region_index": 2
  }]
}
```
Field notes:
- `label` — short unique entity name (acts as the region id)
- `prompt` — concise noun phrase works best (`a red hat` > a full sentence)
- `bbox` — normalized 0–1, **top-left origin**
- `region_type` — `coarse_detail` (person, car) → `medium_detail` (arm, wheel) → `fine_detail`
  (ring, buckle), plus special kinds `text`, `hand`, `face`
- `parent` — label of the containing region → a real containment tree
- `width`/`height` — always multiples of 32; on input supply both, with `width*height` between
  `3072*2560` and `4096*4096`

**Why it matters:** you get free object detection, free semantic tagging, free composition
statistics, and a free hierarchy — no separate vision model, no extra cost, no extra latency.
Everything in §5 is built on this.

### 3.5 `extract_layout` — physical input → structured data
Send any user photo/drawing/handwriting, optionally with a transforming prompt
(`"Remove the bookshelf"`), get back a layout. 80 credits.
**Use it for:** the moment of human input becomes machine-readable the instant it's uploaded —
which is exactly what the brief asks for, *and* it's your dataset.

### 3.6 `create_layout` + `commands[]` — imperative, deterministic composition edits
An ordered array of edits applied on top of the prompt and references. Positions are a normalized
bbox `{x0,y0,x1,y1}` or a point `{x,y}`, both 0–1, top-left origin.

| op | Shape | Meaning |
|---|---|---|
| `add` | `{op, label\|description, at?}` | introduce a subject, optionally positioned |
| `place` | `{op, label\|description, at}` | add at a **required** position |
| `shift` | `{op, label\|description, to, at?, image_index?}` | move a subject |
| `remove` | `{op, label\|description, at?, image_index?}` | delete a subject |
| `keep` | `{op, label?\|description?, at?, image_index?}` | pin/preserve a subject |
| `change` | `{op, label, new_description}` | rewrite a region in place |

**Use it for:** "every visitor gets one `place` command on the shared canvas." That's a whole
hackathon project. It's deterministic, cheap, trivially rate-limitable, and the command log *is*
your data story ("14,203 things placed; here's where people put them").

### 3.7 `reconcile_layout` — the multiplayer-canvas feature
After a user drags/edits regions client-side, send `original_layout` + `edited_layout` and Reve
repairs the semantic inconsistencies before you render. Without this, direct edits produce
contradictory scene descriptions and `render_layout` output degrades.
**Use it for:** any drag-to-arrange UI. It's the difference between a demo and something that
survives 500 contributors.

### 3.8 `color_palette` per region — data-driven colour
Each region accepts RGB triples (0–255) that condition its appearance. Rule from the docs: the
region prompt must **not contradict** the palette, and works best when the prompt also names the
colour (`"a red car"` + `{255,0,0}`).
**Use it for:** map a real variable — sentiment, time of day, city, contributor count — to the
colour of a region. Your artifact literally *renders* your dataset. That's a track-crossing move:
the data intelligence becomes the visual storytelling.

### 3.9 `region_type: "text"` — Reve's typography engine, addressable
Reve's standout capability is legible in-image text. `region_type: "text"` marks a text region
explicitly, with its own bbox and parent.
**Use it for:** handwritten-word input → a rendered typographic artifact where the user's word is
placed in a controlled region. Also: `hand` and `face` region types for human-subject photos.

### 3.10 Postprocessing pipeline
```json
"postprocessing": [
  { "process": "upscale", "upscale_factor": 2 },
  { "process": "remove_background" },
  { "process": "fit_image", "max_dim": 512 },
  { "process": "effect", "effect_name": "my-effect", "effect_parameters": { "filterId": { "uniformId": 0.8 } } }
]
```
- `upscale` — integer 1–4
- `remove_background` — transparent PNG. **Use it for:** every contribution becomes a free-floating
  sticker you can composite into an infinite shared canvas in CSS. Warning: needs a clear subject.
- `fit_image` — `max_dim` / `max_width` / `max_height`, each ≤4096, never enlarges, **costs 0 credits**.
  Generate your thumbnails/grid tiles here for free instead of running your own image pipeline.
- `effect` — apply a preset **by name**, with optional per-parameter overrides in the form
  `{ filterId: { uniformId: value } }`.

### 3.11 `async` + `callback_url` + `public: true` (⭐ deploy-saver)
```json
"async": { "callback_url": "https://example.com/notify", "image_format": "image/jpeg", "public": true }
```
- Returns **202** immediately with `request_id`, `result_url`, `status: "processing"`.
- Poll `GET /v2/image/response?request_id=…` — it long-polls up to **5 s** then returns 202 again.
- `callback_url` gets **exactly one POST, no retries** (must be https, publicly routable) — so always
  keep polling as a fallback.
- **`public: true`** (only on `create` / `render_layout`, only with an `image/*` format) makes the
  result a **signed, unauthenticated static-asset URL** — i.e. **Reve hosts your image for you, on a
  URL you can drop straight into an `<img src>` or an OG tag.** No S3, no blob store.
- Results expire after **1 hour** (the stored image stays in your project). Billing is identical
  to sync.

**This solves the 40–80 s v2 latency problem on serverless.** Fire and forget, take the webhook.

### 3.12 `?breadcrumb=` — free request tagging
Append `&breadcrumb=<anything>` to any request. Stored with the request, **searchable in the console
Usage page**, ignored by the model, doesn't need to be unique.
**Use it for:** `?breadcrumb=contribution-<id>-<step>` — you get a free join key between your
database and Reve's own usage analytics, and a free per-feature cost breakdown for your dashboard.

### 3.13 `test_time_scaling`
Integer 1–15 (docs say "between 1 and 5" in one place, max 15 clamped — use ≤5). Higher = better
image, more credits. **Docs explicitly say: don't enable it on v2 models.** Use on v1 for a paid/
"premium contribution" tier if you want a quality lever.

### 3.14 `GET /v1/image/effect` — effect discovery
Returns `{ effects: [{ name, source, description?, category? }] }`. `source` is `saved` (your
project) or `builtin` (system preset, e.g. `cmyk_halftone`, category `textures`). Query param
`source` = `all` (default) | `project` | `preset`. Parameter *definitions* are not returned — you
create presets in the Reve app, save them with a name, and apply the name via API.
**Use it for:** define 3–4 house effects in the Reve app (your "look"), expose them as the only
style choices in your UI. That's a brand system, not a prompt.

### 3.15 `<reve-layout-overlay>` web component (⭐ dual-track weapon)
```html
<script type="module">import "https://unpkg.com/@reve-ai/web-sdk/dist/index.js";</script>
<reve-layout-overlay src="photo.png" default-color="#fff" selected-color="#ff4000"
  idle-opacity="0.25" show-labels="true" selection-mode="single"></reve-layout-overlay>
```
Zero dependencies, no shadow DOM, no framework. Set `.layout` and `.colorMap` (label → CSS colour)
as properties.

Attributes: `src`, `layout`, `color-map`, `default-color` (`#ffffff`), `selected-color` (`#ff4000`),
`idle-opacity` (`0.25`, `0` hides), `show-labels` (`true`), `selection-mode` (`single`|`multiple`|`none`).

Methods: `select(label)`, `unselect(label)`, `setSelected(label, bool)`, `clearSelection()`,
`getSelectedLabels()`, `selectedLabels`, `getRegionLabels()`.

Events (bubbling `CustomEvent`, `detail = { region, index, label }`):
`reve-region-hover-enter`, `reve-region-hover-leave`, `reve-region-clicked`,
`reve-region-selected`, `reve-region-unselected`.

**Why this is the single highest-leverage thing in the whole API for you:** it is simultaneously
(a) a beautiful interactive UI you get for free, (b) a *behavioural telemetry stream* — which
regions people hover, in what order, for how long, which they click — and (c) proof to judges that
your data is real usage data, not a seeded database. Pipe those five events into your analytics
table and the TECHNATION track is yours to lose.

Also exported: `ReveClient` (fetch wrapper for all five v2 endpoints + `listPostprocessors()` +
`listEffects(source)`), `imageResponseToBlob()`, `imageResponseToObjectUrl()`, and all TS types.
`listPostprocessors()` returns `credits_base` / `credits_per_megapixel` → **build a live cost meter
in the UI**.

> ⚠️ **Never ship the `papi.…` token to the browser.** Proxy through your backend. The docs say this
> twice. Judges will check.

### 3.16 SDKs & agent integration
- Python: `pip install reve` (3.10+) — `reve.v2.image`: `create`, `extract_layout`, `create_layout`,
  `render_layout`, `reconcile_layout`. `ImageInput.data` takes a path, bytes, or a PIL Image.
  Typed exceptions: `ReveAuthenticationError`, `ReveBudgetExhaustedError`,
  `ReveRateLimitError` (has `.retry_after`), `ReveValidationError`, `ReveContentViolationError`.
- Web: `npm install @reve-ai/web-sdk` (or unpkg CDN).
- **`SKILL.md`**: `github.com/reve-ai/reve-sdk/tree/main/skills/reve-image` — drop it into Claude
  Code / your agent and it knows the whole API. Do this on day one; it makes the whole team faster.

---

## 4. Feature → track mapping

| Feature | Reve track | Data track | Priority |
|---|:---:|:---:|---|
| `layout` returned free with every image | ● | ●●● | **P0** |
| `<reve-layout-overlay>` + region events | ●● | ●●● | **P0** |
| `extract_layout` on user input | ● | ●●● | **P0** |
| `reference:@<name>` brand/character consistency | ●●● | — | **P0** |
| `async` + `public: true` hosted URLs | — | ● | **P0 (infra)** |
| `?breadcrumb=` tagging | — | ●● | P1 |
| `X-Reve-Credits-Used` / latency headers | — | ●● | P1 |
| `create_layout` commands as contribution unit | ●● | ●●● | P1 |
| `color_palette` driven by real data | ●●● | ●● | P1 |
| Saved `effect` presets as house style | ●●● | — | P1 |
| `remove_background` → sticker canvas | ●● | — | P2 |
| `region_type: "text"` typography | ●●● | — | P2 |
| `reconcile_layout` for drag-edit | ● | ● | P2 (if multiplayer) |
| `fit_image` free thumbnails | — | — | P2 (cost saver) |
| `<frame>N</frame>` multi-contribution merge | ●● | ● | P2 |

---

## 5. Copy-paste starters

### Cheapest public loop (v1, fast, ~$0.007/contribution)
```bash
curl -X POST "https://api.reve.com/v1/image/remix?breadcrumb=contrib-$ID" \
  -H "Authorization: Bearer $REVE_API_KEY" \
  -H "Accept: image/webp" -H "Content-Type: application/json" \
  -d '{"prompt":"the drawing in <img>0</img> rendered in the house style",
       "reference_images":["'"$B64"'"],
       "version":"latest-fast","aspect_ratio":"1:1"}' -o out.webp
```

### Structure-first loop (physical input → data → shared artifact)
```js
// 1. user input -> structured data (and your dataset row)
const extracted = await reve.extractLayout({ image: { data: b64 } });

// 2. merge one region into the shared, growing layout
const merged = await reve.createLayout({
  prompt: sharedCaption,
  references: [{ layout: sharedLayout }, { image: { data: b64 }, prompt: userWord }],
  commands: [{ op: "place", description: userWord, at: { x: userX, y: userY } }],
  aspect_ratio: "16:9",
});

// 3. render the artifact, hosted by Reve, no blob store needed
const img = await reve.renderLayout({
  layout: merged.layout,
  references: [{ image: { ref: "reference:@housestyle" } }],
  postprocessing: [{ process: "fit_image", max_dim: 2048 }],
  async: { public: true, image_format: "image/webp", callback_url: WEBHOOK },
});
```

### Overlay + telemetry in ~10 lines
```js
import "@reve-ai/web-sdk";
const o = document.querySelector("reve-layout-overlay");
o.src = imageUrl; o.layout = layout; o.colorMap = paletteByLabel;
for (const ev of ["hover-enter","hover-leave","clicked","selected","unselected"])
  o.addEventListener(`reve-region-${ev}`, e =>
    track(ev, { label: e.detail.label, bbox: e.detail.region.bbox, t: performance.now() }));
```

---

## Sources
- [Reve API console docs](https://api.reve.com/console/docs) (v1 + v2 endpoint reference, layouts, commands, async, postprocessing, breadcrumbs, effects)
- [Reve API help article](https://help.reve.com/hc/en-us/articles/46837930295316-Reve-API)
- [reve-ai/reve-sdk](https://github.com/reve-ai/reve-sdk) — Python SDK, `SKILL.md`, web SDK
- [Reve web SDK README](https://github.com/reve-ai/reve-sdk/blob/main/web-sdk/README.md) — `<reve-layout-overlay>`
- [Reve skill file for agents](https://github.com/reve-ai/reve-sdk/tree/main/skills/reve-image)
- [ComfyUI Reve nodes](https://docs.comfy.org/tutorials/partner-nodes/reve/reve-image), [fal.ai Reve 2.1](https://fal.ai/models/reve/2.1/remix/api), [Replicate Reve Remix](https://replicate.com/reve/remix) — alternative hosted access if direct credits run out
