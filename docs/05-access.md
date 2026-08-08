# Access — onboarding Connor

Everything needed to work on this. **No secrets are in this file** — see "Getting credentials" below.

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

## Local development

You do **not** need any production credentials to develop. Run your own Postgres:

```bash
git clone git@github.com:AlaqmarG/git-out-of-town.git
cd git-out-of-town
cp .env.example .env          # the placeholder password is fine locally
docker compose up -d got-db   # override file publishes 5432 for local dev
npm install                   # installs all workspaces
npm run dev
```

- `npm install` at the root installs every workspace — never run it inside `apps/web`.
- `db/init.sql` runs on **first** container start only. Re-apply with
  `docker compose down -v got-db && docker compose up -d got-db` (destroys local data).
- 📱 Camera, geolocation, and device orientation need **HTTPS** — they will not work on `localhost`
  from a phone. Test against the deployed URL.

---

## Getting credentials

**SSH key — don't copy Alaqmar's.** Send Alaqmar your **public** key (`~/.ssh/id_ed25519.pub`,
or generate one with `ssh-keygen -t ed25519`) and it gets appended to `~/.ssh/authorized_keys` on the
box. That way access is per-person and revocable, and a leaked key doesn't hand over Traefik,
Keycloak, and the brockcsc production apps along with it.

**Komodo** — Alaqmar creates you an account at https://manage.wayfarerbx.com.

**Everything else** — already in GitHub Actions secrets; CI uses them automatically and nobody needs
copies locally:

| Secret | Status |
|---|---|
| `KOMODO_URL`, `KOMODO_STACK`, `SITE_URL`, `SITE_HOST` | ✅ set |
| `POSTGRES_PASSWORD`, `ADMIN_DELETE_SECRET` | ✅ set (randomly generated) |
| `KOMODO_API_KEY`, `KOMODO_API_SECRET` | ❌ create in Komodo → Settings → API Keys |
| `REPLICATE_API_TOKEN` | ❌ needed for the transformation |
| `NEXT_PUBLIC_GOOGLE_MAPS_API_KEY` | ❌ needed for Street View (P1) |

```bash
gh secret set <NAME> --repo AlaqmarG/git-out-of-town
```

The prod DB password lives on the VPS in `~/gitoutoftown/.env`. Only needed for manual deploys.

---

## How deploys work

Push to `main` → CI runs `check → docker → deploy → smoke`. Only green commits reach the server.
Komodo builds the image **on the VPS**, natively for ARM64. Details in
[`04-deploy.md`](04-deploy.md).

Until the Komodo API secrets are set, the deploy job skips with a notice instead of failing.
