import Foundation

/// The parts of a photo's adjustments, as the inspector's sections group them (ADR 0016, ADR 0018).
/// A part also holds what the inspector no longer shows, so that a section's reset puts it back.
public enum DevelopPart: CaseIterable, Sendable {
    /// What is set before the film: exposure and metering, the scene's highlights and shadows,
    /// white balance, the RAW decoder, the lens with the halation, and the diffusion filter. The frame is not part of it: the crop
    /// controls own it.
    case shot
    /// The film's format, development, grain and couplers. The film itself is the
    /// heading's choice, not this part's.
    case film
    /// The print: its exposure, filters, development, pre-flash, glare,
    /// curves and the lab's compensation. The paper and whether there is a print are not part of it.
    case print
    /// The scan: sharpening, the scanner, its white and black points, and the color options.
    case scan
}

public extension DevelopSettings {
    /// These adjustments with `part` back to how a new photo starts, the rest as it is.
    func resetting(_ part: DevelopPart) -> DevelopSettings {
        var result = self
        let start = DevelopSettings()
        switch part {
        case .shot:
            result.exposureEV = start.exposureEV
            result.autoExposure = start.autoExposure
            result.meteringMethod = start.meteringMethod
            result.sceneTone = start.sceneTone
            result.temperature = start.temperature
            result.tint = start.tint
            result.autoWhiteBalance = start.autoWhiteBalance
            result.lensCorrection = start.lensCorrection
            result.rawDecoding = start.rawDecoding
            result.lensBlur = start.lensBlur
            result.diffusionFilter = start.diffusionFilter
            result.halationEnabled = start.halationEnabled
            result.halationAmount = start.halationAmount
            result.scatterAmount = start.scatterAmount
            result.halationDetail = start.halationDetail
        case .film:
            result.filmFormatMM = start.filmFormatMM
            result.filmDevelopmentTime = start.filmDevelopmentTime
            result.grainEnabled = start.grainEnabled
            result.grainParticleArea = start.grainParticleArea
            result.grainDetail = start.grainDetail
            result.couplersEnabled = start.couplersEnabled
            result.couplersAmount = start.couplersAmount
            result.couplersDetail = start.couplersDetail
        case .print:
            result.printExposure = start.printExposure
            result.yellowFilterShift = start.yellowFilterShift
            result.magentaFilterShift = start.magentaFilterShift
            result.printDevelopmentTime = start.printDevelopmentTime
            result.preflashExposure = start.preflashExposure
            result.preflashYellowShift = start.preflashYellowShift
            result.preflashMagentaShift = start.preflashMagentaShift
            result.printCompensatesExposure = start.printCompensatesExposure
            result.printGlare = start.printGlare
            result.printCurves = start.printCurves
        case .scan:
            result.sharpenAmount = start.sharpenAmount
            result.sharpenRadius = start.sharpenRadius
            result.scanner = start.scanner
            result.color = start.color
        }
        return result
    }

    /// Whether `part` is as a new photo starts.
    func isAtStart(_ part: DevelopPart) -> Bool {
        resetting(part) == self
    }
}
