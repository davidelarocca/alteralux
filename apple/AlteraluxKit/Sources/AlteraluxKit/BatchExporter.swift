import Darwin
import Foundation

/// One photo to export, with the adjustments to develop it with.
public struct ExportJob: Sendable, Equatable {
    public let photo: URL
    public let settings: DevelopSettings
    /// The name of the file to write, with its extension ("IMG_0042 Kodak Portra 400.jpg").
    public let fileName: String

    public init(photo: URL, settings: DevelopSettings, fileName: String) {
        self.photo = photo
        self.settings = settings
        self.fileName = fileName
    }
}

/// Where exported photos are written.
public enum ExportDestination: Sendable, Equatable {
    /// A folder with this name beside each photo, created when it is not there.
    case subfolder(String)
    /// One folder for all the photos.
    case folder(URL)
}

/// What to do with a photo whose exported file is already there.
public enum ExistingFilePolicy: Sendable, Equatable {
    /// Write the new file beside the old one, under the first free name ("name 2.jpg").
    case keepBoth
    /// Put the new file in place of the old one.
    case replace
    /// Leave the old file and do not develop the photo again.
    case skip
}

/// Develops several photos and writes them, one after the other.
public struct BatchExporter: Sendable {
    private let renderer: FilmRenderer

    public init(renderer: FilmRenderer) {
        self.renderer = renderer
    }

    /// The photos among `jobs` whose file is already at `destination`: the ones a new export
    /// has to decide about.
    public static func alreadyExported(_ jobs: [ExportJob], at destination: ExportDestination) -> [ExportJob] {
        jobs.filter { job in
            PhotoFileActions.exists(file(for: job, at: destination), FileManager.default)
        }
    }

    /// Where the file of `job` goes when its name is free.
    static func file(for job: ExportJob, at destination: ExportDestination) -> URL {
        outputFolder(for: job.photo, destination: destination).appendingPathComponent(job.fileName)
    }

    /// - Parameters:
    ///   - existing: what to do with a photo whose file is already there. Nothing is ever
    ///     written over a file unless this says to replace it.
    ///   - progress: called before each photo is started, with its position in `jobs`
    ///     (from 0) and the job.
    /// - Returns: one result per photo that was started, in order: `destination` is the file
    ///   written, or the file left alone for a photo that was skipped; `error` the localized
    ///   reason a photo was not written.
    @concurrent
    public func export(
        _ jobs: [ExportJob], to destination: ExportDestination, options: ExportOptions,
        existing: ExistingFilePolicy = .keepBoth,
        progress: @Sendable (Int, ExportJob) async -> Void = { _, _ in },
    ) async -> [FileActionResult] {
        var results: [FileActionResult] = []
        let manager = FileManager.default

        for (index, job) in jobs.enumerated() {
            guard !Task.isCancelled else { break }
            await progress(index, job)

            let named = Self.file(for: job, at: destination)
            let isThere = PhotoFileActions.exists(named, manager)
            if existing == .skip, isThere {
                results.append(FileActionResult(source: job.photo, destination: named))
                continue
            }

            var reservedURL: URL?
            do {
                let decoder = try PhotoDecoder(url: job.photo)
                let photoLongSide = max(decoder.width, decoder.height)
                let decodeLimit = options.longSide.flatMap { requested in
                    requested > 0 && requested < photoLongSide ? requested : nil
                }
                let whiteBalance = decoder.asShotWhiteBalance.map {
                    job.settings.whiteBalance(asShot: $0)
                }
                let loaded = try await decoder.decode(
                    maxDimension: decodeLimit, whiteBalance: whiteBalance,
                )
                let developed = try await renderer.render(
                    loaded, settings: job.settings, quality: .full,
                )

                let folder = Self.outputFolder(for: job.photo, destination: destination)
                try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                // Written under a name of its own first: an old file is replaced only by a
                // new one that is whole.
                let written = try reserveFile(
                    named: existing == .replace && isThere ? ".\(UUID().uuidString)-\(job.fileName)" : job.fileName,
                    in: folder,
                )
                reservedURL = written
                try ImageExporter.write(
                    developed, to: written, options: options, originalURL: job.photo,
                )
                var output = written
                if existing == .replace, isThere {
                    output = try manager.replaceItemAt(named, withItemAt: written) ?? named
                }
                results.append(FileActionResult(source: job.photo, destination: output))
            } catch {
                if let reservedURL {
                    try? manager.removeItem(at: reservedURL)
                }
                results.append(
                    FileActionResult(
                        source: job.photo, destination: nil, error: error.localizedDescription,
                    ),
                )
            }
        }

        return results
    }

    private static func outputFolder(for photo: URL, destination: ExportDestination) -> URL {
        switch destination {
        case let .subfolder(name):
            photo.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        case let .folder(url):
            url
        }
    }

    /// Takes the first free name in `folder` by creating the file, empty: a name taken between
    /// the look and the write, by another export or another app, is never written over.
    private func reserveFile(named name: String, in folder: URL) throws -> URL {
        var candidate = PhotoFileActions.freeURL(for: name, in: folder)
        while true {
            // Readable like any file the user saves: the permissions asked for are narrowed by
            // the user's own mask, as for a file written without reserving its name first.
            let everyone = S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH
            let descriptor = open(candidate.path, O_CREAT | O_EXCL | O_WRONLY, mode_t(everyone))
            if descriptor >= 0 {
                guard close(descriptor) == 0 else {
                    let error = posixError()
                    try? FileManager.default.removeItem(at: candidate)
                    throw error
                }
                return candidate
            }
            guard errno == EEXIST else { throw posixError() }
            candidate = PhotoFileActions.freeURL(for: name, in: folder)
        }
    }

    private func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
