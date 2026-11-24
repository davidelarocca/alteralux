import Foundation
import Synchronization

/// A lensfun database loaded in memory: the cameras, the lenses with their calibrations and the
/// mounts, read from a folder of XML files in lensfun's format and never changed afterward.
///
/// Loading reads every file of the folder, a few megabytes for the whole of lensfun's database,
/// so it is meant to run in the background once, at launch. Finding the profile of a photo's lens
/// then takes a few milliseconds.
public final class LensDatabase: Sendable {
    private let cameras: [CameraRecord]
    private let lenses: [LensRecord]
    /// The mounts a camera mount also takes lenses of, by lowercased mount name.
    private let compatibleMounts: [String: [String]]
    /// The indexes in `cameras` by lowercased model name.
    private let camerasByModel: [String: [Int]]
    /// The indexes in `lenses` by lowercased mount name.
    private let lensesByMount: [String: [Int]]

    /// The number of cameras in the database.
    public var cameraCount: Int {
        cameras.count
    }

    /// The number of lenses in the database.
    public var lensCount: Int {
        lenses.count
    }

    /// Loads every `.xml` file in `directory`.
    ///
    /// - Throws: `LensDatabaseError` when a file is not well-formed XML.
    public init(directory: URL) throws {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "xml" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let parsed = Mutex<[LensDatabaseFile?]>(Array(repeating: nil, count: urls.count))
        DispatchQueue.concurrentPerform(iterations: urls.count) { index in
            let file = LensDatabaseParser.parse(contentsOf: urls[index])
            parsed.withLock { $0[index] = file }
        }
        let files = parsed.withLock { $0 }
        var allCameras: [CameraRecord] = []
        var allLenses: [LensRecord] = []
        var mounts: [String: [String]] = [:]
        for (url, file) in zip(urls, files) {
            guard let file else { throw LensDatabaseError.unreadable(url) }
            allCameras += file.cameras
            allLenses += file.lenses
            for (name, compats) in file.mounts {
                mounts[name.lowercased(), default: []] += compats.map { $0.lowercased() }
            }
        }
        cameras = allCameras
        lenses = allLenses
        compatibleMounts = mounts

        var byModel: [String: [Int]] = [:]
        for (index, camera) in allCameras.enumerated() {
            for model in camera.models {
                byModel[model.lowercased(), default: []].append(index)
            }
        }
        camerasByModel = byModel
        var byMount: [String: [Int]] = [:]
        for (index, lens) in allLenses.enumerated() {
            for mount in lens.mounts {
                byMount[mount.lowercased(), default: []].append(index)
            }
        }
        lensesByMount = byMount
    }

    // MARK: Lookup

    /// The profile of the lens a photo was taken with, or `nil` when the camera or the lens is
    /// not in the database or the answer is not clear.
    ///
    /// The camera is found by its maker and model, ignoring case (the maker may also be a longer
    /// or shorter spelling of the database's). The lens is found among those of the camera's
    /// mount, or of a mount compatible with it, by the lens model the photo gives, in lensfun's
    /// way: every word of the photo's lens model, numbers included, must be in the database's
    /// name. A lens whose calibration was made on a sensor much smaller than the camera's is not
    /// taken. The best score wins, and a tie between lenses with different names gives `nil`.
    ///
    /// A photo that names no lens (a camera with a fixed lens) gets the fixed lens of its camera
    /// when the database has exactly one for it, under the camera's name: the database calls such
    /// a lens after everything its record holds ("Ricoh GR III & compatibles + GW-4" is the GR
    /// III's own lens and, at another focal length, the lens with its wide converter).
    public func lens(for info: PhotoLensInfo) -> LensProfile? {
        guard let camera = camera(for: info), camera.cropFactor > 0.01 else { return nil }
        let name = info.lensName
        guard !name.isEmpty else {
            return fixedLens(of: camera, focalLength: info.focalLength).map {
                LensProfile(lens: $0, cameraCropFactor: camera.cropFactor, name: camera.models.first)
            }
        }
        return lens(named: name, camera: camera, focalLength: info.focalLength).map {
            LensProfile(lens: $0, cameraCropFactor: camera.cropFactor)
        }
    }

    /// The camera a photo was taken with.
    func camera(for info: PhotoLensInfo) -> CameraRecord? {
        let model = info.cameraModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return nil }
        let maker = info.cameraMaker.trimmingCharacters(in: .whitespacesAndNewlines)

        let exact = (camerasByModel[model.lowercased()] ?? []).map { cameras[$0] }.filter { makerMatches($0, maker) }
        if let first = exact.first {
            return first
        }

