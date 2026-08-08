# Ops

Infrastructure, deployment, and onboarding.

---

## URLs

| What | Where |
|---|---|
| Live site | https://gitoutoftown.129-153-49-190.sslip.io |
| Health | https://gitoutoftown.129-153-49-190.sslip.io/api/health |
| Repo | https://github.com/AlaqmarG/git-out-of-town (private) |
| Komodo | https://manage.wayfarerbx.com |

## The VPS

| | |
|---|---|
| Host | `129.153.49.190` |
| User | `opc` |
| OS / arch | Oracle Linux 9.8, **aarch64 (Ampere)** |
| Disk | 183G total, ~164G free |
| Proxy | shared Traefik v3.6 on `wayfarer-net`, certresolver `letsencrypt` |
| Our stack | compose project `gitoutoftown`, in `~/gitoutoftown` |
| Containers | `gitoutoftown-got-app-1`, `-got-db-1`, `-got-uploads-1` |

⚠️ **This box also runs production workloads** (`brockcsc-prod-app`, `keycloak`, `komodo-core`,
plus the shared Traefik and Postgres). Don't restart anything outside the `got-` prefix, and never
`docker compose down` from a directory you didn't check first.

### SSH setup

Add to `~/.ssh/config`:

```
Host wayfare-vps-runner
	HostName 129.153.49.190
	User opc
	IdentityFile ~/.ssh/wayfare-ampere.pem
```

```bash
chmod 600 ~/.ssh/wayfare-ampere.pem
ssh wayfare-vps-runner
```

### Useful commands

```bash
ssh wayfare-vps-runner 'docker ps --filter name=got-'
ssh wayfare-vps-runner 'docker logs -f --tail 50 gitoutoftown-got-app-1'
ssh wayfare-vps-runner 'docker exec -it gitoutoftown-got-db-1 psql -U graffiti -d graffiti'
ssh wayfare-vps-runner 'cd ~/gitoutoftown && docker compose -p gitoutoftown -f docker-compose.yaml up -d --build'
```

---
---

## Komodo stack setup (one time)

1. https://manage.wayfarerbx.com → **Stacks** → New → `gitoutoftown`
2. **Source:** this Git repo, branch `main`, file `docker-compose.yaml` (build context is the repo root — the monorepo Dockerfile needs it)
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
---

## What triggers CI/CD

Both workflows use **positive path filters**, so an unrelated change runs nothing.

| Changed | Runs |
|---|---|
| `apps/web/**`, `packages/shared/**`, `db/**`, `scripts/**`, Dockerfile, compose, root manifests | **CI** → typecheck, lint, tests, build, docker, **deploy**, smoke |
| `apps/ios/**` (excluding markdown) | **iOS** → unsigned simulator build |
| Any `*.md`, `docs/**` | **nothing** |

Markdown is excluded even inside otherwise-relevant directories (`!**/*.md`), so editing
`apps/web/CLAUDE.md` never rebuilds or redeploys, and editing `apps/ios/CLAUDE.md` never burns a
macOS runner — those bill at **10x** on private repos.

There are no required status checks on `main`, so a skipped workflow cannot leave a PR hanging.

---

## Storage

Uploads live on the `uploads` volume at `/data/uploads`, written by the app and served by nginx at
`/uploads/*`. Image bytes never pass through Node — the map pulls hundreds at once on a single pan.

Write `<uuid>.png`; store the relative path in `pieces.raw_image_path` / `final_image_path`.

---
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
