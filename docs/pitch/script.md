# Pitch script — 4 minutes

[Overview](../../README.md) · [Plan](../PLAN.md) · [Devpost](../devpost.md) · **Pitch** · [Deck](index.html)

Open `docs/pitch/index.html` in a browser. Arrow keys move. Format is 1 min setup → **4 min pitch**
→ 2 min Q&A → 1 min exit.

## Before you walk in

- [ ] Phone on venue wifi, app open, marker scanned, AR session already relocalized.
- [ ] Second screen or laptop on `/data`, already loaded, count visible.
- [ ] Deck open in a third window, slide 01.
- [ ] Refresh the numbers on **slide 08** — it ships with `__ real AR pieces / __ total rows`.
- [ ] Fill the five screenshot slots (dashed boxes in the deck) with the venue captures.

---

## The 4 minutes

**0:00 – 0:20 · Hook (slide 01–02)**

> "Graffiti works because of *where* it is. You have to go to the wall. That's the whole point, and
> it's exactly what the internet strips out — post it online and it stops being a place and becomes
> a picture of one. Git Out of Town is a version where your tag stays put, costs nobody a wall, and
> someone on the other side of the world can still walk up to it."

**0:20 – 1:10 · Paint it live (slide 03)** — *this is the demo, do it first while you have attention*

Hold the phone up, paint, tap to place. Talk while you do it.

> "Point at a wall. Draw with your finger. Tap. That's the whole contribution — under a minute, no
> login, no install. ARKit raycasts onto the real surface, and LiDAR mesh classification tells us
> whether that's a wall, a floor or a ceiling. Watch the map."

Point at `/data`. The count ticks up over SSE, no refresh.

> "That piece is on the public map now, for everyone."

**1:10 – 1:30 · The floor shot (slide 04)**

> "This is the one I want you to look at. That piece is *lying on the floor* — correctly
> foreshortened, wrapped to the depth map, occluded by real geometry. A web app cannot produce this
> frame. That's the line between a filter and actual placement."

**1:30 – 2:30 · How placement works (slide 05)** — *the technical core, take your time*

> "Placing something is easy. Agreeing on *where* it is turned out to be the hard part, and it's
> where most of the engineering went.
>
> One — a printed marker gives every device the same origin. We put a `markerTransform` on the
> wire, so 'here' means the same thing on your phone and mine. That matters because judging happens
> indoors and GPS is useless in here.
>
> Two — every visitor's ARWorldMap merges into the venue's map, versioned with lineage. The spot
> gets *easier* to find the more people scan it, and a ghosted guide shows you where to stand to
> relocalize. That's the 'gets better with more people' property, built into the coordinate system
> rather than promised on a roadmap.
>
> Three — the decal wraps to the dense depth map instead of sitting on a flat quad, and real
> geometry occludes it. Walk behind a pillar and the paint goes behind the pillar."

**2:30 – 3:00 · Realism (slide 06)**

> "Then we spent real time making it behave like aerosol. Feathered noise edges instead of a crisp
> alpha cut, colour pulled toward the wall so pigment sits *in* the surface, paint thinning at
> grazing incidence, multi-coat variation, and a Sobel wall-grain normal map so the brick reads
> through. All of that applies to *other people's* pieces too — so a stranger's tag looks painted on
> your wall, not pasted over your camera."

**3:00 – 3:25 · The public half (slide 07–08)**

> "The map is the public artifact. Hand-authored basemap, no stock style, no map API key. Three zoom
> tiers — density glow, pins tinted with each piece's own dominant colour, then the artwork itself.
> Every piece carries a photo of the surface it was painted on.
>
> `/data` is the TECHNATION side: surface mix straight off LiDAR, geography, client breakdown,
> updating live over Postgres `LISTEN/NOTIFY`. It's a page you can drive, not a screenshot. And I'll
> be straight — most rows in there right now are seeded demo data and the dashboard labels them as
> seeded. The real number is the AR pieces, which is why I painted one in front of you."

**3:25 – 3:50 · Lasting value + next (slide 09–11)**

> "It's a community garden, not a personal diary — the venue's map thickens with every visitor.
> Next is persistent anchors so a spot survives without the printed marker, walls and crews,
> time-lapse so you can scrub a wall's history, Android via WebXR, and community moderation,
> because this is public art pinned to real addresses."

**3:50 – 4:00 · Close (slide 12)**

> "26 hours, two people, two apps, one API contract, self-hosted. Open the link on your phone —
> there's a piece in this room waiting for you."

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
