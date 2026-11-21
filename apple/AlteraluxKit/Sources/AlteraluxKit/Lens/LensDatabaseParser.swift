import Foundation

/// What one lensfun XML file holds.
struct LensDatabaseFile: Sendable {
    /// The compatible mounts of each mount, by the mount's name.
    var mounts: [String: [String]] = [:]
    var cameras: [CameraRecord] = []
    var lenses: [LensRecord] = []
}

/// Reads one lensfun database file (the format of `data/db/*.xml`: `<mount>`, `<camera>` and
/// `<lens>` elements) with Foundation's XML parser.
///
/// Unknown elements and attributes are ignored, so a newer database still loads. Distortion,
/// fringing and vignetting entries whose model is not supported (lensfun's Adobe "acm" models)
/// are left out, and so are lenses and cameras with no model.
final class LensDatabaseParser: NSObject, XMLParserDelegate {
    private(set) var file = LensDatabaseFile()

    private var stack: [String] = []
    private var text = ""
    private var language: String?
    private var mountName: [String] = []
    private var mountCompats: [String] = []
    private var isInMount = false
    private var camera: CameraRecord?
    private var lens: LensRecord?

    /// The contents of the file at `url`, or `nil` when it is not well-formed XML.
    static func parse(contentsOf url: URL) -> LensDatabaseFile? {
        guard let parser = XMLParser(contentsOf: url) else { return nil }
        let delegate = LensDatabaseParser()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        return parser.parse() ? delegate.file : nil
    }

    // MARK: XMLParserDelegate

    func parser(
        _: XMLParser,
        didStartElement name: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes: [String: String] = [:],
    ) {
        let parent = stack.last
        stack.append(name)
        text = ""
        language = nil
        switch name {
        case "mount" where parent == "lensdatabase":
            isInMount = true
            mountName = []
            mountCompats = []
        case "camera" where parent == "lensdatabase":
            camera = CameraRecord()
        case "lens" where parent == "lensdatabase":
            lens = LensRecord()
        case "maker", "model", "name":
            language = attributes["lang"]
        case "focal" where parent == "lens":
            readFocal(attributes)
        case "center" where parent == "lens":
            lens?.center = SIMD2(number(attributes["x"]), number(attributes["y"]))
        case "distortion" where parent == "calibration":
            readDistortion(attributes)
        case "tca" where parent == "calibration":
            readTCA(attributes)
        case "vignetting" where parent == "calibration":
            readVignetting(attributes)
        default:
            break
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_: XMLParser, didEndElement name: String, namespaceURI _: String?, qualifiedName _: String?) {
        stack.removeLast()
        let parent = stack.last
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "mount":
            if parent == "lensdatabase" {
                if let first = mountName.first {
                    file.mounts[first, default: []].append(contentsOf: mountCompats)
                }
                isInMount = false
            } else if !value.isEmpty {
                camera?.mount = value
                lens?.mounts.append(value)
            }
        case "camera" where parent == "lensdatabase":
            if let camera, !camera.models.isEmpty, !camera.makers.isEmpty {
                file.cameras.append(camera)
            }
            camera = nil
        case "lens" where parent == "lensdatabase":
            if let lens, !lens.models.isEmpty {
                file.lenses.append(lens)
            }
            lens = nil
        default:
            readText(name, value)
        }
        text = ""
    }

    /// The text of a `<maker>`, `<model>`, `<name>`, `<compat>`, `<cropfactor>` or `<aspect-ratio>`.
    private func readText(_ name: String, _ value: String) {
        guard !value.isEmpty else { return }
        switch name {
        case "name" where isInMount:
            mountName.append(value)
        case "compat" where isInMount:
            mountCompats.append(value)
        case "maker":
            camera?.makers.addName(value, isDefault: language == nil)
            lens?.makers.addName(value, isDefault: language == nil)
        case "model":
            camera?.models.addName(value, isDefault: language == nil)
            lens?.models.addName(value, isDefault: language == nil)
        case "cropfactor":
            camera?.cropFactor = number(value)
            if lens != nil {
                lens?.cropFactor = number(value)
            }
        case "aspect-ratio" where lens != nil:
            lens?.aspectRatio = aspectRatio(value)
        default:
            break
        }
    }

    // MARK: Elements

    private func readFocal(_ attributes: [String: String]) {
        if let value = attributes["value"] {
            lens?.minFocal = number(value)
            lens?.maxFocal = number(value)
        }
        if let value = attributes["min"] {
            lens?.minFocal = number(value)
        }
        if let value = attributes["max"] {
            lens?.maxFocal = number(value)
        }
    }

    private func readDistortion(_ attributes: [String: String]) {
        let model: LensDistortionModel
        switch attributes["model"] {
        case "poly3": model = .poly3
        case "poly5": model = .poly5
        case "ptlens": model = .ptlens
        default: return
        }
        let terms = SIMD3(
            number(attributes["a"] ?? attributes["k1"]),
            number(attributes["b"] ?? attributes["k2"]),
            number(attributes["c"] ?? attributes["k3"]),
        )
        let focal = number(attributes["focal"])
        var realFocal = number(attributes["real-focal"])
        if realFocal <= 0 {
            switch model {
            case .ptlens: realFocal = focal * (1 - terms.x - terms.y - terms.z)
            case .poly3: realFocal = focal * (1 - terms.x)
            default: realFocal = focal
            }
        }
        lens?.calibrations.distortion.append(
            DistortionCalibration(model: model, focal: focal, realFocal: realFocal, terms: terms),
        )
    }

    private func readTCA(_ attributes: [String: String]) {
        let model: LensTCAModel
        switch attributes["model"] {
        case "linear": model = .linear
        case "poly3": model = .poly3
        default: return
        }
        let names = [["kr", "vr"], ["kb", "vb"], ["cr"], ["cb"], ["br"], ["bb"]]
        var terms: [Double] = [1, 1, 0, 0, 0, 0]
        for (index, spellings) in names.enumerated() {
            if let value = spellings.compactMap({ attributes[$0] }).first {
                terms[index] = number(value)
            }
        }
        lens?.calibrations.tca.append(TCACalibration(model: model, focal: number(attributes["focal"]), terms: terms))
    }

    private func readVignetting(_ attributes: [String: String]) {
        guard attributes["model"] == "pa" else { return }
        lens?.calibrations.vignetting.append(
            VignettingCalibration(
                focal: number(attributes["focal"]),
                aperture: number(attributes["aperture"]),
                distance: number(attributes["distance"]),
                terms: SIMD3(number(attributes["k1"]), number(attributes["k2"]), number(attributes["k3"])),
            ),
        )
    }

    private func number(_ value: String?) -> Double {
        value.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? 0
    }

    /// "3:2" or "1.5".
    private func aspectRatio(_ value: String) -> Double {
        let parts = value.split(separator: ":").map { number(String($0)) }
        if parts.count == 2, parts[1] != 0 {
            return parts[0] / parts[1]
        }
        return parts.first ?? 1.5
    }
}

private extension [String] {
    /// Adds a name: one with no language is the default and comes first; translations follow.
    mutating func addName(_ value: String, isDefault: Bool) {
        if isDefault {
            insert(value, at: 0)
        } else {
            append(value)
        }
    }
}
