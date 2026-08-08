/**
 * Token bucket, in memory. Single container, so a shared store would be overkill.
 * Resets on deploy — acceptable: this exists to stop a bot draining Replicate
 * credits, not to enforce a billing quota.
 */

type Bucket = { tokens: number; last: number };

const buckets = new Map<string, Bucket>();

/** Stop unbounded growth if we get scanned. */
const MAX_KEYS = 10_000;

export interface RateLimit {
  ok: boolean;
  retryAfter: number;
}

export function rateLimit(key: string, capacity: number, refillPerSec: number): RateLimit {
  const now = Date.now();
  let b = buckets.get(key);

  if (!b) {
    if (buckets.size >= MAX_KEYS) buckets.clear();
    b = { tokens: capacity, last: now };
    buckets.set(key, b);
  }

  b.tokens = Math.min(capacity, b.tokens + ((now - b.last) / 1000) * refillPerSec);
  b.last = now;

  if (b.tokens < 1) {
    return { ok: false, retryAfter: Math.ceil((1 - b.tokens) / refillPerSec) };
  }
  b.tokens -= 1;
  return { ok: true, retryAfter: 0 };
}

/**
 * Client IP behind Traefik. `x-forwarded-for` is a chain; the leftmost entry is
 * the original client. Trustworthy here only because nothing but our own proxy
 * can reach the app container.
 */
export function clientIp(req: Request): string {
  const fwd = req.headers.get("x-forwarded-for");
  if (fwd) return fwd.split(",")[0]!.trim();
  return req.headers.get("x-real-ip")?.trim() || "unknown";
}
