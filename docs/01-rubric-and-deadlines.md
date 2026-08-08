# Start Here

Short version. Deep API detail lives in `REVE-API-REFERENCE.md`.

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

## 3. Reve access — where you actually stand

| Surface | Status | Verdict |
|---|---|---|
| `app.reve.com` | ✅ Logged in, **Free plan** | Enough to win the Reve track |
| `api.reve.com` | ❌ **"Closed to new users."** No "Enable API" on your account page | Blocked |
| fal.ai / Replicate | ✅ Open signup today | Reve `create`/`edit`/`remix`, **no layout endpoints** |

**Ask the organizers for Reve API access tonight** — Reve is a sponsor, so a participant key is the
likeliest route. But do **not** block on it. Assume no API and design accordingly; treat a key as a bonus.

Your Free plan has daily "creative energy" that refreshes (yours refills in ~18h) — enough to hand-make
a brand kit, not enough to serve live traffic.

---

## 4. What to build

**Native iOS for the experience, web for the artifact.** See `02-build-plan.md` for the full plan.

```
iOS (ARKit)  ──┐
 paint on the  │
 real world    ├─→  Postgres on our VPS  ──→  Web: public map + /data dashboard
               │                                (what judges and strangers open)
web capture  ──┘
 (seeding path)
        ↑
   Reve-made brand system ships inside both clients
```

**Why both clients.** The rubric demands something public and live that a stranger can reach — "not
just something you demo from your own laptop." A native app cannot satisfy that in this timeframe, so
the web carries it. But AR is a far better 4-minute demo than a browser, and the web is also where
`/data` lives.

**Use Reve for brand, not for the live pipeline.** Its "where to start" points at `app.reve.com`, the
consumer app — this track is design-time craft. The one exception is the transformation itself
(Replicate `reve edit-fast`, ~$0.01), which sits in the user path with a raw-scribble fallback.

**Native AR earns you a dataset nobody else has.** With LiDAR, `ARMeshClassification` records what
kind of surface each piece landed on — wall, floor, ceiling, table. *"68% of graffiti goes on walls,
3% on ceilings, and those get looked at longest."* That is exactly the "true and interesting insight"
TECHNATION asks for, and no web-only project can produce it.

> ⚠️ **Sequencing rule:** the web P0s must never block on iOS. If ARKit eats the night, the web still
> ships and you still have a project.

---

## 5. Tonight's Reve brand kit (~1 hour in the app)

Make these by hand at `app.reve.com`, download, commit to the repo:

- [ ] **Sticker pack, 12–20 pieces** — ships in the iOS picker *and* on the web map. Do this first.
- [ ] Logotype / wordmark — Reve's in-image text rendering is its single strongest capability
- [ ] iOS app icon + launch screen
- [ ] Favicon
- [ ] Hero illustration for the landing page
- [ ] Empty state ("nothing here yet — add the first one")
- [ ] 404 / error art
- [ ] Devpost cover image
- [ ] **Save 2–3 named Effects in the app** → your house look, reused across every asset

Consistency is what separates "designed" from "generated." Same palette, same effect, same
character across all assets. That's the whole track.

---

## 6. The data dashboard (`/data`)

Four charts is plenty. Each must be a **live DB query** with n-counts and a last-updated timestamp —
"real and current, not fabricated or hardcoded" is stated explicitly.

1. **Geographic map** — where contributors are from. The doc names this twice; take the free points.
   Coarse geo from a request header, no extra dependency.
2. **Surfaces of the world** — the ARKit mesh-classification breakdown. Native-only; lead with it.
3. **Rhythm over time** — contributions per hour + average time-to-draw. Real human behaviour.
4. **Attention vs. intent** — what got painted vs. what got looked at.

Make at least one **interactive** (filter by hour, hover for detail) — "something users can actually
explore, not something you screenshot for your slides."

**Wire up live updates.** Poll every few seconds or use a subscription, so you can contribute from
your phone mid-pitch and the judges watch the numbers move. That's an explicitly stated bonus.

---

## 7. Gotchas that will actually bite you

Rubric-driven:
- [ ] **Test the 60-second rule on a real stranger.** Hand someone your phone, say nothing, watch.
      This is 30% of the score and the cheapest thing to verify.
- [ ] **Name your transformation explicitly in the pitch.** Constraint #2 asks for it by name.
- [ ] **Hand-edit every Reve asset.** Unedited AI visuals are an explicit mark-down.
- [ ] **Have an answer for "would this live past the weekend?"** That's 20%, and it's a Q&A question.
- [ ] **Contribute live during the pitch** so the artifact and dashboard both move while judges watch.

Operational:
- [ ] **Buy a real domain.** "Permanent" is in the brief; the `sslip.io` fallback URL undercuts it.
- [ ] **Get a signed iOS build on a real device in the first hour** — before any features. Provisioning
      is where iOS hackathon projects die.
- [ ] **Seed real contributions before 3 PM Sunday.** An empty shared artifact demos terribly, and
      "gets better with more people" is unprovable with three items. Get 20+ friends in Saturday night.
- [ ] **Moderate the input.** Public UGC, and judges will try to break it.
- [ ] **Venue wifi dies.** Have a local fallback and a seeded DB.
- [ ] **Rehearse the 4 minutes three times.** Judges see you multiple times in the 2-hour window.
- [ ] Make the repo **public** before submitting.
- [ ] Put `/data` in the main nav — an unlinked dashboard isn't "surfaced."

---

## 8. Suggested order

**Tonight (before 11 PM):** Devpost draft with all 3 tracks ← *do this first, it's the only hard gate*
**Tonight:** buy domain · Xcode project signed onto a device · Reve sticker pack
**Overnight:** iOS draw + AR placement · web map + API · persistence
**Morning:** `/data` dashboard · web capture for seeding · polish with the brand kit
**By 1 PM Sun:** submit — public repo, live link
**Before 3 PM:** rehearse the pitch three times
