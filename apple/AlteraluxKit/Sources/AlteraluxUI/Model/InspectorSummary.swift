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
    /// Whether the paper is a black and white one, which has no color filters.
    var blackAndWhitePrint = false

    /// Between two values.
    private static let separator = " · "
    /// In place of a parameter that is switched off.
    private static let switchedOff = "–"

    /// The shot: the white balance of a RAW, then the exposure.
    ///
    /// - Parameter whiteBalance: the temperature and tint the sliders show; `nil` when the
    ///   photo's white balance cannot be chosen.
    func shot(whiteBalance: WhiteBalance? = nil) -> String {
        var values: [String] = []
        if let whiteBalance {
            values.append(number(whiteBalance.temperature, fractionDigits: 0))
            values.append(number(whiteBalance.tint, fractionDigits: 0))
        }
        values.append(number(settings.exposureEV, fractionDigits: 1, showsSign: true))
        return values.joined(separator: Self.separator)
    }

    /// The film: its format, grain and halation.
    ///
    /// - Parameter formatName: the film format as the reader's language names it.
    func film(formatName: String) -> String {
        [
            formatName,
            settings.grainEnabled ? number(settings.grainParticleArea, fractionDigits: 2) : Self.switchedOff,
            settings.halationEnabled ? number(settings.halationAmount, fractionDigits: 2) : Self.switchedOff,
        ].joined(separator: Self.separator)
    }

    /// The print's exposure and filters, or that there is no print.
    var print: String {
        guard !settings.scanFilm else { return String(localized: "Scanned directly", locale: locale) }
        guard !blackAndWhitePrint else {
            return number(settings.printExposure, fractionDigits: 2)
        }
        return [
            number(settings.printExposure, fractionDigits: 2),
            number(settings.yellowFilterShift, fractionDigits: 0, showsSign: true),
            number(settings.magentaFilterShift, fractionDigits: 0, showsSign: true),
        ].joined(separator: Self.separator)
    }

    var scan: String {
        number(settings.sharpenAmount, fractionDigits: 2)
    }

    private func number(_ value: Double, fractionDigits: Int, showsSign: Bool = false) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(fractionDigits))
                // A temperature is read as one number: "5200", not "5,200".
                .grouping(.never)
                .sign(strategy: showsSign ? .always(includingZero: false) : .automatic)
                .locale(locale),
        )
    }
}
