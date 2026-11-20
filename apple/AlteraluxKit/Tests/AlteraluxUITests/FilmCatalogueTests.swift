import AlteraluxEngine
import Foundation
import Testing
@testable import AlteraluxUI

/// How the films are arranged for choosing one: their kinds, the search, the arrow keys.
@MainActor
struct FilmCatalogueTests {
    private func catalogue() async -> FilmCatalogue {
        let model = AppModel(dataDirectory: WindowedTests.engineData)
        await model.start()
        return model.filmCatalogue
    }

    /// A film added upstream must get its emblem and its speed here, not show plain unnoticed.
    @Test func everyFilmOfTheEngineHasItsLook() async {
        let catalogue = await catalogue()
        #expect(!catalogue.entries.isEmpty)
        let plain = catalogue.entries.filter { $0.look == .plain }.map(\.id)
        #expect(plain.isEmpty, "films with no entry in FilmLook.byStock: \(plain)")
        let unused = Set(FilmLook.byStock.keys).subtracting(catalogue.entries.map(\.id))
        #expect(unused.isEmpty, "FilmLook.byStock names films the engine does not list: \(unused)")
    }

    @Test func filmsAreGroupedByKindInTheListsOrder() async {
        let groups = await catalogue().groups()
        #expect(groups.map(\.kind) == [.colorNegative, .slide, .blackAndWhite, .motionPicture])
        let kinds = Dictionary(uniqueKeysWithValues: groups.map { ($0.kind, $0.films.map(\.id)) })
        #expect(kinds[.colorNegative]?.contains("kodak_portra_400") == true)
        #expect(kinds[.slide]?.contains("fujifilm_velvia_100") == true)
        // Black and white wins over reversal and over motion picture.
        #expect(kinds[.blackAndWhite]?.contains("kodak_trix") == true)
        #expect(kinds[.blackAndWhite]?.contains("kodak_doublex") == true)
        #expect(kinds[.motionPicture]?.contains("kodak_vision3_250d") == true)
    }

    @Test func numbersInNamesAreOrderedAsNumbers() async throws {
        let groups = await catalogue().groups()
        let cinema = groups.first { $0.kind == .motionPicture }?.films.map(\.id) ?? []
        let fifty = try? #require(cinema.firstIndex(of: "kodak_vision3_50d"))
        let twoHundred = try? #require(cinema.firstIndex(of: "kodak_vision3_200t"))
        #expect(try fifty != nil && twoHundred != nil && #require(fifty) < #require(twoHundred))
    }

    @Test func searchMatchesEveryWordWhateverTheCaseAndTheOrder() async {
        let catalogue = await catalogue()
        #expect(catalogue.groups(matching: "PORTRA").flatMap(\.films).count == 5)
        #expect(catalogue.groups(matching: "800 portra").flatMap(\.films).map(\.id) == [
            "kodak_portra_800", "kodak_portra_800_push1", "kodak_portra_800_push2",
        ])
        #expect(catalogue.groups(matching: "vel").map(\.kind) == [.slide])
        #expect(catalogue.groups(matching: "no such film").isEmpty)
        #expect(catalogue.groups(matching: "   ") == catalogue.groups())
    }

    @Test func theArrowKeysWalkTheListedFilmsAndStopAtTheEnds() async throws {
        let groups = await catalogue().groups(matching: "portra")
        let listed = groups.flatMap(\.films).map(\.id)
        let first = try #require(listed.first)
        let last = try #require(listed.last)
        #expect(FilmCatalogue.film(from: first, offset: 1, in: groups) == listed[1])
        #expect(FilmCatalogue.film(from: first, offset: -1, in: groups) == first)
        #expect(FilmCatalogue.film(from: last, offset: 1, in: groups) == last)
        // From a film that is not listed, down starts at the top and up at the bottom.
        #expect(FilmCatalogue.film(from: "fujifilm_velvia_100", offset: 1, in: groups) == first)
        #expect(FilmCatalogue.film(from: nil, offset: -1, in: groups) == last)
        #expect(FilmCatalogue.film(from: first, offset: 1, in: []) == nil)
    }
}
