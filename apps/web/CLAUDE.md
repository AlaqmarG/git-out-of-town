# apps/web

Next.js 16 App Router. Frontend, API, and the `/data` dashboard.

## Layout

```
app/api/pieces/route.ts   POST + GET pieces
app/api/health/route.ts   readiness probe
lib/                      server-side building blocks
```

## lib/

| Module | Responsibility | Gotcha |
|---|---|---|
| `db.ts` | Shared `pg.Pool`, `UPLOAD_DIR` | Import the pool; don't build another. **SSE needs a dedicated `Client`** — pooled connections get recycled and silently stop listening. |
| `pieces.ts` | Row↔type mapping, queries, validation | `toPiece()` is the only snake_case→camelCase boundary |
| `storage.ts` | Upload writes + type sniffing | Type comes from **magic bytes**, not `Content-Type`. This is public UGC. |
| `geocode.ts` | lat/lng → city/country | Best effort; never blocks a write |
| `ratelimit.ts` | In-memory token bucket | Resets on deploy. Guards Replicate credits, not a quota. |

## Adding an endpoint

1. Type it in `packages/shared/src/index.ts`
2. Query in `lib/pieces.ts` — return shared types, never raw rows
3. Route with `runtime = "nodejs"` (fs + pg) and `dynamic = "force-dynamic"`
4. Rate-limit anything that writes

## Traps

- **`next typegen` must run before `tsc`.** Already wired into `npm run typecheck`. Running `tsc`
  directly fails with `Cannot find name 'LayoutProps'`.
- **`NEXT_PUBLIC_*` is inlined at BUILD time** — a Docker build arg, not runtime env. Changing the
  Maps key needs a rebuild, not a restart.
- **No CDN geo headers.** Self-hosted behind our own Traefik, so no `x-vercel-ip-city` /
  `cf-ipcountry`. City comes from reverse-geocoding submitted GPS coords.
- **Image bytes never stream through Node.** nginx serves `/uploads/*`; the map loads hundreds at
  once on a pan. Build URLs with `uploadUrl()` from `@got/shared`.
