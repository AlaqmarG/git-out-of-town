# Demo runbook

Judging is **3:00–5:00 PM today**, judged multiple times. Devpost hard cutoff **1:00 PM**.

This is written to be read under pressure. Everything below was verified against the live
deployment at **04:35 Aug 9**. Where the pitch in [`PLAN.md`](PLAN.md) no longer matches what
actually works, this file wins.

---

## 1. What is actually true right now

Verify before believing — these move:

```bash
curl -s https://gitoutoftown.129-153-49-190.sslip.io/api/stats | python3 -m json.tool
```

| | |
|---|---|
| Live pieces | **20** — 16 seeded, 3 real iOS, 1 stray web test |
| Genuine ARKit/LiDAR surface rows | **3 of 19** (2 `wall`, 1 `door`) |
| `final_image_path` populated | **0 of 45 rows ever created** |
| Cities | 1 (Toronto) |
| Web contribution path | **does not exist** — removed in #60 |
| Live map auto-refresh | **no** — reloads on map move only |
| `/data` auto-refresh | **yes** — polls `/api/stats` every 5s |
| Infra | app/db/uploads all up, TLS valid to Nov 6, CI green, `main` deployed |

### Three things in the pitch that the data does not currently support

1. **"Lead with surface classification"** (2:15–3:00 beat). `/data` captions that chart
   *"From ARKit's surface classification. Only a native AR client can record this."* That is
   **false for 16 of the 19 recorded surfaces** — they came from the seeder's Street View wall
   heuristic (`scripts/lib/graffiti.mjs`, `surface.kind`) and were posted as `client: "web"`.
   A TECHNATION judge asking "how does a browser record ARKit classification?" ends the section.
   → **Fix it with §2.1, or drop the beat.**

2. **"Scribble → Reve model → polished graffiti"** (1:30–2:15 beat). There is no runtime model
   call in the product. `final_image_path` is NULL on every row that has ever existed, and there
   is no Replicate/Reve code under `apps/web`. → **Name the transformation you actually ship**
   (see §5, Q1). It is a good one. Do not claim the one you don't.

3. **"Here's the URL — paint something"** (3:30–4:00 beat). The browser painting path was
   deleted. The website is view-only. Nobody in the room can contribute from the URL.
   → **Hand them the phone instead** (§3).

---

## 2. Pre-demo checklist

### 2.1 The highest-leverage hour you have (do this first, by ~1:30 PM)

Walk the block around the venue and **paint 15–25 real pieces in the app**, then delete the seeds.
This is not polish — it converts three separate liabilities into the strongest part of the pitch:

- every surface row becomes genuine LiDAR classification, so the `/data` caption becomes true and
  the beat you wanted to lead with becomes real;
- "the data is real and current, not fabricated" is an explicit rubric line, and
  `scripts/seed.mjs`'s own docstring says to delete these rows before judging;
- the map cluster lands where you are standing, not 3.5 km away.

Then remove the seeds:

```bash
ssh wayfare-vps-runner "docker exec gitoutoftown-got-db-1 psql -U graffiti -d graffiti \
  -c \"UPDATE pieces SET deleted_at = now() WHERE session_id LIKE 'seed-%' AND deleted_at IS NULL;\""
curl -s https://gitoutoftown.129-153-49-190.sslip.io/api/stats | python3 -m json.tool | head -20
```

Soft delete — reversible with `SET deleted_at = NULL` on the same `WHERE`.

**Do not delete the seeds until real pieces outnumber them.** An honest empty map scores worse
than a seeded one you describe accurately. If §2.1 doesn't happen, say "we pre-painted the venue
so the map isn't empty" out loud — owning it costs nothing and getting caught costs 30%.

### 2.2 Reinstall the iOS build (mandatory — free provisioning expires after 7 days)

Run from the repo root. Full detail and error table: `apps/ios/CLAUDE.md`.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
set -a; . ./.env; set +a
: "${IOS_TEAM:?set IOS_TEAM in .env}" "${IOS_BUNDLE:?set IOS_BUNDLE in .env}"

DEVICE=$(xcrun devicectl list devices |
  grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | head -1)

xcodebuild -project apps/ios/ios.xcodeproj -scheme ios -configuration Debug \
  -destination "id=$DEVICE" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$IOS_TEAM" PRODUCT_BUNDLE_IDENTIFIER="$IOS_BUNDLE" build

