import AlteraluxEngine
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AlteraluxKit

private let batchTestDataDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("engine/vendor/spektrafilm-rs/data")

private func makeWorkspace() throws -> URL {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("alteralux-batch-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func writePhoto(
    named name: String, in folder: URL, width: Int = 96, height: Int = 64,
) throws -> URL {
    let context = try #require(
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ),
    )
    context.setFillColor(red: 0.8, green: 0.15, blue: 0.1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let url = folder.appendingPathComponent(name)
    let destination = try #require(
        CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil),
    )
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

private func readImageSize(_ url: URL) throws -> (width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return (image.width, image.height)
}

private struct ProgressEvent: Sendable, Equatable {
    let index: Int
    let photo: URL
    let fileName: String
}

private actor ProgressRecorder {
    private var recorded: [ProgressEvent] = []

    func record(_ index: Int, _ job: ExportJob) {
        recorded.append(ProgressEvent(index: index, photo: job.photo, fileName: job.fileName))
    }

    func events() -> [ProgressEvent] {
        recorded
    }
}

struct BatchExporterTests {
    private func exporter() throws -> BatchExporter {
        try BatchExporter(
            renderer: FilmRenderer(dataDirectory: batchTestDataDirectory, backend: .cpu),
        )
    }

    @Test func exportsSeveralPhotosBesideTheirSources() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sources = workspace.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let photos = try (1 ... 3).map { number in
            try writePhoto(named: "IMG_000\(number).png", in: sources)
        }
        let jobs = zip(photos, 1 ... 3).map { pair in
            let (photo, number) = pair
            return ExportJob(
                photo: photo, settings: DevelopSettings(),
                fileName: "IMG_000\(number) Kodak Portra 400.jpg",
            )
        }

        let batchExporter = try exporter()
        let results = await batchExporter.export(
            jobs, to: .subfolder("Developed"), options: ExportOptions(),
        )

