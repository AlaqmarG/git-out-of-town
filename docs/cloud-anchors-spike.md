# Spike: Google Cloud Anchors for cross-user precision

**Status: investigation only. Nothing is wired in.** No shipping file changed, no dependency added,
no code path the demo executes was touched. Everything below is a proposal for after the hackathon.
Verified against Google's docs on 2026-08-09; links at the bottom.

---

## What we do today

Three placement strategies, in the order `ARPaintView.Coordinator` prefers them:

| | Where | How it fails |
|---|---|---|
| **ARWorldMap relocalization** | `WorldMapStore.swift`, `maybeRelocalize()` | Needs `.resetTracking`, which deletes every anchor **including the LiDAR mesh** — so it is confined to the first 6 s of a session, before `meshCount > 0`. Miss that window and it never runs again. |
| **Stored `placementTransform` + GPS** | `worldPosition(for:from:cameraPos:)` | Off by whatever the GPS fix is off by. Indoors that is tens of metres. |
| **Billboard at GPS** | web pieces, no transform | Position only, no orientation. |

The world-map path also moves real bytes: compressed maps are 1–10 MB (`MAX_MAP_BYTES` is 32 MB),
and `maybeRelocalize()` will download and try up to **three** candidates, polling each for 10 s.

---

## How Cloud Anchors work

**Host:** you hand an `ARAnchor` to `GARSession`. The SDK uploads visual data from recent frames;
Google builds a 3D feature map of the space around the anchor and returns a **Cloud Anchor ID**
(an opaque string). You share that string however you like — for us, a column on `pieces`.

**Resolve:** another device sends the ID plus visual data from its current frame. Google matches
against the stored feature map and returns the anchor's pose in the resolving device's session.

On iOS, `GARSession` is a **sidecar to ARKit**, not a replacement for it: you keep your own
`ARSession` and `ARWorldTrackingConfiguration` and call `-update:(ARFrame *)` each frame. Nothing in
the docs asks you to change the `ARConfiguration` — the fact the whole case rests on, and the one
claim here most worth testing on device, since `sceneReconstruction` is what we would be risking.

The rest of the surface is small: `+sessionWithError:` (keyless) or `+sessionWithAPIKey:bundleIdentifier:error:`,
`-setConfiguration:error:` with `cloudAnchorMode = .enabled`, `-estimateFeatureMapQualityForHosting:error:`,
and `-hostCloudAnchor:TTLDays:completionHandler:error:` / `-resolveCloudAnchorWithIdentifier:completionHandler:error:`,
both returning cancellable futures. See the sketch at the end for the Swift shape.

---

## The verified numbers

| | Value | Source |
|---|---|---|
| Latest iOS SDK | **1.54.0**, released 2026-04-22 — actively maintained | GitHub releases |
| Min iOS | **13.0** (`Package.swift` declares `.iOS(.v13)`; the 1.48.0 notes dropped <13.0). The README still says 11.0 — it is stale. We target 26.2, so this is a non-issue. | `Package.swift` |
| Install | SPM: `https://github.com/google-ar/arcore-ios-sdk`, product `ARCoreCloudAnchors`. Also CocoaPods `ARCore/CloudAnchors`. | README |
| Build settings | `-ObjC` in Other Linker Flags, Enable Modules = Yes, Link Frameworks Automatically = Yes, Bitcode = No | README |
| Binary weight | `CloudAnchors.zip` 5.6 MB + `GARSession.zip` 2.9 MB + `Base.zip` 35 MB of xcframework download | `dl.google.com/arcore/swiftpm/1.54.0/*` |
| Transitive deps | nanopb, GoogleDataTransport, gtm-session-fetcher, **and `firebase-ios-sdk` (FirebaseRemoteConfig)** | `Package.swift` |
| Max TTL | **1 day** with an API key, **365 days** with keyless auth | iOS dev guide |
| Quotas | 30 host req/min and 300 resolve req/min, per IP **and** project; 40 simultaneous operations per session; SDK-wide 1,000 sessions/min or 100,000 req/min per project | iOS dev guide, `GARSession` reference, quota page |
| Cloud API | `arcore.googleapis.com` ("ARCore API") must be enabled | authorization guide |
| Deprecation policy | If Google discontinues Cloud Anchors it commits to "commercially reasonable efforts" to keep it running **one year** after the announcement | deprecation policy |

### Cost — do not write "free" in a slide without re-checking

Google publishes **quotas but no price list** for the ARCore API. I could not find an official page
stating Cloud Anchors is free of charge; the "it's free" claims in circulation are third-party. The
honest position: there is no published charge and no billing account is demanded to enable the API,
but that is an observation, not a commitment. Re-verify before it becomes a business assumption.

