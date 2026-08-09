import ARKit
import CoreImage
import UIKit

/// Rectifies the camera pixels under a placed quad into a perspective-correct,
/// brightness-normalized luminance map. Multiplied into the graffiti material,
/// the paint inherits the real surface's grain — mortar lines, wood, concrete —
/// aligned exactly with where it sits on the wall.
enum SurfaceTexture {
    private static let context = CIContext()

    /// `basis` is the pre-upright placement frame: col0 = right, col1 = up,
    /// col2 = normal, col3 = position.
    static func luminanceMap(frame: ARFrame, basis: simd_float4x4, size: Float) -> UIImage? {
        let buffer = frame.capturedImage
        let imageSize = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))

        let right = simd_make_float3(basis.columns.0)
        let up = simd_make_float3(basis.columns.1)
        let pos = simd_make_float3(basis.columns.3)
        let half = size / 2

        // Project each corner into sensor pixels, then flip into CI's
        // bottom-left-origin coordinates.
        func ciPoint(_ world: SIMD3<Float>) -> CGPoint {
            let p = frame.camera.projectPoint(world, orientation: .landscapeRight, viewportSize: imageSize)
            return CGPoint(x: p.x, y: imageSize.height - p.y)
        }
        let tl = ciPoint(pos - right * half + up * half)
        let tr = ciPoint(pos + right * half + up * half)
        let bl = ciPoint(pos - right * half - up * half)
        let br = ciPoint(pos + right * half - up * half)

        let source = CIImage(cvPixelBuffer: buffer)
        var image = source.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": CIVector(cgPoint: tl),
            "inputTopRight": CIVector(cgPoint: tr),
            "inputBottomLeft": CIVector(cgPoint: bl),
            "inputBottomRight": CIVector(cgPoint: br),
        ])
        guard image.extent.width > 16, image.extent.height > 16,
              image.extent.width < 8192, image.extent.height < 8192 else { return nil }

        image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])

        // Push the average toward white so multiplying darkens only where the
        // surface itself darkens.
        let gain = min(max(0.9 / max(averageLuminance(of: image), 0.05), 0.6), 3.5)
        image = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
        ])

        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
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
