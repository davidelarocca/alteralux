import AlteraluxKit
import Foundation
import Testing
@testable import AlteraluxUI

/// What a collapsed section of the inspector shows beside its title.
struct InspectorSummaryTests {
    private func settings() -> DevelopSettings {
        var settings = DevelopSettings()
        settings.exposureEV = 0.3
        settings.printExposure = 1.15
        settings.yellowFilterShift = -12
        settings.grainParticleArea = 0.35
        return settings
    }

    @Test func valuesAreWrittenAsTheirControlsWriteThem() {
        let summary = InspectorSummary(settings: settings(), locale: Locale(identifier: "en_US"))
        #expect(summary.shot() == "Auto +0.3 EV")
        #expect(summary.film(formatName: "35 mm") == "35 mm · 0.35 · 1.00")
        #expect(summary.print == "+0.2 stop · -12 · 0")
        #expect(summary.scan == "0.70")
    }

    /// A RAW shows its white balance first, as the section does. A temperature is one number.
    @Test func theShotSectionShowsTheWhiteBalanceOfARaw() {
        let whiteBalance = InspectorSummary.ShownWhiteBalance(
            value: WhiteBalance(temperature: 5234.6, tint: 7.7), isAutomatic: false,
        )
        let english = InspectorSummary(settings: settings(), locale: Locale(identifier: "en_US"))
        #expect(english.shot(whiteBalance: whiteBalance) == "5235 K · 8 · Auto +0.3 EV")
        let italian = InspectorSummary(settings: settings(), locale: Locale(identifier: "it_IT"))
        #expect(italian.shot(whiteBalance: whiteBalance) == "5235 K · 8 · Auto +0,3 EV")
    }

    @Test func numbersFollowTheLanguageOfTheView() {
        let summary = InspectorSummary(settings: settings(), locale: Locale(identifier: "it_IT"))
        #expect(summary.shot() == "Auto +0,3 EV")
        #expect(summary.scan == "0,70")
    }

    @Test func aParameterThatIsSwitchedOffShowsADash() {
        var settings = settings()
        settings.grainEnabled = false
        let summary = InspectorSummary(settings: settings, locale: Locale(identifier: "en_US"))
        #expect(summary.film(formatName: "35 mm") == "35 mm · – · 1.00")
    }

    /// The modes are said, not only the numbers.
    @Test func theAutomaticModesAreNamed() {
        var settings = settings()
        settings.autoExposure = false
        let automatic = InspectorSummary.ShownWhiteBalance(value: WhiteBalance(temperature: 5000, tint: 0), isAutomatic: true)
        let summary = InspectorSummary(settings: settings, locale: Locale(identifier: "en_US"))
        #expect(summary.shot(whiteBalance: automatic) == "Auto WB · +0.3 EV")
    }

    @Test func aFilmScannedDirectlyHasNoPrintValues() {
        var settings = settings()
        settings.scanFilm = true
        let summary = InspectorSummary(settings: settings, locale: Locale(identifier: "en_US"))
        #expect(summary.print == "Scanned directly")
    }
}
