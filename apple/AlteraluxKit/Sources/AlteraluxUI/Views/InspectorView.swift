import AlteraluxEngine
import AlteraluxKit
import DesignSystem
import SwiftUI

/// The adjustments, in a form of the system's controls. The film is the heading; under it the
/// sections follow the path of light: camera, print, film character, scan. A collapsed section
/// shows its values.
struct InspectorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    @AppStorage("inspector.camera.isExpanded") private var showsCamera = true
    @AppStorage("inspector.print.isExpanded") private var showsPrint = true
    @AppStorage("inspector.filmCharacter.isExpanded") private var showsFilmCharacter = true
    @AppStorage("inspector.scan.isExpanded") private var showsScan = true
    /// The inspector's height: the film list grows with it.
    @State private var height: CGFloat?

    var body: some View {
        @Bindable var model = model
        let summary = InspectorSummary(
            settings: model.settings, locale: locale, blackAndWhitePrint: model.selectedPaper?.isBlackAndWhite == true,
        )

        Form {
            MaterialsHeading(paneHeight: height)
            InspectorSection(
                "Camera", isExpanded: $showsCamera,
                summary: summary.camera(
                    formatName: formatName,
                    whiteBalance: model.canAdjustWhiteBalance
                        ? WhiteBalance(temperature: model.temperature, tint: model.tint) : nil,
                ),
            ) {
                WhiteBalanceControls()
                LensCorrectionToggle()
                CameraControls(settings: $model.settings, developmentTimes: model.filmDevelopmentTimes)
            }
            if !model.settings.scanFilm {
                InspectorSection("Print", isExpanded: $showsPrint, summary: summary.print) {
                    PrintControls(
                        settings: $model.settings, isBlackAndWhite: model.selectedPaper?.isBlackAndWhite == true,
                        developmentTimes: model.printDevelopmentTimes,
                    )
                }
            }
            InspectorSection(
                "Film Character", isExpanded: $showsFilmCharacter, summary: summary.filmCharacter,
            ) {
                FilmCharacterControls(settings: $model.settings)
            }
            InspectorSection("Scan", isExpanded: $showsScan, summary: summary.scan) {
                ParameterSlider(
                    "Sharpening", value: $model.settings.sharpenAmount, in: 0 ... 2,
                    step: 0.05, defaultValue: 0.7,
                )
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

    /// The film format in the reader's language, for the summary of the camera section.
    private var formatName: String {
        guard let format = FilmFormat(rawValue: model.settings.filmFormatMM) else { return "" }
        return String(localized: format.title)
    }
}

/// The film as the heading of the inspector, and what goes with it: the paper it is printed
/// on, or the choice to scan it directly.
private struct MaterialsHeading: View {
    @Environment(AppModel.self) private var model
    /// The inspector's height, for the film list to grow with it.
    let paneHeight: CGFloat?
    @State private var showsFilms = false

    var body: some View {
        @Bindable var model = model

        Section {
            HeadingButton(caption: caption, title: model.selectedFilm?.displayName ?? "") {
                showsFilms = true
            }
            .help("Choose the film")
            .popover(isPresented: $showsFilms, arrowEdge: .bottom) {
                FilmPicker(paneHeight: paneHeight)
            }
            if !model.settings.scanFilm {
                // The paper's name is long: it gets the row's whole width, under its caption,
                // as the film's name does above it.
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Paper")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                    WindowPopUp(
                        "Paper", selection: Binding(get: { model.settings.paperID }, set: { model.choosePaper($0) }),
                        options: model.papers.map { WindowPopUpOption($0.id, title: $0.displayName) },
                    )
                    .labelsHidden()
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle("Scan the film directly", isOn: $model.settings.scanFilm)
                .help("Skip the print. The usual choice for slide film.")
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

/// Temperature and tint: what the RAW decoder takes as neutral, before the film sees the
/// photo. They start from what the camera recorded and go back to it.
private struct WhiteBalanceControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let neutral = model.neutralWhiteBalance

        // A photo that is not a RAW has its white balance in its pixels: a line says so, in
        // place of two sliders that could not move.
        if model.whiteBalanceIsFixed {
            Text("White balance can be chosen for RAW photos only.")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        } else {
            Group {
                Toggle("Automatic white balance", isOn: $model.isWhiteBalanceAutomatic)
                    .help("Start from the light measured in the photo where the camera's white balance is far from it.")
                if model.isWhiteBalanceAutomatic, model.cameraChoseWhiteBalance {
                    Text("The camera chose this white balance itself, from the scene: it is kept.")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
                ParameterSlider(
                    "Temperature", value: $model.temperature, in: model.temperatureRange,
                    step: AppModel.temperatureStep, defaultValue: neutral.temperature, fractionDigits: 0,
                )
                .help("The color of the light, in kelvin. Lower values make the photo cooler.")
                ParameterSlider(
                    "Tint", value: $model.tint, in: AppModel.tintRange,
                    step: AppModel.tintStep, defaultValue: neutral.tint, fractionDigits: 0,
                )
            }
            .disabled(!model.canAdjustWhiteBalance)
        }
    }
}

/// Whether the lens is corrected, where the RAW decoder, the camera's own data or a lens profile
/// know this camera's lens, with a line that says which of the last two does; otherwise a line
/// says there is nothing to correct with.
private struct LensCorrectionToggle: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Toggle("Lens correction", isOn: $model.isLensCorrected)
            .disabled(!model.correctsLens)
            .help("Straightens the lens's curved lines, brightens its darker corners and takes away its colored fringes.")
        if model.hasPhoto, !model.correctsLens {
            Text("No correction is known for this photo's lens.")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        } else if let correction = model.cameraLensCorrection {
            CameraCorrectionLine(correction: correction)
        } else if let lens = model.lensProfileName {
            Text("Lensfun profile: \(lens)")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Who corrects the lens when the camera recorded some of it: the camera alone, or with lensfun,
/// or only the vignetting after Apple's decoder.
private struct CameraCorrectionLine: View {
    let correction: CameraLensCorrection

    var body: some View {
        let lens = correction.lensName
        Group {
            switch (correction.geometrySource, correction.vignettingSource) {
            case (.apple, _):
                Text("Vignetting corrected with the camera's data")
            case (.lensfun, _):
                Text("Lensfun profile, vignetting from the camera: \(lens)")
            case (_, .lensfun):
                Text("Camera's own correction, vignetting from lensfun: \(lens)")
            default:
                Text("Camera's own correction: \(lens)")
            }
        }
        .font(Typography.caption)
        .foregroundStyle(.secondary)
    }
}

private struct CameraControls: View {
    @Binding var settings: DevelopSettings
    /// The times the film was measured at, when it can be developed for longer or shorter.
    let developmentTimes: [Double]

    var body: some View {
        ParameterSlider(
            "Exposure", value: $settings.exposureEV, in: -5 ... 5,
            step: 0.1, fractionDigits: 1, showsSign: true,
        )
        Toggle("Automatic metering", isOn: $settings.autoExposure)
        WindowPopUp(
            "Film format", selection: $settings.filmFormatMM,
            options: FilmFormat.allCases.map { WindowPopUpOption($0.rawValue, title: String(localized: $0.title)) },
        )
        .help("Smaller formats show more grain and wider halos.")
        if !developmentTimes.isEmpty {
            DevelopmentTimePicker("Development", time: $settings.filmDevelopmentTime, times: developmentTimes)
                .help("Developed longer, the film gains contrast; shorter, it loses it.")
        }
    }
}

private struct PrintControls: View {
    @Binding var settings: DevelopSettings
    /// A black and white paper has no color to filter.
    let isBlackAndWhite: Bool
    /// The times the paper was measured at, when it can be developed for longer or shorter.
    let developmentTimes: [Double]

    var body: some View {
        ParameterSlider("Print exposure", value: $settings.printExposure, in: 0.2 ... 3, defaultValue: 1)
        if !isBlackAndWhite {
            ParameterSlider(
                "Yellow filter", value: $settings.yellowFilterShift, in: -50 ... 50,
                step: 1, fractionDigits: 0, showsSign: true,
            )
            ParameterSlider(
                "Magenta filter", value: $settings.magentaFilterShift, in: -50 ... 50,
                step: 1, fractionDigits: 0, showsSign: true,
            )
        }
        if !developmentTimes.isEmpty {
            DevelopmentTimePicker("Paper development", time: $settings.printDevelopmentTime, times: developmentTimes)
        }
    }
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

/// Grain and halation: each can be switched off, with its switch on the slider's row.
private struct FilmCharacterControls: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        ParameterSlider(
            "Grain", value: $settings.grainParticleArea, in: 0.05 ... 1,
            defaultValue: 0.2, isOn: $settings.grainEnabled,
        )
        ParameterSlider(
            "Halation", value: $settings.halationAmount, in: 0 ... 3,
            step: 0.05, defaultValue: 1, isOn: $settings.halationEnabled,
        )
        .help("The red glow around bright lights.")
    }
}
