# Baking graffiti into a photograph

These modules take a Street View still and a generated throw-up and return one JPEG that
looks like a photograph of a painted wall. The paint is composited **server-side, in
perspective**; the web no longer overlays anything on top.

```
streetview.mjs   fetch a still (disk-cached — every fetch is billed)
   ↓
surface.mjs      find a flat wall and recover the plane it lies on
   ↓
art.mjs          draw a throw-up sized to that plane   ← letters.mjs, rng.mjs
   ↓
composite.mjs    warp it onto the plane, then blend it into the surface
   ↓
graffiti.mjs     the entry point: paintStreetView(lat, lng, heading)
```

`image.mjs` is the shared raster toolkit. `jpeg-js` is the only image dependency, and it is
pure JS on purpose — `sharp` is a native build and a deployment liability on the ARM VPS.

---

## Why each pass exists

Ordered by how much each contributes. The surprise is that the geometry is *not* the top of
the list: a perfect homography with flat, even paint still reads as a decal, while
imperfect perspective with convincing coverage reads as paint.

### 1. Coverage wear — the one that matters most

Spray travels in a straight line. It does not reach into a recess, so mortar joints, grime
lines and pitting stay bare and read straight through the colour. This single pass does
more for believability than everything below it.

The trick is measuring relief *physically*. The obvious implementation — normalise local
darkness by the region's own variance — fails badly: on a smooth roller shutter the variance
is pure JPEG noise, so it amplifies ±1-unit noise into ±2 swings and punches holes through
the paint at random. Instead, `shade` is how much darker a pixel is than its surroundings
**as a fraction of local brightness**. A mortar joint reads ≈ −1.5, a shutter's shallow
groove ≈ −0.7, and sensor noise ≈ −0.05 and is correctly ignored.

### 2. Texture modulation

The wall's own fine detail multiplies through the paint, so brick keeps reading as brick
under the colour. Two details:

- It reads from a **narrow** local reference (blur r=5). Given a wide one it also picks up
  window reveals and door frames, and printing a whole window through the paint makes the
  piece look like coloured glass.
- It goes through a soft knee (`tanh`), not a hard clamp, so mortar passes almost linearly
  while stronger structure saturates. Opaque paint hides structure; it does not hide grain.

It deliberately reads the **raw** luminance, noise and all. That carries the photograph's own
grain onto the paint, perfectly correlated with the surrounding pixels in a way that added
noise never is.

### 3. Light matching

Paint is lit by whatever is lighting that bit of wall, so the colour is scaled by a
**wide** blur (r=22) of the local luminance — the illumination field with the texture
removed. It is also pulled toward the scene's illuminant, and desaturated: nothing in a
street photograph is as vivid as a paint swatch, and bright paint on a shadowed wall is the
classic tell.

### 4. Perspective

`surface.mjs` recovers the actual plane and `composite.mjs` warps onto it with an inverse
homography and bilinear sampling — destination→source, because forward-mapping leaves holes
wherever the quad is magnified. 2×2 supersampled, since the art is always rendered larger
than it lands.

The vanishing point leans on one fact about the imagery: the Street View static API renders
a rectilinear projection, so at `pitch=0` the horizon is **exactly the centre row**. Every
vanishing point of a horizontal line lies on that row, which turns a fragile 2-D fit into a
1-D one. Each oriented pixel then votes for its own vanishing point directly
(`x + (y − cy)·tanφ`), weighted by `|cosφ|` — the precision of that estimate, so a perfectly
horizontal edge correctly contributes nothing. The axis is compressed through `atan`, so
"at infinity" is a real bin and a frontal wall produces a clean peak there rather than a
smeared tail.

The quad is then the **inscribed** rectangle of the region measured on the plane, not the
bounding box. A rectangle in the image is a trapezoid on a raked plane whose far end covers
far more ground than its near end; bounding it produces a world rectangle several times
larger than the region that was vetted, which reprojects halfway across the frame.

### 5. Occlusion

Paint must not cross the lamp post standing in front of the wall. A robust colour model
(median/MAD) of the chosen region flags outliers — but it also flags the window frames *on*
the wall, and punching those out makes the piece look transparent. Two guards: morphological
opening deletes anything thinner than a few pixels, so frame lines go while poles and cars
survive; and the mask's authority is scaled by how well the model actually fits the region,
because on a box straddling brick and plywood its verdicts are mostly noise.

