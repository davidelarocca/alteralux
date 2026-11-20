import CoreGraphics
import Darwin
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AlteraluxKit

/// Photo facts read directly from files, without making thumbnails.
struct PhotoInfoTests {
    private static let finderTagsAttribute = "com.apple.metadata:_kMDItemUserTags"

    private struct Fixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("alteralux-photo-info-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func file(_ name: String, contents: Data = Data("photo".utf8)) throws -> URL {
            let url = root.appendingPathComponent(name)
            try contents.write(to: url)
            return url
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func writeImage(width: Int, height: Int, orientation: Int? = nil) throws -> URL {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ),
        )
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alteralux-photo-info-\(UUID().uuidString).tiff")
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil),
        )
        let properties = orientation.map { [kCGImagePropertyOrientation as String: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func writeFinderTags(_ names: [String], to file: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: names, format: .binary, options: 0)
        try writeFinderTagsAttribute(data, to: file)
    }

    private func writeFinderTagsAttribute(_ data: Data, to file: URL) throws {
        let result: Int32 = file.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return data.withUnsafeBytes { buffer in
                setxattr(path, Self.finderTagsAttribute, buffer.baseAddress, data.count, 0, 0)
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    @Test func readsWideAndUprightShapes() throws {
        let wide = try writeImage(width: 120, height: 80)
        defer { try? FileManager.default.removeItem(at: wide) }
        let upright = try writeImage(width: 80, height: 120)
        defer { try? FileManager.default.removeItem(at: upright) }

        #expect(PhotoInfoReader.info(of: wide).aspectRatio == 1.5)
        #expect(PhotoInfoReader.info(of: upright).aspectRatio == 2.0 / 3.0)
    }

    @Test func orientationChangesTheShownShape() throws {
        let rotated = try writeImage(width: 120, height: 80, orientation: 6)
        defer { try? FileManager.default.removeItem(at: rotated) }

        #expect(PhotoInfoReader.info(of: rotated).aspectRatio == 2.0 / 3.0)
    }

    @Test func rawShapeMatchesTheDecoderAndIsMarkedRaw() throws {
        let raw = try TestDNG.writeGrayCard(width: 192, height: 160)
        defer { try? FileManager.default.removeItem(at: raw) }
        let decoder = try PhotoDecoder(url: raw)

        let info = PhotoInfoReader.info(of: raw)

        #expect(info.isRaw && decoder.isRaw)
        #expect(info.aspectRatio == Double(decoder.width) / Double(decoder.height))
        #expect(info.aspectRatio == 1.2)
    }

    @Test func aNonImageGetsTheUnknownShape() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let text = try fixture.file("notes.txt")

        let info = PhotoInfoReader.info(of: text)

        #expect(info.aspectRatio == PhotoInfo.unknownAspectRatio)
        #expect(!info.isRaw)
    }

    @Test func readsTheFileCreationDate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.file("dated.tiff")
        let requestedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.creationDate: requestedDate], ofItemAtPath: file.path)
        let storedDate = try #require(file.resourceValues(forKeys: [.creationDateKey]).creationDate)

        #expect(PhotoInfoReader.info(of: file).date == storedDate)
    }

    /// A photo that says when it was taken is dated by it, not by its file, which a copy renews.
    @Test func readsTheDateThePhotoWasTaken() throws {
        let context = try #require(
            CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ),
        )
        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alteralux-taken-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let exif: [String: Any] = [
            kCGImagePropertyExifDateTimeOriginal as String: "2024:07:14 18:30:05",
            kCGImagePropertyExifOffsetTimeOriginal as String: "+02:00",
        ]
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyExifDictionary as String: exif] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        #expect(PhotoInfoReader.info(of: url).date == ISO8601DateFormatter().date(from: "2024-07-14T16:30:05Z"))
        // Without an offset the time is the Mac's own.
        var local = DateComponents(year: 2024, month: 7, day: 14, hour: 18, minute: 30, second: 5)
        local.calendar = Calendar(identifier: .gregorian)
        let properties = [kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifDateTimeOriginal as String: "2024:07:14 18:30:05"]]
        #expect(PhotoInfoReader.dateTaken(from: properties) == local.date)
    }

    @Test func readsFileSizeInBytes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.file("sized.tiff", contents: Data([0x01, 0x02, 0x03, 0x04]))

        #expect(PhotoInfoReader.info(of: file).fileSize == 4)
    }

    @Test func readsTagsWrittenThroughURLResourceValuesWithTheirColor() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var file = try fixture.file("tagged.tiff")
        var resourceValues = URLResourceValues()
        resourceValues.tagNames = ["Red"]
        try file.setResourceValues(resourceValues)

        #expect(PhotoInfoReader.tags(of: file) == [FinderTag(name: "Red")])
    }

    @Test func readsFinderTagColorsAndOrderFromTheAttribute() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.file("tagged.tiff")
        try writeFinderTags(["First\n6", "No color\n0", "Second\n4", "\n5", "Last\n7"], to: file)

        #expect(
            PhotoInfoReader.tags(of: file) == [
                FinderTag(name: "First", color: .red),
                FinderTag(name: "No color"),
                FinderTag(name: "Second", color: .blue),
                FinderTag(name: "Last", color: .orange),
            ],
        )
    }

    @Test func brokenFinderTagAttributeFallsBackToResourceTagNames() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var file = try fixture.file("tagged.tiff")
        var resourceValues = URLResourceValues()
        resourceValues.tagNames = ["Fallback", "Second"]
        try file.setResourceValues(resourceValues)
        let brokenAttribute = Data([0x01, 0x02, 0x03])
        try writeFinderTagsAttribute(brokenAttribute, to: file)

        #expect(
            PhotoInfoReader.tags(attributeData: brokenAttribute, fallbackNames: { ["Fallback", "Second"] }) == [
                FinderTag(name: "Fallback"),
                FinderTag(name: "Second"),
            ],
        )
        let resourceNames = (try? file.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
        #expect(PhotoInfoReader.tags(of: file) == resourceNames.map { FinderTag(name: $0) })
    }

    @Test func infosReturnsAnEntryForEveryPhoto() throws {
        let first = try writeImage(width: 120, height: 80)
        defer { try? FileManager.default.removeItem(at: first) }
        let second = try writeImage(width: 80, height: 120)
        defer { try? FileManager.default.removeItem(at: second) }
        let fixture = try Fixture()
        defer { fixture.remove() }
        let text = try fixture.file("notes.txt")
        let missing = fixture.root.appendingPathComponent("missing.tiff")
        let photos = [first, second, text, missing]

        let infos = PhotoInfoReader.infos(of: photos)

        #expect(infos.count == photos.count)
        #expect(Set(infos.keys) == Set(photos))
        #expect(infos[missing] == PhotoInfo())
    }

    /// A tag written with a color keeps it while other tags come and go: set by name through
    /// the system, it would lose it.
    @Test func aTagKeepsItsColorWhenOthersAreAddedAndRemoved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("alteralux-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("photo.jpg")
        try Data("pixels".utf8).write(to: file)
        let missing = folder.appendingPathComponent("missing.jpg")

        #expect(PhotoFileActions.addTag(FinderTag(name: "Trip", color: .green), to: [file, missing]).map(\.succeeded) == [true, false])
        #expect(PhotoFileActions.addTag("Plain", to: [file]).first?.succeeded == true)
        // A tag of a name already there is not added again, whatever its color.
        _ = PhotoFileActions.addTag(FinderTag(name: "Trip", color: .red), to: [file])
        #expect(PhotoInfoReader.tags(of: file) == [FinderTag(name: "Trip", color: .green), FinderTag(name: "Plain")])
        #expect(PhotoFileActions.tags(of: file) == ["Trip", "Plain"])

        _ = PhotoFileActions.removeTag("Plain", from: [file])
        #expect(PhotoInfoReader.tags(of: file) == [FinderTag(name: "Trip", color: .green)])
        _ = PhotoFileActions.removeTag("Trip", from: [file])
        #expect(PhotoInfoReader.tags(of: file).isEmpty && PhotoFileActions.tags(of: file).isEmpty)
    }
}