        #expect(results.count == jobs.count)
        for (result, job) in zip(results, jobs) {
            let expectedURL = sources.appendingPathComponent("Developed", isDirectory: true)
                .appendingPathComponent(job.fileName)
            #expect(result.succeeded)
            #expect(result.destination == expectedURL)
            #expect(try readImageSize(expectedURL) == (96, 64))
        }
    }

    @Test func writesAllPhotosIntoOneCreatedFolder() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let firstFolder = workspace.appendingPathComponent("first", isDirectory: true)
        let secondFolder = workspace.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let first = try writePhoto(named: "first.png", in: firstFolder)
        let second = try writePhoto(named: "second.png", in: secondFolder)
        let output = workspace.appendingPathComponent("output/nested", isDirectory: true)
        let jobs = [
            ExportJob(photo: first, settings: DevelopSettings(), fileName: "first.jpg"),
            ExportJob(photo: second, settings: DevelopSettings(), fileName: "second.jpg"),
        ]

        let batchExporter = try exporter()
        let results = await batchExporter.export(
            jobs, to: .folder(output), options: ExportOptions(),
        )

        #expect(results.map(\.succeeded) == [true, true])
        #expect(results.map(\.destination) == [output.appendingPathComponent("first.jpg"), output.appendingPathComponent("second.jpg")])
        #expect(try readImageSize(output.appendingPathComponent("first.jpg")) == (96, 64))
        #expect(try readImageSize(output.appendingPathComponent("second.jpg")) == (96, 64))
    }

    @Test func unreadablePhotoFailsWithoutStoppingOtherExports() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let first = try writePhoto(named: "first.png", in: workspace)
        let unreadable = workspace.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: unreadable)
        let last = try writePhoto(named: "last.png", in: workspace)
        let output = workspace.appendingPathComponent("exports", isDirectory: true)
        let jobs = [
            ExportJob(photo: first, settings: DevelopSettings(), fileName: "first.jpg"),
            ExportJob(photo: unreadable, settings: DevelopSettings(), fileName: "broken.jpg"),
            ExportJob(photo: last, settings: DevelopSettings(), fileName: "last.jpg"),
        ]

        let batchExporter = try exporter()
        let results = await batchExporter.export(
            jobs, to: .folder(output), options: ExportOptions(),
        )

        #expect(results.count == 3)
        #expect(results[0].succeeded)
        #expect(!results[1].succeeded)
        #expect(results[1].destination == nil)
        #expect(results[1].error != nil)
        #expect(results[2].succeeded)
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("first.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("broken.jpg").path))
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("last.jpg").path))
    }

    @Test func existingFileIsKeptAndNextNameIsUsed() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let photo = try writePhoto(named: "source.png", in: workspace)
        let output = workspace.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let original = output.appendingPathComponent("Developed.jpg")
        let originalContents = Data("keep this file".utf8)
        try originalContents.write(to: original)
        let job = ExportJob(photo: photo, settings: DevelopSettings(), fileName: "Developed.jpg")

        let batchExporter = try exporter()
        let results = await batchExporter.export(
            [job], to: .folder(output), options: ExportOptions(),
        )

        #expect(results.count == 1)
        #expect(results[0].destination == output.appendingPathComponent("Developed 2.jpg"))
        #expect(try Data(contentsOf: original) == originalContents)
        #expect(try readImageSize(output.appendingPathComponent("Developed 2.jpg")) == (96, 64))
    }

    /// A photo exported before is recognized under the name another film or format gave its
    /// file, and under the number of a second copy; other files of the folder are not its own.
    @Test func earlierExportsAreRecognizedUnderAnotherFilmFormatOrNumber() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let output = workspace.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let names = ["Paris Portra.jpg", "Paris Ektar.tif", "paris ektar 2.HEIC", "Paris 2 Portra.jpg", "Paris Portra.txt", "Rome Portra 12.png"]
        for name in names {
            try Data("old".utf8).write(to: output.appendingPathComponent(name))
        }
        let job = { (photo: String) in
            ExportJob(
                photo: workspace.appendingPathComponent("\(photo).png"), settings: DevelopSettings(),
                fileName: "\(photo) Ektar.jpg", earlierNames: ["\(photo) Portra", "\(photo) Ektar"],
            )
        }
        let jobs = [job("Paris"), job("Rome"), job("Oslo")]

        let earlier = BatchExporter.earlierExports(of: jobs, at: .folder(output))
        #expect(Set(earlier[jobs[0].photo, default: []].map(\.lastPathComponent)) == ["Paris Portra.jpg", "Paris Ektar.tif", "paris ektar 2.HEIC"])
        #expect(earlier[jobs[1].photo, default: []].map(\.lastPathComponent) == ["Rome Portra 12.png"])
        #expect(earlier[jobs[2].photo] == nil)
        #expect(BatchExporter.alreadyExported(jobs, at: .folder(output)).map(\.photo) == [jobs[0].photo, jobs[1].photo])
        // A folder that is not there yet holds no earlier export.
        #expect(BatchExporter.alreadyExported(jobs, at: .subfolder("Developed")).isEmpty)
    }

    @Test func replacingTakesTheOldFilesOfAPhotoAwayAndSkippingLeavesItAlone() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let photo = try writePhoto(named: "source.png", in: workspace)
        let other = try writePhoto(named: "other.png", in: workspace)
        let output = workspace.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for name in ["source Portra.jpg", "source Ektar.jpg", "source Ektar 2.jpg", "unrelated.jpg"] {
            try Data("old".utf8).write(to: output.appendingPathComponent(name))
        }
        let jobs = [photo, other].map { photo in
            let name = photo.deletingPathExtension().lastPathComponent
            return ExportJob(
                photo: photo, settings: DevelopSettings(), fileName: "\(name) Ektar.jpg",
                earlierNames: ["\(name) Portra", "\(name) Ektar"],
            )
        }
        let files = { try FileManager.default.contentsOfDirectory(atPath: output.path).sorted() }
        // Old files are removed here, not sent to the Trash of whoever runs the tests.
        let batchExporter = try BatchExporter(
            renderer: FilmRenderer(dataDirectory: batchTestDataDirectory, backend: .cpu),
            discard: { try FileManager.default.removeItem(at: $0) },
        )

        // Skipping develops only the photo that was never exported.
        let skipped = await batchExporter.export(jobs, to: .folder(output), options: ExportOptions(), existing: .skip)
        #expect(skipped.filter { !$0.succeeded }.isEmpty)
        #expect(try files() == ["other Ektar.jpg", "source Ektar 2.jpg", "source Ektar.jpg", "source Portra.jpg", "unrelated.jpg"])
        #expect(try Data(contentsOf: output.appendingPathComponent("source Ektar.jpg")) == Data("old".utf8))

        // Replacing leaves one file per photo, the new one, and touches nothing else.
        let replaced = await batchExporter.export(jobs, to: .folder(output), options: ExportOptions(), existing: .replace)
        #expect(replaced.map(\.destination?.lastPathComponent) == ["source Ektar.jpg", "other Ektar.jpg"])
        #expect(try files() == ["other Ektar.jpg", "source Ektar.jpg", "unrelated.jpg"])
        #expect(try readImageSize(output.appendingPathComponent("source Ektar.jpg")) == (96, 64))
        #expect(try Data(contentsOf: output.appendingPathComponent("unrelated.jpg")) == Data("old".utf8))
    }

    /// Two photos told to write the same name, as a RAW and its JPEG would be without care:
    /// replacing never lets the second take the place of what the first just wrote.
    @Test func twoPhotosOfOneNameNeverReplaceEachOther() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let first = try writePhoto(named: "twin.png", in: workspace)
        let second = try writePhoto(named: "twin.tiff", in: workspace)
        let output = workspace.appendingPathComponent("exports", isDirectory: true)
        let jobs = [first, second].map {
            ExportJob(photo: $0, settings: DevelopSettings(), fileName: "twin Ektar.jpg", earlierNames: ["twin Ektar"])
        }
        let files = { try FileManager.default.contentsOfDirectory(atPath: output.path).sorted() }
        let batchExporter = try BatchExporter(
            renderer: FilmRenderer(dataDirectory: batchTestDataDirectory, backend: .cpu),
            discard: { try FileManager.default.removeItem(at: $0) },
        )

        for _ in 1 ... 2 {
            let results = await batchExporter.export(jobs, to: .folder(output), options: ExportOptions(), existing: .replace)
            #expect(results.map(\.destination?.lastPathComponent) == ["twin Ektar.jpg", "twin Ektar 2.jpg"])
            #expect(try files() == ["twin Ektar 2.jpg", "twin Ektar.jpg"])
        }
    }

    @Test func longSideLimitsOutputAndNeverEnlarges() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let photo = try writePhoto(named: "source.png", in: workspace, width: 128, height: 64)
        let output = workspace.appendingPathComponent("exports", isDirectory: true)
        let jobs = [
            ExportJob(photo: photo, settings: DevelopSettings(), fileName: "small.jpg"),
            ExportJob(photo: photo, settings: DevelopSettings(), fileName: "original.jpg"),
        ]

        let batchExporter = try exporter()
        let small = await batchExporter.export(
            [jobs[0]], to: .folder(output), options: ExportOptions(longSide: 32),
        )
        let original = await batchExporter.export(
            [jobs[1]], to: .folder(output), options: ExportOptions(longSide: 256),
        )

        #expect(small.first?.succeeded == true)
        #expect(try readImageSize(output.appendingPathComponent("small.jpg")) == (32, 16))
        #expect(original.first?.succeeded == true)
        #expect(try readImageSize(output.appendingPathComponent("original.jpg")) == (128, 64))
    }

    @Test func progressRunsOnceForEachPhotoInOrder() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let photos = try ["first.png", "second.png", "third.png"].map {
            try writePhoto(named: $0, in: workspace)
        }
        let jobs = photos.enumerated().map { index, photo in
            ExportJob(photo: photo, settings: DevelopSettings(), fileName: "\(index).jpg")
        }
        let recorder = ProgressRecorder()

        let batchExporter = try exporter()
        let results = await batchExporter.export(
            jobs, to: .folder(workspace.appendingPathComponent("exports")),
            options: ExportOptions(),
            progress: { index, job in await recorder.record(index, job) },
        )

        #expect(results.filter { !$0.succeeded }.isEmpty)
        #expect(await recorder.events() == jobs.enumerated().map { index, job in
            ProgressEvent(index: index, photo: job.photo, fileName: job.fileName)
        })
    }

    @Test func cancellationFromProgressStopsBeforeTheNextPhoto() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let photos = try ["first.png", "second.png", "third.png"].map {
            try writePhoto(named: $0, in: workspace)
        }
        let jobs = photos.enumerated().map { index, photo in
            ExportJob(photo: photo, settings: DevelopSettings(), fileName: "\(index).jpg")
        }
        let recorder = ProgressRecorder()
        let batchExporter = try exporter()

        let task = Task {
            await batchExporter.export(
                jobs, to: .folder(workspace.appendingPathComponent("exports")),
                options: ExportOptions(),
                progress: { index, job in
                    await recorder.record(index, job)
                    if index == 0 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                },
            )
        }
        let results = await task.value

        #expect(results.count == 1)
        #expect(results[0].succeeded)
        #expect(await recorder.events() == [
            ProgressEvent(index: 0, photo: jobs[0].photo, fileName: jobs[0].fileName),
        ])
        #expect(FileManager.default.fileExists(
            atPath: workspace.appendingPathComponent("exports/0.jpg").path,
        ))
        #expect(!FileManager.default.fileExists(
            atPath: workspace.appendingPathComponent("exports/1.jpg").path,
        ))
    }

    @Test func oldExportOptionsDecodeWithoutLongSide() throws {
        let data = Data(
            #"{"format":"jpeg","colorProfile":"sRGB","quality":0.92,"copiesMetadata":true}"#.utf8,
        )
        let options = try JSONDecoder().decode(ExportOptions.self, from: data)
        #expect(options.longSide == nil)
    }
}
