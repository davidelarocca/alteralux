import Foundation
import UniformTypeIdentifiers

/// A folder and the photos and subfolders it contains directly.
public struct FolderNode: Identifiable, Sendable {
    public let url: URL
    public let name: String
    public let photoCount: Int
    public let children: [FolderNode]

    public var id: URL {
        url
    }

    public init(url: URL, name: String, photoCount: Int, children: [FolderNode]) {
        self.url = url
        self.name = name
        self.photoCount = photoCount
        self.children = children
    }
}

/// Lists folders and photos without opening or indexing image contents.
public enum FolderContents {
    public static let photoTypes: [UTType] = [.rawImage, .image]

    private static let resourceKeys: Set<URLResourceKey> = [
        .contentTypeKey,
        .isDirectoryKey,
        .isHiddenKey,
        .isPackageKey,
        .isSymbolicLinkKey,
        .localizedNameKey,
    ]

    /// Builds a tree of folders, counting photos directly inside each folder.
    public static func tree(of url: URL, types: [UTType] = photoTypes) throws -> FolderNode {
        try requireRealDirectory(url)
        return try makeNode(at: url, resourceValues: nil, types: types)
    }

    /// Returns the photos directly in a folder, in Finder-style name order.
    public static func photos(in url: URL, types: [UTType] = photoTypes) throws -> [URL] {
        try requireRealDirectory(url)
        let items = try contents(of: url)
        return items.compactMap { item, values in
            guard values.isHidden != true,
                  values.isSymbolicLink != true,
                  values.isDirectory != true,
                  isPhoto(item, contentType: values.contentType, types: types)
            else {
                return nil
            }
            return item
        }.sorted(by: finderSort)
    }

    private static func makeNode(
        at url: URL,
        resourceValues: URLResourceValues?,
        types: [UTType],
    ) throws -> FolderNode {
        let values = try resourceValues ?? url.resourceValues(forKeys: [.localizedNameKey])
        let items = try contents(of: url)
        var photoCount = 0
        var children: [FolderNode] = []

        for (item, itemValues) in items where itemValues.isHidden != true && itemValues.isSymbolicLink != true {
            if itemValues.isDirectory == true {
                guard !isPackage(item, values: itemValues) else { continue }
                try children.append(makeNode(at: item, resourceValues: itemValues, types: types))
            } else if isPhoto(item, contentType: itemValues.contentType, types: types) {
                photoCount += 1
            }
        }

        children.sort { finderSort($0.name, $1.name) }
        return FolderNode(
            url: url,
            name: values.localizedName ?? url.lastPathComponent,
            photoCount: photoCount,
            children: children,
        )
    }

    private static func contents(of url: URL) throws -> [(URL, URLResourceValues)] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
        ).map { item in
            try (item, item.resourceValues(forKeys: resourceKeys))
        }
    }

    private static func isPackage(_ url: URL, values: URLResourceValues) -> Bool {
        values.isPackage == true || ["app", "photoslibrary"].contains(url.pathExtension.lowercased())
    }

    private static func requireRealDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true, values.isDirectory == true else {
            throw FolderContentsError.notAFolder(url)
        }
    }

    private static func isPhoto(_ url: URL, contentType: UTType?, types: [UTType]) -> Bool {
        let type = contentType ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return false }
        return types.contains { type.conforms(to: $0) }
    }

    private static func finderSort(_ lhs: URL, _ rhs: URL) -> Bool {
        finderSort(lhs.lastPathComponent, rhs.lastPathComponent)
    }

    private static func finderSort(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}

private enum FolderContentsError: Error {
    case notAFolder(URL)
}
