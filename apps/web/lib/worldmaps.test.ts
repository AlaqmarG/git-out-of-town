import { describe, expect, it } from "vitest";
import { chainRejection, MAX_CHAIN_DRIFT_M, type ScanQuality } from "./worldmaps";

type Parent = ScanQuality & { supersededAt: Date | null };

const parent: Parent = {
  lat: 43.6426,
  lng: -79.3871,
  featurePoints: 1000,
  anchorCount: 3,
  supersededAt: null,
};

/** A child that clears every gate, to be spoiled one field at a time. */
const better = { ...parent, featurePoints: 1400, anchorCount: 3 };

function reason(child: Partial<typeof better>, over: Partial<Parent> = {}): string | null {
  return chainRejection({ ...parent, ...over }, { ...better, ...child });
}

describe("chainRejection", () => {
  it("lets a richer map with the same anchors supersede its parent", () => {
    expect(reason({})).toBeNull();
  });

  it("carries extra anchors forward", () => {
    expect(reason({ anchorCount: 7 })).toBeNull();
  });

  // The race: two phones relocalize against the same map and both walk on. The
  // second must not clobber the first, whose anchors it never saw.
  it("refuses a parent someone else already extended", () => {
    expect(reason({}, { supersededAt: new Date() })).toMatch(/already been extended/);
  });

  // Anchor loss is the failure that silently breaks the venue: the map still
  // relocalizes, but the pieces it was supposed to pin are gone.
  it("refuses a map that lost anchors, however rich it got", () => {
    expect(reason({ anchorCount: 2, featurePoints: 99_999 })).toMatch(/drop 1 anchor/);
  });

  it("refuses a map that is no better", () => {
    expect(reason({ featurePoints: 1000 })).toMatch(/not meaningfully richer/);
    expect(reason({ featurePoints: 400 })).toMatch(/sparser/);
  });

  // A post pins an anchor the parent has never heard of. Holding that to the
  // feature-growth bar would strand the piece: the painter stood still, so the
  // scan barely grew, and the only map carrying their piece is refused.
  it("takes a new piece as improvement enough on its own", () => {
    expect(reason({ anchorCount: 4, featurePoints: parent.featurePoints })).toBeNull();
  });

  // 5% of a big map is a real walk; 5% of a tiny one is sensor noise. Both gates
  // have to hold, or a thin scan ratchets up on jitter alone.
  it.each([
    ["a 4% gain on a big map", 1000, 1040, false],
    ["a 6% gain on a big map", 1000, 1060, true],
    ["a 49-point gain on a tiny map", 100, 149, false],
    ["a 50-point gain on a tiny map", 100, 150, true],
  ])("%s", (_label, parentPoints, childPoints, allowed) => {
    const why = reason({ featurePoints: childPoints }, { featurePoints: parentPoints });
    expect(why === null).toBe(allowed);
  });

  it("accepts a first chain onto a parent that reported no feature count", () => {
    expect(reason({ featurePoints: 50 }, { featurePoints: 0 })).toBeNull();
    expect(reason({ featurePoints: 49 }, { featurePoints: 0 })).toMatch(/not meaningfully richer/);
  });

  describe("drift", () => {
    const metresNorth = (m: number) => parent.lat + m / 111320;

    it("allows a walk within the venue", () => {
      expect(reason({ lat: metresNorth(MAX_CHAIN_DRIFT_M - 10) })).toBeNull();
    });

    // Otherwise a bad GPS fix — or a malicious client — grafts a scan of another
    // building onto this venue's lineage and nobody relocalizes here again.
    it("refuses a map from somewhere else", () => {
      expect(reason({ lat: metresNorth(MAX_CHAIN_DRIFT_M + 10) })).toMatch(/too far/);
      expect(reason({ lat: 48.85, lng: 2.35 })).toMatch(/too far/);
    });

    it("measures longitude at the parent's latitude, not the equator", () => {
      // 250 m of longitude at 43.6°N is ~0.0031°, which would read as ~180 m if
      // the cosine were dropped — well inside the limit.
      const lng = parent.lng + 300 / (111320 * Math.cos((parent.lat * Math.PI) / 180));
      expect(reason({ lng })).toMatch(/too far/);
    });
  });
});
