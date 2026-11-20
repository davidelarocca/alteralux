import DesignSystem
import SwiftUI
import Testing

// Visual regression for the components of docs/COMPONENT_REGISTRY.md: each image is compared,
// in light and dark, with the one approved in snapshots/. A missing or different image fails
// and waits for /swift-harness:approve-snapshots; a test never writes a baseline.

private let components = "apple/DesignSystem/Sources/DesignSystem/Components"

extension WindowedTests {
    @MainActor
    struct ParameterSliderSnapshots {
        private let source = "\(components)/ParameterSlider.swift"
        /// The narrowest a slider gets: the inspector's minimum width.
        private let sizes = ["280"]
        /// The value is a formatted number: every image names its language, or it would
        /// follow the language of the Mac that runs the test.
        private let english = "en"

        @Test func positiveValue() {
            #expect(Snapshot.verify("ParameterSlider", sizes: sizes, state: "positive", locale: english, source: source) {
                SliderHost("Exposure", value: 0.3)
            } == [])
        }

        @Test func negativeValueAtTheEndOfTheRange() {
            #expect(Snapshot.verify("ParameterSlider", sizes: sizes, state: "minimum", locale: english, source: source) {
                SliderHost("Yellow filter", value: -50, in: -50 ... 50, step: 1, fractionDigits: 0)
            } == [])
        }

        @Test func unsignedValue() {
            #expect(Snapshot.verify("ParameterSlider", sizes: sizes, state: "unsigned", locale: english, source: source) {
                SliderHost("Print exposure", value: 1, in: 0.2 ... 3, step: 0.01, defaultValue: 1, fractionDigits: 2, showsSign: false)
            } == [])
        }

        @Test func longTitle() {
            #expect(Snapshot.verify("ParameterSlider", sizes: sizes, state: "long-text", locale: english, source: source) {
                SliderHost("A long parameter name that has to share the row with its value", value: 0.3)
            } == [])
        }

        @Test(arguments: ["it", "ar"])
        func otherLanguages(locale: String) {
            #expect(Snapshot.verify("ParameterSlider", sizes: sizes, state: "positive", locale: locale, source: source) {
                SliderHost("Exposure", value: 0.3)
            } == [])
        }
    }

    @MainActor
    struct ThumbnailCellSnapshots {
        private let source = "\(components)/ThumbnailCell.swift"
        private let sizes = ["116x88"]

        @Test(arguments: [false, true])
        func placeholder(isSelected: Bool) {
            let state = isSelected ? "placeholder-selected" : "placeholder"
            #expect(Snapshot.verify("ThumbnailCell", sizes: sizes, state: state, source: source) {
                ThumbnailCell(image: nil, isSelected: isSelected)
            } == [])
        }

        @Test(arguments: [false, true])
        func photo(isSelected: Bool) throws {
            let picture = try #require(WindowedTests.testPicture())
            let state = isSelected ? "photo-selected" : "photo"
            #expect(Snapshot.verify("ThumbnailCell", sizes: sizes, state: state, source: source) {
                ThumbnailCell(image: picture, isSelected: isSelected)
            } == [])
        }
    }

    @MainActor
    struct StatusBadgeSnapshots {
        private let source = "\(components)/StatusBadge.swift"
        private let sizes = ["320x60"]

        /// A badge where the app draws it: over the viewer's surround.
        private func overTheViewer(_ badge: StatusBadge) -> some View {
            badge
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.DS.viewerSurround)
        }

        @Test func shortText() {
            #expect(Snapshot.verify("StatusBadge", sizes: sizes, state: "short", source: source) {
                overTheViewer(StatusBadge("Original"))
            } == [])
        }

        @Test func longText() {
            #expect(Snapshot.verify("StatusBadge", sizes: sizes, state: "long-text", source: source) {
                overTheViewer(StatusBadge("A longer status that still fits on one line"))
            } == [])
        }

        @Test func rightToLeft() {
            #expect(Snapshot.verify("StatusBadge", sizes: sizes, state: "short", locale: "ar", source: source) {
                overTheViewer(StatusBadge("Original"))
            } == [])
        }
    }
}
