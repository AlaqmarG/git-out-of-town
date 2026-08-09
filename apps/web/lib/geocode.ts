/**
 * Reverse geocoding: lat/lng -> city, country.
 *
 * We are self-hosted behind our own Traefik, so there are NO CDN geo headers
 * (no `x-vercel-ip-city`, no `cf-ipcountry`). Instead we reverse-geocode the
 * GPS coordinates the client already sends — more accurate than IP anyway,
 * since it reflects where the piece was painted, not where the phone's carrier
 * egresses.
 *
 * Best effort only. Never blocks or fails a write; city/country stay null.
 */

const NOMINATIM = "https://nominatim.openstreetmap.org/reverse";
const CONTACT = "git-out-of-town (SummerHacks 2026)";
const TIMEOUT_MS = 2500;
/**
 * Longest a contribution will wait on a label. Lookups are serialised at ~1/sec,
 * so a rush of pieces from unseen places would otherwise queue up behind each
 * other and make posting feel broken. The lookup still finishes and fills the
 * cache; only *this* caller stops waiting for it.
 */
const BUDGET_MS = 3000;

export interface Place {
  city: string | null;
  country: string | null;
}

/**
 * Cache key at 3dp ≈ 110m. Seeding a venue collapses to a single lookup, which
 * keeps us well inside Nominatim's 1 req/sec policy.
 */
const cache = new Map<string, Place>();
const MAX_CACHE = 5_000;

function key(lat: number, lng: number): string {
  return `${lat.toFixed(3)},${lng.toFixed(3)}`;
}

/** Serialise requests ~1/sec so we stay a good Nominatim citizen. */
let chain: Promise<unknown> = Promise.resolve();

export async function reverseGeocode(lat: number, lng: number): Promise<Place> {
  const k = key(lat, lng);
  const hit = cache.get(k);
  if (hit) return hit;

  const run = chain.then(async () => {
    const again = cache.get(k);
    if (again) return again;

    const url = `${NOMINATIM}?format=jsonv2&zoom=10&lat=${lat}&lon=${lng}`;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);

    try {
      const res = await fetch(url, {
        signal: ctrl.signal,
        headers: { "User-Agent": CONTACT, Accept: "application/json" },
      });
      if (!res.ok) {
        // Drain before bailing out. An unread response body keeps its connection
        // checked out of undici's pool, and Nominatim rejects in bursts (403/429),
        // so one pinned connection per rejection eventually wedges every later
        // lookup — silently, since this path is best-effort and swallows errors.
        await res.arrayBuffer();
        return { city: null, country: null };
      }

      const body = (await res.json()) as {
        address?: Record<string, string | undefined>;
      };
      const a = body.address ?? {};
      const place: Place = {
        city: a.city ?? a.town ?? a.village ?? a.municipality ?? a.county ?? null,
        country: a.country ?? null,
      };

      if (cache.size >= MAX_CACHE) cache.clear();
      cache.set(k, place);
      return place;
    } catch {
      // Aborted, offline, or rate limited — a piece without a city label is fine.
      return { city: null, country: null };
    } finally {
      clearTimeout(timer);
      await new Promise((r) => setTimeout(r, 1000));
    }
  });

  chain = run.catch(() => undefined);

  let timer: ReturnType<typeof setTimeout> | undefined;
  const budget = new Promise<Place>((resolve) => {
    timer = setTimeout(() => resolve({ city: null, country: null }), BUDGET_MS);
  });
  return Promise.race([run, budget]).finally(() => clearTimeout(timer));
}
