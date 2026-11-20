import Darwin
import Foundation

/// One photo to export, with the adjustments to develop it with.
public struct ExportJob: Sendable, Equatable {
    public let photo: URL
    public let settings: DevelopSettings
    /// The name of the file to write, with its extension ("IMG_0042 Kodak Portra 400.jpg").
    public let fileName: String
    /// The names, without extension, an earlier export of this photo may have: one for each
    /// film it could have been developed with ("IMG_0042 Kodak Ektar 100"). The name of
    /// `fileName` is always one of them.
    public let earlierNames: [String]

    public init(photo: URL, settings: DevelopSettings, fileName: String, earlierNames: [String] = []) {
        self.photo = photo
        self.settings = settings
        self.fileName = fileName
        self.earlierNames = earlierNames
    }
}

/// Where exported photos are written.
public enum ExportDestination: Sendable, Equatable {
    /// A folder with this name beside each photo, created when it is not there.
    case subfolder(String)
    /// One folder for all the photos.
    case folder(URL)
}

/// What to do with a photo that was exported before: its file is in the destination, under
/// the same name or under the name another film or format gave it.
public enum ExistingFilePolicy: Sendable, Equatable {
    /// Write the new file beside the old ones, under the first free name ("name 2.jpg").
    case keepBoth
    /// Write the new file and take the old ones away: they are discarded, which in the app
    /// means the Trash, so a file replaced by mistake can be taken back. Nothing is written
    /// over.
    case replace
    /// Leave the old files and do not develop the photo again.
    case skip
}

/// Develops several photos and writes them, one after the other.
public struct BatchExporter: Sendable {
    private let renderer: FilmRenderer
    private let discard: @Sendable (URL) throws -> Void

    /// - Parameter discard: takes away an earlier export that a new one replaces. The app
    ///   passes nothing, and the file goes to the Trash.
    public init(
        renderer: FilmRenderer,
        discard: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
    ) {
        self.renderer = renderer
        self.discard = discard
    }

    /// The photos among `jobs` that were exported to `destination` before: the ones a new
    /// export has to decide about.
    public static func alreadyExported(_ jobs: [ExportJob], at destination: ExportDestination) -> [ExportJob] {
        let earlier = earlierExports(of: jobs, at: destination)
        return jobs.filter { earlier[$0.photo] != nil }
    }

    /// The files at `destination` that are earlier exports of each photo: a file in one of the
    /// formats the app writes, named as the photo's job would name it or as another film would
    /// have, with or without the number a second copy takes ("name 2.jpg").
    static func earlierExports(of jobs: [ExportJob], at destination: ExportDestination) -> [URL: [URL]] {
        let extensions = Set(ExportOptions.Format.allCases.map(\.fileExtension))
        var found: [URL: [URL]] = [:]
        for (folder, jobs) in Dictionary(grouping: jobs, by: { outputFolder(for: $0.photo, destination: destination) }) {
            var photos: [String: URL] = [:]
            for job in jobs {
                // Two photos that would write the same name: the files are the first one's.
                for name in job.earlierNames + [(job.fileName as NSString).deletingPathExtension] where photos[name.lowercased()] == nil {
                    photos[name.lowercased()] = job.photo
                }
            }
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where extensions.contains(file.pathExtension.lowercased()) {
                let name = file.deletingPathExtension().lastPathComponent.lowercased()
                // "name 2" is a second copy of "name".
                let withoutNumber = Self.withoutCopyNumber(name)
                if let photo = photos[name] ?? photos[withoutNumber] {
                    found[photo, default: []].append(file)
                }
            }
        }
        return found
    }

    /// "name 2" without its number: "name". Any other name comes back as it is.
    private static func withoutCopyNumber(_ name: String) -> String {
        let digits = name.reversed().prefix(while: \.isNumber).count
        guard digits > 0, name.dropLast(digits).last == " " else { return name }
        return String(name.dropLast(digits + 1))
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
        // What was there before this export started: what it writes itself does not count.
        let earlier = Self.earlierExports(of: jobs, at: destination)
        // What this export wrote is never replaced by a later photo of the same name.
        var finished: Set<URL> = []

        for (index, job) in jobs.enumerated() {
            guard !Task.isCancelled else { break }
            await progress(index, job)

            let named = Self.file(for: job, at: destination)
            let isThere = PhotoFileActions.exists(named, manager) && !finished.contains(named.standardizedFileURL)
            let old = earlier[job.photo] ?? []
            if existing == .skip, let kept = old.first {
                results.append(FileActionResult(source: job.photo, destination: isThere ? named : kept))
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
                if existing == .replace {
                    if isThere {
                        // The old file of this name goes where the other old ones go, and the
                        // new one takes its name. If it cannot be taken away both stay: the
                        // new one under the first free name.
                        try? discard(named)
                        let name = PhotoFileActions.exists(named, manager) ? PhotoFileActions.freeURL(for: job.fileName, in: folder) : named
                        try manager.moveItem(at: written, to: name)
                        output = name
                    }
                    let kept = finished.union([output.standardizedFileURL])
                    for file in old where !kept.contains(file.standardizedFileURL) {
                        try? discard(file)
                    }
                }
                finished.insert(output.standardizedFileURL)
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
