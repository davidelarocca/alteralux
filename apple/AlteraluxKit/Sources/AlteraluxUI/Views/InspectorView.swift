import AlteraluxEngine
import AlteraluxKit
import DesignSystem
import SwiftUI

/// The adjustments, in a form of the system's controls, in the order of the analog process
/// (ADR 0016): the film's name as the heading, then the shot (the photo as the camera took it,
/// set right before the film sees it), the film, the print and the scan. A collapsed section shows
/// its values.
struct InspectorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    @AppStorage("inspector.shot.isExpanded") private var showsShot = true
    @AppStorage("inspector.film.isExpanded") private var showsFilm = true
    @AppStorage("inspector.print.isExpanded") private var showsPrint = true
    @AppStorage("inspector.scan.isExpanded") private var showsScan = true
    /// The inspector's height: the film list grows with it.
    @State private var height: CGFloat?

    var body: some View {
        @Bindable var model = model
        let summary = InspectorSummary(
            settings: model.settings, locale: locale, blackAndWhitePrint: model.selectedPaper?.isBlackAndWhite == true,
        )

        Form {
            FilmHeading(paneHeight: height)
            InspectorSection(
                "Shot", isExpanded: $showsShot, summary: summary.shot(whiteBalance: shownWhiteBalance),
                isModified: model.isModified(.shot), reset: model.resetter(.shot),
            ) {
                ExposureControls(settings: $model.settings)
                WhiteBalanceControls()
                LensControls(settings: $model.settings)
            }
            if showsShot {
                ShotDetails(settings: $model.settings)
            }
            InspectorSection(
                "Film", isExpanded: $showsFilm, summary: summary.film(formatName: formatName),
                isModified: model.isModified(.film), reset: model.resetter(.film),
            ) {
                FilmControls(settings: $model.settings, developmentTimes: model.filmDevelopmentTimes)
            }
            if showsFilm {
                FilmDetails(settings: $model.settings)
            }
            InspectorSection(
                "Print", isExpanded: $showsPrint, summary: summary.print,
                isModified: model.isModified(.print), reset: model.resetter(.print),
            ) {
                PrintControls(
                    settings: $model.settings, isBlackAndWhite: model.selectedPaper?.isBlackAndWhite == true,
                    developmentTimes: model.printDevelopmentTimes,
                )
            }
            if showsPrint, !model.settings.scanFilm {
                PrintDetails(settings: $model.settings)
            }
            InspectorSection(
                "Scan", isExpanded: $showsScan, summary: summary.scan,
                isModified: model.isModified(.scan), reset: model.resetter(.scan),
            ) {
                ParameterSlider(
                    "Sharpening", value: $model.settings.sharpenAmount, in: 0 ... 2,
                    step: 0.05, defaultValue: 0.7,
                )
                .help("How much the scanner sharpens the edges; 0 leaves the scan as soft as the film made it.")
            }
            if showsScan {
                ScanDetails(settings: $model.settings)
            }
            Section {
                Button("Reset Adjustments") { model.resetAdjustments() }
            }
        }
        .formStyle(.grouped)
        // Thin scroll bars, as the photo's: wide ones would stay with a mouse.
        .thinScrollBars()
        // The same margin on both sides, wide enough for the scroll bar when the system always
        // shows it: the controls keep clear of it and the form stays centered without it.
        .contentMargins(.horizontal, Spacing.s, for: .scrollContent)
        .disabled(model.films.isEmpty)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
    }

    /// The white balance the shot section's summary shows: `nil` when it cannot be chosen.
    private var shownWhiteBalance: InspectorSummary.ShownWhiteBalance? {
        guard model.canAdjustWhiteBalance else { return nil }
        return .init(
            value: WhiteBalance(temperature: model.temperature, tint: model.tint),
            isAutomatic: model.isWhiteBalanceAutomatic,
        )
    }

    /// The film format in the reader's language, for the summary of the film section.
    private var formatName: String {
        guard let format = FilmFormat(rawValue: model.settings.filmFormatMM) else { return "" }
        return String(localized: format.title)
    }
}

/// The film as the heading of the inspector: the look the photo takes.
private struct FilmHeading: View {
    @Environment(AppModel.self) private var model
    /// The inspector's height, for the film list to grow with it.
    let paneHeight: CGFloat?
    @State private var showsFilms = false

    var body: some View {
        Section {
            HeadingButton(caption: caption, title: model.selectedFilm?.displayName ?? "") {
                showsFilms = true
            }
            .help("Choose the film")
            .popover(isPresented: $showsFilms, arrowEdge: .bottom) {
                FilmPicker(paneHeight: paneHeight)
            }
        }
    }

    /// "Film · color negative · ISO 400": what the name under it is.
    private var caption: Text {
        guard let film = model.selectedFilmEntry else { return Text("Film") }
        let kind = switch film.kind {
        case .colorNegative: Text("Film · color negative")
        case .slide: Text("Film · slide")
        case .blackAndWhite: Text("Film · black and white")
        case .motionPicture: Text("Film · motion picture")
        }
        guard let iso = film.look.iso else { return kind }
        return Text("\(kind) · ISO \(Text(verbatim: String(iso)))")
    }
}

