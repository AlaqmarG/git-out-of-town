# Git Out of Town — agent context

SummerHacks 2026. Paint graffiti onto the real world in AR; it pins to that spot forever on a
living world map anyone can visit.

**Read this fully before touching anything.** It records the decisions and traps that are not
obvious from the code.

---

## 1. Repo layout

npm **workspaces** monorepo. Run `npm install` and every script from the **repo root** — never
inside `apps/web`.

```
apps/web         Next.js 16 (App Router) — frontend + API + /data dashboard
apps/ios         SwiftUI + ARKit client. NOT an npm workspace, just a folder.
packages/shared  @got/shared — the API contract both clients honour
db/init.sql      Postgres schema (runs on first container start only)
docs/            Plan, rubric, deployment, access
```

| Command (from root) | Does |
|---|---|
| `npm run dev` | Next dev server |
| `npm run build` | Builds `@got/web` |
| `npm run typecheck` | All workspaces. Runs `next typegen` first — **required** |
| `npm run lint` | All workspaces |

---

## 2. Architecture

```
apps/ios  ─┐                                    ┌─ Traefik (shared, TLS) ─ /uploads/* → nginx
           ├─→ POST /api/pieces ─→ Postgres ─→  │
apps/web  ─┘                        │           └─ /*          → Next.js :3000
                                    └─ pg_notify('new_piece') → SSE → live map
```

- **iOS is the experience** (AR contribution). **Web is the public artifact** (map + `/data`).
- Both write through the same `POST /api/pieces`. `client` column distinguishes them.
- Images are written to a volume and served **by nginx**, never streamed through Node — the map
  loads hundreds at once on a single pan.

---

## 3. Conventions

**Database is `snake_case`, TypeScript is `camelCase`.** The mapping lives in exactly one place:
`toPiece()` in `apps/web/lib/pieces.ts`. If you add a column, update: `db/init.sql` →
`packages/shared/src/index.ts` → `Row` interface → `toPiece()` → `COLS`.

**`packages/shared` is the contract.** Anything crossing the network is typed there. iOS mirrors
those field names exactly. Don't invent per-client shapes.

**`db/init.sql` only runs on the FIRST container start.** It is not a migration system. Changing it
does nothing to an existing database — you must also `ALTER TABLE` the live one by hand:
```bash
ssh wayfare-vps-runner "docker exec gitoutoftown-got-db-1 psql -U graffiti -d graffiti -c 'ALTER TABLE ...'"
```
Use `ADD COLUMN IF NOT EXISTS` so both paths converge.

**Image paths in the DB are relative to `UPLOAD_DIR`** (e.g. `b4/b47cf9….png`), sharded by the
first two characters. Public URL is `/uploads/<path>`. Build it with `uploadUrl()` from
`@got/shared`.

---

## 4. What exists right now

| Area | State |
|---|---|
| Repo, CI/CD, VPS, Postgres, TLS | ✅ done and verified |
| `POST`/`GET /api/pieces` | ✅ PR #33 |
| `GET /api/health` | ✅ |
| Web map, `/data`, SSE, admin delete | ❌ not started (#12–#17) |
| iOS app | ❌ not started (#23–#31) |
| Reve art | ❌ not started (#5, #6) |

Live: https://gitoutoftown.129-153-49-190.sslip.io

---

## 5. Key files

| File | Why it matters |
|---|---|
| `apps/web/lib/db.ts` | Shared `pg` Pool + `UPLOAD_DIR`. Import the pool, don't make your own. |
| `apps/web/lib/pieces.ts` | Row↔type mapping, queries, request validation |
| `apps/web/lib/storage.ts` | Magic-byte sniffing + sharded writes |
| `apps/web/lib/geocode.ts` | Best-effort reverse geocode; never blocks a write |
| `apps/web/lib/ratelimit.ts` | In-memory token bucket |
| `packages/shared/src/index.ts` | **The contract.** Start here. |
| `db/init.sql` | Schema + the `new_piece` NOTIFY trigger |

---

## 6. Traps — read before debugging

**SSE must use a dedicated `pg.Client`, never the shared `Pool`.** A pooled connection gets handed
to another query and silently stops listening. The `new_piece` trigger already exists.

**No CDN geo headers.** We're self-hosted behind our own Traefik — there is no `x-vercel-ip-city` or
`cf-ipcountry`. City/country come from reverse-geocoding the submitted GPS coords
(`lib/geocode.ts`), which is more accurate anyway.

**`NEXT_PUBLIC_*` is inlined at BUILD time.** It's a Docker build arg in `docker-compose.yaml`.
Changing the Maps key needs a **rebuild**, not a restart.

**The VPS is ARM64** (OCI Ampere). Komodo builds on the server so this is handled — but never push
an amd64 image at it or the container dies with `exec format error`.

**The VPS also runs production workloads** (`brockcsc-prod-app`, `keycloak`, shared Traefik and
Postgres). Only touch containers prefixed `got-`. Never `docker compose down` from an unchecked
directory.

**Camera / geolocation / device orientation require HTTPS.** They do not work on `localhost` from a
phone. Test against the deployed URL.

**`next typegen` must run before `tsc`.** Next 16 generates global types (`LayoutProps`,
`PageProps`) into `.next/types`. This is already wired into the `typecheck` script — if you run
`tsc` directly it will fail with `Cannot find name 'LayoutProps'`.

**Don't add `docker-compose.override.yaml` to a deploy.** It publishes Postgres on 5432 for local
dev only. Deploy with an explicit `-f docker-compose.yaml`.

---

## 7. Local development

```bash
cp .env.example .env          # placeholder password is fine locally
docker compose up -d got-db   # override publishes 5432
npm install
npm run dev
```

Re-apply a changed schema locally (**destroys local data**):
```bash
docker compose down -v got-db && docker compose up -d got-db
```

---

## 8. Deploying

`main` is **protected — changes go through a PR.** CI runs `check → docker → deploy → smoke`.

Komodo auto-deploy is **not live yet** (missing `KOMODO_API_KEY`/`KOMODO_API_SECRET`), so the deploy
job skips with a notice. Until then, redeploy by hand:

```bash
ssh wayfare-vps-runner "cd ~/gitoutoftown && docker compose -p gitoutoftown -f docker-compose.yaml up -d --build"
```

Debugging:
```bash
ssh wayfare-vps-runner 'docker ps --filter name=got-'
ssh wayfare-vps-runner 'docker logs --tail 50 gitoutoftown-got-app-1'
ssh wayfare-vps-runner 'docker exec -it gitoutoftown-got-db-1 psql -U graffiti -d graffiti'
```

Full detail: `docs/04-deploy.md`. Onboarding/credentials: `docs/05-access.md`.

---

## 9. What the judging actually rewards

Worth knowing before making tradeoffs — 30% Solution Design (a stranger figures it out in **under
60 seconds**, publicly live), 30% Technical Craft (works live, transformation is real), 20%
Originality (**half of it is how it looks**), 20% Lasting Value.

Two consequences for code decisions:
- **Unedited generic AI visuals get marked down explicitly.** Hand-edit every Reve asset.
- **`/data` must be live-queried and explorable**, never hardcoded or screenshotted.

Rubric detail: `docs/01-rubric-and-deadlines.md`. Plan: `docs/02-build-plan.md`.
