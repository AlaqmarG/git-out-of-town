# Git Out of Town

Spray-paint the real world. Hold up your phone, paint on what you see, and it pins to that spot
forever — on a living world map anyone can explore.

**SummerHacks 2026** · Main track + Best Use of Reve + TECHNATION Data Intelligence

---

## Deadlines

| When | What |
|---|---|
| **11:00 PM Aug 8** | Devpost draft with all 3 tracks — **miss = disqualified** |
| 11:00 AM Aug 9 | Soft deadline / feature freeze |
| **1:00 PM Aug 9** | Final submission — hard cutoff |
| 3:00–5:00 PM Aug 9 | Live judging (4-min pitch) |

---

## Stack

Next.js (App Router) · Postgres · MapLibre GL JS · Replicate (Reve) · Docker + Caddy on OCI via Komodo

## Getting started

```bash
cp .env.example .env
docker compose up -d db      # Postgres only
npm install
npm run dev
```

> ⚠️ Camera, geolocation, and device orientation **require HTTPS** — they will not work on
> `localhost` from a phone. Test against the Vercel preview URL.

## Docs

| | |
|---|---|
| [`docs/01-rubric-and-deadlines.md`](docs/01-rubric-and-deadlines.md) | Judging rubric, tracks, what scores points |
| [`docs/02-build-plan.md`](docs/02-build-plan.md) | Architecture, scope, risks, pitch |
| [`docs/03-reve-reference.md`](docs/03-reve-reference.md) | Reve API reference (only if we get a key) |
| [`docs/04-deploy.md`](docs/04-deploy.md) | Komodo + OCI deployment, and the two OCI gotchas |

## Ground rules

- Hand-edit every Reve asset. Unedited AI visuals are an explicit mark-down in the rubric.
- P0 before P1. See the scope section in the build plan.