### 6. Edge treatment and grain

A light blur on the warped alpha, scaled to the piece — real spray has no crisp boundary,
but a fixed 1px blur is invisible on a wall-sized throw-up and turns a small one to mush.
Then grain matched to the photograph's own, measured by MAD of its high-frequency content.

### …and one fix in the artwork itself

`art.mjs` used to render strokes with a wide gradient falloff, which seems like the obvious
way to draw spray. It is wrong: it produces an airbrushed glow around every letter, and once
composited that halo was the loudest tell in the frame. Strokes are now hard-edged with a
~1.3px feather, and overspray is a separate pass of individual droplets — which is what you
actually see on a wall.

---

## Choosing where to paint

`surface.mjs` scores every 8px cell, then sweeps for the best rectangle of good cells with
an integral image.

The discriminator that matters is **coarse** flatness, not fine flatness. Brick is full of
detail but is perfectly flat once blurred; a car, a window or a hedge is not. So the
dominant term is the variance of a *blurred* luminance, with fine gradient energy only a
tiebreaker. Quality is cubed in the score but area carries a high exponent — a small
immaculate patch is the wrong answer, because a postage stamp of paint in the middle of a
garage door looks exactly like an algorithm being timid.

Three things score perfectly on every flatness test and must never be painted:

| | how it is caught |
|---|---|
| **Sky** | Blue outright by colour. Overcast white is indistinguishable from a white wall, so it needs a flood fill from the top edge that refuses to cross a strong edge. |
| **Grass** | The most dangerous false positive: flat, evenly textured, below the horizon, and it scores like a beautiful wall. A green-dominant test misses dry olive grass, so vegetation is caught by **hue** (46°–178°), a band no masonry occupies. |
| **Tarmac** | Below the horizon, grey, and with no vertical lines nearby. With a level camera only a vertical plane can show vertical lines, so door jambs and downpipes are the cleanest evidence that a smooth grey rectangle is a wall and not pavement. |

Interiors are excluded upstream: user-contributed photospheres are indexed at the same
coordinates as the road-level car imagery and some are shot indoors, so `streetview.mjs`
takes only imagery whose copyright line is Google's.

---

## What works and what does not

**Works well**

- Brick and cinderblock, frontal or raked. The best case by some distance — mortar joints
  crossing the letters sell it completely.
- Painted concrete and stucco.
- Roller shutters and garage doors, frontal.
- Raking walls up to about a 3:1 foreshortening. Beyond that the estimate is rejected.

**Still looks wrong**

- **Boarded windows and panelled doors.** Panel edges show through the paint. They are the
  same few pixels wide as a mortar joint and only ~1.5× the contrast, so no filter separates
  them — the difference is semantic, not signal-level. The honest fix is placement, but
  every threshold strict enough to reject these also rejects good brick walls.
- **Ground planes are disabled.** The geometry is correct — an exact ground homography from
  the camera height — but tarmac and gravel never looked like anything but a sticker lying
  in the road, and a throw-up in the middle of a road is not a thing that happens. The code
  is still there behind `allowGround`.
- **Placement is not smart, only safe.** It finds a large flat region; it has no idea what a
  writer would actually choose, so pieces sometimes sit high up a wall rather than at
  arm's reach.

**Hit rate.** Roughly a third of Toronto locations yield a wall on some heading. The rest
are trees, parked cars, or glass, and the pipeline returns `null` so the seeder can move on
rather than paint something nobody believes.

---

## Iterating on this

Everything is seeded (`rng.mjs`), so a given seed reproduces a render exactly — without that
you cannot tell whether a change helped or the dice changed.

```js
import { paintPhoto } from "./graffiti.mjs";
const out = paintPhoto(jpegBytes, { seed: 42, word: "TDOT" });
```

Stills are cached under `.cache/streetview` (gitignored). Delete it to refetch; every fetch
is billed. Write samples somewhere you can actually look at them and compare — a contact
sheet of attempts side by side is worth far more than judging one render at a time.
