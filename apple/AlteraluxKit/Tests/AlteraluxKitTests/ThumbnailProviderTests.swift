import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AlteraluxKit

/// Builds ImageIO files in private temporary folders for thumbnail tests.
struct ThumbnailProviderTests {
    private struct ColorComponents {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
    }

    private struct Palette {
        let topLeft: ColorComponents
        let topRight: ColorComponents
        let bottomLeft: ColorComponents
        let bottomRight: ColorComponents

        static let corners = Palette(
            topLeft: ColorComponents(red: 1, green: 0, blue: 0),
            topRight: ColorComponents(red: 0, green: 1, blue: 0),
            bottomLeft: ColorComponents(red: 0, green: 0, blue: 1),
            bottomRight: ColorComponents(red: 1, green: 1, blue: 0),
        )

        static let alternate = Palette(
            topLeft: ColorComponents(red: 0, green: 1, blue: 1),
            topRight: ColorComponents(red: 1, green: 0, blue: 1),
            bottomLeft: ColorComponents(red: 0.2, green: 0.2, blue: 0.2),
            bottomRight: ColorComponents(red: 1, green: 0.5, blue: 0),
        )
    }

    @Test func aThumbnailKeepsProportionsAndDoesNotEnlargeSmallImages() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageURL = folder.appendingPathComponent("picture.png")
        try writePicture(to: imageURL, width: 400, height: 200, type: .png)
        let provider = ThumbnailProvider(cacheDirectory: nil)

        let preview = try #require(await provider.thumbnail(for: imageURL, maxDimension: 100))
        #expect(preview.width == 100)
        #expect(preview.height == 50)

