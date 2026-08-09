import { type Server, createServer } from "node:http";
import sharp from "sharp";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { upscaleFactor, upscaleIfSmall, weatherPiece } from "@/lib/transform";

const { query, saveImage, deleteImage, readFile } = vi.hoisted(() => ({
  query: vi.fn(),
  saveImage: vi.fn(async () => "cd/aged.png"),
  deleteImage: vi.fn(async () => {}),
  readFile: vi.fn(),
}));

vi.mock("@/lib/db", () => ({
  pool: { query },
  UPLOAD_DIR: "/data/uploads",
  ensureSchema: async () => {},
}));
vi.mock("node:fs/promises", async (orig) => ({
  ...(await orig<typeof import("node:fs/promises")>()),
  readFile,
}));
vi.mock("@/lib/storage", async (orig) => ({
  ...(await orig<typeof import("@/lib/storage")>()),
  saveImage,
  deleteImage,
}));

const png = (size: number) =>
  sharp({ create: { width: size, height: size, channels: 3, background: "#ff0000" } })
    .png()
    .toBuffer();

describe("upscaleFactor", () => {
  it.each([
    [64, 64, 4],
    [128, 128, 4],
    [200, 150, 3],
    [300, 300, 2],
    [500, 500, 2],
  ])("upscales %ix%i art by %ix", (w, h, scale) => {
    expect(upscaleFactor(w, h)).toBe(scale);
  });

  // Anything the restyle can already fill is left alone: an upscale there only
  // costs money and softens good line art.
  it.each([
    [512, 512],
    [513, 200],
    [200, 4096],
    [2048, 1536],
  ])("leaves %ix%i alone", (w, h) => {
    expect(upscaleFactor(w, h)).toBeNull();
  });

  it("never asks for more than 4x, however tiny the art", () => {
    expect(upscaleFactor(2, 2)).toBe(4);
  });

  it("skips art whose dimensions could not be read", () => {
    expect(upscaleFactor(0, 0)).toBeNull();
  });
});

