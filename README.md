# Git Out of Town

![Git Out of Town cover](docs/assets/brand/devpost-cover-1200.png)

Spray paint the real world without leaving a mark on it.

Git Out of Town is a shared AR graffiti wall built at SummerHacks 2026. Draw or place a sticker in
the iOS app, spray it onto a real surface, and it appears on a public map seconds later. Anyone can
browse without an account or an install. Painting currently requires the native iOS build.

[Live map](https://gitoutoftown.129-153-49-190.sslip.io) ·
[Live data](https://gitoutoftown.129-153-49-190.sslip.io/data) ·
[Devpost draft](docs/devpost-final-draft.md)

## How it works

The app includes PencilKit drawing and a 36-piece sticker pack. On LiDAR iPhones, ARKit projects the
art onto measured geometry so it can follow corners, inherit wall texture, and hide behind real
objects. Other iPhones fall back to plane detection.

Pieces are placed using the best signal available: a shared printed marker, visual `ARWorldMap`
scans, surface alignment, or GPS. Freehand art posts immediately, then an optional Replicate
pipeline can restyle and weather it.

The website uses a custom MapLibre style over OpenFreeMap tiles. PostgreSQL stores the wall and
pushes new pieces to open maps through Server-Sent Events. The `/data` dashboard shows live
locations, colours, surfaces, painting time, and views.

We made 18 sticker symbols with Reve and paired them with 18 word stickers rendered from a graffiti
alphabet we wrote ourselves.

## Stack

SwiftUI · ARKit · SceneKit · PencilKit · Next.js 16 · React 19 · TypeScript · MapLibre GL ·
PostgreSQL 17 · Replicate · Docker · nginx · Traefik · Komodo

## Run locally

Requires Node.js 22 or newer and Docker.

```bash
cp .env.example .env
npm ci
docker compose up -d got-db
set -a; . ./.env; set +a
npm run dev
```

Open http://localhost:3000. Run checks with:

```bash
npm run typecheck
npm run lint
npm test
npm run build
```

The iOS app needs Xcode 26. Device setup is documented in
[`apps/ios/CLAUDE.md`](apps/ios/CLAUDE.md).

## Repository

```text
apps/web/          Web app, API, map, dashboard
apps/ios/          Native AR client
packages/shared/   TypeScript API contract
db/                PostgreSQL schema
scripts/           Tests, seeding, graffiti tools
docs/              Product, judging, demo, operations
```

Start with the [Devpost draft](docs/devpost-final-draft.md), [judging criteria](docs/judging-criteria.md),
[demo runbook](docs/DEMO-RUNBOOK.md), or [operations guide](docs/OPS.md).
