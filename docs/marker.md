# The printed AR origin marker

A poster that two phones can both look at to agree where "zero" is.

Without it, each device's world origin is wherever its own session happened to start, and the only
thing tying two devices together is GPS — metres of error indoors, and worse under a roof. Point
both phones at the same poster and both move their world origin onto it, so their coordinates share
an origin to a few centimetres.

**File:** [`assets/ar-origin-marker.png`](assets/ar-origin-marker.png) · **Code:**
`apps/ios/ios/ImageMarkerOrigin.swift`

## Printing it

**Exactly 18.0 × 18.0 cm.** Print at **100% / "Actual size"**, never "Fit to page" — A4 and Letter
both default to shrinking a full-bleed image by a few percent. That same 18 cm is declared in
`apps/ios/ios/Assets.xcassets/ARMarkers.arresourcegroup/OriginMarker.arreferenceimage/Contents.json`,
and ARKit trusts it completely: a printout at 95% makes it think it is standing 95% as far away, so
every distance in the session is wrong by that ratio — silently, with tracking that still looks
perfect. The poster carries a **10.0 cm ruler**; measure it after printing, and reprint rather than
adjusting anything in the app.

Then mount it flat, no curl, matte paper if you have it. Tape all four corners to a wall at roughly
chest height, somewhere both phones can see it from a metre or two.

## Using it at the venue

1. Print the poster and tape it to the wall.
2. Open **Paint** on each phone and point it at the poster for a second from about 1 m.
3. Each phone shows **"Marker found — positions are now exact"** and keeps it for the session.
4. Paint on one phone, within a couple of metres of the poster. Post it.
5. The other phone shows it on the same bricks, within a few seconds.

That is the whole interaction. There is no button. Step 3 has to happen on **both** phones before
step 4 — a piece painted without the poster in view carries no marker pose, and a viewer that never
saw the poster cannot use one.

## When it does not work

Nothing breaks. If the poster is never seen — not printed, out of frame, too dark, too far — the
app behaves exactly as it does today: GPS plus `ARWorldMap` relocalization. The marker is additive.

The origin is adopted **once per world frame**, and only while nothing has been placed in the scene
yet: moving the origin under art that is already on a wall would teleport it. Re-detecting the same
poster later in the session does nothing. A `.resetTracking` (world-map relocalization, or "Start
Over" on the coaching overlay) throws the world frame away, and the poster is adopted again after it.

## What crosses the wire

A piece painted with the poster in view carries a second copy of its placement, `markerTransform` —
the same 4x4, expressed in the poster's own frame instead of in lat/lng plus a compass bearing. It
is null for every piece painted without one, which is what makes the migration free: an old row
reads as "no marker" because that is the truth.

A viewer that has locked onto the same poster prefers it and ignores lat/lng entirely — no GPS, no
surface snapping, no reanchor loop second-guessing it. That is the whole cross-device path:

```
painter          marker frame (physical)          viewer
world_A  ──inverse(frame_A)──▶  markerTransform  ──frame_B──▶  world_B
```

Both devices measure `frame` off the same physical object, so **neither compass appears in the
round trip** — that is why this is exact and lat/lng is not.

## Why the origin move is translation-only

Only the origin moves; the axes stay north-up ENU, because that is what every geo conversion in
`ARPaintView` and every `ARWorldMap` we upload is written against. Rotating the world onto the
poster's yaw would silently re-frame all of it, including scans already on the server.

The poster's **rotation** is still needed — ENU comes from the compass, and two compasses indoors
disagree by degrees, which is tens of centimetres a couple of metres out. So it is kept in
`ImageMarkerOrigin.frame` and applied only at the wire boundary, never to the session.

That frame takes gravity for two of its three axes and the poster only for the yaw: ARKit's
image-anchor rotation is good to a degree or two, the gravity vector to a tenth of one. It assumes
the poster hangs roughly plumb — tape it straight.

## Accuracy, honestly

What is left after the compass cancels is the two devices' disagreement about the poster's *yaw*,
multiplied by how far the piece is from the poster. Modelling that with 1.5° (1σ) of image-anchor
noise per device:

| piece is | median | p95 |
|---|---|---|
| within 1 m of the poster | 1.3 cm | 5 cm |
| 1–2 m | 3.4 cm | 11 cm |
| 2–4 m | 5.3 cm | 15 cm |

So: **single-digit centimetres if you paint within a metre or so of the poster**, degrading roughly
linearly with distance. The same model with no marker — two compasses, no shared reference — gives
errors up to 1.9 m. Paint near the poster.

These are modelled numbers, not measured ones: the error is dominated by an assumption about ARKit's
image-anchor yaw noise. **Nobody has yet run the two-phone test on real hardware.** Do that before
believing the table.

The poster's identity is positional, not encoded — one per venue. Two posters inside the ~300 m
piece-fetch radius would be indistinguishable, and pieces from one would appear at the other.
