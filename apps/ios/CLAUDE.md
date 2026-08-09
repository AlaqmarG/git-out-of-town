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

Three tabs (`iosApp.swift`): **Paint** (AR, `ContentView` + `ARPaintView`), **Around You**
(native MapKit, `MapTabView.swift`) and **Stats** (`WebView.swift` — the live site's `/data`
rendered in-app; that page is canonical, don't rebuild it natively). Flow: tap → semi-transparent preview + size slider → Place (stamps
the quad, blends in the surface texture via `SurfaceTexture.swift`) → Post/Discard card — nothing
uploads without the explicit Post. LiDAR devices get scene reconstruction: mesh occlusion +
per-face `surface_type` (`MeshOcclusion.swift`); non-LiDAR devices fall back to plane
classification, and everything still works.

## Decisions already made — don't relitigate

- **Draw in 2D with PencilKit, place as a textured quad** at a raycast hit. `ModelEntity` plane mesh
  + `UnlitMaterial` carrying the PNG. Do **not** paint in 3D space.
- **Never run `ARGeoTrackingConfiguration`.** It has no `sceneReconstruction` property, so switching
  to it silently destroys the LiDAR mesh — and with it occlusion, decal wrapping, and surface
  classification. We shipped that swap once: in a covered city (Toronto) it fired a few seconds
  after launch with `.removeExistingAnchors` and quietly disabled every depth feature. Geo precision
  is worth less than depth, and indoors it never localises anyway. `GeoCheck.swift` is a harness
  only; do not wire it into the session.
- **`ARWorldMap` relocalization is scoped tightly** (`WorldMapStore.swift`): save only after a
  post, once the session has reached `.mapped`; match only in the first seconds of a fresh
  session, before any mesh exists — a late `.resetTracking` deletes the depth mesh. Do not widen
  either window.
- **Get a signed build on a real device before writing features.** Provisioning is what kills iOS
  hackathon projects.

## Pushing a build to a physical iPhone

This works today and is fully scriptable — do **not** drive the Xcode GUI for it.

`xcode-select` on this Mac points at CommandLineTools, so **every** command needs:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

### Signing: override, never commit

`project.pbxproj` pins `DEVELOPMENT_TEAM = N3P4T5Z6P8` / `PRODUCT_BUNDLE_IDENTIFIER = summerhacks.ios`.
That team belongs to someone else, and that bundle ID is already registered to it — a different
Apple ID cannot build it. **Do not edit the project file to fix this**; you would break whoever
owns that team. Pass overrides on the `xcodebuild` command line instead.

Your values live in `.env` (gitignored), keyed as in `.env.example`:

```sh
IOS_TEAM=...      # your team ID; free "Personal Team" is fine
IOS_BUNDLE=...    # globally unique and owned by that team
```

Find your team ID with:

```sh
defaults read com.apple.dt.Xcode | grep -A3 IDEProvisioningTeamByIdentifier
```

`IOS_BUNDLE` has to be yours. Reusing `summerhacks.ios` fails with *"Failed Registering Bundle
Identifier"* because it is already registered to the team pinned in the project file.

### Build, install, launch

Run from the repo root, like every other script here.

```sh
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

`-allowProvisioningUpdates` is required: it creates the development certificate, registers the
device, and issues the profile. Without it the build fails with *"No profiles for ... were found"*.

Because the overrides live on the command line, **the ▶︎ Run button in Xcode still fails** with the
original signing errors. That is expected. Build from the CLI.

### Two steps only a human can do

1. **Developer Mode** — Settings → Privacy & Security → Developer Mode → on, then reboot.
   Check with `xcrun devicectl device info details --device "$DEVICE" | grep developerModeStatus`.
2. **Trust the profile** — after the *first* install with a new certificate, Settings → General →
   VPN & Device Management → Developer App → Trust. Until then `process launch` fails with
   *"its profile has not been explicitly trusted by the user"*. One-time per certificate, not per build.

### Symptoms → cause

| Symptom | Cause |
|---|---|
| `devicectl: unable to find utility` | `DEVELOPER_DIR` not exported |
| Device state `connected (no DDI)`, Xcode says *"developer disk image could not be mounted"* | Developer Mode off. Once on, any `devicectl` call mounts it — the Xcode alert is stale, dismiss it |
| `No Account for Team "N3P4T5Z6P8"` | `IOS_TEAM` unset, so the pinned team leaked through |
| `Failed Registering Bundle Identifier` | `IOS_BUNDLE` unset, or set to one your team doesn't own |
| App installs, won't launch, *"invalid code signature"* | Profile not trusted on device (step 2 above) |
| App installs, won't launch, *"device was not ... unlocked"* | Screen is locked. Install works locked; launch does not |

Free personal-team builds **expire after 7 days**, and the account is capped at 3 apps / 10 App IDs
per week. Reinstall before demoing.

## Info.plist

`NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`

## LiDAR

`ARMeshClassification` at the raycast hit gives `surfaceType` (wall/floor/ceiling/…). This is the
dataset no web-only project can produce — send it when available, null otherwise.
