import SpektrafilmEngine
import SpektrafilmKit
import SwiftUI

/// The adjustments, grouped in the order light travels: materials, camera,
/// print, film character, scan.
struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Materials") {
                Picker("Film", selection: $model.settings.filmID) {
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

            Section("Camera") {
                ParameterSlider(
                    title: "Exposure", value: $model.settings.exposureEV, range: -5...5,
                    step: 0.1, fractionDigits: 1, showsSign: true)
                Toggle("Automatic metering", isOn: $model.settings.autoExposure)
                Picker("Film format", selection: $model.settings.filmFormatMM) {
                    Text("110").tag(17.0)
                    Text("35 mm").tag(35.0)
                    Text("Medium format").tag(60.0)
                    Text("Large format").tag(120.0)
                }
                .help("Smaller formats show more grain and wider halos.")
            }

            if !model.settings.scanFilm {
                Section("Print") {
                    ParameterSlider(
                        title: "Print exposure", value: $model.settings.printExposure,
                        range: 0.2...3, step: 0.01, defaultValue: 1)
                    ParameterSlider(
                        title: "Yellow filter", value: $model.settings.yellowFilterShift,
                        range: -50...50, step: 1, fractionDigits: 0, showsSign: true)
                    ParameterSlider(
                        title: "Magenta filter", value: $model.settings.magentaFilterShift,
                        range: -50...50, step: 1, fractionDigits: 0, showsSign: true)
                }
            }

            Section("Film Character") {
                Toggle("Grain", isOn: $model.settings.grainEnabled)
                if model.settings.grainEnabled {
                    ParameterSlider(
                        title: "Grain size", value: $model.settings.grainParticleArea,
                        range: 0.05...1, step: 0.01, defaultValue: 0.2)
                }
                Toggle("Halation", isOn: $model.settings.halationEnabled)
                    .help("The red glow around bright lights.")
                if model.settings.halationEnabled {
                    ParameterSlider(
                        title: "Halation strength", value: $model.settings.halationAmount,
                        range: 0...3, step: 0.05, defaultValue: 1)
                }
            }

            Section("Scan") {
                ParameterSlider(
                    title: "Sharpening", value: $model.settings.sharpenAmount,
                    range: 0...2, step: 0.05, defaultValue: 0.7)
            }

            Section {
                Button("Reset Adjustments") { model.resetAdjustments() }
            } footer: {
                Text(model.renderSummary)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .disabled(model.films.isEmpty)
    }
}