/// The film: its frame, its development and its grain. Its halation is with the lens, in the shot
/// (ADR 0018).
private struct FilmControls: View {
    @Binding var settings: DevelopSettings
    /// The times the film was measured at, when it can be developed for longer or shorter.
    let developmentTimes: [Double]

    var body: some View {
        WindowPopUp(
            "Film format", selection: $settings.filmFormatMM,
            options: FilmFormat.allCases.map { WindowPopUpOption($0.rawValue, title: String(localized: $0.title)) },
        )
        .help("Smaller formats show more grain and wider halos.")
        if !developmentTimes.isEmpty {
            DevelopmentTimePicker("Development", time: $settings.filmDevelopmentTime, times: developmentTimes)
                .help("Developed longer, the film gains contrast; shorter, it loses it.")
        }
        ParameterSlider(
            "Grain size", value: $settings.grainParticleArea, in: 0.05 ... 1,
            defaultValue: 0.2, isOn: $settings.grainEnabled, unit: "µm²",
        )
        .help("The size of the film's silver grains: larger is coarser and more visible.")
    }
}

/// The print: whether there is one and whether the lab compensates the exposure, its paper, and
/// how it is exposed and filtered under the enlarger: what spektrafilm's own interface has in view.
private struct PrintControls: View {
    @Environment(AppModel.self) private var model
    @Binding var settings: DevelopSettings
    /// A black and white paper has no color to filter.
    let isBlackAndWhite: Bool
    /// The times the paper was measured at, when it can be developed for longer or shorter.
    let developmentTimes: [Double]

    var body: some View {
        Toggle("Scan the film directly", isOn: $settings.scanFilm)
            .help("Skip the print. The usual choice for slide film.")
        if !settings.scanFilm {
            Toggle("The lab compensates the exposure", isOn: $settings.printCompensatesExposure)
                .help("Prints to a normal density, as a lab would: the shot's exposure then changes the negative, not the brightness.")
            // The paper's name is long: it gets the row's whole width, under its caption.
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Paper")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                WindowPopUp(
                    "Paper", selection: Binding(get: { settings.paperID }, set: { model.choosePaper($0) }),
                    options: model.papers.map { WindowPopUpOption($0.id, title: $0.displayName) },
                )
                .labelsHidden()
                .fixedSize(horizontal: false, vertical: true)
            }
            .help("The paper the negative is printed on: its contrast and its colors.")
            ParameterSlider(
                "Print exposure", value: stops($settings.printExposure), in: -2.3 ... 1.5,
                step: 0.1, fractionDigits: 1, showsSign: true, unit: "stop", ends: SliderEnds("Lighter", "Darker"),
            )
            .help("How long the paper is exposed under the enlarger: more light makes a darker print.")
            if !isBlackAndWhite {
                ParameterSlider(
                    "Yellow filter", value: $settings.yellowFilterShift, in: -50 ... 50,
                    step: 1, fractionDigits: 0, showsSign: true, ends: SliderEnds("Yellower", "Bluer"),
                )
                .help("The enlarger's yellow filter: more filter makes the print bluer, less makes it yellower.")
                ParameterSlider(
                    "Magenta filter", value: $settings.magentaFilterShift, in: -50 ... 50,
                    step: 1, fractionDigits: 0, showsSign: true, ends: SliderEnds("More magenta", "Greener"),
                )
                .help("The enlarger's magenta filter: more filter makes the print greener, less makes it more magenta.")
            }
            if !developmentTimes.isEmpty {
                DevelopmentTimePicker("Paper development", time: $settings.printDevelopmentTime, times: developmentTimes)
                    .help("Developed longer, the paper gains contrast; shorter, it loses it.")
            }
        }
    }
}

/// A multiplier of exposure as stops: 2 is +1, 0.5 is -1.
private func stops(_ multiplier: Binding<Double>) -> Binding<Double> {
    Binding(
        get: { log2(max(multiplier.wrappedValue, 0.01)) },
        set: { multiplier.wrappedValue = pow(2, $0) },
    )
}

/// The time a black and white material is developed for, among those it was measured at. With
/// none chosen the engine takes the middle one, which the picker shows.
private struct DevelopmentTimePicker: View {
    private let title: LocalizedStringKey
    @Binding private var time: Double?
    private let times: [Double]

    init(_ title: LocalizedStringKey, time: Binding<Double?>, times: [Double]) {
        self.title = title
        _time = time
        self.times = times
    }

    var body: some View {
        WindowPopUp(
            title, selection: Binding(get: { time ?? times[(times.count - 1) / 2] }, set: { time = $0 }),
            options: times.map { minutes in
                WindowPopUpOption(
                    minutes,
                    title: Measurement(value: minutes, unit: UnitDuration.minutes).formatted(.measurement(width: .abbreviated)),
                )
            },
        )
    }
}