        // Words of the photo's model all in the database's, the closest name winning when alone.
        let pattern = LensFuzzyMatch.words(of: model)
        var best = 0
        var bestCameras: [CameraRecord] = []
        for camera in cameras where makerMatches(camera, maker) {
            let score = LensFuzzyMatch.score(patternWords: pattern, names: camera.models)
            if score > best {
                best = score
                bestCameras = [camera]
            } else if score == best, score > 0 {
                bestCameras.append(camera)
            }
        }
        guard bestCameras.count == 1 else { return nil }
        return bestCameras[0]
    }

    /// Whether a camera of the database is by the maker a photo names: the same name apart from
    /// case, or one that has every word of the other ("Nikon Corporation" and "NIKON").
    private func makerMatches(_ camera: CameraRecord, _ maker: String) -> Bool {
        guard !maker.isEmpty else { return true }
        let words = LensFuzzyMatch.words(of: maker)
        return camera.makers.contains { name in
            LensFuzzyMatch.sameName(name, maker)
                || LensFuzzyMatch.score(patternWords: words, nameWords: LensFuzzyMatch.words(of: name)) > 0
                || LensFuzzyMatch.score(patternWords: LensFuzzyMatch.words(of: name), nameWords: words) > 0
        }
    }

    /// The mounts whose lenses fit a camera mount, with the score lensfun gives each kind: 10 for
    /// the mount itself, 9 for a compatible one.
    private func mounts(of camera: CameraRecord) -> [(mount: String, score: Int)] {
        let own = camera.mount.lowercased()
        return [(own, 10)] + (compatibleMounts[own] ?? []).map { ($0, 9) }
    }

    private func lens(named name: String, camera: CameraRecord, focalLength: Double) -> LensRecord? {
        let pattern = LensFuzzyMatch.words(of: name)
        guard !pattern.isEmpty else { return nil }

        var best = 0
        var winners: [LensRecord] = []
        var seen = Set<Int>()
        for (mount, mountScore) in mounts(of: camera) {
            for index in lensesByMount[mount] ?? [] where seen.insert(index).inserted {
                let lens = lenses[index]
                guard let cropScore = Self.cropScore(camera: camera, lens: lens), Self.covers(lens, focalLength) else { continue }
                let nameScore = Self.nameScore(pattern, lens)
                guard nameScore > 0 else { continue }
                let score = cropScore + mountScore + max(1, nameScore * 4 / 10)
                if score > best {
                    best = score
                    winners = [lens]
                } else if score == best {
                    winners.append(lens)
                }
            }
        }
        return Self.unique(winners)
    }

    /// The fixed lens of a camera: the only lens of its mount, or the only one called "fixed lens".
    private func fixedLens(of camera: CameraRecord, focalLength: Double) -> LensRecord? {
        let own = (lensesByMount[camera.mount.lowercased()] ?? []).map { lenses[$0] }.filter {
            Self.cropScore(camera: camera, lens: $0) != nil && Self.covers($0, focalLength)
        }
        if own.count == 1 {
            return own[0]
        }
        let plain = own.filter { $0.models.contains { $0.lowercased().contains("fixed lens") && !$0.lowercased().contains("converter") } }
        return plain.count == 1 ? plain[0] : nil
    }

    /// The best match of the pattern against a lens's names, with and without its maker in front
    /// (photos say "Sony FE 24-70mm F2.8 GM", the database "FE 24-70mm f/2.8 GM").
    private static func nameScore(_ pattern: [[UInt8]], _ lens: LensRecord) -> Int {
        let withMaker = lens.makers.flatMap { maker in lens.models.map { "\(maker) \($0)" } }
        return LensFuzzyMatch.score(patternWords: pattern, names: lens.models + withMaker)
    }

    /// Lensfun's score for how close a lens's calibration sensor is to the camera's, from 2 to 10;
    /// `nil` when the camera's sensor is much smaller than the one calibrated (a ratio under
    /// 0.96), where lensfun would not take the lens.
    private static func cropScore(camera: CameraRecord, lens: LensRecord) -> Int? {
        let ratio = camera.cropFactor / lens.cropFactor
        switch ratio {
        case ..<LensCalibrations.minimumCropRatio: return nil
        case ..<1: return 3
        case ..<1.01: return 5
        case ..<1.11: return 10
        case ..<1.21: return 8
        case ..<1.31: return 6
        case ..<1.41: return 4
        default: return 2
        }
    }

    /// Whether a photo's focal length is one the lens has, with a margin of 5%. A lens that does
    /// not say its range covers everything.
    private static func covers(_ lens: LensRecord, _ focalLength: Double) -> Bool {
        guard focalLength > 0, lens.maxFocal > 0 else { return true }
        return focalLength >= min(lens.minFocal, lens.maxFocal) * 0.95 && focalLength <= max(lens.minFocal, lens.maxFocal) * 1.05
    }

    /// The winner of a search, when there is one: a single lens, or several that are the same
    /// lens listed twice (the first with calibrations wins).
    private static func unique(_ winners: [LensRecord]) -> LensRecord? {
        guard let first = winners.first else { return nil }
        let sameLens = winners.allSatisfy {
            LensFuzzyMatch.sameName($0.displayName, first.displayName)
        }
        guard sameLens else { return nil }
        return winners.first(where: \.hasCalibrations) ?? first
    }
}

/// Why a lens database could not be loaded.
public enum LensDatabaseError: Error, Equatable {
    /// The file is not well-formed lensfun XML.
    case unreadable(URL)
}

private extension PhotoLensInfo {
    var lensName: String {
        lensModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
