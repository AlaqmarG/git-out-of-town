import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Every knob that makes paint read as sprayed rather than pasted. `feather` is
/// baked into the artwork here; the rest reach the per-fragment pass in
/// `ARPaintView` — all but `wallCap` as literals compiled into the shader.
enum Aerosol {
    /// Edge blur radius in 512ths of the art. Measured: 0.8 leaves a 3 px alpha
    /// ramp, 1.5 leaves 6 — the band the shader's noise has to dissolve.
    static let feather: CGFloat = 1.5

    /// How far the wall's own shading is blended through the paint.
    static let wallStrength: Float = 0.7
    static let paintOpacity: Float = 0.99

    /// Spray on concrete scatters off the grain instead of returning a clean primary.
    static let desaturate: Float = 0.12

    /// Paint only re-emits the light falling on the wall, so it cannot out-shine
    /// it — with headroom, since a wall's average includes its shadowed side.
    static let capHeadroom: Float = 1.25
    /// A photo of a dark wall must dull the art, not crush it to black.
    static let wallLumaFloor: Float = 0.35

    /// Thinning at grazing incidence: one cone of paint over more surface.
    static let graze: Float = 0.45

    /// Nobody lays one perfect coat. Low-frequency wander reads as passes.
    static let coats: Float = 0.14

    /// How far edge noise moves the alpha cutoff — a spray boundary is droplets.
    static let edgeBite: Float = 0.26
    /// Alpha band treated as "edge". Above `edgeHigh` the coat is solid and the
    /// noise must not touch it, or the whole piece shimmers.
    static let edgeLow: Float = 0.04
    static let edgeHigh: Float = 0.60

    /// Noise cells across the frame: droplets at the edge, arm-sized for coats.
    static let edgeNoiseScale: Float = 210
    static let coatNoiseScale: Float = 5

    /// Relief of the wall's grain, as `intensity` on the Sobel normal map. Past
    /// ~1 the wall turns to plastic; at 0 it is a flat sheet.
    static let bump: CGFloat = 0.7
}

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

        // Soften the original edge, then lay it over the droplets. The ramp this
        // leaves is what the shader's noise threshold erodes into droplets.
        let softened = source
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: Aerosol.feather * unit])
            .cropped(to: extent)

        let combined = softened.composited(over: dots).cropped(to: extent)
        guard let out = context.createCGImage(combined, from: extent) else { return image }
        return UIImage(cgImage: out)
    }
}
