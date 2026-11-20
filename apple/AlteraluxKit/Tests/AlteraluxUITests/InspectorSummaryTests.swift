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
        #expect(summary.camera(formatName: "35 mm") == "+0.3 · 35 mm")
        #expect(summary.print == "1.15 · -12 · 0")
        #expect(summary.filmCharacter == "0.35 · 1.00")
        #expect(summary.scan == "0.70")
    }

    /// A RAW shows its white balance first, as the section does. A temperature is one number.
    @Test func theCameraSectionShowsTheWhiteBalanceOfARaw() {
        let whiteBalance = WhiteBalance(temperature: 5234.6, tint: 7.7)
        let english = InspectorSummary(settings: settings(), locale: Locale(identifier: "en_US"))
        #expect(english.camera(formatName: "35 mm", whiteBalance: whiteBalance) == "5235 · 8 · +0.3 · 35 mm")
        let italian = InspectorSummary(settings: settings(), locale: Locale(identifier: "it_IT"))
        #expect(italian.camera(formatName: "35 mm", whiteBalance: whiteBalance) == "5235 · 8 · +0,3 · 35 mm")
    }

    @Test func numbersFollowTheLanguageOfTheView() {
        let summary = InspectorSummary(settings: settings(), locale: Locale(identifier: "it_IT"))
        #expect(summary.camera(formatName: "35 mm") == "+0,3 · 35 mm")
        #expect(summary.scan == "0,70")
    }

    @Test func aParameterThatIsSwitchedOffShowsADash() {
        var settings = settings()
        settings.grainEnabled = false
        let summary = InspectorSummary(settings: settings, locale: Locale(identifier: "en_US"))
        #expect(summary.filmCharacter == "– · 1.00")
    }
}
