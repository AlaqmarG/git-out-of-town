import ARKit
import CoreImage
import UIKit

/// Crops the camera frame under a placed quad and turns it into a normalized
/// luminance map. Multiplied into the graffiti material, the paint inherits the
/// real surface's grain — mortar lines, wood, concrete — instead of floating flat.
enum SurfaceTexture {
    private static let context = CIContext()

    static func luminanceMap(frame: ARFrame, placement: simd_float4x4, size: Float) -> UIImage? {
        let buffer = frame.capturedImage
        let imageSize = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))

        let half = size / 2
        let corners = [
            SIMD4<Float>(-half, -half, 0, 1), SIMD4<Float>(half, -half, 0, 1),
            SIMD4<Float>(-half, half, 0, 1), SIMD4<Float>(half, half, 0, 1),
        ].map { corner -> CGPoint in
            let world = placement * corner
            return frame.camera.projectPoint(
                simd_make_float3(world),
                orientation: .landscapeRight,
                viewportSize: imageSize
            )
        }

        let xs = corners.map(\.x), ys = corners.map(\.y)
        var rect = CGRect(
            x: xs.min()!, y: ys.min()!,
            width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!
        ).intersection(CGRect(origin: .zero, size: imageSize))
        guard rect.width > 16, rect.height > 16 else { return nil }

        // projectPoint is top-left origin; CIImage is bottom-left.
        rect.origin.y = imageSize.height - rect.maxY

        var image = CIImage(cvPixelBuffer: buffer)
            .cropped(to: rect)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])

        // Push the average toward white so multiplying darkens only where the
        // surface itself darkens.
        let gain = min(max(0.9 / max(averageLuminance(of: image), 0.05), 0.6), 3.5)
        image = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
        ])

        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .right)
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
