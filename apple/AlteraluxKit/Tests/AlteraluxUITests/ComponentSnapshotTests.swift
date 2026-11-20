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

        /// A value in the thousands is one number, without a separator: a temperature.
        @Test func largeValue() {
            #expect(Snapshot.verify("ParameterSlider", sizes: sizes, state: "large-value", locale: english, source: source) {
                SliderHost(
                    "Temperature", value: 5250, in: 2000 ... 12000, step: 50, defaultValue: 4500,
                    fractionDigits: 0, showsSign: false,
                )
            } == [])
        }

        /// Disabled, the title and the value are dimmed: the slider alone looks the same.
        @Test func disabled() {
            #expect(Snapshot.verify("ParameterSlider", sizes: sizes, state: "disabled", locale: english, source: source) {
                SliderHost(
                    "Temperature", value: 5500, in: 2000 ... 12000, step: 50, defaultValue: 5500,
                    fractionDigits: 0, showsSign: false,
                )
                .disabled(true)
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

        @Test(arguments: [true, false])
        func withItsSwitch(isOn: Bool) {
            let state = isOn ? "switch-on" : "switch-off"
            #expect(Snapshot.verify("ParameterSlider", sizes: sizes, state: state, locale: english, source: source) {
                SliderHost("Grain", value: 0.35, in: 0.05 ... 1, step: 0.01, defaultValue: 0.2, fractionDigits: 2, showsSign: false, isOn: isOn)
            } == [])
        }

        @Test func withoutLabels() {
            #expect(Snapshot.verify("ParameterSlider", sizes: sizes, state: "labels-hidden", locale: english, source: source) {
                SliderHost("Zoom", value: 1.2).labelsHidden()
            } == [])
        }
    }

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

        @Test func rightToLeft() {
            #expect(Snapshot.verify("InspectorSection", sizes: sizes, state: "collapsed", locale: "ar", source: source) {
                section("Camera", isExpanded: false, summary: "+0.3 · 35 mm")
            } == [])
        }
    }

    @MainActor
    struct HeadingButtonSnapshots {
        private let source = "\(components)/HeadingButton.swift"
        private let sizes = ["280x72"]

        private func heading(_ title: String) -> some View {
            HeadingButton(caption: Text("Film · color negative · ISO 400"), title: title) {}
                .padding(Spacing.m)
        }

        @Test func shortTitle() {
            #expect(Snapshot.verify("HeadingButton", sizes: sizes, state: "short", source: source) {
                heading("Kodak Portra 400")
            } == [])
        }

        @Test func longTitle() {
            #expect(Snapshot.verify("HeadingButton", sizes: sizes, state: "long-text", source: source) {
                heading("Kodak Double-X Negative Film 5222, with more to its name")
            } == [])
        }

        @Test func rightToLeft() {
            #expect(Snapshot.verify("HeadingButton", sizes: sizes, state: "short", locale: "ar", source: source) {
                heading("Kodak Portra 400")
            } == [])
        }
    }

    @MainActor
    struct FilmEmblemSnapshots {
        private let source = "\(components)/FilmEmblem.swift"
        private let sizes = ["240x54"]

        /// A light ground, a dark one, a long label and the emblem of a film with no look yet.
        @Test func emblems() {
            #expect(Snapshot.verify("FilmEmblem", sizes: sizes, state: "kinds", source: source) {
                HStack(spacing: Spacing.s) {
                    FilmEmblem(ground: .violet, band: .cream, label: "400")
                    FilmEmblem(ground: .gold, band: .bronze, label: "200")
                    FilmEmblem(ground: .darkViolet, band: .cream, label: "800+2")
                    FilmEmblem(ground: .plain, band: .ash, label: "")
                }
                .padding(Spacing.m)
            } == [])
        }

        /// An emblem is a picture: it is not mirrored.
        @Test func rightToLeft() {
            #expect(Snapshot.verify("FilmEmblem", sizes: sizes, state: "kinds", locale: "ar", source: source) {
                HStack(spacing: Spacing.s) {
                    FilmEmblem(ground: .violet, band: .cream, label: "400")
                    FilmEmblem(ground: .petrol, band: .sky, label: "250D")
                }
                .padding(Spacing.m)
            } == [])
        }
    }

    @MainActor
    struct ThumbnailCellSnapshots {
        private let source = "\(components)/ThumbnailCell.swift"

        /// In a grid the cell has the size the grid gives it and shows the whole photo: an
        /// upright one keeps its sides, with the cell's ground beside it.
        @Test(arguments: [false, true])
        func wholePhotoInAGrid(isSelected: Bool) {
            let state = isSelected ? "whole-photo-selected" : "whole-photo"
            #expect(Snapshot.verify("ThumbnailCell", sizes: ["200"], state: state, source: source) {
                ThumbnailCell(
                    image: WindowedTests.testPicture(width: 120, height: 240), isSelected: isSelected,
                    size: CGSize(width: 160, height: 120), showsWholePhoto: true,
                )
            } == [])
        }

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
    struct ChoiceListButtonSnapshots {
        private let source = "\(components)/ChoiceListButton.swift"
        private let sizes = ["360x80"]

        /// The button where the app puts it, in the floating bar over the photos: with its title,
        /// with its symbol alone, and disabled. Drawn straight on the photos' dark surround, the
        /// light appearance's dark text could not be read.
        private func buttons() -> some View {
            FloatingBar {
                ChoiceListButton(Text(verbatim: "Tag"), choices: [], empty: Text(verbatim: "No Tags"))
                ChoiceListButton(Text(verbatim: "Move to…"), symbol: "folder", choices: [], empty: Text(verbatim: "No Folders"))
                ChoiceListButton(Text(verbatim: "Recipe"), choices: [], empty: Text(verbatim: "No Recipes"))
                    .disabled(true)
            }
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.DS.viewerSurround)
        }

        @Test func titleSymbolAndDisabled() {
            #expect(Snapshot.verify("ChoiceListButton", sizes: sizes, state: "closed", locale: "en", source: source) {
                buttons()
            } == [])
        }

        @Test func rightToLeft() {
            #expect(Snapshot.verify("ChoiceListButton", sizes: sizes, state: "closed", locale: "ar", source: source) {
                buttons()
            } == [])
        }
    }

    @MainActor
    struct FloatingBarSnapshots {
        private let source = "\(components)/FloatingBar.swift"
        private let sizes = ["560x90"]
        private let english = "en"

        /// A bar where the app draws it: over the surround of the photos.
        private func overThePhotos(_ bar: some View) -> some View {
            bar
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.DS.viewerSurround)
        }

        private func actions() -> some View {
            FloatingBar {
                Text(verbatim: "3 photos")
                Divider()
                Menu {} label: { Text(verbatim: "Recipe") }
                Button {} label: { Text(verbatim: "Export…") }
                Button {} label: { Text(verbatim: "Discard") }
                    .disabled(true)
            }
            .fixedSize()
        }

        @Test func actionsAndADisabledOne() {
            #expect(Snapshot.verify("FloatingBar", sizes: sizes, state: "actions", locale: english, source: source) {
                overThePhotos(actions())
            } == [])
        }

        @Test func longText() {
            #expect(Snapshot.verify("FloatingBar", sizes: sizes, state: "long-text", locale: english, source: source) {
                overThePhotos(
                    FloatingBar {
                        Text(verbatim: "A selection described at length")
                        Button {} label: { Text(verbatim: "One Action With a Long Title") }
                    }
                    .fixedSize(),
                )
            } == [])
        }

        @Test func rightToLeft() {
            #expect(Snapshot.verify("FloatingBar", sizes: sizes, state: "actions", locale: "ar", source: source) {
                overThePhotos(actions())
            } == [])
        }
    }

    @MainActor
    struct SelectionMarqueeSnapshots {
        private let source = "\(components)/SelectionMarquee.swift"
        private let sizes = ["320x140"]

        /// The rectangle over three thumbnails, as it is dragged across the library's grid.
        private func overThumbnails() -> some View {
            ZStack(alignment: .topLeading) {
                HStack(spacing: Spacing.m) {
                    ForEach(0 ..< 3) { _ in
                        ThumbnailCell(image: nil, isSelected: false, size: CGSize(width: 80, height: 60))
                    }
                }
                .padding(Spacing.l)
                SelectionMarquee()
                    .frame(width: 150, height: 80)
                    .offset(x: 50, y: 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.DS.viewerSurround)
        }

        @Test func overThePhotos() {
            #expect(Snapshot.verify("SelectionMarquee", sizes: sizes, state: "over-thumbnails", locale: "en", source: source) {
                overThumbnails()
            } == [])
        }

        @Test func rightToLeft() {
            #expect(Snapshot.verify("SelectionMarquee", sizes: sizes, state: "over-thumbnails", locale: "ar", source: source) {
                overThumbnails()
            } == [])
        }
    }

    @MainActor
    struct CropFrameSnapshots {
        private let source = "\(components)/CropFrame.swift"
        private let sizes = ["380x260"]

        /// A frame over part of a photo, and one over the whole of it.
        private func frame(_ rect: CGRect) -> some View {
            ZStack(alignment: .topLeading) {
                Color.DS.thumbnailPlaceholder
                    .frame(width: 320, height: 213)
                    .offset(x: 30, y: 23.5)
                CropFrame(rect: rect, onDrag: { _, _ in }, onDragEnd: {})
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.DS.viewerSurround)
        }

        @Test func overPartOfThePhoto() {
            #expect(Snapshot.verify("CropFrame", sizes: sizes, state: "part", locale: "en", source: source) {
                frame(CGRect(x: 90, y: 50, width: 200, height: 160))
            } == [])
        }

        @Test func overTheWholePhoto() {
            #expect(Snapshot.verify("CropFrame", sizes: sizes, state: "whole", locale: "en", source: source) {
                frame(CGRect(x: 30, y: 23.5, width: 320, height: 213))
            } == [])
        }

        /// Laid out left to right in every language: the photo is not mirrored.
        @Test func rightToLeft() {
            #expect(Snapshot.verify("CropFrame", sizes: sizes, state: "part", locale: "ar", source: source) {
                frame(CGRect(x: 90, y: 50, width: 200, height: 160))
            } == [])
        }
    }

    @MainActor
    struct FormSheetSnapshots {
        private let source = "\(components)/FormSheet.swift"
        private let sizes = ["420x300"]
        private let english = "en"

        private func options(confirmIsEnabled: Bool = true) -> some View {
            FormSheet(
                Text(verbatim: "Export 340 Photos"),
                confirm: SheetAction(Text(verbatim: "Export"), isEnabled: confirmIsEnabled) {},
                cancel: SheetAction(Text(verbatim: "Cancel")) {},
            ) {
                Picker(selection: .constant(0)) {
                    Text(verbatim: "JPEG").tag(0)
                } label: {
                    Text(verbatim: "Format")
                }
                Toggle(isOn: .constant(true)) {
                    Text(verbatim: "Include camera metadata")
                }
            }
        }

        @Test func optionsAndTwoButtons() {
            #expect(Snapshot.verify("FormSheet", sizes: sizes, state: "options", locale: english, source: source) {
                options()
            } == [])
        }

        @Test func aDefaultButtonThatWaits() {
            #expect(Snapshot.verify("FormSheet", sizes: sizes, state: "waiting", locale: english, source: source) {
                options(confirmIsEnabled: false)
            } == [])
        }

        /// Something going on: a message, a progress, and the one button that stops it.
        @Test func progressAndOneButton() {
            #expect(Snapshot.verify("FormSheet", sizes: sizes, state: "progress", locale: english, source: source) {
                FormSheet(
                    Text(verbatim: "Developing"), message: Text(verbatim: "The files go beside the originals."),
                    confirm: nil, cancel: SheetAction(Text(verbatim: "Stop")) {},
                ) {
                    ProgressView(value: 0.35) {
                        Text(verbatim: "120 of 340 · DSC_4836.NEF")
                    }
                }
            } == [])
        }

        @Test func longText() {
            #expect(Snapshot.verify("FormSheet", sizes: sizes, state: "long-text", locale: english, source: source) {
                FormSheet(
                    Text(verbatim: "A title long enough to need a second line in a sheet as narrow as this one is"),
                    message: Text(verbatim: "A message that explains at some length what is about to happen, and wraps."),
                    confirm: SheetAction(Text(verbatim: "A long default button")) {},
                    cancel: SheetAction(Text(verbatim: "A long way out")) {},
                ) {
                    Toggle(isOn: .constant(false)) {
                        Text(verbatim: "An option with a long title beside its switch")
                    }
                }
            } == [])
        }

        @Test func rightToLeft() {
            #expect(Snapshot.verify("FormSheet", sizes: sizes, state: "options", locale: "ar", source: source) {
                options()
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

    @MainActor
    struct SearchFieldSnapshots {
        private let source = "\(components)/SearchField.swift"
        /// The width of the film list it sits on.
        private let sizes = ["300x52"]

        private func field(_ text: String, prompt: String = "Search") -> some View {
            SearchField("Search films", prompt: prompt, text: .constant(text))
                .padding(Spacing.m)
        }

        @Test func empty() {
            #expect(Snapshot.verify("SearchField", sizes: sizes, state: "empty", source: source) {
                field("")
            } == [])
        }

        @Test func typed() {
            #expect(Snapshot.verify("SearchField", sizes: sizes, state: "typed", source: source) {
                field("Portra")
            } == [])
        }

        @Test func longText() {
            #expect(Snapshot.verify("SearchField", sizes: sizes, state: "long-text", source: source) {
                field("", prompt: "A long prompt that has more words than the field has room for")
            } == [])
        }

        @Test func disabled() {
            #expect(Snapshot.verify("SearchField", sizes: sizes, state: "disabled", source: source) {
                field("Portra").disabled(true)
            } == [])
        }

        @Test func rightToLeft() {
            #expect(Snapshot.verify("SearchField", sizes: sizes, state: "typed", locale: "ar", source: source) {
                field("Portra")
            } == [])
        }
    }
}
