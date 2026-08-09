# db

Postgres 17. Schema of record for the whole project.

## ⚠️ `init.sql` is not a migration system

It runs **only on first container start**. Editing it does nothing to an existing database.

Every schema change is two steps:

```bash
# 1. edit db/init.sql (use ADD COLUMN IF NOT EXISTS)
# 2. apply to the live database by hand:
ssh wayfare-vps-runner "docker exec gitoutoftown-got-db-1 psql -U graffiti -d graffiti \
  -c 'ALTER TABLE pieces ADD COLUMN IF NOT EXISTS foo TEXT'"
```

Locally, `docker compose down -v got-db && docker compose up -d got-db` re-runs it — **destroys
local data**.

> Nested quoting through `ssh` → `docker exec` → `psql` mangles heredocs silently and reports
> success. Use separate `-c` flags and verify with `\d pieces` afterwards.

## Tables

| | |
|---|---|
| `pieces` | One piece of graffiti. `client` distinguishes ios/web; native AR columns are null from web. |
| `views` | Attention data — which pieces got looked at |
| `sessions` | Anonymous contributor sessions |
| `world_maps` | ARWorldMap scans. Versioned: a scan that extends an earlier one sets `parent_id`, inherits `root_id`, and stamps the parent's `superseded_at`. Reads serve heads only. The API creates and alters this lazily, so a deploy needs no manual step. |

## Live updates

`pieces_notify` fires `pg_notify('new_piece', …)` on insert. Consume with a **dedicated `pg.Client`**
in an SSE route — never the shared Pool, which recycles connections and silently stops listening.
