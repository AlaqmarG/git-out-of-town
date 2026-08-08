import { describe, expect, it } from "vitest";
import { detectImage } from "./storage";

const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(8)]);
const WEBP = Buffer.concat([
  Buffer.from("RIFF"), Buffer.alloc(4), Buffer.from("WEBP"), Buffer.alloc(4),
]);

describe("detectImage", () => {
  it.each([
    ["png", PNG, "png"],
    ["jpeg", JPEG, "jpg"],
    ["webp", WEBP, "webp"],
  ])("identifies %s from magic bytes", (_l, buf, ext) => {
    expect(detectImage(buf)).toBe(ext);
  });

  it.each([
    ["plain text", Buffer.from("not an image at all")],
    ["empty", Buffer.alloc(0)],
    ["too short to sniff", Buffer.from([0x89, 0x50])],
    ["gif (unsupported)", Buffer.concat([Buffer.from("GIF89a"), Buffer.alloc(8)])],
    ["svg (script vector)", Buffer.from('<svg xmlns="http://www.w3.org/2000/svg">')],
    ["png header truncated", Buffer.from([0x89, 0x50, 0x4e, 0x47])],
  ])("rejects %s", (_l, buf) => {
    expect(detectImage(buf)).toBeNull();
  });

  // The whole point: a client can claim any Content-Type, so only bytes count.
  it("ignores what the client claims and trusts the bytes", () => {
    expect(detectImage(Buffer.from("GIF89a-pretending-to-be-png"))).toBeNull();
  });
});
