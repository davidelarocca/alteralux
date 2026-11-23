import Foundation
import Testing
@testable import AlteraluxKit

/// The inspector's sections as parts of the adjustments: each is put back on its own, and only
/// it counts as changed.
struct DevelopPartsTests {
    private func edited() -> DevelopSettings {
        var settings = DevelopSettings()
        settings.filmID = "fujifilm_velvia_100"
        settings.paperID = "fujifilm_crystal_archive_typeii"
        settings.scanFilm = true
        settings.crop = PhotoCrop(left: 0.1, top: 0.1, width: 0.8, height: 0.8)
        settings.exposureEV = 1.2
        settings.temperature = 4300
        settings.diffusionFilter.enabled = true
        settings.grainParticleArea = 0.5
        settings.halationDetail.bounces = 5
        settings.printExposure = 1.4
        settings.printGlare.percent = 0.08
        settings.sharpenAmount = 1.1
        settings.color.outputGamut = .oklch
        return settings
    }

    @Test func eachPartIsPutBackAlone() {
        let settings = edited()
        let shot = settings.resetting(.shot)
        #expect(shot.exposureEV == 0 && shot.temperature == nil && !shot.diffusionFilter.enabled)
        // The halation is with the lens, in the shot.
        #expect(shot.halationDetail == HalationDetail())
        #expect(shot.grainParticleArea == 0.5 && shot.printExposure == 1.4)

        let film = settings.resetting(.film)
        #expect(film.grainParticleArea == 0.2 && film.halationDetail.bounces == 5)
        #expect(film.exposureEV == 1.2)

        let print = settings.resetting(.print)
        #expect(print.printExposure == 1 && print.printGlare == GlareSettings())
        #expect(print.sharpenAmount == 1.1)

        let scan = settings.resetting(.scan)
        #expect(scan.sharpenAmount == 0.7 && scan.color == ColorSettings())
        #expect(scan.printExposure == 1.4)
    }

    /// The materials and the frame belong to no section: no reset touches them.
    @Test func theMaterialsAndTheFrameStay() {
        let settings = edited()
        for part in DevelopPart.allCases {
            let reset = settings.resetting(part)
            #expect(reset.filmID == settings.filmID && reset.paperID == settings.paperID)
            #expect(reset.scanFilm == settings.scanFilm && reset.crop == settings.crop)
        }
    }

    @Test func aPartIsChangedUntilItIsPutBack() {
        let settings = edited()
        for part in DevelopPart.allCases {
            #expect(!settings.isAtStart(part), "\(part)")
            #expect(settings.resetting(part).isAtStart(part), "\(part)")
        }
        #expect(DevelopPart.allCases.allSatisfy { DevelopSettings().isAtStart($0) })
    }
}
