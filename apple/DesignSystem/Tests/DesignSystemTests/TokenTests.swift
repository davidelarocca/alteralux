import AppKit
import SwiftUI
import Testing
@testable import DesignSystem

/// `swift test` compiles asset catalogs from Xcode 27 on. Before that the
/// catalog is copied as a folder and no color resolves, in tests only.
private let assetCatalogIsCompiled = Bundle.module.url(forResource: "Assets", withExtension: "car") != nil

struct ColorTokenTests {
    /// `Color("name", bundle:)` never fails when created, so check that every
    /// semantic color really is in the catalog.
    @Test(
        .enabled(if: assetCatalogIsCompiled, "this toolchain does not compile asset catalogs for swift test"),
        arguments: Color.DS.names,
    )
    func semanticColorResolves(_ name: String) {
        #expect(NSColor(named: name, bundle: .module) != nil, "Colors.xcassets has no color named \(name)")
    }

    @Test func everyColorOfTheCatalogHasAnAccessor() throws {
        let catalog = try #require(Bundle.module.resourceURL)
        // In a compiled catalog the names are not listed as files: nothing to compare.
        let sets = (try? FileManager.default.contentsOfDirectory(atPath: catalog.appendingPathComponent("Colors.xcassets").path)) ?? []
        let names = sets.filter { $0.hasSuffix(".colorset") }.map { String($0.dropLast(".colorset".count)) }
        for name in names {
            #expect(Color.DS.names.contains(name), "\(name) is in the catalog but not in Color.DS.names")
        }
    }
}

struct MotionTokenTests {
    @Test func movingAnimationsAreDroppedUnderReduceMotion() {
        #expect(Motion.moving(Motion.standard, reduced: true) == nil)
        #expect(Motion.moving(Motion.standard, reduced: false) == Motion.standard)
    }
}

struct SpacingTokenTests {
    @Test func spacingScaleIsOrdered() {
        let scale = [Spacing.xxs, Spacing.xs, Spacing.s, Spacing.m, Spacing.l, Spacing.xl]
        #expect(scale == scale.sorted())
        #expect(Set(scale).count == scale.count)
    }
}
