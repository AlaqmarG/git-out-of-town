# Deploy — Komodo on the OCI VPS

Deployed onto the existing `wayfare-vps-runner` box. **We do not run our own reverse proxy** — the
shared Traefik already owns :80/:443. We attach to it with labels.

```
Traefik (shared, wayfarer-net, letsencrypt)
 ├── Host(SITE_HOST) && PathPrefix(/uploads) → got-uploads (nginx, :80)  ← user art
 └── Host(SITE_HOST)                        → got-app (Next.js, :3000)
                                                  └── got-db (Postgres 17, internal only)
```

## The host

| | |
|---|---|
| SSH | `ssh wayfare-vps-runner` (`opc@129.153.49.190`, key `~/.ssh/wayfare-ampere.pem`) |
| OS / arch | Oracle Linux 9.8, **aarch64 (Ampere)** |
| Disk | 183G total, ~164G free |
| Komodo | https://manage.wayfarerbx.com |
| Proxy | Traefik v3.6, network `wayfarer-net`, certresolver `letsencrypt`, entrypoint `websecure` |

### Why there is no Caddy and no multi-arch build
- Traefik already binds :80/:443. A second proxy would fail to start with a port conflict.
- The host is **ARM64**. Because Komodo builds the image *on the server*, this is a non-issue. If we
  ever push from CI to a registry instead, the build must be multi-arch or the container dies with
  `exec format error`.

---

## Hostname — no DNS purchase needed

The box already uses **sslip.io** wildcard DNS (see `brockcsc.129-153-49-190.sslip.io`). Any
`*.129-153-49-190.sslip.io` name resolves to the host automatically, and Let's Encrypt will issue for
it. So we can go live immediately:

```
SITE_HOST=gitoutoftown.129-153-49-190.sslip.io
```

Swap in the real domain later by changing `SITE_HOST` and pointing an A record at `129.153.49.190`.
Nothing else changes. **Buy the real domain anyway** — "permanent" is in the judging brief and an
sslip.io URL undercuts it.

---

## Komodo stack setup (one time)

1. https://manage.wayfarerbx.com → **Stacks** → New → `gitoutoftown`
2. **Source:** this Git repo, branch `main`, file `docker-compose.yaml`
   - The repo is private, so Komodo needs a GitHub account/token configured with read access.
3. **Environment:**
   ```env
   SITE_HOST=gitoutoftown.129-153-49-190.sslip.io
   POSTGRES_PASSWORD=<strong random>
   ADMIN_DELETE_SECRET=<strong random>
   REPLICATE_API_TOKEN=<token>
   NEXT_PUBLIC_GOOGLE_MAPS_API_KEY=<key>
   ```
4. Deploy. Komodo clones and runs `docker compose up -d --build` on the host — building natively for
   ARM64.

> ⚠️ `NEXT_PUBLIC_*` is inlined at **build** time (wired as a build arg in the compose file).
> Changing the Maps key requires a **rebuild**, not a restart.

---

## CD — GitHub Actions → Komodo

`.github/workflows/ci.yml` runs `check → docker → deploy → smoke`. Deploy only fires on green
commits to `main`, so a broken build never reaches the server.

Add these repo secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `KOMODO_URL` | `https://manage.wayfarerbx.com` |
| `KOMODO_API_KEY` | Komodo → Settings → API Keys |
| `KOMODO_API_SECRET` | issued alongside the key |
| `KOMODO_STACK` | `gitoutoftown` |
| `SITE_URL` | `https://gitoutoftown.129-153-49-190.sslip.io` |

```bash
gh secret set KOMODO_URL --repo AlaqmarG/git-out-of-town --body "https://manage.wayfarerbx.com"
gh secret set KOMODO_API_KEY --repo AlaqmarG/git-out-of-town
gh secret set KOMODO_API_SECRET --repo AlaqmarG/git-out-of-town
gh secret set KOMODO_STACK --repo AlaqmarG/git-out-of-town --body "gitoutoftown"
gh secret set SITE_URL --repo AlaqmarG/git-out-of-town --body "https://gitoutoftown.129-153-49-190.sslip.io"
```

Until they are set, the deploy and smoke jobs **skip with a notice** rather than failing — CI stays
green while the rest is being wired.

The deploy step calls `POST {KOMODO_URL}/execute` with `{"type":"DeployStack","params":{"stack":…}}`.
If your Komodo version expects a different shape, that one `curl` in `ci.yml` is the only thing to
change.

**Alternative (no secrets):** point a plain GitHub webhook at Komodo's listener. Simpler, but it
deploys on *every* push including broken ones — which is why CI-gated deploy is preferred.

---

## Local development

```bash
cp .env.example .env
docker compose up -d got-db     # override file publishes 5432 for local dev
npm install
npm run dev
```

`db/init.sql` runs on **first** container start only. To re-apply after editing:

```bash
docker compose down -v got-db && docker compose up -d got-db   # ⚠️ destroys local data
```

> 📱 Camera, geolocation, and device orientation require **HTTPS** — they will not work on
> `localhost` from a phone. Test against the deployed URL.

---

## Storage

Uploads live on the `uploads` volume at `/data/uploads`, written by the app and served by nginx at
`/uploads/*`. Image bytes never pass through Node — the map pulls hundreds at once on a single pan.

Write `<uuid>.png`; store the relative path in `pieces.raw_image_path` / `final_image_path`.

---

## Live updates

`db/init.sql` installs a trigger firing `pg_notify('new_piece', …)` on insert. Consume it in an SSE
route with a **dedicated `pg.Client`** — never the shared `Pool`, since a pooled connection gets
recycled and silently stops listening.

Fallback: poll `/api/pieces?since=` every 3s. Fine at this scale; not worth losing an hour.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| 404 from Traefik | `SITE_HOST` mismatch, or container not on `wayfarer-net` |
| Cert not issued | Hostname doesn't resolve to `129.153.49.190` yet |
| `exec format error` | An amd64 image reached the ARM host — build on the server |
| Uploads 404 but app works | `got-uploads` router priority lost to the catch-all; it is set to 100 |
| DB connection refused | `got-db` is on `internal` only — the app must be on that network too |

```bash
ssh wayfare-vps-runner 'docker ps --filter name=got-'
ssh wayfare-vps-runner 'docker logs --tail 50 gitoutoftown-got-app-1'
```
