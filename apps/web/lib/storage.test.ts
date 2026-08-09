import { describe, expect, it } from "vitest";
import { detectImage, MAX_SNAPSHOT_BYTES, readImagePart } from "./storage";

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

describe("readImagePart", () => {
  const form = (part?: Blob) => {
    const f = new FormData();
    if (part) f.set("snapshot", new File([part], "guide.jpg"));
    return f;
  };
  const jpeg = (bytes: number) =>
    new Blob([Buffer.concat([JPEG, Buffer.alloc(Math.max(bytes - JPEG.length, 0))])]);

  it("returns the bytes and the sniffed extension", async () => {
    const got = await readImagePart(form(jpeg(40_000)), "snapshot", MAX_SNAPSHOT_BYTES);
    expect(got?.ext).toBe("jpg");
    expect(got?.buf.length).toBe(40_000);
  });

  // Every caller uses this for a decoration riding along with something
  // valuable, so an unusable part must be droppable without distinguishing
  // "absent" from "junk".
  it.each([
    ["an absent part", undefined],
    ["an empty part", new Blob([])],
    ["something that isn't an image", new Blob([Buffer.from("stand here and match this view")])],
    ["an oversized part", jpeg(MAX_SNAPSHOT_BYTES + 1)],
  ])("returns null for %s", async (_l, part) => {
    expect(await readImagePart(form(part), "snapshot", MAX_SNAPSHOT_BYTES)).toBeNull();
  });

  it("accepts a part exactly at the limit", async () => {
    const got = await readImagePart(form(jpeg(MAX_SNAPSHOT_BYTES)), "snapshot", MAX_SNAPSHOT_BYTES);
    expect(got?.ext).toBe("jpg");
  });
});
