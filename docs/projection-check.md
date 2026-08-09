# Projection check

Does `ARCamera.projectPoint` land a world point where SceneKit actually draws it?

Every placement depends on the answer. `ProjectedDecal.build` and `DepthDecal.build` decide which
part of the painted overlay belongs to which piece of real geometry by calling
`camera.projectPoint(_:orientation:viewportSize:)` — and then SceneKit renders the result. If the
two disagree by a constant amount, the art lands that far from where the user painted it, in AR and
in every composited still, and nothing else in the app would ever notice.

`apps/ios/ios/ProjectionCheck.swift` measures it on-device. It is debug-only and touches nothing in
the placement path.

## Running it — 30 seconds

1. Build and install (`apps/ios/CLAUDE.md` → *Pushing a build to a physical iPhone*).
2. Open **Paint**, wait for tracking to go green.
3. **Long-press the status pill** at the top — the existing debug toggle.
4. Point at a wall a metre or two away and **hold the phone still**.

Nine points get projected two ways at 4 Hz: four synthetic ones at 0.4 / 1 / 2.5 / 6 m spread across
the frame, plus the four corners and centre of the most recently placed piece if there is one. Place
a piece first if you want the corners covered.

On screen:

- **green crosshair** — `ARCamera.projectPoint`
- **pink crosshair** — `SCNSceneRenderer.projectPoint`
- **cyan dot** — a real `SCNNode` at that world point, i.e. what the renderer genuinely does
- yellow line and number — the gap, in points

A reading is drawn above the shutter:

```
proj Δ 0.31/0.62 px mean/max · n9 · portrait 393×852 · as-px 0.31
```

## Reading it

**Pass:** mean and max under ~1–2 px, the three markers stacked on top of each other, and the
numbers stay flat as you turn the phone toward different walls and depths. Sub-pixel is what
agreement actually looks like — the two calls should be evaluating the same matrix. (The app is
locked to portrait, so the orientation field should always read `portrait`; `ROTATED` is itself the
bug.)

**`proj hold still · pose skew 3e-03`** is not a failure. `ARSCNView` drives `pointOfView` from the
frame's camera, so while they are in step the two transforms are the same matrix; a difference means
the check straddled two frames and any gap it measured would be camera motion, not disagreement. It
refuses to print a number rather than print a false one. Stop moving and it clears.

**A gap that scales with distance from the top-left corner** — roughly ×3 on an iPhone — is units,
not geometry: SceneKit returned device pixels. The `as-px` figure is the same comparison done in
pixel space; if *that* is the small number, that is what happened, and the fix belongs in
`ProjectionCheck`, not in the app.

**Crosshairs mirrored vertically** means SceneKit used a bottom-left origin. Again a harness fix:
flip `scenekit.y` against the viewport height.

**A `drawable …` suffix** means the renderer's viewport is not the view's bounds × display scale.
That invalidates the `viewportSize:` argument everywhere, not just here — chase it before anything
else.

## If it genuinely fails

A real disagreement is constant: same pixel offset at every depth, every screen position, every
orientation. That means one correction, applied once, at the single place the app converts a world
point to a screen point — `camera.projectPoint(...)` in `ProjectedDecal.build`
(`apps/ios/ios/ProjectedDecal.swift`). `DepthDecal` does not call it; it goes the other way, from
screen to world through `DepthDecal.frame(for:viewport:orientation:)`, so a fix there is the same
offset with the opposite sign. Correct both, not one.

An offset that *varies* with depth or screen position is not a projection-path bug — it is the wrong
orientation or the wrong viewport being passed somewhere. Check what the harness prints for
orientation and viewport against what `ARPaintView.Coordinator.capture()` stored in the
`CapturedScene`.