describe("upscaleIfSmall", () => {
  let server: Server | undefined;
  const realFetch = globalThis.fetch;

  beforeEach(() => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    process.env.REPLICATE_API_TOKEN = "test-token";
  });

  afterEach(async () => {
    vi.restoreAllMocks();
    globalThis.fetch = realFetch;
    delete process.env.REPLICATE_API_TOKEN;
    if (!server) return;
    server.closeAllConnections();
    await new Promise((r) => server!.close(r));
    server = undefined;
  });

  it("does not call Replicate for art that is already big enough", async () => {
    const big = await png(1024);
    const fetchSpy = vi.fn();
    globalThis.fetch = fetchSpy as unknown as typeof fetch;

    expect(await upscaleIfSmall(big)).toBe(big);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("returns the original bytes when Replicate rejects the prediction", async () => {
    const small = await png(96);
    globalThis.fetch = (async () =>
      Response.json({ detail: "no credit" }, { status: 402 })) as typeof fetch;

    expect(await upscaleIfSmall(small)).toBe(small);
  });

  it("returns the original bytes when the prediction never succeeds", async () => {
    const small = await png(96);
    globalThis.fetch = (async () =>
      Response.json({ status: "failed", error: "CUDA OOM" })) as typeof fetch;

    expect(await upscaleIfSmall(small)).toBe(small);
  });

  it("returns the original bytes when there is no API token", async () => {
    const small = await png(96);
    delete process.env.REPLICATE_API_TOKEN;
    const fetchSpy = vi.fn();
    globalThis.fetch = fetchSpy as unknown as typeof fetch;

    expect(await upscaleIfSmall(small)).toBe(small);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  // A corrupt upscale must never reach the restyle — sharp would throw on it
  // and take the whole transform down with it.
  it("returns the original bytes when the output is not an image", async () => {
    const small = await png(96);
    globalThis.fetch = (async (input: string | URL | Request) => {
      if (String(input).includes("api.replicate.com")) {
        return Response.json({ status: "succeeded", output: "https://cdn.test/x" });
      }
      return new Response("<!doctype html><h1>404</h1>");
    }) as typeof fetch;

    expect(await upscaleIfSmall(small)).toBe(small);
  });

  it("passes the upscaled bytes on when Replicate succeeds", async () => {
    const small = await png(96);
    const upscaled = await png(384);
    globalThis.fetch = (async (input: string | URL | Request) => {
      if (String(input).includes("api.replicate.com")) {
        return Response.json({ status: "succeeded", output: "https://cdn.test/x" });
      }
      return new Response(upscaled);
    }) as typeof fetch;

    const out = await upscaleIfSmall(small);
    expect((await sharp(out).metadata()).width).toBe(384);
  });

  /**
   * Regression, same shape as geocode.test.ts: an unread response body keeps
   * its connection checked out of undici's pool. This path swallows every
   * failure by design, so a leak is invisible in the return value — count TCP
   * connections instead. The body must exceed the socket buffer (~64KB) or
   * undici quietly slurps it and hides the bug.
   */
  it("reuses one connection when Replicate keeps rejecting", async () => {
    const small = await png(96);
    let opened = 0;
    server = createServer((_req, res) => {
      res.writeHead(500, { "content-type": "application/json" });
      res.end(JSON.stringify({ detail: "x".repeat(200_000) }));
    });
    server.on("connection", () => opened++);
    await new Promise<void>((r) => server!.listen(0, "127.0.0.1", () => r()));
    const { port } = server.address() as { port: number };

    // Point the module's hardcoded Replicate URL at the stub without mocking
    // the transport — the pooling behaviour under test is undici's, not ours.
    globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
      const u = new URL(String(input));
      return realFetch(`http://127.0.0.1:${port}${u.pathname}`, init);
    }) as typeof fetch;

    for (let i = 0; i < 4; i++) {
      expect(await upscaleIfSmall(small)).toBe(small);
    }

    expect(opened).toBeLessThanOrEqual(2);
  }, 30_000);
});

const realSetTimeout = globalThis.setTimeout;

describe("weatherPiece", () => {
  let art: Buffer;
  // A fresh id per test: the in-flight guard is module state, so reusing one
  // would let a test that leaves a pass running silently no-op the next.
  let pieceId = 0;
  let responses: Response[] = [];
  const fetchMock = vi.fn(async (url: string, init?: RequestInit) => {
    const next = responses.shift();
    if (!next) throw new Error(`unexpected fetch: ${init?.method ?? "GET"} ${url}`);
    return next;
  });

  /** A Replicate prediction that finished inside the `Prefer: wait` window. */
  const succeeded = (output: string) =>
    Response.json({ status: "succeeded", output, urls: { get: "https://api.replicate.com/x" } });

  const imageResponse = () => new Response(new Uint8Array(art));

  /** SELECT finds art to age; the UPDATE that follows claims the piece. */
  function pieceWithArt(rowCount = 1) {
    query.mockResolvedValueOnce({ rows: [{ art: "ab/x.png" }] }).mockResolvedValueOnce({ rowCount });
  }

  /** Weather, then isolate, then the download of the finished PNG. */
  function fullPipeline(download: Response) {
    responses = [succeeded("https://replicate/aged"), succeeded("https://replicate/cut"), download];
  }

  /** Every UPDATE the module issued, so "the piece was left alone" is checkable. */
  const writes = () => query.mock.calls.filter((c) => String(c[0]).includes("UPDATE"));

  beforeEach(async () => {
    art ??= await png(600);
    pieceId++;
    vi.stubGlobal("fetch", fetchMock);
    vi.stubEnv("REPLICATE_API_TOKEN", "test-token");
    query.mockReset();
    readFile.mockReset().mockResolvedValue(art);
    saveImage.mockClear();
    deleteImage.mockClear();
    fetchMock.mockClear();
    responses = [];
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
    vi.useRealTimers();
  });

  it("ages the piece and records the variant path", async () => {
    pieceWithArt();
    fullPipeline(imageResponse());

    await expect(weatherPiece(pieceId)).resolves.toBe("cd/aged.png");

    const [sql, params] = writes()[0]!;
    expect(sql).toContain("weathered_image_path = $2");
    expect(params).toEqual([pieceId, "cd/aged.png"]);
  });

  it("asks for drips and weathering, not another restyle", async () => {
    pieceWithArt();
    fullPipeline(imageResponse());
    await weatherPiece(pieceId);

    const { input } = JSON.parse(String(fetchMock.mock.calls[0]![1]!.body));
    expect(input.prompt).toMatch(/drip/i);
    expect(input.prompt).toMatch(/grime|faded/i);
  });

  /**
   * An aged scribble would outrank the polished art forever, since the map
   * prefers the weathered copy over the final one.
   */
  it("ages the finished piece, never the raw scribble", async () => {
    query.mockResolvedValueOnce({ rows: [] });
    await weatherPiece(pieceId);

    const sql = String(query.mock.calls[0]![0]);
    expect(sql).toContain("final_image_path IS NOT NULL");
    expect(sql).not.toContain("raw_image_path");
  });

  // A piece only ever gains an image. Nothing below may take one away.
  describe("failing soft", () => {
    it("does nothing when the piece is gone, deleted, unrestyled, or already aged", async () => {
      query.mockResolvedValueOnce({ rows: [] });
      await expect(weatherPiece(pieceId)).resolves.toBeNull();
      expect(fetchMock).not.toHaveBeenCalled();
      expect(writes()).toHaveLength(0);
    });

    it("does nothing when the stored art is not an image", async () => {
      query.mockResolvedValueOnce({ rows: [{ art: "ab/x.png" }] });
      readFile.mockResolvedValueOnce(Buffer.from("not an image at all"));
      await expect(weatherPiece(pieceId)).resolves.toBeNull();
      expect(fetchMock).not.toHaveBeenCalled();
      expect(writes()).toHaveLength(0);
    });

    it("leaves the piece untouched when Replicate errors", async () => {
      query.mockResolvedValueOnce({ rows: [{ art: "ab/x.png" }] });
      responses = [Response.json({ detail: "nope" }, { status: 500 })];
      await expect(weatherPiece(pieceId)).rejects.toThrow(/HTTP 500/);
      expect(writes()).toHaveLength(0);
    });

    it("leaves the piece untouched when the prediction fails", async () => {
      query.mockResolvedValueOnce({ rows: [{ art: "ab/x.png" }] });
      responses = [Response.json({ status: "failed", error: "E001" })];
      await expect(weatherPiece(pieceId)).rejects.toThrow(/failed/);
      expect(writes()).toHaveLength(0);
    });

    it("leaves the piece untouched when the result is not an image", async () => {
      query.mockResolvedValueOnce({ rows: [{ art: "ab/x.png" }] });
      fullPipeline(new Response("<html>gone</html>"));
      await expect(weatherPiece(pieceId)).rejects.toThrow(/not an image/);
      expect(saveImage).not.toHaveBeenCalled();
      expect(writes()).toHaveLength(0);
    });

    it("refuses to call Replicate without a token", async () => {
      vi.stubEnv("REPLICATE_API_TOKEN", "");
      query.mockResolvedValueOnce({ rows: [{ art: "ab/x.png" }] });
      await expect(weatherPiece(pieceId)).rejects.toThrow(/REPLICATE_API_TOKEN/);
      expect(fetchMock).not.toHaveBeenCalled();
    });
  });

  // Undrained bodies hold their sockets open; this repo has been bitten twice.
  describe("draining response bodies", () => {
    it("drains a failed download before throwing", async () => {
      query.mockResolvedValueOnce({ rows: [{ art: "ab/x.png" }] });
      const failed = new Response("nginx 404 page", { status: 404 });
      fullPipeline(failed);

      await expect(weatherPiece(pieceId)).rejects.toThrow(/HTTP 404/);
      expect(failed.bodyUsed).toBe(true);
    });

    it("drains a burst-limit response before retrying it", async () => {
      // Only setTimeout: faking microtasks too would stall the body reads.
      vi.useFakeTimers({ toFake: ["setTimeout"] });
      pieceWithArt();
      const limited = new Response("rate limited", { status: 429 });
      responses = [limited, succeeded("a"), succeeded("b"), imageResponse()];

      const pending = weatherPiece(pieceId);
      // The backoff isn't scheduled until the 429's body has been read, so let
      // the real event loop get that far before jumping the clock.
      for (let i = 0; i < 100 && !limited.bodyUsed; i++) {
        await new Promise((r) => realSetTimeout(r, 2));
      }
      expect(limited.bodyUsed).toBe(true);

      await vi.advanceTimersByTimeAsync(12_000);
      await expect(pending).resolves.toBe("cd/aged.png");
    });
  });

  it("only runs one pass per piece at a time", async () => {
    pieceWithArt();
    fullPipeline(imageResponse());

    const [first, second] = await Promise.all([weatherPiece(pieceId), weatherPiece(pieceId)]);
    expect(first).toBe("cd/aged.png");
    expect(second).toBeNull();
    expect(writes()).toHaveLength(1);
  });

  it("discards its output when a concurrent pass already claimed the piece", async () => {
    pieceWithArt(0);
    fullPipeline(imageResponse());

    await expect(weatherPiece(pieceId)).resolves.toBeNull();
    expect(deleteImage).toHaveBeenCalledWith("cd/aged.png");
  });
});
