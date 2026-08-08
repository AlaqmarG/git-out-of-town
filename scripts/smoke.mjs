#!/usr/bin/env node
/**
 * Functional smoke test against a running deployment.
 *
 *   npm run test:smoke                        # against SITE_URL or localhost:3000
 *   SMOKE_URL=https://… npm run test:smoke    # against anything
 *   SMOKE_WRITE=1 npm run test:smoke          # include the write round-trip
 *
 * Read-only by default. The write path creates a real row and there is no admin
 * delete endpoint yet (#17), so CI runs read-only to avoid polluting /data.
 * Once #17 lands, wire cleanup in and make writes the default.
 */

const BASE = (process.env.SMOKE_URL || process.env.SITE_URL || "http://localhost:3000").replace(/\/$/, "");
const WRITE = process.env.SMOKE_WRITE === "1";

let passed = 0;
const failures = [];

async function check(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  ✓ ${name}`);
  } catch (err) {
    failures.push({ name, message: err.message });
    console.log(`  ✗ ${name}\n      ${err.message}`);
  }
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

async function expectStatus(path, want, init) {
  let res = await fetch(`${BASE}${path}`, init);

  // The write path is rate limited (burst 10, refill 1/6s). Repeated smoke runs
  // legitimately exhaust it, so honour Retry-After once rather than reporting a
  // false failure.
  if (res.status === 429 && want !== 429) {
    const wait = Math.min(15, Number(res.headers.get("retry-after") || 7));
    console.log(`      rate limited, waiting ${wait}s…`);
    await new Promise((r) => setTimeout(r, wait * 1000));
    res = await fetch(`${BASE}${path}`, init);
  }

  assert(res.status === want, `${path} → expected ${want}, got ${res.status}`);
  return res;
}

/** Smallest valid PNG: 1x1 transparent. */
const PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk" +
    "YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
  "base64",
);

function form(meta, bytes = PNG, filename = "t.png", type = "image/png") {
  const fd = new FormData();
  fd.append("image", new Blob([bytes], { type }), filename);
  if (meta !== undefined) fd.append("meta", typeof meta === "string" ? meta : JSON.stringify(meta));
  return fd;
}

const validMeta = {
  lat: 0.0001,
  lng: 0.0001, // Null Island — obviously synthetic if a row ever escapes cleanup
  kind: "spray",
  sessionId: `smoke-${Date.now()}`,
  client: "web",
};

console.log(`\nSmoke test → ${BASE}${WRITE ? "  (write mode)" : "  (read-only)"}\n`);

console.log("health");
await check("GET /api/health returns ok", async () => {
  const res = await expectStatus("/api/health", 200);
  const body = await res.json();
  assert(body.ok === true, `expected ok:true, got ${JSON.stringify(body)}`);
});

console.log("\nreads");
await check("GET /api/pieces returns a well-formed list", async () => {
  const res = await expectStatus("/api/pieces", 200);
  const body = await res.json();
  assert(Array.isArray(body.pieces), "pieces is not an array");
  assert(typeof body.total === "number", "total is not a number");
});

await check("GET /api/pieces respects limit", async () => {
  const res = await expectStatus("/api/pieces?limit=1", 200);
  const { pieces } = await res.json();
  assert(pieces.length <= 1, `limit=1 returned ${pieces.length}`);
});

await check("GET /api/pieces accepts a bbox", async () => {
  const res = await expectStatus("/api/pieces?bbox=-79.6,43.5,-79.2,43.8", 200);
  const { pieces } = await res.json();
  for (const p of pieces) {
    assert(p.lat >= 43.5 && p.lat <= 43.8, `piece ${p.id} lat ${p.lat} outside bbox`);
    assert(p.lng >= -79.6 && p.lng <= -79.2, `piece ${p.id} lng ${p.lng} outside bbox`);
  }
});

console.log("\nquery validation");
await check("rejects a malformed bbox", () => expectStatus("/api/pieces?bbox=1,2,3", 400));
await check("rejects a bbox with a blank part", () => expectStatus("/api/pieces?bbox=1,,3,4", 400));
await check("rejects an out-of-range limit", () => expectStatus("/api/pieces?limit=99999", 400));
await check("rejects a non-numeric limit", () => expectStatus("/api/pieces?limit=abc", 400));
await check("rejects a malformed since", () => expectStatus("/api/pieces?since=not-a-date", 400));

if (WRITE) {
  console.log("\nwrite round-trip");
  let created;

  await check("POST /api/pieces creates a piece", async () => {
    const res = await expectStatus("/api/pieces", 201, { method: "POST", body: form(validMeta) });
    created = await res.json();
    assert(typeof created.id === "number", "response has no numeric id");
    assert(created.rawImagePath, "response has no rawImagePath");
    assert(created.client === "web", `expected client web, got ${created.client}`);
  });

  await check("the stored image is served by nginx", async () => {
    assert(created, "skipped — nothing was created");
    const res = await expectStatus(`/uploads/${created.rawImagePath}`, 200);
    const type = res.headers.get("content-type") || "";
    assert(type.includes("image/png"), `expected image/png, got ${type}`);
  });

  await check("the new piece is retrievable", async () => {
    assert(created, "skipped — nothing was created");
    const res = await expectStatus("/api/pieces?limit=100", 200);
    const { pieces } = await res.json();
    assert(pieces.some((p) => p.id === created.id), `piece ${created.id} not in the list`);
  });

  console.log(
    `\n  ⚠️  created piece id=${created?.id ?? "?"} at 0.0001,0.0001 — delete it before judging`,
  );
}

console.log("\nwrite validation (rejected before anything is stored)");
await check("rejects a non-multipart body", () =>
  expectStatus("/api/pieces", 415, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: "{}",
  }));

await check("rejects a missing meta part", () =>
  expectStatus("/api/pieces", 400, { method: "POST", body: form(undefined) }));

await check("rejects meta that is not JSON", () =>
  expectStatus("/api/pieces", 400, { method: "POST", body: form("{nope") }));

await check("rejects an out-of-range lat", () =>
  expectStatus("/api/pieces", 400, { method: "POST", body: form({ ...validMeta, lat: 999 }) }));

await check("rejects an unknown kind", () =>
  expectStatus("/api/pieces", 400, { method: "POST", body: form({ ...validMeta, kind: "laser" }) }));

await check("rejects bytes that are not an image", () =>
  expectStatus("/api/pieces", 415, {
    method: "POST",
    body: form(validMeta, Buffer.from("definitely not a png"), "t.png", "image/png"),
  }));

console.log(`\n${failures.length ? "FAILED" : "PASSED"} — ${passed} passed, ${failures.length} failed\n`);
if (failures.length) {
  for (const f of failures) console.error(`  ✗ ${f.name}: ${f.message}`);
  process.exit(1);
}
