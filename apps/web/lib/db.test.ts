import { beforeEach, describe, expect, it, vi } from "vitest";

const { query } = vi.hoisted(() => ({ query: vi.fn() }));
vi.mock("pg", () => ({
  Pool: class {
    query = query;
    on() {}
  },
}));

/**
 * `weathered_image_path` postdates the deployed database and every read of a
 * piece selects it, so a deploy without it would 500 the whole map.
 */
describe("ensureSchema", () => {
  beforeEach(() => {
    vi.resetModules();
    query.mockReset();
  });

  it("applies the schema step once per process, however many callers ask", async () => {
    query.mockResolvedValue({});
    const { ensureSchema } = await import("./db");
    await Promise.all([ensureSchema(), ensureSchema(), ensureSchema()]);
    expect(query).toHaveBeenCalledTimes(1);
    expect(String(query.mock.calls[0]![0])).toContain("ADD COLUMN IF NOT EXISTS");
  });

  // A cached rejection would 500 every read until the container restarted.
  it("retries after a database blip instead of poisoning the memo", async () => {
    query.mockRejectedValueOnce(new Error("connection reset")).mockResolvedValue({});
    const { ensureSchema } = await import("./db");
    await expect(ensureSchema()).rejects.toThrow(/connection reset/);
    await expect(ensureSchema()).resolves.toBeUndefined();
    expect(query).toHaveBeenCalledTimes(2);
  });
});
