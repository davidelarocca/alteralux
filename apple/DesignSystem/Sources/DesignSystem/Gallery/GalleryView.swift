import SwiftUI

/// Every component of the design system in every state: the visual inventory.
/// Shown from Xcode previews; not meant for reuse in the app.
public struct GalleryView: View {
    @State private var exposure = 0.3
    @State private var filter = -12.0
    @State private var grain = 0.35
    @State private var grainIsOn = true
    @State private var showsSection = false

    public init() {}

    public var body: some View {
        Form {
            Section("ParameterSlider") {
                ParameterSlider("Exposure", value: $exposure, in: -5 ... 5, step: 0.1, fractionDigits: 1, showsSign: true)
                ParameterSlider("Yellow filter", value: $filter, in: -50 ... 50, step: 1, fractionDigits: 0, showsSign: true)
                ParameterSlider("Grain", value: $grain, in: 0.05 ... 1, defaultValue: 0.2, isOn: $grainIsOn)
            }
            Section("HeadingButton") {
                HeadingButton(caption: Text("Film · color negative · ISO 400"), title: "Kodak Portra 400") {}
            }
            InspectorSection("InspectorSection", isExpanded: $showsSection, summary: "+0.3 · 35 mm") {
                ParameterSlider("Exposure", value: $exposure, in: -5 ... 5, step: 0.1, fractionDigits: 1, showsSign: true)
            }
            Section("FilmEmblem") {
                HStack(spacing: Spacing.s) {
                    FilmEmblem(ground: .violet, band: .cream, label: "400")
                    FilmEmblem(ground: .gold, band: .bronze, label: "200")
                    FilmEmblem(ground: .petrol, band: .sky, label: "250D")
                    FilmEmblem(ground: .plain, band: .ash, label: "")
                }
            }
            Section("ThumbnailCell") {
                HStack(spacing: Spacing.s) {
                    ThumbnailCell(image: nil, isSelected: false)
                    ThumbnailCell(image: nil, isSelected: true)
                }
            }
            Section("StatusBadge") {
                StatusBadge("Original")
            }
            Section("FormSheet") {
                FormSheet(
                    Text("Save as New Recipe"), message: Text("The recipe keeps the look of this photo."),
                    confirm: SheetAction(Text("Save")) {}, cancel: SheetAction(Text("Cancel")) {},
                ) {
                    TextField("Name", text: .constant("Warm evening"))
                }
            }
            Section("Colors") {
                swatch("viewerSurround", Color.DS.viewerSurround)
                swatch("thumbnailPlaceholder", Color.DS.thumbnailPlaceholder)
                swatch("hairline", Color.DS.hairline)
            }
        }
        .formStyle(.grouped)
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        LabeledContent(name) {
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(color)
                .frame(width: ThumbnailCell.size.width, height: Spacing.xl)
        }
    }
}

#Preview("Gallery") {
    GalleryView()
        .frame(width: 420, height: 560)
}
