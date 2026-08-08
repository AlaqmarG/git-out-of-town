# packages/shared

`@got/shared` — the API contract. Both clients honour it; the iOS app mirrors these names exactly.

## Rules

- **Anything crossing the network is typed here.** No per-client shapes.
- **`camelCase` only.** The database is `snake_case`; conversion happens once, in `toPiece()` in
  `apps/web/lib/pieces.ts`.
- Source of truth for the schema itself is `db/init.sql`. Keep them in step.

## Adding a field

1. `db/init.sql` — with `ADD COLUMN IF NOT EXISTS`
2. **`ALTER TABLE` the live database by hand** — `init.sql` only runs on first container start
3. `src/index.ts` — the type
4. `apps/web/lib/pieces.ts` — `COLS`, `Row`, `toPiece()`, and `validateMeta()` if client-supplied

Miss step 2 and it works locally, fails in production.

## No build step

`main` points straight at `src/index.ts`; Next transpiles it via `transpilePackages`. Don't add a
bundler.
