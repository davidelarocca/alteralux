import AlteraluxEngine
import DesignSystem
import Foundation

/// The kinds the films are grouped by in the list, in the list's order.
enum FilmKind: CaseIterable {
    case colorNegative
    case slide
    case blackAndWhite
    case motionPicture

    /// Black and white comes first: a black and white reversal or cinema stock is looked for
    /// among the black and white films.
    init(of stock: StockInfo) {
        if stock.isBlackAndWhite {
            self = .blackAndWhite
        } else if stock.isPositive {
            self = .slide
        } else if stock.isMotionPicture {
            self = .motionPicture
        } else {
            self = .colorNegative
        }
    }
}

/// What the app adds to a film of the engine to show it: its emblem and its speed. The engine's
/// profiles carry neither.
struct FilmLook: Equatable {
    let ground: FilmEmblem.Ink
    let band: FilmEmblem.Ink
    /// The speed as the film's name writes it ("400H", "250D"), drawn on the emblem.
    let label: String
    /// The film's speed as its maker rates it in daylight, when the app knows it. For most films
    /// it is the number in the name. The two black and white cinema stocks carry none in theirs:
    /// Kodak's data sheets give Double-X 5222 an exposure index of 250 in daylight (200 under
    /// tungsten light) and Tri-X Reversal 7266 one of 200 (160 under tungsten light). A pushed
    /// film shows the speed of the stock, not the index it was exposed at.
    let iso: Int?

    /// For a film the app has no emblem for: a new profile upstream shows plain until it gets one.
    static let plain = FilmLook(ground: .plain, band: .ash, label: "", iso: nil)

    /// The look of each film the engine ships, by profile name. `FilmCatalogueTests` fails when
    /// the engine lists a film that is missing here.
    static let byStock: [String: FilmLook] = [
        "fujifilm_c200": FilmLook(ground: .pine, band: .bone, label: "200", iso: 200),
        "fujifilm_pro_400h": FilmLook(ground: .mint, band: .slate, label: "400H", iso: 400),
        "fujifilm_xtra_400": FilmLook(ground: .leaf, band: .fuchsia, label: "400", iso: 400),
        "kodak_ektar_100": FilmLook(ground: .brick, band: .amber, label: "100", iso: 100),
        "kodak_gold_200": FilmLook(ground: .gold, band: .bronze, label: "200", iso: 200),
        "kodak_portra_160": FilmLook(ground: .violet, band: .cream, label: "160", iso: 160),
        "kodak_portra_400": FilmLook(ground: .violet, band: .cream, label: "400", iso: 400),
        "kodak_portra_800": FilmLook(ground: .violet, band: .cream, label: "800", iso: 800),
        "kodak_portra_800_push1": FilmLook(ground: .deepViolet, band: .cream, label: "800+1", iso: 800),
        "kodak_portra_800_push2": FilmLook(ground: .darkViolet, band: .cream, label: "800+2", iso: 800),
        "kodak_ultramax_400": FilmLook(ground: .cobalt, band: .amber, label: "400", iso: 400),
        "fujifilm_provia_100f": FilmLook(ground: .azure, band: .silver, label: "100F", iso: 100),
        "fujifilm_velvia_100": FilmLook(ground: .magenta, band: .fern, label: "100", iso: 100),
        "kodak_ektachrome_100": FilmLook(ground: .royal, band: .amber, label: "E100", iso: 100),
        "kodak_kodachrome_64": FilmLook(ground: .vermilion, band: .yellow, label: "64", iso: 64),
        "kodak_doublex": FilmLook(ground: .black, band: .white, label: "XX", iso: 250),
        "kodak_trix": FilmLook(ground: .graphite, band: .ash, label: "TX", iso: 200),
        "kodak_verita_200d": FilmLook(ground: .umber, band: .sky, label: "200D", iso: 200),
        "kodak_vision3_50d": FilmLook(ground: .petrol, band: .sky, label: "50D", iso: 50),
        "kodak_vision3_200t": FilmLook(ground: .petrol, band: .tungsten, label: "200T", iso: 200),
        "kodak_vision3_250d": FilmLook(ground: .petrol, band: .sky, label: "250D", iso: 250),
        "kodak_vision3_500t": FilmLook(ground: .petrol, band: .tungsten, label: "500T", iso: 500),
    ]
}

/// One film as the list shows it.
struct FilmEntry: Identifiable, Equatable {
    let stock: StockInfo
    let kind: FilmKind
    let look: FilmLook

    var id: String {
        stock.id
    }

    var name: String {
        stock.displayName
    }

    init(_ stock: StockInfo) {
        self.stock = stock
        kind = FilmKind(of: stock)
        look = FilmLook.byStock[stock.id] ?? .plain
    }
}

/// The films of one kind, in the order the list shows them.
struct FilmGroup: Identifiable, Equatable {
    let kind: FilmKind
    let films: [FilmEntry]

    var id: FilmKind {
        kind
    }
}

/// The engine's films, arranged for choosing one: grouped by kind, searched by name, and walked
/// with the arrow keys.
struct FilmCatalogue: Equatable {
    let entries: [FilmEntry]

    /// Films are ordered by name, with the numbers in it compared as numbers: Vision3 50D comes
    /// before Vision3 200T.
    init(films: [StockInfo] = []) {
        entries = films
            .map(FilmEntry.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func entry(id: String) -> FilmEntry? {
        entries.first { $0.id == id }
    }

    /// The groups to list for a search: every word typed must be in the film's name, in any order
    /// and whatever the case or the accents. Kinds with no match are left out.
    func groups(matching query: String = "") -> [FilmGroup] {
        let words = query.split(whereSeparator: \.isWhitespace)
        let matches = entries.filter { entry in
            words.allSatisfy { entry.name.localizedStandardContains($0) }
        }
        return FilmKind.allCases.compactMap { kind in
            let films = matches.filter { $0.kind == kind }
            return films.isEmpty ? nil : FilmGroup(kind: kind, films: films)
        }
    }

    /// The film `offset` rows from `id` in the listed groups, stopping at the ends. With no
    /// starting film, or one that is not listed, it is the first film going down and the last
    /// going up.
    static func film(from id: String?, offset: Int, in groups: [FilmGroup]) -> String? {
        let listed = groups.flatMap(\.films).map(\.id)
        guard !listed.isEmpty else { return nil }
        guard let id, let index = listed.firstIndex(of: id) else {
            return offset >= 0 ? listed.first : listed.last
        }
        return listed[min(max(index + offset, 0), listed.count - 1)]
    }
}
