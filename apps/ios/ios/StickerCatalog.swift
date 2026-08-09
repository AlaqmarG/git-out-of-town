import UIKit

/// A die-cut sticker, art-directed in Reve and shipped with the app.
///
/// The source art lives in `apps/web/public/stickers/<id>.png` (served to the web
/// map at `/stickers/<id>.png`); the app carries a bundled copy under
/// `ios/Stickers/` so the picker works offline and instantly. `id` is the
/// filename stem and is what the server records as `stickerId`.
struct Sticker: Identifiable {
    let id: String
    let name: String
    let image: UIImage
}

enum StickerCatalog {
    /// Keep in step with `apps/web/public/stickers/`. Order is the picker order.
    /// The lettering pieces are the seed throw-ups from `scripts/lib/letters.mjs`.
    static let ids = [
        "star", "heart", "bolt", "flame", "ghost", "skull", "eye", "crown",
        "wifi", "boombox", "spraycan", "roller", "raccoon", "pigeon", "splat",
        "bang", "arrow", "blob",
        "stackt", "tdot", "6ix", "got", "wall", "fresh", "king", "bold", "crew",
        "riot", "neon", "dusk", "halt", "void", "echo", "rust", "zine", "flux",
    ]

    /// Loads every sticker from the app bundle. The Xcode project syncs the whole
    /// `ios/` folder into the target, which copies the PNGs flat into the bundle
    /// root (the `Stickers/` subdirectory is not preserved), so look them up by
    /// filename stem only.
    static func load() -> [Sticker] {
        ids.compactMap { id in
            guard let url = Bundle.main.url(forResource: id, withExtension: "png"),
                  let image = UIImage(contentsOfFile: url.path) else {
                return nil
            }
            return Sticker(id: id, name: id.capitalized, image: image)
        }
    }
}
