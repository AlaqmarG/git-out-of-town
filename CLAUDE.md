# Git Out of Town

Paint graffiti onto the real world in AR; it pins to that spot forever on a living world map anyone
can visit. SummerHacks 2026.

**Live:** https://gitoutoftown.129-153-49-190.sslip.io

| | |
|---|---|
| What we're building, scope, rubric | [`docs/PLAN.md`](docs/PLAN.md) |
| Deploy, VPS, onboarding | [`docs/OPS.md`](docs/OPS.md) |
| Reve API lookup | [`docs/reve-api.md`](docs/reve-api.md) |

Each directory has its own `CLAUDE.md` with local detail. Read the one for the area you're touching.

---

## Layout

npm **workspaces**. Run `npm install` and every script from the **repo root**, never inside a workspace.

```
apps/web         Next.js 16 — frontend + API + /data dashboard
apps/ios         SwiftUI + ARKit. Not an npm workspace, just a folder.
packages/shared  @got/shared — the API contract both clients honour
db/              Postgres schema
```

`npm run dev` · `npm run build` · `npm run typecheck` · `npm run lint`

---

## Architecture

```
apps/ios ─┐                                  ┌─ /uploads/* → nginx (static)
          ├─→ POST /api/pieces → Postgres →  │
apps/web ─┘                        │         └─ /*         → Next.js :3000
                                   └─ pg_notify → SSE → live map
```

iOS is the experience (AR contribution). Web is the public artifact (map + `/data`). Both write
through the same API; the `client` column distinguishes them.

---

## Rules that hold everywhere

- **DB is `snake_case`, TS is `camelCase`.** One conversion point: `toPiece()` in `apps/web/lib/pieces.ts`.
- **`packages/shared` is the contract.** Anything crossing the network is typed there.
- **HTTPS is required** for camera, geolocation, and device orientation. They do not work on
  `localhost` from a phone — test against the deployed URL.
- **`main` is protected.** Work on a branch, open a PR.
- **Only touch containers prefixed `got-`.** The VPS also runs production workloads.

---

## Current state

✅ Repo, CI/CD, VPS, Postgres, TLS, `POST`/`GET /api/pieces`, `/api/health`
❌ Web map & `/data` (#12–#17) · iOS app (#23–#31) · Reve art (#5, #6)
