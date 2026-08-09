import CoreGraphics
import Foundation

/// Pins `PaintMask`'s orientation: mask row 0 must be the TOP of the artwork,
/// because the projector samples it with v-down screen UVs. A flip here mirrors
/// every placement — paint at the top of the screen gets culled against the
/// bottom of the art — and the failure is invisible on symmetric test art, so
/// every case below is deliberately asymmetric in both axes.
///
/// Runs on the Mac, no simulator:
///
///     swiftc -O apps/ios/ios/PaintMask.swift \
///            apps/ios/tests/PaintMaskOrientationTests.swift -o /tmp/paintmask
///     /tmp/paintmask
@main
enum PaintMaskOrientationTests {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ what: String) {
            print("\(condition ? "ok  " : "FAIL") \(what)")
            if !condition { failures += 1 }
        }

        // Opaque only in the top-left quadrant: catches a vertical flip.
        guard let quadrant = PaintMask(cgImage: image(64) { x, y in x < 32 && y < 32 }),
              let quadrantBounds = quadrant.bounds else {
            print("FAIL PaintMask returned nil"); exit(1)
        }
        check(near(quadrantBounds, CGRect(x: 0, y: 0, width: 0.5, height: 0.5)),
              "top-left quadrant → bounds \(fmt(quadrantBounds)), want (0, 0, 0.5, 0.5)")
        check(quadrant.isPainted(u: 0.25, v: 0.25), "top-left quadrant is painted at (0.25, 0.25)")
        check(!quadrant.isPainted(u: 0.25, v: 0.75), "bottom-left is NOT painted — a vertical flip would fail here")
        check(!quadrant.isPainted(u: 0.75, v: 0.25), "top-right is NOT painted")

        // A wide, short bar along the top: catches a transposed mask, which a
        // square quadrant cannot see.
        guard let bar = PaintMask(cgImage: image(64) { x, y in x < 48 && y < 16 }),
              let barBounds = bar.bounds else {
            print("FAIL PaintMask returned nil"); exit(1)
        }
        check(near(barBounds, CGRect(x: 0, y: 0, width: 0.75, height: 0.25)),
              "top bar → bounds \(fmt(barBounds)), want (0, 0, 0.75, 0.25)")

        // Fully transparent art has no bounds at all, and must not crash.
        check(PaintMask(cgImage: image(64) { _, _ in false })?.bounds == nil, "blank art → nil bounds")

        print(failures == 0 ? "PaintMask orientation: all checks passed" : "\(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }

    /// `side`×`side` premultiplied RGBA, opaque wherever `opaque` says so.
    /// Row 0 of the buffer is the top of the image, CGImage's own convention.
    private static func image(_ side: Int, opaque: (Int, Int) -> Bool) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side where opaque(x, y) {
                let i = (y * side + x) * 4
                pixels[i] = 236; pixels[i + 1] = 64; pixels[i + 2] = 140; pixels[i + 3] = 255
            }
        }
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    /// One 96th is the mask's own cell size; resampling may bleed a single cell.
    private static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        let tolerance = 1.5 / 96.0
        return abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
            && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    private static func fmt(_ r: CGRect) -> String {
        String(format: "(%.3f, %.3f, %.3f, %.3f)", r.minX, r.minY, r.width, r.height)
    }
}