APP=$(find ~/Library/Developer/Xcode/DerivedData/ios-*/Build/Products/Debug-iphoneos \
  -maxdepth 1 -name '*.app' | head -1)
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" "$IOS_BUNDLE"
```

The ▶︎ Run button in Xcode **will** fail — the signing overrides only exist on the CLI. That is
expected, not a problem to debug at 2:45 PM.

If a **new** certificate was issued, one human step follows: Settings → General → VPN & Device
Management → Developer App → Trust. Once per certificate.

### 2.3 T-30 minutes

```bash
B=https://gitoutoftown.129-153-49-190.sslip.io
curl -s -o /dev/null -w 'health %{http_code} %{time_total}s\n'   $B/api/health
curl -s -o /dev/null -w 'map    %{http_code} %{time_total}s\n'   $B/
curl -s -o /dev/null -w 'data   %{http_code} %{time_total}s\n'   $B/data
curl -s "$B/api/pieces?bbox=-180,-90,180,90" | python3 -c 'import json,sys;print("pieces",json.load(sys.stdin)["total"])'
```

All four in well under a second is normal (measured: health 0.15s, map 0.06s, data 0.14s).

- [ ] Phone: **airplane mode off, hotspot ON**, tethered laptop to it. Do not trust venue wifi.
- [ ] Phone: battery >70%, **Low Power Mode off** (it throttles ARKit), auto-lock → Never.
- [ ] Phone: **Do Not Disturb on**. A notification banner across a mirrored AR view is a lost demo.
- [ ] Screen mirroring rehearsed on the actual projector, at the actual resolution.
- [ ] Screen recording of a successful end-to-end paint saved **to the laptop**, not just the phone.
- [ ] Admin secret pasted into `/admin` on the phone browser (it stores in `localStorage`) and
      confirmed working *before* you need it.
- [ ] `/data` open in a second browser tab, already loaded.
- [ ] **Deploy freeze from 2:00 PM.** No merges to `main` — every merge that touches
      `apps/web/**` rebuilds the container on the VPS. Nothing is worth a cold container at 3:05.

---

## 3. The 4-minute pitch, as it actually works today

> **0:00–0:30 — the wall.** Map on the projector, already dense. "People painted every one of
> these on a real wall, standing in front of it, in the last day." Zoom out once to show they're
> anchored to real streets, then back in.

> **0:30–1:45 — paint one, live.** Phone mirrored. Point at a wall, shoot, draw, place. Say the
> quiet part while it saves: *"that took under thirty seconds and nobody explained it to me."*
> Then **drag the map a few pixels** — that is what reloads it — and the new piece is there.
> Do not stand there waiting for it to appear on its own. It won't.

> **1:45–2:30 — name the transformation.** This is 30% of the score. Say it in this shape:
> *"Your drawing is 2D. The wall isn't. We take the LiDAR depth mesh of the surface you're
> pointing at, fit a plane to it, and project your strokes onto that plane as a textured decal —
> so it wraps the geometry, sits behind anything in front of it, and picks up the wall's own
> texture. Then we anchor it to GPS + heading so it's still there when someone else walks up."*
> Point at a piece that curves around a corner. **Do not say "an AI model repaints it."**

> **2:30–3:15 — `/data`, and this is the live one.** Lead with **pieces per hour** and the
> **counter**, not surfaces. The page repolls every 5 seconds — paint a second piece from the
> phone mid-sentence and let the number tick up while the judge is looking at it. That is the
> TECHNATION "dashboard updates live while judges are watching" bonus, and it is real.
> Only then, if §2.1 got done: *"and because it's a native AR client, we know what people paint
> **on** — walls, doors, ceilings. No web app can collect that."* If §2.1 did **not** get done,
> skip the surface chart entirely.

> **3:15–3:40 — Reve.** "Every sticker in the pack was art-directed by us in Reve, then
> hand-edited — none of it is a first output." Have `docs/reve-prompts-used.md` open in a tab.

> **3:40–4:00 — lasting value.** **Hand the judge the phone.** They paint. It appears on the
> projector behind you. That is the entire "gets better with more people" argument, delivered
> instead of asserted — and it is the only contribution path that exists.

Rehearse the mirroring twice. AR demos live or die on whether the room can see the phone.

---

## 4. When it breaks mid-demo

| What breaks | Do this, in one move |
|---|---|
| **Venue wifi dies** | Phone hotspot, laptop already paired. Test this at 2:30, not at 3:05. |
| **GPS is garbage indoors** | Expected. Accuracy is recorded, not enforced — the piece still saves and still lands on the map, just loosely placed. Say so: *"we record the GPS accuracy rather than pretend it's perfect."* Then demo against an exterior wall or a window bay if there is one. |
| **AR won't find a plane** | Move to a flat matte wall with texture and decent light. Glass, mirrors, and blank white walls are the failure cases. Have one wall scouted and pre-tested before 3 PM. |
| **Piece doesn't appear on the map** | Drag the map. It only reloads on move. If it's still missing, `/data`'s counter is the proof it saved — cut to that tab. |
| **`/data` numbers frozen** | The 5s poll dropped. Reload the tab; it server-renders fresh. |
| **The map shows "Could not reach the wall"** | The `/api/pieces` fetch failed. Reload once. If it repeats: `curl .../api/health`, then `ssh wayfare-vps-runner 'docker logs --tail 50 gitoutoftown-got-app-1'`. |
| **`POST` returns 429** | Rate limit is **10 posts then 1 per 6 seconds, per client IP** — and behind venue NAT the whole room shares one bucket. Wait ~10s and repost. **Never run the seeder from venue wifi**; it will drain the bucket you need. |
| **Somebody paints something vile** | `/admin` on your phone → tap it → gone. Soft delete, undoable. Rehearse this once so you're not learning the UI in front of a judge. |
| **Whole site is down** | Do not redeploy mid-window — the ARM rebuild is minutes, not seconds. Play the screen recording, keep talking, fix it between judging passes. |
| **App won't launch on the phone** | "Profile not trusted" → Settings → General → VPN & Device Management → Trust. "Device not unlocked" → unlock the screen. Both are 10-second fixes; know them cold. |

Between judging passes, not during: `ssh wayfare-vps-runner 'docker ps --filter name=got-'`.

---

## 5. The two questions you are guaranteed to get

### Q1. "How does the transformation actually work?" (30% — Technical Craft)

> "The hard part is that a drawing is flat and a wall isn't. When you point the phone at a
> surface, we take ARKit's LiDAR depth mesh, fit a plane to the mesh at the raycast hit, and
> project your strokes onto that plane as a textured decal — so it wraps the geometry instead of
> floating in front of it, real objects occlude it correctly, and it samples the wall's own
> texture so it reads as paint on brick rather than a sticker on glass. The same mesh gives us
> ARKit's surface classification, so we know it was a wall and not a floor. Then we anchor it:
> GPS, compass heading, altitude and the full 4×4 placement transform go up with the image, which
> is why anyone can open the map afterwards and find it in the right place, pointing the right
> way. The seeded pieces use the same idea in 2D — we detect a wall quad in a Street View still
> and composite the art into it in perspective."

If asked point-blank whether a model is involved: **"Not at paint time — no."** The stickers were
art-directed in Reve at design time; the placement pipeline is geometry, and it runs on-device in
real time. That answer is stronger than a hedge, and a hedge here is exactly what gets probed.

### Q2. "Would anyone use this after the hackathon?" (20% — Lasting Value)

> "It's already public and already running — that URL is a live map anyone can open with no
> install, and the pieces on it are anchored to real coordinates, not a demo database. The thing
> that makes it work is that it's strictly better the more people paint: one piece is a novelty,
> a hundred on one street is a map of what a neighbourhood thinks of itself. The honest gap is
> distribution — contributing needs the AR client, and right now that's a dev build. TestFlight is
> the next step, not a rewrite. What we'd keep is the viewing side, which already works for
> strangers: a city-scale, permanent, public wall that costs nothing to look at."

Do not oversell a business model. The rubric asks whether it brings people joy and gets better
with more people, not whether it monetises.

---

## 6. Known rough edges, if a judge finds one

- `/api/stream` (SSE) exists and works, but **nothing on the web consumes it** and it withholds
  its first byte for 15 seconds. The live dashboard is a 5-second poll. If asked, say that — the
  poll is the honest, working implementation.
- `/uploads/*` is served by nginx with `ETag`/`Last-Modified` but **no `Cache-Control`**, so
  images revalidate on every load. Fine at 20 pieces; it would bite at a thousand.
- Scene stills are up to ~1.3 MB each. Only fetched when a piece is opened, but on venue wifi a
  detail view can take a beat. Open one before the judge does.
- The API rate limiter is in-memory and resets on deploy.
