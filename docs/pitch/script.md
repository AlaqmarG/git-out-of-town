# Pitch script — 4 minutes

[Overview](../../README.md) · [Plan](../PLAN.md) · [Devpost](../devpost.md) · **Pitch** · [Deck](index.html)

Open `docs/pitch/index.html` in a browser. **← →** or **space** move between slides, **home / end**
jump to the ends. Seven slides, ~34 s each. Format is 1 min setup → **4 min pitch** → 2 min Q&A →
1 min exit.

Word budget: ~500 spoken words at ~130 wpm. Everything below is inside that. If you are over, cut
from slide 03, never from slides 01–02.

## Before you walk in

- [ ] Phone on venue wifi, app open, marker scanned, AR session already relocalized.
- [ ] Second screen or laptop on `/data`, already loaded, count visible.
- [ ] Deck open in a third window, slide 01.
- [ ] Refresh the numbers on **slide 05** — it ships with `__ real AR pieces / __ total rows`.
      There are at least four real AR pieces at the venue; check `/data` for the live figure
      rather than quoting that from memory.
- [ ] Fill the three remaining screenshot slots (dashed boxes): the "Spot scanned" post card
      (slide 03), AR view mode with 2+ pieces (slide 04), a full-screen piece preview (slide 07).

---

## The 4 minutes

**0:00 – 1:05 · Hook and paint it live (slide 01)** — *the demo is first, while you have attention*

Say the hook, then hold the phone up and paint. Keep talking while you do it.

> "Graffiti works because of *where* it is. You have to go to the wall — and that's exactly what the
> internet strips out. Post it online and the place becomes a picture of a place.
>
> Git Out of Town is a version where your tag stays put, costs nobody a wall, and someone across the
> world can still walk up to it. I'll make one now. Point at the wall. Draw. Tap.
>
> ARKit raycasts the real surface, LiDAR tells us that's a wall and not a floor, and it's on the
> public map before I put the phone down."

Point at `/data`. The count ticks up over SSE, no refresh. *(~105 words + painting)*

**1:05 – 1:25 · The floor shot (slide 02)**

> "Look at this one. That piece is *lying on the floor* — correctly foreshortened, wrapped to the
> depth map, occluded by real geometry. A web app cannot produce this frame. That's the line between
> a filter and actual placement." *(~44 words)*

**1:25 – 2:20 · How placement works (slide 03)** — *the technical core; walk the diagram*

> "Placing something is easy. Agreeing on *where* it is is the hard part, and it's where the
> engineering went.
>
> One — a printed marker gives every device the same origin. A `markerTransform` on the wire means
> 'here' is the same on your phone and mine. Judging is indoors; GPS is useless in here.
>
> Two — every visitor's ARWorldMap merges into the venue's map, versioned with lineage. The spot
> gets *easier* to find the more people scan it. That's a property of the coordinate system, not a
> roadmap promise — a community garden, not a personal diary.
>
> Three — the decal wraps to the depth map instead of a flat quad, and real geometry occludes it.
> Walk behind a pillar, the paint goes behind the pillar.
>
> And it never just fails — it falls down the ladder at the bottom: marker, geo anchor,
> surface-aligned, GPS. There is always something." *(~145 words)*

**2:20 – 2:50 · Realism and Reve (slide 04)**

> "Then we made it behave like aerosol. Feathered overspray edges, colour pulled toward the wall so
> pigment sits *in* the surface, paint thinning at grazing incidence, and a wall-grain normal map so
> brick reads through. Reve is the design backbone — one hand-tuned house style, not a filter. And it
> applies to *other people's* pieces, so a stranger's tag looks painted on your wall." *(~66 words)*

**2:50 – 3:20 · The public half (slide 05)**

> "The map is the public artifact — hand-authored basemap, no stock style, no map API key. Open a
> spot and you get every piece there with a distance *and a bearing*: five metres southwest, seven
> west. On a window, on a wall, on a floor — that's LiDAR classification, not a label anyone typed.
> `/data` is the TECHNATION side, live over Postgres `LISTEN/NOTIFY`. And I'll be straight: most
> rows are seeded demo data, labelled as seeded. The real number is the AR pieces." *(~80 words)*

**3:20 – 3:40 · Three tracks (slide 06)**

> "Three tracks, one build. Main: one moment of input, under sixty seconds. Reve: a visual identity,
> every colour from one file. TECHNATION: real, current, explorable, and honest about what's seeded.
> 26 hours, two people, two apps, one API contract, self-hosted." *(~43 words)*

**3:40 – 4:00 · Close (slide 07)**

> "Next is persistent anchors so a spot survives without the marker, walls and crews, time-lapse,
> Android via WebXR, and community moderation — this is public art pinned to real addresses. Open
> the link on your phone. There's a piece in this room waiting for you." *(~48 words)*

---

## Q&A — the three they will ask

**1. "Does the anchor actually persist? What happens tomorrow, or without the marker?"**

Honest answer:

> "Today, persistence comes from two things: the printed marker as the shared origin, and our own
> ARWorldMap store that chains each visitor's scan into one venue map. Both are real and running.
> What we do *not* have is a permanent, marker-free anchor — and the obvious off-the-shelf fix has a
> catch: Google's Cloud Anchors expire, the hosted anchor has a TTL, so 'forever' is not something
> you get for free from a vendor. That's exactly why we built the world-map chaining ourselves —
> it's the piece that can actually outlive a TTL. Right now, without the marker, relocalization
> degrades to GPS plus compass bearing, which is metre-scale, not centimetre-scale."

Do not claim ARGeoAnchor coverage. It is an opportunistic upgrade, not the floor.

**2. "How much of that data is real?"**

Honest answer, and say it before they find it:

> "Most of it is seeded. Of the rows in the database, the large majority are `client: "web"` seed
> data we generated to build and style the dashboard against, and they are labelled as seeded in the
> data itself — you can filter them out. The genuinely user-generated pieces are the AR ones, and
> there are only a handful, including the one I just painted. I'd rather tell you that than have you
> assume the count is usage. The pipeline is real and current; the *volume* is a day-old project's
> volume."

Refresh the actual numbers before the pitch. Do not quote a total as if it were contributions.

**3. "What stops this from being a photo filter with GPS on it?"**

> "Three things you can check in one frame. The paint is occluded by real geometry — walk behind
> something and it disappears correctly. It's wrapped to the LiDAR depth map, so on a floor it
> foreshortens and on a curved surface it bends. And a second device relocalizes to the *same*
> coordinate frame and sees the same piece in the same physical spot. A filter fails all three."

### Two more worth having ready

- **"What if someone paints something offensive?"** — It's public art pinned to real addresses.
  Today: everything is attributable per piece and removable server-side. Next: community moderation,
  because the neighbourhood should get a say in what stays up. We're not pretending we solved it in
  26 hours.
- **"Why iOS only?"** — LiDAR depth and ARKit mesh classification are what make the floor shot
  possible, and no cross-platform layer exposes them well. The *viewing* half is already
  cross-platform — the map is a link, works on anything. WebXR for contribution on Android is next.
- **"Where did the cut slides go?"** — Problem framing folded into slide 01, the community-garden
  property into slide 03, and what's-next into the close. Nothing was dropped, just spoken faster.
