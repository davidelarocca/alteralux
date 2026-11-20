import Foundation

/// What happened to one file in a batch action.
public struct FileActionResult: Sendable, Equatable {
    /// The file the action was asked to act on.
    public let source: URL
    /// Where the file is now. `nil` when it went to the Trash and the system gave no location,
    /// or when the action failed.
    public let destination: URL?
    /// The localized description of the failure, `nil` when the action succeeded.
    public let error: String?

    public init(source: URL, destination: URL?, error: String? = nil) {
        self.source = source
        self.destination = destination
        self.error = error
    }

    public var succeeded: Bool {
        error == nil
    }
}

/// Organizing photos on disk: move, copy, trash and Finder tags, on the real files.
///
/// Every function acts on several files and reports per file, so one file that cannot be
/// handled does not stop the others. Everything is synchronous and has no state, so it is
/// safe to call off the main thread.
public enum PhotoFileActions {
    // MARK: Move and copy

    /// Moves the files into `folder`, keeping their names unless one is already taken there.
    public static func move(_ files: [URL], to folder: URL) -> [FileActionResult] {
        transfer(files, to: folder, isMove: true) { source, destination in
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }

    /// Copies the files into `folder`, keeping their names unless one is already taken there.
    public static func copy(_ files: [URL], to folder: URL) -> [FileActionResult] {
        transfer(files, to: folder, isMove: false) { source, destination in
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    // MARK: Trash

    /// Moves the files to the Trash. `destination` is where the system put each one, when it says.
    public static func trash(_ files: [URL]) -> [FileActionResult] {
        files.map { file in
            do {
                var resulting: NSURL?
                try FileManager.default.trashItem(at: file, resultingItemURL: &resulting)
                return FileActionResult(source: file, destination: resulting as URL?)
            } catch {
                return failure(file, error)
            }
        }
    }

    // MARK: Finder tags

    /// The file's Finder tags, empty when it has none or they cannot be read.
    public static func tags(of file: URL) -> [String] {
        let values = try? file.resourceValues(forKeys: [.tagNamesKey])
        return values?.tagNames ?? []
    }

    /// For a selection, each tag with the number of files that carry it.
    public static func tags(ofAll files: [URL]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for file in files {
            for tag in Set(tags(of: file)) {
                counts[tag, default: 0] += 1
            }
        }
        return counts
    }

    /// Adds one tag to each file, with its color, after the tags it already has. A file that
    /// has a tag of that name is left alone.
    public static func addTag(_ tag: FinderTag, to files: [URL]) -> [FileActionResult] {
        changeTags(of: files) { current in
            current.contains { $0.name == tag.name } ? current : current + [tag]
        }
    }

    /// Adds one tag without a color to each file.
    public static func addTag(_ tag: String, to files: [URL]) -> [FileActionResult] {
        addTag(FinderTag(name: tag), to: files)
    }

    /// Removes one tag from each file, keeping the others in their order and with their colors.
    public static func removeTag(_ tag: String, from files: [URL]) -> [FileActionResult] {
        changeTags(of: files) { current in
            current.filter { $0.name != tag }
        }
    }

    // MARK: Helpers

    private static func transfer(
        _ files: [URL],
        to folder: URL,
        isMove: Bool,
        perform: (URL, URL) throws -> Void,
    ) -> [FileActionResult] {
        let manager = FileManager.default
        var isFolder: ObjCBool = false
        let folderExists = manager.fileExists(atPath: folder.path, isDirectory: &isFolder) && isFolder.boolValue
        let target = folder.resolvingSymlinksInPath()

        return files.map { file in
            guard folderExists else {
                return failure(file, CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: folder.path]))
            }
            guard manager.fileExists(atPath: file.path) else {
                return failure(file, CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: file.path]))
            }
            // A move into the folder the file is already in has nothing to do.
            if isMove, file.deletingLastPathComponent().resolvingSymlinksInPath() == target {
                return FileActionResult(source: file, destination: file)
            }
            let destination = freeURL(for: file.lastPathComponent, in: folder)
            do {
                try perform(file, destination)
                return FileActionResult(source: file, destination: destination)
            } catch {
                return failure(file, error)
            }
        }
    }

    /// The first name in `folder` that is not taken: `name.ext`, then `name 2.ext`, `name 3.ext`.
    static func freeURL(for name: String, in folder: URL) -> URL {
        let manager = FileManager.default
        let first = folder.appendingPathComponent(name)
        if !exists(first, manager) {
            return first
        }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var number = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
            let url = folder.appendingPathComponent(candidate)
            if !exists(url, manager) {
                return url
            }
            number += 1
        }
    }

    /// True for anything at the path, including a link whose target is gone.
    static func exists(_ url: URL, _ manager: FileManager) -> Bool {
        (try? manager.attributesOfItem(atPath: url.path)) != nil
    }

    private static func changeTags(of files: [URL], _ change: ([FinderTag]) -> [FinderTag]) -> [FileActionResult] {
        files.map { file in
            do {
                guard FileManager.default.fileExists(atPath: file.path) else {
                    throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: file.path])
                }
                let current = PhotoInfoReader.tags(of: file)
                let updated = change(current)
                if updated != current {
                    try PhotoInfoReader.write(updated, to: file)
                }
                return FileActionResult(source: file, destination: file)
            } catch {
                return failure(file, error)
            }
        }
    }

    private static func failure(_ file: URL, _ error: any Error) -> FileActionResult {
        FileActionResult(source: file, destination: nil, error: error.localizedDescription)
    }
}
