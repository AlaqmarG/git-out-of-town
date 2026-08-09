# apps/web

Next.js 16 App Router. Frontend, API, and the `/data` dashboard.

## Layout

```
app/api/pieces/route.ts   POST + GET pieces
app/api/health/route.ts   readiness probe
components/MapCanvas.tsx  the map (client component)
lib/                      server-side building blocks + map/theme
```

## The map

| File | Role |
|---|---|
| `lib/theme.ts` | **All colour lives here.** Swap these when the Reve art lands (#5/#6) and the map, UI and markers follow. Never hardcode a colour elsewhere. |
| `lib/map-style.ts` | Hand-authored dark basemap over OpenFreeMap vector tiles (free, no API key). Not a stock style — a default basemap is what the rubric marks down. |
| `components/MapCanvas.tsx` | Creates the map, fetches by bbox on `moveend` (latest-wins abort), empty state, error toast. Calls `onPiecesChange` — that is the hook #13 renders markers from. |

`lib/map-style.test.ts` guards the traps: undeclared sources, unknown source-layers,
legacy filter syntax, and layer ordering. Run it before touching the style.

## lib/

| Module | Responsibility | Gotcha |
|---|---|---|
| `db.ts` | Shared `pg.Pool`, `UPLOAD_DIR` | Import the pool; don't build another. **SSE needs a dedicated `Client`** — pooled connections get recycled and silently stop listening. |
| `pieces.ts` | Row↔type mapping, queries, validation | `toPiece()` is the only snake_case→camelCase boundary |
| `storage.ts` | Upload writes + type sniffing | Type comes from **magic bytes**, not `Content-Type`. This is public UGC. |
| `geocode.ts` | lat/lng → city/country | Best effort; never blocks a write |
| `ratelimit.ts` | In-memory token bucket | Resets on deploy. Guards Replicate credits, not a quota. |
| `transform.ts` | Replicate passes: upscale → restyle → isolate, then weather | **Never on the AR path.** Runs after the piece is stored; every failure leaves the piece with the image it already had. Drain every response body. |

## Developing without a local database

You do **not** need Postgres or Docker to work on the UI. Point the dev server at a
running deployment:

```bash
DEV_PROXY_ORIGIN=https://gitoutoftown.129-153-49-190.sslip.io npm run dev
```

`/api/*` and `/uploads/*` are rewritten to that origin (`next.config.ts`). The rewrites live
in `beforeFiles` — our own `/api` routes exist on disk and would otherwise win. Unset in
production, so it is inert there.

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
- **maplibre-gl.css sets `.maplibregl-map { position: relative }`** on whatever element you hand
  the map. That overrides a Tailwind `absolute` utility on the same node and collapses it to
  height 0 — the map then renders nothing, with no error. Position the map container with an
  **inline style**, not a utility class.
- **Image bytes never stream through Node.** nginx serves `/uploads/*`; the map loads hundreds at
  once on a pan. Build URLs with `uploadUrl()` from `@got/shared`.

<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