### Accuracy — Google publishes no number

Worth stating plainly, because the premise of this spike assumed one. The strongest official claims
are qualitative: `GARFeatureMapQuality`

- `INSUFFICIENT` — feature quality is low,
- `SUFFICIENT` — "likely sufficient ... although the accuracy of the resolved pose will likely be reduced",
- `GOOD` — "likely sufficient ... with a high degree of accuracy",

plus "best used for room-scale AR experiences". The centimetre figures you find online are blog
posts, not Google. **We cannot justify this on a published accuracy advantage over ARWorldMap.** The
case has to rest on the operational differences below.

### Indoors

Works indoors — room-scale is the stated design point, and unlike `ARGeoAnchor` there is no VPS
coverage map to fall outside of. It needs the same things ARWorldMap needs: texture, light, and the
painter physically moving around the anchor (not pivoting on the spot). It additionally needs a live
internet connection at both host and resolve time.

### Privacy

- Hosting: video data is uploaded, "stored temporarily", and "marked for automatic deletion after the
  Cloud Anchor hosting process has finished".
- Resolving: video data is "processed in real-time, in memory only" and not retained.
- Google states it does not share this video data with third parties; transit is HTTPS.
- **Mandatory disclosure.** Google requires the app to show, prominently, "To power this session,
  Google will process sensor data (e.g., camera and location)" with a learn-more link. That is a
  visible UI change and an App Store privacy-label change.
- Second-order: pulling `FirebaseRemoteConfig` in transitively brings Firebase Installations and its
  identifier into an app that currently talks to nobody but our own VPS.

---

## The TTL problem — this is the blocker

Our pitch is "it pins to that spot forever". Cloud Anchors cannot do forever.

- Maximum TTL is **365 days**, and only with keyless auth (API key = 24 hours).
- The Management API can `PATCH` an anchor's `expireTime` — but only **up to its
  `maximumExpireTime`**, and in Google's own example an anchor created 2020-06-29 has
  `maximumExpireTime` 2021-06-29. So the ceiling looks fixed at creation + 1 year. I found no
  documented way to raise `maximumExpireTime`, which means renewal is capped, not open-ended. *(This
  is inference from the documented example, not an explicit statement — confirm empirically before
  building on it.)*
- Recovering a spot past that ceiling means **re-hosting from a device physically standing there**,
  which produces a *new* anchor ID and a slightly different pose.

Two ways to live with it:

1. **Accept it as product truth.** A piece stays pinned for a year, and every visit that re-hosts it
   renews it. Graffiti fades unless someone comes back — arguably a better story than "forever", and
   it makes the map a record of what is still cared about.
2. **Keep the existing paths as the durable layer**, with the cloud anchor as an expiring precision
   cache on top. Low-risk, and what the sketch below assumes.

---

## Integration sketch against this codebase

### Contract and storage

| File | Change |
|---|---|
| `packages/shared/src/index.ts` | `Piece`: add `cloudAnchorId: string \| null` and `cloudAnchorExpiresAt: string \| null`. `CreatePieceRequest`: add `cloudAnchorId?: string`. Document that it is *optional precision*, never the source of truth — `placementTransform` stays authoritative. |
| `db/init.sql` | `pieces`: `cloud_anchor_id TEXT`, `cloud_anchor_expires_at TIMESTAMPTZ`; partial index `WHERE cloud_anchor_id IS NOT NULL`. |
| `apps/web/lib/pieces.ts` | `Row`, `toPiece()`, the two column lists, and the `meta` validator (`validateMeta`) — the single snake↔camel conversion point. |
| `apps/web/app/api/pieces/route.ts` | Nothing, if the id rides in `meta`. |
| new `apps/web/app/api/arcore-token/route.ts` | Mints the keyless JWT (below). |
| `apps/ios/ios/APIClient.swift` | `PieceDTO` + `MetaDTO` field, mirroring shared. |

`cloudAnchorId` should be set by a **PATCH after the fact**, not on `POST /api/pieces`: hosting
takes seconds and can fail, and blocking the post on it would regress the demo's snappiest moment.

### Auth: keyless means we run a token endpoint

An API key caps TTL at one day, so keyless is effectively mandatory. Keyless on iOS means an
RS256-signed JWT with `iss`/`sub` = service-account email, `aud` = `https://arcore.googleapis.com/`,
`exp` = `iat + 3600`, handed to `-setAuthToken:` and refreshed hourly. The signing key must not ship
in the app, so:

