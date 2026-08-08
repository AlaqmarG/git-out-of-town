import { describe, expect, it } from "vitest";
import { parseBBox, uploadUrl } from "./index";

describe("parseBBox", () => {
  it("parses west,south,east,north", () => {
    expect(parseBBox("-79.6,43.5,-79.2,43.8")).toEqual({
      west: -79.6, south: 43.5, east: -79.2, north: 43.8,
    });
  });

  it("accepts a whole-world box", () => {
    expect(parseBBox("-180,-90,180,90")).toEqual({
      west: -180, south: -90, east: 180, north: 90,
    });
  });

  it.each([
    ["too few parts", "1,2,3"],
    ["too many parts", "1,2,3,4,5"],
    ["non-numeric", "a,b,c,d"],
    ["empty", ""],
    ["trailing comma", "1,2,3,"],
    ["blank part", "1,,3,4"],
    ["Infinity", "1,2,3,Infinity"],
    ["lng out of range", "-181,43,-79,44"],
    ["lat out of range", "-79,-91,-78,44"],
    ["south above north", "-79,44,-78,43"],
  ])("returns null for %s", (_l, raw) => {
    expect(parseBBox(raw)).toBeNull();
  });
});

describe("uploadUrl", () => {
  it("builds a public path", () => {
    expect(uploadUrl("b4/abc.png")).toBe("/uploads/b4/abc.png");
  });

  it("does not double the slash when the path is already rooted", () => {
    expect(uploadUrl("/b4/abc.png")).toBe("/uploads/b4/abc.png");
  });
});
