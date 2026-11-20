import AlteraluxKit
import CoreGraphics

/// The thumbnails of the strip: the library's own at first, then the photo's developed look.
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
    }

    /// Develops a photo of the strip that is not on screen at the size of its thumbnail, with its
    /// settings, and shows it in the strip. Decoded small, a RAW included, it takes a fraction of
    /// a second; a newer change to the photo's settings wins.
    func redrawThumbnail(of item: PhotoItem) {
        guard let renderer else { return }
        let url = item.url
        let settings = item.settings
        let dimension = Self.thumbnailDimension
        Task {
            let developed = await Task.detached(priority: .utility) { () -> SendableImage in
                guard let decoder = try? PhotoDecoder(url: url) else { return SendableImage(nil) }
                let whiteBalance = decoder.asShotWhiteBalance.map { settings.whiteBalance(asShot: $0) }
                guard
                    let loaded = try? await decoder.decode(
                        maxDimension: dimension, whiteBalance: whiteBalance, crop: settings.crop,
                    ),
                    let image = try? await renderer.render(loaded, settings: settings, quality: .preview(maxDimension: dimension))
                else { return SendableImage(nil) }
                return SendableImage(image.cgImage)
            }.value
            guard item.settings == settings, let image = developed.image else { return }
            item.thumbnail = image
        }
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
