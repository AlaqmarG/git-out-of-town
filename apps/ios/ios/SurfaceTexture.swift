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
        // surface itself darkens. The bias is a floor: without it a shadowed or
        // dark-painted wall multiplies the art down to black and the piece the
        // user just made is simply not there.
        let bias: CGFloat = 0.25
        let gain = min(max(0.9 / max(averageLuminance(of: ci), 0.05), 0.6), 3.5) * (1 - bias)
        ci = ci.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
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
