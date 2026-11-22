import AlteraluxKit
import Foundation

// The RAW decoder's highlight recovery and noise reduction for the selected photo (ADR 0016): each
// shows the decoder's own choice for the photo's camera until it is changed, and goes back to `nil`
// when it is set to that choice again.

extension AppModel {
    /// What the RAW decoder offers the selected photo; `nil` while no RAW is open.
    var rawDefaults: RawDecodingDefaults? {
        sources?.decoder.rawDefaults
    }

    var highlightRecovery: Bool {
        get { settings.rawDecoding.highlightRecovery ?? rawDefaults?.highlightRecovery ?? true }
        set { settings.rawDecoding.highlightRecovery = newValue == rawDefaults?.highlightRecovery ? nil : newValue }
    }

    var luminanceNoiseReduction: Double {
        get { settings.rawDecoding.luminanceNoiseReduction ?? rawDefaults?.luminanceNoiseReduction ?? 0 }
        set { settings.rawDecoding.luminanceNoiseReduction = Self.choice(newValue, default: rawDefaults?.luminanceNoiseReduction) }
    }

    var colorNoiseReduction: Double {
        get { settings.rawDecoding.colorNoiseReduction ?? rawDefaults?.colorNoiseReduction ?? 0 }
        set { settings.rawDecoding.colorNoiseReduction = Self.choice(newValue, default: rawDefaults?.colorNoiseReduction) }
    }

    var moireReduction: Double {
        get { settings.rawDecoding.moireReduction ?? rawDefaults?.moireReduction ?? 0 }
        set { settings.rawDecoding.moireReduction = Self.choice(newValue, default: rawDefaults?.moireReduction) }
    }

    /// `value`, or `nil` when it is the decoder's own choice.
    private static func choice(_ value: Double, default defaultValue: Double?) -> Double? {
        guard let defaultValue, abs(value - defaultValue) < 0.005 else { return value }
        return nil
    }
}
