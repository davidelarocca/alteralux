import AlteraluxKit
import CoreGraphics

/// The thumbnails of the strip and the grid: the camera's own at first, then, for a photo with
/// adjustments, the photo developed with them.
extension AppModel {
    func loadThumbnail(for item: PhotoItem) {
        let url = item.url
        Task { [thumbnails = library.thumbnails] in
            // The same thumbnails as the library's grid: quick, and kept.
            let image = await thumbnails.thumbnail(for: url, maxDimension: Self.thumbnailDimension)
            if item.thumbnail == nil {
                item.thumbnail = image
            }
        }
        if item.hasAdjustments {
            redrawThumbnail(of: item)
        }
    }

    /// Develops a photo of the strip that is not on screen at the size of its thumbnail, with its
    /// settings, and shows it in the strip. Decoded small, a RAW included, it takes a fraction of
    /// a second; a newer change to the photo's settings wins.
    func redrawThumbnail(of item: PhotoItem) {
        let request = DevelopedThumbnails.Request(
            photo: item.url, settings: item.settings, maxDimension: Self.thumbnailDimension,
        )
        Task {
            guard let image = await developedThumbnail(request), item.settings == request.settings else { return }
            item.thumbnail = image
        }
    }

    /// A photo developed small with `request`'s adjustments, when it is already made; at once.
    func keptDevelopedThumbnail(_ request: DevelopedThumbnails.Request) async -> CGImage? {
        await library.developedThumbnails.kept(request)
    }

    /// A photo developed small with `request`'s adjustments, made now when it is not kept.
    /// `nil` until the engine has started.
    func developedThumbnail(_ request: DevelopedThumbnails.Request) async -> CGImage? {
        guard let renderer else { return nil }
        return await library.developedThumbnails.thumbnail(request, renderer: renderer, lenses: lenses)
    }

    /// Updates the strip thumbnail with the developed look.
    func refreshSelectedThumbnail() {
        guard let item = selection, let preview else { return }
        let image = SendableImage(preview.cgImage)
        Task {
            let thumbnail = await Task.detached(priority: .utility) {
                SendableImage(image.image.flatMap { Self.downscale($0, to: Self.thumbnailDimension) })
            }.value
            if let thumbnail = thumbnail.image {
                item.thumbnail = thumbnail
            }
        }
    }

    private nonisolated static func downscale(_ image: CGImage, to maxDimension: Int) -> CGImage? {
        let scale = Double(maxDimension) / Double(max(image.width, image.height))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// Carries an immutable `CGImage` across tasks.
struct SendableImage: @unchecked Sendable { // concurrency: CGImage is immutable once created
    let image: CGImage?
    init(_ image: CGImage?) {
        self.image = image
    }
}
