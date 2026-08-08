# Deploy — Komodo on OCI

Self-hosted: Next.js + Postgres + Caddy, all in one compose stack. No Supabase, no external DB.

```
Caddy (:80/:443, auto-HTTPS)
 ├── /uploads/*  → static files off the shared volume
 └── /*          → app:3000  (Next.js standalone)
                      └── db:5432 (Postgres 17, 200GB volume)
```

---

## ⚠️ Two OCI gotchas that will eat an hour

**1. Ports 80/443 are blocked twice.** OCI needs *both*:
- **Security List / NSG** — add ingress rules for TCP 80 and 443 in the VCN subnet
- **Host firewall** — Oracle images ship with iptables rules that drop everything:
  ```bash
  sudo iptables -I INPUT 1 -p tcp --dport 80  -j ACCEPT
  sudo iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT
  sudo netfilter-persistent save     # Ubuntu
  ```
  Opening only the Security List is the single most common "why is my site unreachable" on OCI.

**2. Ampere instances are ARM64.** If your VPS is an A1 (the free-tier ARM shape), images must be
`linux/arm64`. This is why we let **Komodo build on the server** — it builds natively and the problem
disappears. If you ever switch to a registry, you must build multi-arch or it will fail to start with
an `exec format error`.

---

## First-time setup

### 1. DNS
Point an A record at the VPS public IP. Caddy needs this resolving *before* it can issue a cert.

### 2. Env file on the server
Komodo injects environment into the stack. Set at minimum:

```env
SITE_DOMAIN=gitoutoftown.com
POSTGRES_PASSWORD=<strong random>
ADMIN_DELETE_SECRET=<strong random>
REPLICATE_API_TOKEN=<token>
NEXT_PUBLIC_GOOGLE_MAPS_API_KEY=<key>
```

> `NEXT_PUBLIC_*` is **inlined at build time**, not read at runtime. It is wired as a Docker build arg
> in `docker-compose.yaml`. If you change the Maps key you must **rebuild**, not just restart.

### 3. Komodo stack
1. Komodo → **Stacks** → New
2. Source: this Git repo, branch `main`, file `docker-compose.yaml`
3. Paste the env above into the stack's Environment
4. Deploy

Komodo clones the repo and runs `docker compose up -d --build` on the server. Because it builds
locally, ARM64 is handled for free.

### 4. Auto-deploy on push (the CD half)
In Komodo, enable the stack's **webhook** and copy the URL, then:

```
GitHub repo → Settings → Webhooks → Add webhook
  Payload URL:  <komodo webhook url>
  Content type: application/json
  Secret:       <komodo webhook secret>
  Events:       Just the push event
```

Push to `main` → Komodo pulls, rebuilds, redeploys.

---

## CI

`.github/workflows/ci.yml` runs on every push and PR: typecheck → lint → `next build` → Docker build
verification. It does **not** push an image — deployment is Komodo's job. This keeps a broken
Dockerfile from reaching the server without adding registry auth.

---

## Local development

```bash
cp .env.example .env
docker compose up -d db          # Postgres only
npm install
npm run dev
```

Schema in `db/init.sql` runs automatically on **first** container start only. To re-apply after
editing it:

```bash
docker compose down -v db && docker compose up -d db   # ⚠️ destroys local data
```

> 📱 Camera, geolocation, and device orientation need **HTTPS**. They will not work on `localhost`
> from a phone. Test against the deployed domain, or tunnel with `cloudflared`/`ngrok`.

---

## Storage

Uploads go to the `uploads` volume at `/data/uploads`, served by Caddy at `/uploads/*` — Next.js
never streams image bytes. Both `app` and `caddy` mount the same volume (Caddy read-only).

With ~200GB, storage is not a constraint. Write `<uuid>.png` and store the relative path in
`pieces.raw_image_path` / `final_image_path`.

---

## Live updates (replaces Supabase Realtime)

`db/init.sql` installs a trigger that fires `pg_notify('new_piece', …)` on insert. Consume it with a
dedicated (non-pooled) client in an SSE route:

```ts
const client = new Client({ connectionString: process.env.DATABASE_URL });
await client.connect();
await client.query("LISTEN new_piece");
client.on("notification", (msg) => { /* push down the SSE stream */ });
```

Use a **dedicated `Client`**, never the shared `Pool` — a pooled connection can be handed to another
query and silently stop listening.

Fallback if SSE fights back: poll `/api/pieces?since=` every 3s. Perfectly acceptable at this scale,
and not worth losing an hour over.

---

## Health

`GET /api/health` returns `{ ok: true }` once Postgres answers. Point Komodo's health check at it.
