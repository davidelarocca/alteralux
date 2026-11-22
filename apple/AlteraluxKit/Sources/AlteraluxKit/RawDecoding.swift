import CoreImage
import Foundation

/// What Apple's RAW decoder does to a photo before the film sees it, beyond its white balance and
/// lens: highlight recovery and noise reduction (ADR 0016). Each `nil` leaves the decoder's own
/// choice for the photo's camera, which `RawDecodingDefaults` reads.
///
/// Noise belongs to the sensor and its sensitivity, as the white balance belongs to the light: a
/// recipe leaves these as the photo has them.
public struct RawDecodingOptions: Codable, Equatable, Sendable {
    /// Rebuilds the colors of the highlights where one of the sensor's channels clipped.
    public var highlightRecovery: Bool?
    /// From 0 to 1.
    public var luminanceNoiseReduction: Double?
    /// From 0 to 1.
    public var colorNoiseReduction: Double?
    /// From 0 to 1.
    public var moireReduction: Double?

    public init(
        highlightRecovery: Bool? = nil, luminanceNoiseReduction: Double? = nil, colorNoiseReduction: Double? = nil,
        moireReduction: Double? = nil,
    ) {
        self.highlightRecovery = highlightRecovery
        self.luminanceNoiseReduction = luminanceNoiseReduction
        self.colorNoiseReduction = colorNoiseReduction
        self.moireReduction = moireReduction
    }
}

/// What the RAW decoder offers for one photo, and does when not told: `nil` for what it does not
/// offer for this photo's camera.
public struct RawDecodingDefaults: Equatable, Sendable {
    public let highlightRecovery: Bool?
    public let luminanceNoiseReduction: Double?
    public let colorNoiseReduction: Double?
    public let moireReduction: Double?

    /// Read from a decoder that has not been told anything yet.
    init(filter: CIRAWFilter) {
        highlightRecovery = filter.isHighlightRecoverySupported ? filter.isHighlightRecoveryEnabled : nil
        luminanceNoiseReduction = filter.isLuminanceNoiseReductionSupported
            ? Double(filter.luminanceNoiseReductionAmount) : nil
        colorNoiseReduction = filter.isColorNoiseReductionSupported ? Double(filter.colorNoiseReductionAmount) : nil
        moireReduction = filter.isMoireReductionSupported ? Double(filter.moireReductionAmount) : nil
    }

    /// Whether the decoder offers any of these for the photo.
    public var offersAny: Bool {
        highlightRecovery != nil || luminanceNoiseReduction != nil || colorNoiseReduction != nil || moireReduction != nil
    }

    /// Tells `filter` what `options` ask, and the photo's defaults for what they leave: the
    /// decoder is kept between decodes, so a choice taken back must be put back too.
    func apply(_ options: RawDecodingOptions, to filter: CIRAWFilter) {
        if let highlightRecovery {
            filter.isHighlightRecoveryEnabled = options.highlightRecovery ?? highlightRecovery
        }
        if let luminanceNoiseReduction {
            filter.luminanceNoiseReductionAmount = Float(options.luminanceNoiseReduction ?? luminanceNoiseReduction)
        }
        if let colorNoiseReduction {
            filter.colorNoiseReductionAmount = Float(options.colorNoiseReduction ?? colorNoiseReduction)
        }
        if let moireReduction {
            filter.moireReductionAmount = Float(options.moireReduction ?? moireReduction)
        }
    }
}
