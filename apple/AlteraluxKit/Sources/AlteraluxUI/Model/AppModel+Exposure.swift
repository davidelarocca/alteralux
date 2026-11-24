import AlteraluxKit
import Foundation

// The exposure of the selected photo as the inspector reads and sets it: left to the engine's
// meter, or chosen by hand (ADR 0020).

extension AppModel {
    /// The stops the exposure slider covers either way.
    static let exposureRange = -5.0 ... 5.0
    static let exposureStep = 0.1

    /// Whether the engine's meter chooses the exposure of the selected photo.
    ///
    /// Turned off, the exposure is the hand's, and starts from what the meter had chosen with
    /// its compensation, so the photo stays as it is until the slider moves. Turned on, the
    /// meter decides from no compensation; one can be added in the meter's own group.
    var isExposureAutomatic: Bool {
        get { settings.autoExposure }
        set {
            guard newValue != settings.autoExposure else { return }
            var changed = settings
            changed.autoExposure = newValue
            if newValue {
                changed.exposureEV = 0
            } else if let meteredExposure {
                let stops = ((meteredExposure + settings.exposureEV) / Self.exposureStep).rounded() * Self.exposureStep
                changed.exposureEV = min(max(stops, Self.exposureRange.lowerBound), Self.exposureRange.upperBound)
            }
            settings = changed
        }
    }

    /// What the engine's meter adds to the selected photo, in stops, once it was read: where the
    /// exposure starts from when the meter is turned off. `nil` until then.
    var meteredExposure: Double? {
        meterReading.flatMap { $0.sources === sources ? $0.stops : nil }
    }

    /// Reads again what the meter adds to the selected photo as `settings` decode and meter it,
    /// once a preview is the settled one. The decoder keeps the last reading, so asking after
    /// every settled preview costs nothing while nothing of it changed.
    func refreshMeteredExposure(for settings: DevelopSettings, isSettled: Bool) {
        guard isSettled, let sources else { return }
        Task {
            if let stops = try? await sources.decoder.meteredExposure(settings: settings) {
                meterReading = (sources, stops)
            }
        }
    }
}