- service-account JSON in `.env` + a GitHub secret (see `docs/OPS.md` conventions),
- `GET /api/arcore-token` returns a fresh JWT,
- iOS caches it and re-fetches before expiry.

That is a real new piece of server surface with a real secret to rotate. Budget for it.

### iOS

One new file, `apps/ios/ios/CloudAnchorStore.swift`, owning the `GARSession` lifecycle, mirroring how
`WorldMapStore.swift` owns "how" while the coordinator decides "when".

Touch points in `ARPaintView.swift`:

- **Frame pump.** Google's sample feeds `GARSession` from `ARSessionDelegate.session(_:didUpdate:)`,
  which `ARSCNViewDelegate` does not carry — and taking `session.delegate` away from a view that
  drives its own node updates is a risk with no upside. Feed frames from the existing
  `renderer(_:updateAtTime:)` hook using `scnView.session.currentFrame` instead: the same place
  `maybeRelocalize()` and `maybeReanchor()` already run.
- **Host.** In `saveScan(pieceId:)`, right where the named `piece:<id>:<mm>` anchor is added, also
  `hostCloudAnchor:TTLDays:365`. Gate it on `estimateFeatureMapQualityForHosting` ≥ `SUFFICIENT` and
  surface the result through the existing `ARController.setScanQuality` chip.
- **Resolve.** A new `maybeResolveCloudAnchors()` sibling to `maybeRelocalize()`, driven off the same
  poll that already fetches nearby pieces. For each nearby piece with a `cloudAnchorId`, resolve it;
  on success route into the existing `attachAnchoredPiece` machinery — `anchoredPieceIDs` already
  suppresses the GPS copy, so nothing downstream changes.
- `ContentView.swift:503` (`ar.saveScan(pieceId:)`) is where the post→host handoff hangs.

### Runtime priority

1. **Cloud anchor resolve** — per-piece, no session reset, can run at any moment.
2. **ARWorldMap relocalize** — unchanged, still first-6-seconds-only, for pieces with no cloud anchor
   or when resolution fails/expires.
3. **`placementTransform` + GPS** — unchanged final fallback, and the only one that never expires.

They compose cleanly because they all end at the same place: a transform for a node, with
`anchoredPieceIDs` deciding who owns the piece.

---

## Honest comparison

### Where Cloud Anchors genuinely win

- **No `.resetTracking`.** This is the big one. Our world-map path is boxed into a 6-second window
  *solely* because relocalizing resets the session and destroys the LiDAR mesh — a constraint
  `apps/ios/CLAUDE.md` calls out as non-negotiable. `GARSession` consumes the frames of the session
  we configured, so on paper resolution can happen at second 90 with a full mesh intact — reaching
  viewers our current path structurally cannot.
- **Per-piece, not per-scan.** Today a piece's precision depends on someone having uploaded a good
  map near it, and on the viewer's session matching *that* map. A cloud anchor belongs to the piece.
- **No multi-MB transfer.** Ship an ID instead of the blob, times up to three candidates.
- **Server-side matching.** Google matches against a feature map built from many angles; ARWorldMap
  relocalization wants a viewpoint similar to the painter's.
- **Cross-platform later.** Same anchors resolve on Android, which our ARWorldMap approach can never
  do.

### Where it does not justify the dependency

- **It cannot deliver "forever."** 365-day ceiling, apparently non-extendable past creation + 1 year.
- **No published accuracy advantage.** We would be adding a dependency on a qualitative claim.
- **Dependency weight.** A closed-source binary framework plus the Firebase SDK, in an app whose
  current dependency count is zero.
- **New server surface and a new secret** (the token endpoint), for a team that currently has one
  service and one database.
- **A Google account becomes load-bearing** for a product about permanent public art, and the
  mandatory sensor-data disclosure has to go in the UI.
- **Network at resolve time.** Same as today's world-map download, but now on Google's uptime too.
- **Hosting still asks the painter to scan.** No UX saving over what we already do.

### The case for not doing it

Our measured failure mode is a *viewer* with a ±20 m indoor GPS fix. Before buying a dependency,
cheaper experiments exist: widen `maybeRelocalize()`'s candidate list, weight `feature_points` harder
in the `/api/worldmaps` ordering (already a `< 150` sort key), or reconstruct against a nearby piece's
transform instead of raw GPS. Those cost days, not a vendor. And the current path is demo-proven,
which counts for a lot.

---

## Recommendation: conditional

Do not adopt now. Adopt if, after the hackathon, **both**:

1. cross-user misplacement is measured — not assumed — to be dominated by viewers who missed the
   6-second relocalization window (which is the failure Cloud Anchors uniquely fixes), and