        let largerLimit = try #require(await provider.thumbnail(for: imageURL, maxDimension: 1000))
        #expect(largerLimit.width == 400)
        #expect(largerLimit.height == 200)
    }

    @Test func anOrientationSixJpegComesBackUprightWithItsCornersInPlace() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pngURL = folder.appendingPathComponent("picture.png")
        let jpegURL = folder.appendingPathComponent("rotated.jpg")
        try writePicture(to: pngURL, width: 400, height: 200, type: .png)
        try writePicture(to: jpegURL, width: 400, height: 200, type: .jpeg, orientation: 6)
        let provider = ThumbnailProvider(cacheDirectory: nil)

        let original = try #require(await provider.thumbnail(for: pngURL, maxDimension: 800))
        let rotated = try #require(await provider.thumbnail(for: jpegURL, maxDimension: 800))
        #expect(rotated.height > rotated.width)
        #expect(rotated.width == 200 && rotated.height == 400)

        let originalTopLeft = try corner(of: original, horizontal: .left, vertical: .top)
        let originalTopRight = try corner(of: original, horizontal: .right, vertical: .top)
        let originalBottomLeft = try corner(of: original, horizontal: .left, vertical: .bottom)
        let originalBottomRight = try corner(of: original, horizontal: .right, vertical: .bottom)
        let rotatedTopLeft = try corner(of: rotated, horizontal: .left, vertical: .top)
        let rotatedTopRight = try corner(of: rotated, horizontal: .right, vertical: .top)
        let rotatedBottomLeft = try corner(of: rotated, horizontal: .left, vertical: .bottom)
        let rotatedBottomRight = try corner(of: rotated, horizontal: .right, vertical: .bottom)

        #expect(similar(rotatedTopLeft, originalBottomLeft))
        #expect(similar(rotatedTopRight, originalTopLeft))
        #expect(similar(rotatedBottomLeft, originalBottomRight))
        #expect(similar(rotatedBottomRight, originalTopRight))
    }

    /// Over its limit, the disk cache loses the thumbnails written longest ago, and keeps the
    /// rest and its other files.
    @Test func theDiskCacheIsPrunedFromTheOldestThumbnails() throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("alteralux-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cache) }
        let names = ["old.jpg", "middle.jpg", "new.jpg"]
        for (age, name) in names.enumerated() {
            let file = cache.appendingPathComponent(name)
            try Data(count: 1000).write(to: file)
            let date = Date(timeIntervalSinceNow: Double(age - names.count) * 3600)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        }
        try Data("index".utf8).write(to: cache.appendingPathComponent("a.index"))

        ThumbnailProvider(cacheDirectory: cache).pruneDiskCache(toAtMost: 2000)

        let left = try Set(FileManager.default.contentsOfDirectory(atPath: cache.path))
        #expect(left == ["middle.jpg", "new.jpg", "a.index"])
    }

    @Test func aFileThatIsNotAnImageHasNoThumbnail() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fileURL = folder.appendingPathComponent("notes.txt")
        try Data("not an image".utf8).write(to: fileURL)
        let provider = ThumbnailProvider(cacheDirectory: nil)

        #expect(await provider.thumbnail(for: fileURL, maxDimension: 100) == nil)
    }

    @Test func aSecondRequestUsesMemoryEvenAfterTheSourceIsDeleted() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageURL = folder.appendingPathComponent("picture.png")
        try writePicture(to: imageURL, width: 400, height: 200, type: .png)
        let provider = ThumbnailProvider(cacheDirectory: nil)

        let first = try #require(await provider.thumbnail(for: imageURL, maxDimension: 160))
        try FileManager.default.removeItem(at: imageURL)
        let second = try #require(await provider.thumbnail(for: URL(fileURLWithPath: imageURL.path), maxDimension: 160))

        #expect(first.width == second.width && first.height == second.height)
        #expect(await provider.decodeCount == 1)
    }

    @Test func aNewProviderReadsTheDiskCacheAfterTheSourceIsDeleted() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("cache", isDirectory: true)
        let imageURL = folder.appendingPathComponent("picture.png")
        try writePicture(to: imageURL, width: 400, height: 200, type: .png)
        let firstProvider = ThumbnailProvider(cacheDirectory: cache)

        let original = try #require(await firstProvider.thumbnail(for: imageURL, maxDimension: 160))
        await firstProvider.waitForDiskWrites()
        try FileManager.default.removeItem(at: imageURL)

        let secondProvider = ThumbnailProvider(cacheDirectory: cache)
        let cached = try #require(await secondProvider.thumbnail(for: imageURL, maxDimension: 160))
        #expect(cached.width == original.width && cached.height == original.height)
        #expect(await secondProvider.decodeCount == 0)
    }

    @Test func removeAllDropsMemoryAndDiskEntries() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("cache", isDirectory: true)
        let imageURL = folder.appendingPathComponent("picture.png")
        try writePicture(to: imageURL, width: 400, height: 200, type: .png)
        let provider = ThumbnailProvider(cacheDirectory: cache)

        #expect(await provider.thumbnail(for: imageURL, maxDimension: 160) != nil)
        await provider.waitForDiskWrites()
        await provider.removeAll()
        try FileManager.default.removeItem(at: imageURL)

        #expect(await provider.thumbnail(for: imageURL, maxDimension: 160) == nil)
        #expect(!FileManager.default.fileExists(atPath: cache.path))
        #expect(await provider.decodeCount == 1)
    }

    @Test func anOverwrittenFileGetsAThumbnailOfItsNewContents() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageURL = folder.appendingPathComponent("picture.png")
        try writePicture(to: imageURL, width: 400, height: 200, type: .png, palette: .corners)
        let provider = ThumbnailProvider(cacheDirectory: nil)

        let original = try #require(await provider.thumbnail(for: imageURL, maxDimension: 200))
        try writePicture(to: imageURL, width: 500, height: 200, type: .png, palette: .alternate)
        let replacement = try #require(await provider.thumbnail(for: imageURL, maxDimension: 200))

        #expect(original.height == 100)
        #expect(replacement.height == 80)
        #expect(await provider.decodeCount == 2)
    }

    @Test func twentyFilesNeverRunMoreThanTwoDecodesAtOnce() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sourceURL = folder.appendingPathComponent("source.png")
        try writePicture(to: sourceURL, width: 1200, height: 600, type: .png)
        let urls = try (0 ..< 20).map { index in
            let url = folder.appendingPathComponent("picture-\(index).png")
            try FileManager.default.copyItem(at: sourceURL, to: url)
            return url
        }
        let provider = ThumbnailProvider(cacheDirectory: nil, concurrency: 2)

        await withTaskGroup(of: Bool.self) { group in
            for url in urls {
                group.addTask {
                    await provider.thumbnail(for: url, maxDimension: 300) != nil
                }
            }
            for await succeeded in group {
                #expect(succeeded)
            }
        }

        #expect(await provider.decodeCount == 20)
        #expect(await provider.highWaterMark <= 2)
    }

    @Test func twentyRequestsForTheSameFileShareOneDecode() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageURL = folder.appendingPathComponent("picture.png")
        try writePicture(to: imageURL, width: 1200, height: 600, type: .png)
        let provider = ThumbnailProvider(cacheDirectory: nil, concurrency: 2)

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 20 {
                group.addTask {
                    await provider.thumbnail(for: imageURL, maxDimension: 300) != nil
                }
            }
            for await succeeded in group {
                #expect(succeeded)
            }
        }

        #expect(await provider.decodeCount == 1)
    }

    @Test func aCancelledRequestBeforeItsTurnDoesNotDecode() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let imageURL = folder.appendingPathComponent("picture.png")
        try writePicture(to: imageURL, width: 400, height: 200, type: .png)
        let provider = ThumbnailProvider(cacheDirectory: nil)
        let cancelledRequest = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await provider.thumbnail(for: imageURL, maxDimension: 100)
        }

        #expect(await cancelledRequest.value == nil)
        #expect(await provider.decodeCount == 0)
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlteraluxKit-ThumbnailProvider-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func writePicture(
        to url: URL,
        width: Int,
        height: Int,
        type: UTType,
        orientation: Int? = nil,
        palette: Palette = .corners,
    ) throws {
        guard let image = picture(width: width, height: height, palette: palette),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else {
            throw ThumbnailTestError.couldNotCreateImage
        }

        var properties: [CFString: Any] = [:]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        if type == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.95
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ThumbnailTestError.couldNotWriteImage
        }
    }

    private func picture(width: Int, height: Int, palette: Palette) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            return nil
        }

        context.setFillColor(red: palette.topLeft.red, green: palette.topLeft.green, blue: palette.topLeft.blue, alpha: 1)
        context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))
        context.setFillColor(red: palette.topRight.red, green: palette.topRight.green, blue: palette.topRight.blue, alpha: 1)
        context.fill(CGRect(x: width / 2, y: height / 2, width: width / 2, height: height / 2))
        context.setFillColor(red: palette.bottomLeft.red, green: palette.bottomLeft.green, blue: palette.bottomLeft.blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        context.setFillColor(red: palette.bottomRight.red, green: palette.bottomRight.green, blue: palette.bottomRight.blue, alpha: 1)
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height / 2))
        return context.makeImage()
    }

    private enum HorizontalCorner: Equatable {
        case left
        case right
    }

    private enum VerticalCorner: Equatable {
        case top
        case bottom
    }

    private func corner(of image: CGImage, horizontal: HorizontalCorner, vertical: VerticalCorner) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let bitmapContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo,
        )
        guard let context = bitmapContext else { throw ThumbnailTestError.couldNotCreateImage }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { throw ThumbnailTestError.couldNotCreateImage }
        let bytes = data.assumingMemoryBound(to: UInt8.self)

        let xOffset = horizontal == .left ? width * 3 / 4 : width / 4
        let yOffset = vertical == .top ? height / 4 : height * 3 / 4
        let offset = yOffset * context.bytesPerRow + xOffset * 4
        return [bytes[offset], bytes[offset + 1], bytes[offset + 2]]
    }

    private func similar(_ first: [UInt8], _ second: [UInt8]) -> Bool {
        zip(first, second).allSatisfy { abs(Int($0) - Int($1)) < 55 }
    }

    private enum ThumbnailTestError: Error {
        case couldNotCreateImage
        case couldNotWriteImage
    }
}
