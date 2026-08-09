import CoreImage
import UIKit

/// Turns the captured photo into a brightness-normalized greyscale map.
/// Multiplied through the artwork with the same projection UVs, the paint picks
/// up the real surface's shading and grain — mortar lines, wood, concrete —
/// exactly where they fall on the wall.
enum SurfaceTexture {
    private static let context = CIContext()

    static func luminance(of image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        var ci = CIImage(cgImage: cg).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])

        // Push the average toward white so multiplying darkens only where the
        // surface itself darkens.
        let gain = min(max(0.9 / max(averageLuminance(of: ci), 0.05), 0.6), 3.5)
        ci = ci.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
        ])

        guard let out = context.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: out)
    }

    private static func averageLuminance(of image: CIImage) -> CGFloat {
        let avg = image.applyingFilter("CIAreaAverage", parameters: [
            kCIInputExtentKey: CIVector(cgRect: image.extent),
        ])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            avg,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return CGFloat(pixel[0]) / 255
    }
}
