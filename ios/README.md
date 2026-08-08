# iOS app

Native SwiftUI + ARKit client. Talks to the same backend as the web app.

**This is a plain folder, not an npm workspace.** The web app at the repo root and this app share a
Git repository and an API contract — nothing else. Do not add npm tooling here.

## API contract

Same endpoints the web client uses. Schema of record: [`../db/init.sql`](../db/init.sql).

| | |
|---|---|
| `POST /api/pieces` | multipart: image + lat, lng, heading, kind, colors, stroke_count, duration_ms |
| `GET /api/pieces?bbox=` | pieces in view |
| `GET /uploads/<path>` | rendered art, served by nginx |

Base URL: `https://gitoutoftown.129-153-49-190.sslip.io`

## Before writing features

Get one signed build onto a real device **first**. Provisioning is where iOS hackathon projects die,
and you want that discovered early, not at 3 AM. See risks in [`../docs/02-build-plan.md`](../docs/02-build-plan.md).

## Notes

- `ARGeoTrackingConfiguration.checkAvailability` — verify at the venue; build the GPS-bearing
  fallback first and treat geo anchors as an upgrade.
- Draw in 2D (PencilKit), place as a textured quad at a raycast hit. Do not paint in 3D space.
- Do not try to relocalize with `ARWorldMap` — unreliable across sessions and devices.
