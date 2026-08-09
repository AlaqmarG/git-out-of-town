import Accelerate
import CoreImage
import UIKit

/// Turns the captured photo into a brightness-normalized greyscale map.
/// Multiplied through the artwork with the same projection UVs, the paint picks
/// up the real surface's shading and grain — mortar lines, wood, concrete —
/// exactly where they fall on the wall.
enum SurfaceTexture {
    /// CIContext is thread-safe, and the surface bake reads it off the main actor.
    nonisolated(unsafe) private static let context = CIContext()

    static func luminance(of image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        // Contrast first: normalising below flattens the map toward a uniform
        // grey, and grain that survives that is the whole point of this map.
        var ci = CIImage(cgImage: cg).applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0,
            kCIInputContrastKey: 1.7,
        ])

        // Push the average toward white so multiplying darkens only where the
        // surface itself darkens. The bias is a floor: without it a shadowed or
        // dark-painted wall multiplies the art down to black and the piece the
        // user just made is simply not there. Kept low — at 0.25 the floor ate
        // the shading it exists to preserve.
        let bias: CGFloat = 0.12
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

    /// Tangent-space normal map of the wall's own grain, so light catches along
    /// mortar lines, brick edges and concrete pits instead of sliding over a
    /// printed sheet. Sobel on raw bytes through vImage — no colour management
    /// to misread the 128 neutral. Nil when there is no usable image, which
    /// leaves the material with no normal map at all.
    nonisolated static func normalMap(of image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        // Grain, not megapixels: 512 on the long edge still resolves mortar at
        // arm's length and keeps the pass in single-digit milliseconds.
        let scale = min(1, 512 / CGFloat(max(cg.width, cg.height)))
        let width = Int((CGFloat(cg.width) * scale).rounded())
        let height = Int((CGFloat(cg.height) * scale).rounded())
        // Below the kernel's own footprint a Sobel is all edge artefact.
        guard width >= 8, height >= 8 else { return nil }

        let count = width * height
        let grey = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        let dx = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        let dy = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        let flat = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        let rgba = UnsafeMutablePointer<UInt8>.allocate(capacity: count * 4)
        defer {
            grey.deallocate(); dx.deallocate(); dy.deallocate()
            flat.deallocate(); rgba.deallocate()
        }
        flat.update(repeating: 255, count: count)

        guard let ctx = CGContext(
            data: grey,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        func buffer(_ data: UnsafeMutablePointer<UInt8>, channels: Int = 1) -> vImage_Buffer {
            vImage_Buffer(
                data: data,
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: width * channels
            )
        }

        // A height field's tangent-space normal is (-dh/du, -dh/dv, 1), so both
        // kernels are Sobel negated. Divisor 8 is the kernel's gain and bias
        // 1024 lands the flat case on 128 — the 0.5 that decodes as "no tilt".
        let sobelX: [Int16] = [1, 0, -1, 2, 0, -2, 1, 0, -1]
        let sobelY: [Int16] = [1, 2, 1, 0, 0, 0, -1, -2, -1]
        var src = buffer(grey)
        var xOut = buffer(dx)
        var yOut = buffer(dy)
        let edge = vImage_Flags(kvImageEdgeExtend)
        guard vImageConvolveWithBias_Planar8(
            &src, &xOut, nil, 0, 0, sobelX, 3, 3, 8, 1024, 0, edge
        ) == kvImageNoError,
            vImageConvolveWithBias_Planar8(
                &src, &yOut, nil, 0, 0, sobelY, 3, 3, 8, 1024, 0, edge
            ) == kvImageNoError
        else { return nil }

        // The four slots are (A, R, G, B) but they are written in argument order,
        // so passing x, y, ones, ones lays out RGBA = (x, y, 1, opaque). Verified,
        // not assumed. `ones` is aliased into both trailing slots on purpose.
        var ones = buffer(flat)
        var onesAgain = buffer(flat)
        var packed = buffer(rgba, channels: 4)
        guard vImageConvert_Planar8toARGB8888(
            &xOut, &yOut, &ones, &onesAgain, &packed, vImage_Flags(kvImageNoFlags)
        ) == kvImageNoError else { return nil }

        // noneSkipLast: this is data, not a picture. Any premultiplied alpha
        // reading would let CoreGraphics rescale the gradients.
        guard let provider = CGDataProvider(data: Data(bytes: rgba, count: count * 4) as CFData),
              let out = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: out)
    }

    /// The four corners of a piece on screen, in unit viewport coordinates with
    /// v running down, named for the artwork corner each one carries.
    struct Corners {
        let topLeft: CGPoint
        let topRight: CGPoint
        let bottomLeft: CGPoint
        let bottomRight: CGPoint
    }

    /// Warps the wall behind a piece into the piece's own UVs. A viewer stands
    /// wherever they like, so the quad is a trapezoid on screen; correcting the
    /// perspective is what lets the grain line up with the art the way it does
    /// on the painter's own device, where the two share a camera pose.
    nonisolated static func rectified(_ photo: UIImage, to corners: Corners) -> UIImage? {
        guard let cg = photo.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        // CoreImage counts y up from the bottom; the corners count it down.
        func vector(_ p: CGPoint) -> CIVector { CIVector(x: p.x * w, y: (1 - p.y) * h) }

        let corrected = CIImage(cgImage: cg).applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": vector(corners.topLeft),
            "inputTopRight": vector(corners.topRight),
            "inputBottomLeft": vector(corners.bottomLeft),
            "inputBottomRight": vector(corners.bottomRight),
        ])
        var out = corrected
        // A degenerate quad yields an infinite or hairline extent, and rendering
        // that either fails or allocates wildly.
        guard out.extent.width.isFinite, out.extent.height.isFinite,
              out.extent.width >= 16, out.extent.height >= 16 else { return nil }
        // Cap the sample: everything downstream of it — the luminance map, the
        // Sobel, the texture upload — is paid per pixel, and grain does not need
        // more than this.
        let longest = max(out.extent.width, out.extent.height)
        if longest > 512 {
            out = out.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: 512 / longest,
            ])
        }
        guard out.extent.width.isFinite, out.extent.height.isFinite,
              out.extent.width >= 8, out.extent.height >= 8,
              let image = context.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: image)
    }

    /// Mean brightness of the raw surface — the thing `luminance(of:)`
    /// deliberately normalizes away. The shader caps the paint here.
    nonisolated static func averageLuminance(of image: UIImage) -> CGFloat? {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return nil }
        // Averaging is linear, so weighting the 1x1 result is the same answer as
        // desaturating every pixel first, minus a full-frame filter pass.
        return averageLuminance(of: CIImage(cgImage: cg))
    }

    nonisolated private static func averageLuminance(of image: CIImage) -> CGFloat {
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
        let luma = 0.299 * CGFloat(pixel[0]) + 0.587 * CGFloat(pixel[1]) + 0.114 * CGFloat(pixel[2])
        return luma / 255
    }
}
