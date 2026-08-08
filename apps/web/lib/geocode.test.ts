import { createServer, type Server } from "node:http";
import { afterEach, expect, it } from "vitest";

import { reverseGeocode } from "@/lib/geocode";

let server: Server | undefined;
const realFetch = globalThis.fetch;

afterEach(async () => {
  globalThis.fetch = realFetch;
  if (!server) return;
  server.closeAllConnections();
  await new Promise((r) => server!.close(r));
  server = undefined;
});

/**
 * Regression: an unread response body keeps its connection checked out of
 * undici's pool. Enough of them and the pool is exhausted — every later fetch()
 * hangs with no error, which is how a seed run wrote four rows and exited 0.
 *
 * `reverseGeocode` swallows every failure by design, so a leak is invisible in
 * its return value. Count TCP connections instead: a drained body lets undici
 * reuse one keep-alive socket, a leaked one forces a fresh socket per call.
 *
 * The body must exceed the socket buffer (~64KB) — undici quietly slurps a
 * small one, which hides the bug.
 */
it("reuses one connection when the geocoder keeps rejecting", async () => {
  let opened = 0;
  server = createServer((_req, res) => {
    res.writeHead(403, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: "x".repeat(200_000) }));
  });
  server.on("connection", () => opened++);
  await new Promise<void>((r) => server!.listen(0, "127.0.0.1", () => r()));
  const { port } = server.address() as { port: number };

  // Point the module's hardcoded Nominatim URL at the stub without mocking the
  // transport — the pooling behaviour under test is undici's, not ours.
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const u = new URL(String(input));
    return realFetch(`http://127.0.0.1:${port}${u.pathname}${u.search}`, init);
  }) as typeof fetch;

  // Distinct coordinates so the 3dp cache cannot short-circuit the lookups.
  for (let i = 0; i < 4; i++) {
    await expect(reverseGeocode(43.6 + i / 100, -79.4)).resolves.toEqual({
      city: null,
      country: null,
    });
  }

  expect(opened).toBeLessThanOrEqual(2);
}, 30_000);
