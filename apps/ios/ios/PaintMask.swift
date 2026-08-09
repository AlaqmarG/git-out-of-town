import CoreGraphics

/// Low-resolution alpha map of the painted overlay: which parts of the screen
/// the user actually painted.
///
/// Kept free of UIKit so `apps/ios/tests` can compile it on the Mac and pin the
/// orientation — see the note on `init(cgImage:side:)`.
struct PaintMask {
    private let alpha: [UInt8]
    private let side: Int
    let bounds: CGRect?

    /// Row 0 of the rasterized mask is the TOP of `cgImage`, which is what the
    /// v-down projected UVs expect.
    ///
    /// No flip belongs here. A raw `CGBitmapContext` maps memory row 0 to the
    /// highest user-space y, so `draw` lands the image upright — unlike
    /// `UIGraphicsImageRenderer`, which pre-flips the CTM and therefore does
    /// need one. Measured, and pinned by `PaintMaskOrientationTests`.
    init?(cgImage: CGImage, side: Int = 96) {
        // RGBA rather than alpha-only: Swift's CGContext can't take the null
        // colour space that an alpha-only context requires.
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &rgba,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var buffer = [UInt8](repeating: 0, count: side * side)
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side {
                let a = rgba[(y * side + x) * 4 + 3]
                buffer[y * side + x] = a
                guard a > 12 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        self.alpha = buffer
        self.side = side
        bounds = maxX < 0 ? nil : CGRect(
            x: CGFloat(minX) / CGFloat(side),
            y: CGFloat(minY) / CGFloat(side),
            width: CGFloat(maxX - minX + 1) / CGFloat(side),
            height: CGFloat(maxY - minY + 1) / CGFloat(side)
        )
    }

    /// True when this point — or a neighbour — carries paint, so triangles
    /// straddling an edge still get covered.
    func isPainted(u: CGFloat, v: CGFloat) -> Bool {
        let x = min(side - 1, max(0, Int(u * CGFloat(side))))
        let y = min(side - 1, max(0, Int(v * CGFloat(side))))
        for dy in -1...1 {
            for dx in -1...1 {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < side, ny >= 0, ny < side else { continue }
                if alpha[ny * side + nx] > 12 { return true }
            }
        }
        return false
    }
}

#if canImport(UIKit)
import UIKit

extension PaintMask {
    init?(overlay: UIImage, side: Int = 96) {
        guard let cg = overlay.uprightCGImage else { return nil }
        self.init(cgImage: cg, side: side)
    }
}

private extension UIImage {
    /// `.cgImage` discards `imageOrientation`, so reading pixels straight off it
    /// would see a rotated or mirrored image. Every overlay we make today is
    /// `.up`; redraw anything that isn't rather than trust that forever.
    var uprightCGImage: CGImage? {
        guard imageOrientation != .up else { return cgImage }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in draw(in: CGRect(origin: .zero, size: size)) }
            .cgImage
    }
}
#endif
