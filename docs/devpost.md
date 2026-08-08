# Devpost draft: Git Out of Town

Cover image: [`assets/brand/devpost-cover-1200.png`](assets/brand/devpost-cover-1200.png) (1200x675).
Written by hand in HTML/SVG using the colours in `lib/theme.ts`, not generated.
Source: [`assets/brand/cover.html`](assets/brand/cover.html). Re-render with:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
  --hide-scrollbars --force-device-scale-factor=2 --window-size=1200,675 \
  --screenshot=cover.png file://$PWD/docs/assets/brand/cover.html
```

**Tracks:** Main, Best Use of Reve, TECHNATION Data Intelligence
**Links:** https://gitoutoftown.129-153-49-190.sslip.io and the repo

---

## Inspiration

We wanted to tag a city without wrecking it.

Graffiti works because of where it is. You have to go to the wall to see it. But walls get painted
over, and the people who paint them get fined. We wanted a version where your tag stays put, and
someone on the other side of the world can still walk up to it.

## What it does

Point your phone at a wall. Draw with your finger. Tap to place it.

The drawing sticks to that spot. We save the GPS position, the compass bearing, and where the
ARKit raycast landed on the real surface. A few seconds later it is on a public map. No app to
install, no login. Anyone can open the link and look around.

Zoom out and you see clusters. Zoom in and you see the wall itself, photographed while it was
being painted.

The transformation: a rough finger drawing goes in, a finished piece in our house style comes out,
pinned to a real place and a real direction, with a photo of the actual surface.

The `/data` page shows how the map is being used. Where people paint from, which surfaces they
pick (wall, floor, ceiling, read straight off LiDAR), and the count going up live.

## How we built it

Two apps, one shared API contract.

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

Placing something is easy. Agreeing on where it is turned out to be the hard part.
`ARGeoTracking` is not available everywhere, and judging happens indoors where GPS is poor. So we
built the GPS and compass version first and treated the precise version as a bonus.

`maplibre-gl.css` sets `position: relative` on whatever element you hand the map. That quietly beat
our Tailwind class and collapsed the map to zero height. No error, no map.

Transparent art on a dark map looked like spilled paint. Putting each piece in a small frame with a
slight tilt fixed it. They read as objects someone left behind.

SSE on a pooled Postgres connection stops listening when the pool recycles it. It needs its own
client.

26 hours, two people, two apps. We made a rule that the website could never wait on the iOS app.

## Accomplishments that we're proud of

It is live and public. You can open it right now and other people's work is already in it.

The look is ours. A map style we wrote, one colour file, a marker system we designed.

The AR side records things a web only project cannot: what surface, how far away, at what angle.

The map updates while you watch it. We can paint something during the pitch and the judges see it
show up.

## What we learned

How precise "here" needs to be was a product decision, not a technical one. Once we settled on
"roughly this spot, facing that way", the rest got much easier.

The visual work was scored, not decoration. Putting every colour in one file early meant we could
restyle the whole app at 3am by editing one thing.

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
augmented-reality, arkit, ios, swift, swiftui, scenekit, lidar, geolocation, maplibre,
mapping, nextjs, typescript, postgresql, server-sent-events, realtime, reve, generative-art,
graffiti, street-art, community, docker, self-hosted, data-visualization, dashboard, geospatial
```

---

## Before the 1 PM submission

The draft describes the project as pitched. Checked against `main` as of the iOS geo anchor merge:

| Claim | State |
|---|---|
| AR paint, placement, scene photo | Done, on `main` (PencilKit, SceneKit, `ARGeoAnchor`) |
| Public live map, three zoom levels | Done, on `main` |
| Live updates without refresh | Done, `/api/stream` |
| `/data` page, the whole TECHNATION claim | In flight, not on `main` |
| Reve brand and the drawing to house style step | Not built. The palette is hand picked, not from Reve |

Cut or soften any row that is still unfinished at 11 AM. If the palette changes again, re-render
the cover so it still matches the app.
