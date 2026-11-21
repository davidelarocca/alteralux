import DesignSystem
import SwiftUI
import Testing

// The pop-up button of the inspector's rows, compared in light and dark with the images approved
// in snapshots/. Kept apart from ComponentSnapshotTests.swift, which is long.

extension WindowedTests {
    @MainActor
    struct WindowPopUpSnapshots {
        private let source = "apple/DesignSystem/Sources/DesignSystem/Components/WindowPopUp.swift"
        /// The inspector's minimum width.
        private let sizes = ["280x200"]

        /// The inspector's rows: a long title beside a short option, whose longest option is
        /// longer, and a time; the paper alone under its caption, cut where it is too long.
        private func rows() -> some View {
            Form {
                WindowPopUp("Film format", selection: .constant(35), options: [
                    WindowPopUpOption(35, title: "35 mm"),
                    WindowPopUpOption(67, title: "Medium format 6 × 7"),
                ])
                WindowPopUp("Development", selection: .constant(12.0), options: [
                    WindowPopUpOption(8.0, title: "8 min"), WindowPopUpOption(12.0, title: "12 min"),
                ])
                WindowPopUp("Paper", selection: .constant(1), options: [
                    WindowPopUpOption(1, title: "Kodak Professional Portra Endura with a long name"),
                ])
                .labelsHidden()
                WindowPopUp("Disabled", selection: .constant(1), options: [WindowPopUpOption(1, title: "5 min")])
                    .disabled(true)
            }
            .formStyle(.grouped)
        }

        @Test func rowsOfAForm() {
            #expect(Snapshot.verify("WindowPopUp", sizes: sizes, state: "rows", locale: "en", source: source) {
                rows()
            } == [])
        }

        @Test func rightToLeft() {
            #expect(Snapshot.verify("WindowPopUp", sizes: sizes, state: "rows", locale: "ar", source: source) {
                rows()
            } == [])
        }
    }
}
