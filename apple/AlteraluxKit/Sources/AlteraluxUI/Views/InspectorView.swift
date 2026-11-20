import AlteraluxEngine
import AlteraluxKit
import DesignSystem
import SwiftUI

/// The adjustments, grouped in the order light travels: materials, camera,
/// print, film character, scan.
struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
            MaterialsSection()
            CameraSection(settings: $model.settings)
            if !model.settings.scanFilm {
                PrintSection(settings: $model.settings)
            }
            FilmCharacterSection(settings: $model.settings)
            Section("Scan") {
                ParameterSlider(
                    "Sharpening", value: $model.settings.sharpenAmount, in: 0 ... 2,
                    step: 0.05, defaultValue: 0.7,
                )
            }
            Section {
                Button("Reset Adjustments") { model.resetAdjustments() }
            } footer: {
                Text(model.renderSummary)
                    .font(Typography.technical)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .disabled(model.films.isEmpty)
    }
}

/// Film, paper, and whether the film is scanned directly.
private struct MaterialsSection: View {
    @Environment(AppModel.self) private var model

    /// Choosing a film also applies its defaults (paper, direct scan).
    private var filmSelection: Binding<String> {
        Binding(
            get: { model.settings.filmID },
            set: { model.chooseFilm($0) },
        )
    }

    var body: some View {
        @Bindable var model = model

        Section("Materials") {
            Picker("Film", selection: filmSelection) {
                ForEach(model.films, id: \.id) { film in
                    Text(film.displayName).tag(film.id)
                }
            }
            if !model.settings.scanFilm {
                Picker("Paper", selection: $model.settings.paperID) {
                    ForEach(model.papers, id: \.id) { paper in
                        Text(paper.displayName).tag(paper.id)
                    }
                }
            }
            Toggle("Scan the film directly", isOn: $model.settings.scanFilm)
                .help("Skip the print. The usual choice for slide film.")
        }
    }
}

private struct CameraSection: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        Section("Camera") {
            ParameterSlider(
                "Exposure", value: $settings.exposureEV, in: -5 ... 5,
                step: 0.1, fractionDigits: 1, showsSign: true,
            )
            Toggle("Automatic metering", isOn: $settings.autoExposure)
            Picker("Film format", selection: $settings.filmFormatMM) {
                Text("110").tag(17.0)
                Text("35 mm").tag(35.0)
                Text("Medium format").tag(60.0)
                Text("Large format").tag(120.0)
            }
            .help("Smaller formats show more grain and wider halos.")
        }
    }
}

private struct PrintSection: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        Section("Print") {
            ParameterSlider("Print exposure", value: $settings.printExposure, in: 0.2 ... 3, defaultValue: 1)
            ParameterSlider(
                "Yellow filter", value: $settings.yellowFilterShift, in: -50 ... 50,
                step: 1, fractionDigits: 0, showsSign: true,
            )
            ParameterSlider(
                "Magenta filter", value: $settings.magentaFilterShift, in: -50 ... 50,
                step: 1, fractionDigits: 0, showsSign: true,
            )
        }
    }
}

private struct FilmCharacterSection: View {
    @Binding var settings: DevelopSettings

    var body: some View {
        Section("Film Character") {
            Toggle("Grain", isOn: $settings.grainEnabled)
            if settings.grainEnabled {
                ParameterSlider("Grain size", value: $settings.grainParticleArea, in: 0.05 ... 1, defaultValue: 0.2)
            }
            Toggle("Halation", isOn: $settings.halationEnabled)
                .help("The red glow around bright lights.")
            if settings.halationEnabled {
                ParameterSlider(
                    "Halation strength", value: $settings.halationAmount, in: 0 ... 3,
                    step: 0.05, defaultValue: 1,
                )
            }
        }
    }
}