2. the team accepts "pinned for a year, renewed by visits" as the product truth.

If (1) holds but (2) does not, the layered design above is still right: cloud anchor as an expiring
precision cache over a permanent `placementTransform`.

Suggested spike-to-decision path: build the sample from
`arcore-ios-sdk/Examples/PersistentCloudAnchorExample` (rewritten in Swift/SwiftUI as of 1.45.0),
host an anchor on a textureless indoor wall and a textured one, and measure resolve latency and
apparent drift on a second device. One afternoon, no changes to our app.

---

## Reference sketch — deliberately not a file

⚠️ **Do not paste this into `apps/ios/ios/`.** `ios.xcodeproj` uses a
`PBXFileSystemSynchronizedRootGroup`, so *any* `.swift` file dropped in that folder is compiled
automatically. A stub referencing `ARCore` would break the build the moment it landed. It lives in
this document precisely so it cannot.

```swift
// Sketch only. Not compiled. Requires the ARCoreCloudAnchors SPM product.
import ARCore
import ARKit

@MainActor
final class CloudAnchorStore {
    private var session: GARSession?

    /// Keyless: the token is minted by GET /api/arcore-token and expires hourly.
    func start(authToken: String) throws {
        let session = try GARSession.session()           // sessionWithError:
        session.setAuthToken(authToken)
        let config = GARSessionConfiguration()
        config.cloudAnchorMode = .enabled
        try session.setConfiguration(config)
        self.session = session
    }

    /// Call from renderer(_:updateAtTime:) with scnView.session.currentFrame,
    /// rather than taking over ARSCNView's session.delegate.
    func update(_ frame: ARFrame) { _ = try? session?.update(frame) }

    func quality(at transform: simd_float4x4) -> GARFeatureMapQuality {
        guard let session, let q = try? session.estimateFeatureMapQuality(forHosting: transform)
        else { return .insufficient }
        return q
    }

    /// 365 is the keyless maximum. With an API key the maximum is 1.
    func host(_ anchor: ARAnchor) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            _ = try? session?.hostCloudAnchor(anchor, ttlDays: 365) { id, state in
                if let id, state == .success { cont.resume(returning: id) }
                else { cont.resume(throwing: CocoaError(.coderInvalidValue)) }
            }
        }
    }

    /// On success, hand the GARAnchor's transform to the existing
    /// attachAnchoredPiece path so anchoredPieceIDs suppresses the GPS copy.
    func resolve(_ id: String) async -> GARAnchor? {
        await withCheckedContinuation { cont in
            _ = try? session?.resolveCloudAnchor(withIdentifier: id) { anchor, state in
                cont.resume(returning: state == .success ? anchor : nil)
            }
        }
    }
}
```

Signatures are transcribed from the Objective-C reference and are illustrative — the Swift-imported
names have not been compiled against the SDK.

---

## Sources

- [Cloud Anchors overview](https://developers.google.com/ar/develop/cloud-anchors)
- [Cloud Anchors developer guide for iOS](https://developers.google.com/ar/develop/ios/cloud-anchors/developer-guide) — TTL, quotas, `cloudAnchorMode`
- [Cloud Anchors developer guide for Android](https://developers.google.com/ar/develop/java/cloud-anchors/developer-guide) — FeatureMapQuality wording, hosting best practices
- [GARSession API reference](https://developers.google.com/ar/reference/ios/interface/GARSession)
- [Enable AR in your iOS app](https://developers.google.com/ar/develop/ios/enable-arcore) — install, build settings
- [Use the ARCore API on Google Cloud](https://developers.google.com/ar/develop/authorization) — keyless JWT claims
- [Cloud Anchor Management API](https://developers.google.com/ar/develop/cloud-anchors/management-api) — `expireTime` / `maximumExpireTime`
- [ARCore privacy requirements](https://developers.google.com/ar/develop/privacy-requirements) — mandatory disclosure string
- [Data safety form guidance](https://developers.google.com/ar/develop/play-safety-label) — what video data is stored and for how long
- [Geospatial API usage quota](https://developers.google.com/ar/develop/c/geospatial/api-usage-quota) — project-wide SDK limits
- [Cloud Anchor deprecation policy](https://developers.google.com/ar/develop/cloud-anchors/cloud-anchor-deprecation-policy)
- [arcore-ios-sdk releases](https://github.com/google-ar/arcore-ios-sdk/releases) and [`Package.swift`](https://github.com/google-ar/arcore-ios-sdk/blob/main/Package.swift)
- [PersistentCloudAnchorExample](https://github.com/google-ar/arcore-ios-sdk/tree/main/Examples/PersistentCloudAnchorExample)
