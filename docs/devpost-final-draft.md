# Devpost final draft: Git Out of Town

**Tagline:** The city is the canvas. The map is the wall.

**Live:** https://gitoutoftown.129-153-49-190.sslip.io

**Source:** https://github.com/AlaqmarG/git-out-of-town

---

## Inspiration

We spent Saturday carrying our laptops between Toronto cafes, parks, and anywhere else with a
table. Somewhere along the way, we started talking about software that belongs to a place instead
of another browser tab.

Graffiti is probably the original location based social network. A tag matters because somebody put
it on that particular wall. We wanted to keep that part while losing the vandalism. Git Out of Town
lets people leave a mark on the city, then gives someone else a reason to walk over and find it.

## What it does

Point the iOS app at a real surface and let it scan for a moment. Take a photo, choose one of our 36
stickers or draw something yourself, then move it around until it looks right. Tap "Spray it on the
wall" and the app fits the art to the surface in front of you.

On a LiDAR iPhone, paint can bend around a corner, pick up texture from the wall, and hide behind
objects in the room. Phones without LiDAR use a simpler plane based version.

Posting adds the piece to a public map within seconds. Anyone can browse without an account or an
install, although painting currently requires the iOS build. Zoom out to see where people have been
active. Zoom in and the pieces appear with photos of the places where they live.

**The transformation:** a flat drawing or sticker becomes paint fitted to a measured physical
surface, tied to a real place, and added to a collage other people can visit. Freehand drawings can
also get a street art restyle and a weathered version after the original has posted.

The "What the wall knows" page shows when people paint, which colours they use, how long they spend,
and what surfaces they choose. It reads from the live database every five seconds, so a new post
changes the dashboard while you watch.

## How we built it

The painting experience is a SwiftUI app built with ARKit. Depth data helps shape art to the room
and identify the surface underneath it. To help another phone find the same spot, we combine visual
scans, a printed marker when one is nearby, surface alignment, and GPS.

The public side is a Next.js site with a MapLibre map whose dark style we made over OpenFreeMap
tiles. PostgreSQL stores the wall, pushes new pieces to open maps, and powers the live stats page.
The site runs in Docker on our own server.

We used Reve as a small design studio. It generated 18 matching stickers from one shared style guide
and two contact-sheet prompts. The other 18 came from the project's procedural graffiti renderer.
Reve also helped us develop the app icon and the rest of the visual direction.

## Challenges we ran into

Getting two phones to agree on where a piece belongs was harder than drawing it. Indoor GPS drifts,
compasses disagree, and visual tracking can reset. We ended up using several placement methods
instead of betting the project on one perfect anchor.

A clean PNG over a camera feed also looks fake immediately. We added soft edges, stray overspray,
uneven coverage, wall texture, and depth until the piece felt connected to the surface.

We had 26 hours, two people, two clients, and a server to keep alive. Each raw contribution is saved
before any optional image processing runs. If a model has a bad minute, the art still reaches the
wall.

## Accomplishments that we're proud of

We have a real public map that people can open now. Paint something on the phone and it appears on
that map a few seconds later. The stats page moves with it.

We are also proud that the AR work responds to the shape and texture of a place. The sticker pack,
map, and app icon give the project a consistent look. One piece is fun; a block full of them starts
to feel like people are talking to each other.

## What we learned

A latitude and longitude only get you part of the way. The wall, the direction you faced, nearby
visual landmarks, and the phone's confidence all matter. The app works best when it uses those
clues together and admits when a placement is approximate.

Reve was most useful when we treated it like an art tool instead of a button. The shared rules and
contact sheets gave us a starting point. Combining those assets with the map, interactions, and AR
treatment gave the project its own voice.

## What's next for Git Out of Town

- TestFlight, Android, and WebXR so more people can paint
- Shared walls, crews, and neighbourhood moderation
- Time lapse for watching a wall change
- Better shared anchors across larger areas
- Paint that ages through sun, rain, and a Toronto winter

---

## Suggested tags

`augmented-reality` · `arkit` · `swiftui` · `lidar` · `maplibre` · `nextjs` · `postgresql` ·
`realtime` · `reve` · `data-visualization` · `geospatial` · `street-art` · `community`
