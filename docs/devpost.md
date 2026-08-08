# Devpost draft — Git Out of Town

Cover image: [`assets/brand/devpost-cover-1200.png`](assets/brand/devpost-cover-1200.png) (1200×675).
Hand-authored in the app's own palette — not model output, per the rubric's mark-down on generic AI visuals.

**Tracks:** Main · Best Use of Reve · TECHNATION Data Intelligence
**Links:** https://gitoutoftown.129-153-49-190.sslip.io · repo

---

## Inspiration

Graffiti is the original location-based social network. A wall means something because it's *that*
wall — you have to go there. But real walls get buffed, and cities are hostile to the people who
paint them.

We wanted the permanence without the vandalism: a city you can actually mark, where your tag
outlives you and a stranger on the other side of the world can walk up to it.

## What it does

Hold up your phone. Point it at a real wall. Finger-paint. Tap to place.

The piece anchors to that exact spot — GPS, compass bearing, and an ARKit raycast onto the real
surface you aimed at — and it's live on a public world map seconds later. No install, no account:
anyone opens the link and explores what the world painted. Zoom out and you see density; zoom in and
you see the actual wall, photographed at the moment of painting, with the art burned into it.

**The transformation:** a crude finger-scribble → a polished piece in our house style → welded to a
real place, a real direction, and a real photograph of the surface it lives on.

`/data` shows the artifact reasoning about itself: where contributors are painting from, which
surfaces the world chooses (wall vs. floor vs. ceiling, straight off LiDAR mesh classification),
and the map ticking up live as people paint.

## How we built it

Two clients, one contract.

- **iOS** — SwiftUI + ARKit. You draw in 2D and we place it as a textured quad at the raycast hit,
  not as paint in 3D space. `ARMeshClassification` at the hit point tells us what you painted on.
  GPS + compass bearing is the anchoring floor; `ARGeoAnchor` is an upgrade we switch on only when
  the venue supports it.
- **Web** — Next.js 16 and MapLibre GL. The basemap is hand-authored, layer by layer, over free
  OpenFreeMap vector tiles — no stock style, no map API key. Markers render in three zoom tiers:
  clustered density glow → pins tinted with each piece's own dominant colour → the framed artwork
  itself.
- **Data** — Postgres. `LISTEN/NOTIFY` on insert feeds an SSE stream, so a piece painted on a phone
  lands on every open map without a refresh.
- **Infra** — self-hosted. Docker, TLS, deployed straight from `main` on push. Uploaded art is
  served by a separate static container, so image bytes never pass through Node — a single pan of
  the map pulls hundreds of them at once.
- **Reve** — the visual identity. Every colour in the app comes from one palette file, so the art
  direction propagates to the map, the UI and the markers at once.

## Challenges we ran into

- **AR's hard problem isn't rendering, it's agreeing on *where*.** `ARGeoTracking` isn't available
  everywhere, and judging is indoors where GPS is bad. We built the GPS + bearing fallback *first*
  and treated precision as the upgrade, not the foundation.
- **`maplibre-gl.css` sets `position: relative` on whatever element you hand the map**, silently
  overriding a Tailwind `absolute` and collapsing the map to zero height. No error, no map.
- **Transparent art on a dark basemap reads as spilled paint.** Framing each piece — backing card,
  border, a tilt seeded off its ID so a wall of them looks hand-placed — was what made them read as
  objects someone left behind.
- **SSE on a pooled Postgres connection silently stops listening** when the pool recycles it. It
  needs its own dedicated client.
- **26 hours, two people, two clients.** We made the rule that web could never be blocked on iOS —
  so if ARKit ate the night, there was still a live artifact.

## Accomplishments that we're proud of

- It's **public and live**, not a laptop demo. You can open it right now and it has other people's
  work in it.
- The look is ours. Hand-authored basemap, one palette file, a marker system we designed — nothing
  templated, nothing straight out of a model.
- The AR path produces a dataset **no web-only project can**: what real surface, at what distance,
  at what device pitch, each piece was painted on.
- The map updates while you watch it. We can paint something mid-pitch and the judges' screen moves.

## What we learned

Anchoring is a product decision, not a technical one — the moment you accept "roughly here, facing
that way," the whole thing becomes buildable in a night. We also learned that visual craft was
scored, not decorative, and building a palette-first system early meant we could restyle the entire
app by editing one file at 3 AM.

## What's next for Git Out of Town

- `ARGeoAnchor` everywhere for centimetre-accurate placement that survives across sessions
- Walls and crews — a shared surface that fills up, and the people who claim it
- Time-lapse: scrub a wall's history and watch it get painted over
- Android via WebXR, and a browser capture path so the barrier is a link, not an install
- Community moderation — this is public art pinned to real addresses, and the neighbourhood should
  get a say in what stays up

---

## Tags

```
augmented-reality, arkit, ios, swift, swiftui, realitykit, lidar, geolocation, maplibre,
mapping, nextjs, typescript, postgresql, server-sent-events, realtime, reve, generative-art,
graffiti, street-art, community, docker, self-hosted, data-visualization, dashboard, geospatial
```
