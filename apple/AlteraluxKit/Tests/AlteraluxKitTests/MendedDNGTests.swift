import CoreGraphics
import Foundation
import Testing
@testable import AlteraluxKit

/// A DNG whose version tags are five bytes long, as the DJI Osmo Action writes them: the system's
/// decoders refuse it, and the app opens it mended in memory.
struct MendedDNGTests {
    private let sound = TestDNG.grayCard()

    /// `sound` with its two version tags as the camera writes them: five bytes each, too many to
    /// stay in the entry, so kept at the end of the file. The test DNG is little-endian.
    private func faulty() -> Data {
        var data = sound
        func number(at offset: Int, size: Int) -> Int {
            (0 ..< size).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
        }
        func long(_ value: Int) -> Data {
            Data((0 ..< 4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) })
        }
        let directory = number(at: 4, size: 4)
        for index in 0 ..< number(at: directory, size: 2) {
            let entry = directory + 2 + index * 12
            guard [50706, 50707].contains(number(at: entry, size: 2)) else { continue }
            let values = Data(data[entry + 8 ..< entry + 12]) + Data([0])
            let offset = data.count
            data.append(values)
            data.replaceSubrange(entry + 4 ..< entry + 8, with: long(5))
            data.replaceSubrange(entry + 8 ..< entry + 12, with: long(offset))
        }
        return data
    }

    private func write(_ data: Data, extension pathExtension: String = "dng") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alteralux-test-\(UUID().uuidString).\(pathExtension)")
        try data.write(to: url)
        return url
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    @Test func theVersionTagsAreMendedAndNothingElse() throws {
        let faulty = faulty()
        #expect(faulty.count == sound.count + 10)
        let url = try write(faulty)
        defer { try? FileManager.default.removeItem(at: url) }
        let mended = try #require(MendedDNG.data(for: url))
        // The entries are the sound file's again; the ten bytes the camera added stay, unused.
        #expect(mended == sound + faulty.suffix(10))
    }

    @Test func aSoundDNGAndOtherFilesAreLeftAlone() throws {
        let dng = try write(sound)
        // The same bytes under another name: only a DNG is looked into.
        let other = try write(faulty(), extension: "tiff")
        defer {
            try? FileManager.default.removeItem(at: dng)
            try? FileManager.default.removeItem(at: other)
        }
        #expect(MendedDNG.data(for: dng) == nil)
        #expect(MendedDNG.data(for: other) == nil)
        #expect(MendedDNG.data(for: URL(fileURLWithPath: "/nonexistent/photo.dng")) == nil)
        // Bytes that are no TIFF, and a file that ends inside its directory.
        let text = try write(Data("not a picture".utf8))
        let cut = try write(sound.prefix(20))
        defer {
            try? FileManager.default.removeItem(at: text)
            try? FileManager.default.removeItem(at: cut)
        }
        #expect(MendedDNG.data(for: text) == nil)
        #expect(MendedDNG.data(for: cut) == nil)
    }

    @Test func aPhotoWithTheFaultOpensAsTheSoundOne() async throws {
        let soundURL = try write(sound)
        let faultyURL = try write(faulty())
        defer {
            try? FileManager.default.removeItem(at: soundURL)
            try? FileManager.default.removeItem(at: faultyURL)
        }
        let expected = try PhotoDecoder(url: soundURL)
        let decoder = try PhotoDecoder(url: faultyURL)
        #expect(decoder.size == expected.size)
        let loaded = try await decoder.decode(maxDimension: 64, settings: DevelopSettings())
        #expect(loaded.width == 64 && loaded.isRaw)

        // The thumbnail and the photo's details come from the mended bytes too.
        let preview = try #require(ImageLoader.originalPreview(of: faultyURL, maxDimension: 64))
        let soundPreview = try #require(ImageLoader.originalPreview(of: soundURL, maxDimension: 64))
        #expect(try bytes(preview) == bytes(soundPreview))
        #expect(PhotoInfoReader.info(of: faultyURL).aspectRatio == PhotoInfoReader.info(of: soundURL).aspectRatio)
    }
}
