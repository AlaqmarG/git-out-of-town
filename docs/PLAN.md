# Plan

What we're building, what wins points, and what to cut.

---
## 1. The clock ⏰

| When | What | Status |
|---|---|---|
| **Tonight, 11:00 PM Aug 8** | Devpost registered, team formed, **draft submitted with your tracks** | Miss = disqualified |
| 11:00 AM Aug 9 | Soft deadline | — |
| **1:00 PM Aug 9** | **Final Devpost submission** | Hard cutoff, no exceptions |
| 3:00–5:00 PM Aug 9 | Live judging, judged multiple times | ≥1 member present |

**You have roughly 26 hours, and only ~14 of them after tonight's draft.**
Pitch format: 1 min setup → **4 min pitch** → 2 min Q&A → 1 min exit.

Submit: a link to the deployed project **or** a public GitHub repo.
No video or slides needed. Someone must demo live on Sunday.

> **Do tonight, before anything else:** register on Devpost, form the team, and submit the draft
> naming all three tracks. It costs 10 minutes and it's the only irreversible deadline.

---

## 2. The actual scoring rubric

From the official Hacker Judging Criteria doc. **You're auto-eligible for the main track no matter
what you build**; sponsor tracks are separate additional prizes that stack on top.

| Weight | Category | The question | What it means concretely |
|---:|---|---|---|
| **30%** | Solution Design & Experience | *Did you build something people will love using?* | A stranger figures it out in **under 60 seconds with zero explanation**. Actually public and live — not demoed from your laptop. |
| **30%** | Technical Craft | *Did you build it well?* | Everything demoed **works live**. The core transformation is real, and you can **explain it confidently** under Q&A. |
| **20%** | Originality & Personal Creativity | *Did you bring your own idea to life, and did it look like it?* | **Half idea, half how it looks.** "A great idea with no visual thought behind it, or a beautifully designed but generic idea, will only get you halfway there." |
| **20%** | Lasting Value & Community | *Would this bring people joy beyond the hackathon?* | Gets **better** with more people. Could realistically keep existing after the weekend. |

### The four hard constraints on the main track
1. **One moment of input** — contributing takes **under 60 seconds** and requires zero explanation.
2. **A non-trivial transformation** — this is your technical core. Must be real, demoed live, and
   **named explicitly** in your pitch.
3. **A stranger sees it** — publicly visible. Live website, shared canvas, real-time feed. *Deploy it.*
4. **It gets better with more people** — "community garden, not personal diary."

### 🚨 The line that should change how you build
> "Judges will notice, and **mark down**, heavy reliance on generic, unedited AI generated visuals.
> Craft and personal design choices go a long way. **Even simple, hand-made touches beat a default
> AI aesthetic.**"

Visual craft isn't polish here — it's ~20% of the main score *plus* the entire Reve track. And raw
un-art-directed model output is an active penalty. Budget real time for it, and hand-edit what Reve
gives you rather than shipping first outputs.

### What each sponsor track's judges look for

**Best Use of Reve** — the doc's "where to start" points at **`app.reve.com`**, the consumer app,
*not* the API. Confirms the plan: this track is design-time craft.
> "If used as a design backbone: does the project's visual identity clearly stand apart from a
> default, templated AI look?"

**TECHNATION** — their own suggested starting points: visualized trends (**where contributors are
from**, common themes, usage over time), interactive dashboards, community sentiment analysis,
**geographic visualization**, engagement analytics.
> - The data is **real and current**, not fabricated or hardcoded for the demo.
> - The visualization is something users can **actually explore**, not something you screenshot for slides.
> - The insight is **meaningful** — tells people something true and interesting.
> - **Bonus: the dashboard updates live while judges are watching.**

That bonus is very winnable: contribute from your phone mid-pitch and let the judges watch the
dashboard tick up.

---
---

## The product

Hold up your phone, see the street through the camera, spray-paint graffiti or slap a sticker. It
anchors to that spot and direction, forever. Anyone — no install — opens the map and explores what
the world painted.

**The transformation (name it explicitly in the pitch):**
crude finger-scribble → Reve model → polished graffiti in our house style → anchored to a real place.

---
---

## Scope

**P0 — no project without these**
- Web: public map showing everyone's pieces, reachable by a stranger
- API: `POST`/`GET /api/pieces`
- iOS: draw → place in AR → persists with lat/lng

**P1**
- iOS: load and render nearby pieces from other sessions; in-app MapKit view
- Web: `/data` dashboard, live drop-ins, Reve brand applied
- Reve transformation
- **Web capture** — a stripped-down "drop a sticker here" path. This is how you seed 20+
  contributors from a shared link; app-install-only seeding will not get you there.

**P2 — cut freely**
- `ARGeoAnchor` precision (keep the GPS fallback)
- Street View, attract mode, time-lapse
- Accounts, likes, comments

> **Sequencing rule:** the web P0s must never be blocked on iOS. If ARKit eats the night, the web
> still ships and you still have a project.

---
---

## Risks

| Risk | Mitigation |
|---|---|
| **Code signing / provisioning eats hours** | Get one build on a real device in the **first hour**, before any features |
| Two clients, two people, one night | Web P0 is the floor. iOS is the demo. Do not let iOS block web. |
| `ARGeoTracking` unavailable at venue | Build the GPS-bearing fallback first |
| No LiDAR on team devices | Plane detection only; drop the surface-classification insight |
| Judging is indoors, GPS poor, everything clusters at the venue | Make it a feature — pre-seed the venue as the densest hotspot. Manual pin fallback. |
| Seeding needs installs | Ship the web capture path (P1) |
| Replicate slow or down | Optimistic UI: show raw scribble, swap when transformed |
| Host is ARM64 (Ampere) | Komodo builds on the server — never push an amd64 image at it |
| Wifi dies mid-pitch | Screen-recorded backup + seeded data |
| Someone paints something vile | Delete button behind an admin route, before sharing publicly |

---
---

## 4-minute pitch

- **0:00–0:30** — Web map on the projector, already full. "People painted all of this in 18 hours."
- **0:30–1:30** — Live AR on your phone, mirrored. Paint on a real wall. It appears on the map.
- **1:30–2:15** — **Name the transformation.** Scribble → finished piece.
- **2:15–3:00** — `/data`. Lead with surface classification. Point at the counter moving.
- **3:00–3:30** — Reve: "Every sticker in the app was art-directed by us in Reve."
- **3:30–4:00** — Lasting value. "Here's the URL — paint something."

Rehearse screen mirroring. **AR demos live or die on whether the room can see your phone.**

Prep the two guaranteed Q&A questions: *how does the transformation work?* (30%) and *would anyone
use this after the hackathon?* (20%).
