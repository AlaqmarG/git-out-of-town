import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Turns clean vector-ish artwork into something that reads as aerosol on a
/// wall. A crisp edge is the loudest "sticker" cue there is, so the edge is
/// softened and then broken up with the speckle a real can throws — overspray
/// dots outside the stroke, thin coverage inside it.
enum SprayPaint {
    private static let context = CIContext()

    static func aerosolize(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let source = CIImage(cgImage: cg)
        let extent = source.extent
        // Scale the effect to the art, not to pixels — a 2048px overlay and a
        // 512px sticker should look equally sprayed.
        let unit = min(extent.width, extent.height) / 512

        // Overspray: a halo of paint just outside the stroke, punched through
        // with noise so it reads as scattered droplets rather than a glow.
        let bleed = source
            .applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": 4 * unit])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 3 * unit])
            .cropped(to: extent)

        let speckle = CIFilter.randomGenerator().outputImage?
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0,
                kCIInputContrastKey: 3.2,
                kCIInputBrightnessKey: -0.34,
            ]) ?? CIImage(color: .black).cropped(to: extent)

        // Speckle gates the halo's alpha: dots survive, the smooth glow doesn't.
        let dots = bleed.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: speckle,
        ])

        // Soften the original edge a touch, then lay it over the droplets.
        let softened = source
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.8 * unit])
            .cropped(to: extent)

        let combined = softened.composited(over: dots).cropped(to: extent)
        guard let out = context.createCGImage(combined, from: extent) else { return image }
        return UIImage(cgImage: out)
    }
}
