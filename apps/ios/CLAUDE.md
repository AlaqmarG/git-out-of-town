# apps/ios

Native SwiftUI + ARKit client. **A plain folder, not an npm workspace** — do not add npm tooling.

Shares a Git repo and an API contract with the web app. Nothing else.

## API

Base: `https://gitoutoftown.129-153-49-190.sslip.io`
Field names and shapes: `../../packages/shared/src/index.ts` (mirror them exactly).

| | |
|---|---|
| `POST /api/pieces` | multipart: `image` (PNG) + `meta` (JSON) |
| `GET /api/pieces?bbox=w,s,e,n` | pieces in view |
| `GET /uploads/<path>` | rendered art |

Always send `client: "ios"` plus the native fields: `surfaceType`, `distanceM`, `devicePitch`,
`usedGeoAnchor`, `hasLidar`.

## Shape

Three tabs (`iosApp.swift`): **Paint** (AR, `ContentView` + `ARPaintView`), **Map** and **Stats**
(`WebView.swift` — the live site's `/` and `/data` rendered in-app; the web pages are canonical,
don't rebuild them natively). Flow: tap → semi-transparent preview + size slider → Place (stamps
the quad, blends in the surface texture via `SurfaceTexture.swift`) → Post/Discard card — nothing
uploads without the explicit Post. LiDAR devices get scene reconstruction: mesh occlusion +
per-face `surface_type` (`MeshOcclusion.swift`); non-LiDAR devices fall back to plane
classification, and everything still works.

## Decisions already made — don't relitigate

- **Draw in 2D with PencilKit, place as a textured quad** at a raycast hit. `ModelEntity` plane mesh
  + `UnlitMaterial` carrying the PNG. Do **not** paint in 3D space.
- **Build the GPS-bearing fallback first.** `ARGeoAnchor` is an upgrade switched on only if
  `ARGeoTrackingConfiguration.checkAvailability` passes *at the venue*. The demo must never depend
  on it. Harness: `GeoCheck.swift`.
- **Do not relocalize with `ARWorldMap`.** Large, device-specific, unreliable across sessions.
- **Get a signed build on a real device before writing features.** Provisioning is what kills iOS
  hackathon projects.

## Info.plist

`NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`

## LiDAR

`ARMeshClassification` at the raycast hit gives `surfaceType` (wall/floor/ceiling/…). This is the
dataset no web-only project can produce — send it when available, null otherwise.
