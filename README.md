# Git Out of Town

**Overview** · [Plan](docs/PLAN.md) · [Devpost](docs/devpost.md) · [Reve playbook](docs/reve-playbook.md) · [Reve prompts](docs/reve-prompts-used.md) · [Third Space Trek](docs/hunt.md)

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

Next.js (App Router) · Postgres · MapLibre GL JS · Replicate (Reve) · Docker on OCI via Komodo, behind shared Traefik

## Getting started

```bash
cp .env.example .env
docker compose up -d got-db  # Postgres only
npm install                  # installs every workspace
npm run dev
```

> ⚠️ Camera, geolocation, and device orientation **require HTTPS** — they will not work on
> `localhost` from a phone. Test against https://gitoutoftown.129-153-49-190.sslip.io

## Repo layout

One repository, two clients. **Not** an npm monorepo — no workspaces, no shared packages.

```
apps/web         Next.js — frontend + API + /data dashboard
apps/ios         Native SwiftUI + ARKit client
packages/shared  API contract types, shared by every client
db/              Postgres schema
docs/            Plan, rubric, deployment, access
```

npm workspaces. Run `npm install` and all scripts from the **repo root** — never inside `apps/web`.
`apps/ios` is a plain folder, not a workspace; Swift shares the repo and the API contract, nothing else.

## Docs

| | |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | **Start here** — architecture, conventions, current state |
| [`docs/PLAN.md`](docs/PLAN.md) | Deadlines, rubric, product, scope, risks, pitch |
| [`docs/OPS.md`](docs/OPS.md) | Onboarding, VPS access, deployment, troubleshooting |
| [`docs/reve-api.md`](docs/reve-api.md) | Reve API reference (only if we get a key) |
| [`docs/hunt.md`](docs/hunt.md) | Third Space Trek — route, schedule, photo log |

Each directory also carries its own `CLAUDE.md` with local detail — `apps/web`, `apps/ios`,
`packages/shared`, `db`.

## Ground rules

- Hand-edit every Reve asset. Unedited AI visuals are an explicit mark-down in the rubric.
- P0 before P1. See the scope section in the build plan.
