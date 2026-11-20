import AlteraluxKit
import Foundation

/// The film formats the inspector offers, by the width of their frame.
enum FilmFormat: Double, CaseIterable, Identifiable {
    case pocket = 17
    case small = 35
    case medium = 60
    case large = 120

    var id: Double {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .pocket: "110"
        case .small: "35 mm"
        case .medium: "Medium format"
        case .large: "Large format"
        }
    }
}

/// The values a collapsed section of the inspector shows beside its title, written as the
/// controls it hides write them.
struct InspectorSummary {
    let settings: DevelopSettings
    /// The language of the view, for the decimal separator.
    let locale: Locale

    /// Between two values.
    private static let separator = " · "
    /// In place of a parameter that is switched off.
    private static let switchedOff = "–"

    /// - Parameter formatName: the film format as the reader's language names it.
    func camera(formatName: String) -> String {
        [number(settings.exposureEV, fractionDigits: 1, showsSign: true), formatName]
            .joined(separator: Self.separator)
    }

    var print: String {
        [
            number(settings.printExposure, fractionDigits: 2),
            number(settings.yellowFilterShift, fractionDigits: 0, showsSign: true),
            number(settings.magentaFilterShift, fractionDigits: 0, showsSign: true),
        ].joined(separator: Self.separator)
    }

    var filmCharacter: String {
        [
            settings.grainEnabled ? number(settings.grainParticleArea, fractionDigits: 2) : Self.switchedOff,
            settings.halationEnabled ? number(settings.halationAmount, fractionDigits: 2) : Self.switchedOff,
        ].joined(separator: Self.separator)
    }

    var scan: String {
        number(settings.sharpenAmount, fractionDigits: 2)
    }

    private func number(_ value: Double, fractionDigits: Int, showsSign: Bool = false) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(fractionDigits))
                .sign(strategy: showsSign ? .always(includingZero: false) : .automatic)
                .locale(locale),
        )
    }
}
