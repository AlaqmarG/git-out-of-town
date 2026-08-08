# Build Plan — Git Out of Town

**Two clients, one backend.** Native iOS is the experience; the web is the public artifact.

| | |
|---|---|
| `apps/ios` | SwiftUI + ARKit. Paint graffiti onto the real world in AR. **The demo.** |
| `apps/web` | Next.js. Public map + `/data` dashboard. **What judges and strangers open.** |
| `packages/shared` | The API contract both clients honour |

Why both: the rubric demands a public, live thing a stranger can reach ("not just something you demo
from your own laptop") — that's the web. But AR in a room is a far better 4-minute demo than a
browser. The web surface is also where `/data` lives, which is most of the TECHNATION track.

---

## The product

Hold up your phone, see the street through the camera, spray-paint graffiti or slap a sticker. It
anchors to that spot and direction, forever. Anyone — no install — opens the map and explores what
the world painted.

**The transformation (name it explicitly in the pitch):**
crude finger-scribble → Reve model → polished graffiti in our house style → anchored to a real place.

---

## Stack

| Layer | Choice |
|---|---|
| iOS | SwiftUI + ARKit + RealityKit |
| Drawing | **PencilKit** (`PKCanvasView`) — free undo, colours, brushes |
| Placement | CoreLocation (GPS + `trueHeading`) + ARKit raycast |
| In-app map | MapKit |
| Web | Next.js App Router (frontend + API + dashboard) |
| Web map | MapLibre GL JS + custom dark style |
| DB | Postgres 17 on the OCI VPS |
| Storage | Mounted volume (~164G free), served by nginx |
| Live updates | Postgres `LISTEN/NOTIFY` → SSE |
| Transformation | Replicate → `reve edit-fast` (~$0.01, seconds) |
| Deploy | Docker Compose via Komodo, behind shared Traefik |

---

## The AR approach — pick the simple one

**Draw in 2D → place as a textured quad.** A `ModelEntity` with a plane mesh and an `UnlitMaterial`
carrying the exported PNG, attached to an `AnchorEntity` at a raycast hit point.

Dramatically simpler than true decal projection, and on camera it looks the same.
**Do not attempt to paint in 3D space.**

### Geo-anchoring: check availability first
```swift
ARGeoTrackingConfiguration.checkAvailability { available, error in ... }
```
- **Available at the venue** → `ARGeoAnchor` for real lat/lng precision. Set `used_geo_anchor = true`.
- **Not available** → `ARWorldTrackingConfiguration` + place by GPS bearing/distance from the user.

**Build the fallback path first.** Treat geo-tracking as an upgrade you switch on if the check passes.
Never let the demo depend on it.

> ⚠️ **Don't relocalize with `ARWorldMap`.** Large, device-specific, unreliable across sessions.
> GPS + heading is imprecise but always works.

### Distribution reality
| Method | By Sunday? | Notes |
|---|---|---|
| Xcode local install | ✅ | Mac + cable. Free-ID profiles expire in **7 days**, 3 apps/device. |
| TestFlight internal | ⚠️ | Paid account; each tester must be an App Store Connect user. |
| TestFlight external | 🎲 | Beta App Review, ~24–48h for a first build. Submit early or not at all. |
| App Store | ❌ | Days. |

**Assume you demo from your own device.** Have the web map on a second screen so judges can explore
without installing anything.

---

## Data model

Full schema: `db/init.sql`. Types: `packages/shared/src/index.ts`.

Shared columns are free from any capture. The **native-only** columns are the interesting ones:

```
client           'ios' | 'web'
surface_type     ARMeshClassification — wall/floor/ceiling/table/seat/door/window
distance_m       camera → anchor at placement
device_pitch     degrees; negative = aimed down
used_geo_anchor  ARGeoAnchor vs GPS fallback
has_lidar        device capability
```

### 🎯 The insight only you will have
With LiDAR, `ARMeshClassification` tells you **what kind of surface** each piece was painted on.

> *"68% of graffiti goes on walls. 14% on the ground. 3% on ceilings — and those get looked at longest."*

Exactly the "true and interesting insight" the TECHNATION rubric asks for, impossible to fake, and no
web-only project at this hackathon can produce it. **Lead the data section with this.**

---

## `/data` dashboard (web)

Live queries only. n-counts and last-updated visible. One interactive filter. Linked from main nav.

1. **Contributor map** — where people painted from (named twice in their doc).
2. **Surfaces of the world** — the mesh-classification breakdown above.
3. **Growth over time** — pieces per hour, scrubbable.
4. **Attention vs. intent** — what got painted vs. what got looked at.

Live-updating via SSE so it ticks up while judges watch — an explicitly stated bonus.

---

## Making the web not feel dead

The web is what judges explore, so it carries most of the Originality score.

1. **Custom dark map style** from the Reve palette. A default basemap reads as a template — the exact
   thing the Reve rubric penalises.
2. **The art is the marker.** Render graffiti PNGs on the map, not pins.
3. **Live drop-ins** via SSE — pieces animate in as they're painted. Paint from your phone mid-pitch
   and the projected map moves.
4. **Attract mode** — on idle, drift between hotspots. Ambient motion during the pitch.
5. **Activity ticker** — "someone just painted in Toronto, 12s ago."

P1: **Street View** — each piece as a `google.maps.Marker` with the PNG as icon, `marker.setMap(panorama)`.
Use markers; `OverlayView` does not work on panoramas.

---

## Reve (sponsor track)

Design-time craft, made by hand in `app.reve.com`, **hand-edited**, committed as assets. Ships in
**both** clients — the iOS sticker picker and the web map use the same art.

**Killer move: the sticker packs are Reve-made.** Every sticker a user can place is art we directed.
That's Reve as the design backbone, their exact judging language.

- [ ] Sticker pack, 12–20 pieces ← do first
- [ ] Spray brush textures + drip overlays
- [ ] App icon + logotype + favicon
- [ ] Launch screen, map pin art, landing hero, empty state, 404, OG image
- [ ] Save 2–3 named Effects for one coherent look

> 🚨 Unedited generic AI visuals get **marked down**. Crop, recolour, composite, hand-tweak.

---

## Scope

**P0 — no project without these**
- Web: public map showing everyone's pieces, reachable by a stranger
- API: `POST`/`GET /api/pieces`
- iOS: draw → place in AR → persists with lat/lng

**P1**
- iOS: load and render nearby pieces from other sessions; in-app MapKit view
- Web: `/data` dashboard, live drop-ins, Reve brand applied
- Reve transformation
- **Web capture** — a stripped-down "drop a sticker here" path. This is how you seed 20+
  contributors from a shared link; app-install-only seeding will not get you there.

**P2 — cut freely**
- `ARGeoAnchor` precision (keep the GPS fallback)
- Street View, attract mode, time-lapse
- Accounts, likes, comments

> **Sequencing rule:** the web P0s must never be blocked on iOS. If ARKit eats the night, the web
> still ships and you still have a project.

---

## Risks

| Risk | Mitigation |
|---|---|
| **Code signing / provisioning eats hours** | Get one build on a real device in the **first hour**, before any features |
| Two clients, two people, one night | Web P0 is the floor. iOS is the demo. Do not let iOS block web. |
| `ARGeoTracking` unavailable at venue | Build the GPS-bearing fallback first |
| No LiDAR on team devices | Plane detection only; drop the surface-classification insight |
| Judging is indoors, GPS poor, everything clusters at the venue | Make it a feature — pre-seed the venue as the densest hotspot. Manual pin fallback. |
| Seeding needs installs | Ship the web capture path (P1) |
| Replicate slow or down | Optimistic UI: show raw scribble, swap when transformed |
| Host is ARM64 (Ampere) | Komodo builds on the server — never push an amd64 image at it |
| Wifi dies mid-pitch | Screen-recorded backup + seeded data |
| Someone paints something vile | Delete button behind an admin route, before sharing publicly |

---

## 4-minute pitch

- **0:00–0:30** — Web map on the projector, already full. "People painted all of this in 18 hours."
- **0:30–1:30** — Live AR on your phone, mirrored. Paint on a real wall. It appears on the map.
- **1:30–2:15** — **Name the transformation.** Scribble → finished piece.
- **2:15–3:00** — `/data`. Lead with surface classification. Point at the counter moving.
- **3:00–3:30** — Reve: "Every sticker in the app was art-directed by us in Reve."
- **3:30–4:00** — Lasting value. "Here's the URL — paint something."

Rehearse screen mirroring. **AR demos live or die on whether the room can see your phone.**

Prep the two guaranteed Q&A questions: *how does the transformation work?* (30%) and *would anyone
use this after the hackathon?* (20%).
