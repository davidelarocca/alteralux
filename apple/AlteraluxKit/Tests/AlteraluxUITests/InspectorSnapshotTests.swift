import DesignSystem
import SwiftUI
import Testing

// Visual regression for the inspector's components (see ComponentSnapshotTests.swift).

private let components = "apple/DesignSystem/Sources/DesignSystem/Components"

extension WindowedTests {
    @MainActor
    struct InspectorSectionSnapshots {
        private let source = "\(components)/InspectorSection.swift"
        private let sizes = ["320x160"]

        private func section(_ title: LocalizedStringKey, isExpanded: Bool, summary: String) -> some View {
            Form {
                InspectorSection(title, isExpanded: .constant(isExpanded), summary: summary) {
                    Toggle("Automatic metering", isOn: .constant(true))
                }
            }
            .formStyle(.grouped)
        }

        @Test func expanded() {
            #expect(Snapshot.verify("InspectorSection", sizes: sizes, state: "expanded", source: source) {
                section("Camera", isExpanded: true, summary: "+0.3 · 35 mm")
            } == [])
        }

        @Test func collapsedShowsItsValues() {
            #expect(Snapshot.verify("InspectorSection", sizes: sizes, state: "collapsed", source: source) {
                section("Camera", isExpanded: false, summary: "+0.3 · 35 mm")
            } == [])
        }

        @Test func longText() {
            #expect(Snapshot.verify("InspectorSection", sizes: sizes, state: "long-text", source: source) {
                section("A section with a long title", isExpanded: false, summary: "a long summary of many values that cannot all fit")
            } == [])
        }

        /// Changed from its defaults: a dot after the title and, open, the Reset button.
        @Test func modified() {
            #expect(Snapshot.verify("InspectorSection", sizes: sizes, state: "modified", source: source) {
                Form {
                    InspectorSection(
                        "Shot", isExpanded: .constant(true), isModified: true, reset: {},
                        content: { Toggle("Automatic metering", isOn: .constant(false)) },
                    )
                }
                .formStyle(.grouped)
            } == [])
        }

        @Test func rightToLeft() {
            #expect(Snapshot.verify("InspectorSection", sizes: sizes, state: "collapsed", locale: "ar", source: source) {
                section("Camera", isExpanded: false, summary: "+0.3 · 35 mm")
            } == [])
        }
    }

    @MainActor
    struct InspectorSubheadingSnapshots {
        private let source = "\(components)/InspectorSubheading.swift"
        private let sizes = ["320x200"]

        @Test func withAndWithoutANote() {
            #expect(Snapshot.verify("InspectorSubheading", sizes: sizes, state: "note", source: source) {
                Form {
                    Section {
                        InspectorSubheading("Grain")
                        Toggle("Grain layers", isOn: .constant(true))
                        InspectorSubheading("Diffusion filter", note: "Off: switch the diffusion filter on to adjust it.")
                    }
                }
                .formStyle(.grouped)
            } == [])
        }

        /// The title with its mode's switch on the row: on with nothing under it, off with the
        /// control it governs, and with a line.
        @Test func withASwitch() {
            #expect(Snapshot.verify("InspectorSubheading", sizes: sizes, state: "switch", source: source) {
                Form {
                    Section {
                        InspectorSubheading(
                            "Exposure", isOn: .constant(true), switchTitle: "Auto", switchLabel: "Automatic exposure",
                        )
                        InspectorSubheading(
                            "White balance", isOn: .constant(false), switchTitle: "Auto",
                            switchLabel: "Automatic white balance", note: "The camera chose it itself.",
                        )
                        Toggle("A control it governs", isOn: .constant(true))
                    }
                }
                .formStyle(.grouped)
            } == [])
        }
    }
}
