import { describe, expect, it } from "vitest";
import { clientIp, rateLimit } from "./ratelimit";

// Unique key per test — the bucket store is module-level state.
let n = 0;
const key = () => `test-${Date.now()}-${n++}`;

describe("rateLimit", () => {
  it("allows exactly `capacity` requests in a burst", () => {
    const k = key();
    const results = Array.from({ length: 5 }, () => rateLimit(k, 3, 1).ok);
    expect(results).toEqual([true, true, true, false, false]);
  });

  it("reports a positive Retry-After once exhausted", () => {
    const k = key();
    rateLimit(k, 1, 1 / 6);
    const denied = rateLimit(k, 1, 1 / 6);
    expect(denied.ok).toBe(false);
    expect(denied.retryAfter).toBeGreaterThan(0);
  });

  it("isolates buckets by key", () => {
    const a = key();
    const b = key();
    expect(rateLimit(a, 1, 1).ok).toBe(true);
    expect(rateLimit(a, 1, 1).ok).toBe(false);
    expect(rateLimit(b, 1, 1).ok).toBe(true);
  });

  it("refills over time", async () => {
    const k = key();
    expect(rateLimit(k, 1, 50).ok).toBe(true);
    expect(rateLimit(k, 1, 50).ok).toBe(false);
    await new Promise((r) => setTimeout(r, 60));
    expect(rateLimit(k, 1, 50).ok).toBe(true);
  });

  it("never refills beyond capacity", async () => {
    const k = key();
    await new Promise((r) => setTimeout(r, 50));
    const burst = Array.from({ length: 4 }, () => rateLimit(k, 2, 100).ok);
    expect(burst.filter(Boolean).length).toBeLessThanOrEqual(3);
  });
});

describe("clientIp", () => {
  const req = (h: Record<string, string>) => new Request("https://x.test", { headers: h });

  it("takes the leftmost x-forwarded-for entry", () => {
    expect(clientIp(req({ "x-forwarded-for": "1.2.3.4, 10.0.0.1, 10.0.0.2" }))).toBe("1.2.3.4");
  });

  it("trims whitespace", () => {
    expect(clientIp(req({ "x-forwarded-for": "  1.2.3.4  " }))).toBe("1.2.3.4");
  });

  it("falls back to x-real-ip", () => {
    expect(clientIp(req({ "x-real-ip": "5.6.7.8" }))).toBe("5.6.7.8");
  });

  it("degrades to a constant rather than throwing", () => {
    expect(clientIp(req({}))).toBe("unknown");
  });
});
