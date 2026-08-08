# Build Plan — Git Out of Town

**Decision: all web.** Public URL, no App Store, no provisioning. "AR" = live camera + compass + GPS.

---

## The product

Hold up your phone, see the street through the camera, spray-paint graffiti or slap a sticker. It
pins to that spot and direction, forever. Anyone can open the map and explore what the world painted.

**The transformation (say this in the pitch):** crude finger-scribble → Reve model → polished graffiti
in our house style → anchored to a real place.

---

## Stack

| Layer | Choice |
|---|---|
| App | Next.js (App Router), self-hosted |
| DB | Postgres 17 on our OCI VPS |
| Storage | Mounted volume (~200GB), served by Caddy |
| Live updates | Postgres `LISTEN/NOTIFY` → SSE |
| Deploy | Docker Compose via Komodo, behind the shared Traefik (auto-HTTPS) |
| Map | MapLibre GL JS + custom dark style |
| Drawing | Canvas 2D |
| "AR" view | `getUserMedia` + `DeviceOrientationEvent` + `navigator.geolocation` |
| Transformation | Replicate → `reve edit-fast` (~$0.01, seconds) |
| Street View (P1) | Google Maps JS API `StreetViewPanorama` |

### iOS Safari notes
- **HTTPS required** for camera / geo / orientation → test on the deployed URL, not localhost.
- `DeviceOrientationEvent.requestPermission()` must fire **from a user gesture**.
- True heading on iOS is `event.webkitCompassHeading`, not `alpha`.
- No WebXR AR, no SLAM, no LiDAR. Pieces pin to a bearing, not a wall. Frame it as
  **"pin to a place and a direction."**

---

## Data model

```sql
pieces(
  id, lat, lng, heading, accuracy_m,
  raw_image_path, final_image_path,
  kind,            -- 'spray' | 'sticker'
  sticker_id, colors, stroke_count, duration_ms,
  city, country, session_id, created_at
)
views(piece_id, session_id, viewed_at)
sessions(id, first_seen, city, country, device)
```

Every column is free from the capture or from a request header. That's the whole TECHNATION dataset.
Full schema: `db/init.sql`. Deployment: `docs/04-deploy.md`.

---

## Making the web not feel dead

P0, in payoff order:
1. **Custom dark map style** from the Reve palette. A default basemap reads as a template — the exact
   thing the Reve rubric penalizes.
2. **The art is the marker.** Render graffiti PNGs on the map, not pins.
3. **Live drop-ins** via `LISTEN/NOTIFY` → SSE — new pieces animate in as they're painted.
4. **Attract mode** — on idle, drift between hotspots. Ambient motion on the projector during the pitch.
5. **Activity ticker** — "someone just painted in Toronto, 12s ago."

P1: **Street View.** Add each piece as a `google.maps.Marker` with the PNG as its icon, then
`marker.setMap(panorama)`. Use markers — `OverlayView` does not work on panoramas. Needs a Google
Cloud billing account + API key restricted by HTTP referrer.

**Hero arc:** land → attract mode over a dark map, clusters glowing → click a hotspot → drop into
Street View with real graffiti pinned to an actual street corner.

---

## `/data` dashboard

Live queries only. n-counts and last-updated visible. One interactive filter. Linked from main nav.

1. **Contributor map** — where people painted from (named twice in their doc).
2. **Which way the world faces** — compass heading distribution. Only we have this.
3. **Growth over time** — pieces per hour, scrubbable.
4. **Attention vs. intent** — what got painted vs. what got looked at.

Live-updating so it ticks up while judges watch — an explicitly stated bonus.

---

## Reve (sponsor track)

Design-time craft, made by hand in `app.reve.com`, **hand-edited**, committed as assets.

**Killer move: the sticker packs are Reve-made.** Every sticker a user can place is art we directed.
That's Reve as the design backbone, which is their exact judging language.

- [ ] Sticker pack, 12–20 pieces ← do first
- [ ] Spray brush textures + drip overlays
- [ ] Logotype + favicon
- [ ] Map pin art, landing hero, empty state, 404, OG image, Devpost cover
- [ ] Save 2–3 named Effects for one coherent look

> 🚨 Unedited generic AI visuals get **marked down**. Crop, recolour, composite, hand-tweak.

---

## Scope

**P0 — no project without these**
- Draw → save → pinned at your GPS location
- Shared map showing everyone's pieces
- Public URL that works on a stranger's phone

**P1** — camera background · Reve transformation · `/data` · Reve brand applied · Street View

**P2 — cut freely** — compass-accurate viewing, time-lapse scrubber, accounts, likes, comments

---

## Risks

| Risk | Mitigation |
|---|---|
| Host is ARM64 (Ampere) | Komodo builds on the server, so this is handled — never push an amd64 image to it |
| iOS permissions fail on a stranger's phone | Build `/permissions` debug page early; test on 3+ real devices |
| Judging is indoors, GPS poor, everything clusters at the venue | Make it a feature — pre-seed the venue as the densest hotspot. Manual pin fallback. |
| Replicate slow or down | Optimistic UI: show raw scribble, swap when transformed |
| Google billing setup stalls | Street View is P1 — cut it, don't let it block |
| Wifi dies mid-pitch | Screen-recorded backup + seeded data |
| Someone paints something vile | Delete button behind an admin route, before sharing publicly |

---

## 4-minute pitch

- **0:00–0:30** — Live map, already full. "People painted all of this in the last 18 hours."
- **0:30–1:30** — Paint live from a phone. It appears on the projected map.
- **1:30–2:15** — **Name the transformation.** Scribble → finished piece.
- **2:15–3:00** — `/data`. Point at the counter moving from your live contribution.
- **3:00–3:30** — Reve: "Every sticker in the app was art-directed by us in Reve."
- **3:30–4:00** — Lasting value. "Here's the URL — paint something."

Prep the two guaranteed Q&A questions: *how does the transformation work?* (30%) and *would anyone
use this after the hackathon?* (20%).
