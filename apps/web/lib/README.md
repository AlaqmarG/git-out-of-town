# `apps/web/lib`

Server-side building blocks. All of these run on the **nodejs** runtime (fs + `pg`), so any route
importing them needs `export const runtime = "nodejs"`.

| Module | Responsibility | Gotcha |
|---|---|---|
| `db.ts` | Shared `pg.Pool`, `UPLOAD_DIR` | Import the pool; don't construct another. **SSE needs a dedicated `Client`, not this Pool** — pooled connections get recycled and silently stop listening. |
| `pieces.ts` | Row↔type mapping, queries, validation | `toPiece()` is the single snake_case→camelCase boundary. Adding a column means touching `COLS`, `Row`, `toPiece`, and `@got/shared`. |
| `storage.ts` | Writes uploads, sniffs image type | Type comes from **magic bytes**, not `Content-Type` — this is public UGC. Returns a path relative to `UPLOAD_DIR`, sharded 2 chars deep. |
| `geocode.ts` | lat/lng → city/country | Best effort only, never blocks a write. Cached ~110m, serialised to ~1 req/s for Nominatim's policy. We have no CDN geo headers (self-hosted). |
| `ratelimit.ts` | In-memory token bucket | Resets on deploy. Guards Replicate credits, not a billing quota. Key off `clientIp()`. |

## Adding an endpoint

1. Type the request/response in `packages/shared/src/index.ts`.
2. Query in `pieces.ts` (or a sibling), returning shared types — never raw rows.
3. Route in `apps/web/app/api/<name>/route.ts` with `runtime = "nodejs"` and
   `dynamic = "force-dynamic"`.
4. Rate-limit anything that writes.
