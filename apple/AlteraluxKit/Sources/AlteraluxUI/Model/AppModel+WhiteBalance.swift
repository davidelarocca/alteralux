import AlteraluxKit
import Foundation

// The white balance of the selected photo as the inspector reads and sets it.

extension AppModel {
    /// The temperatures the slider covers, in kelvin, when the camera's own is among them.
    static let temperatureRange = 2000.0 ... 12000.0
    static let temperatureStep = 50.0
    static let tintRange = -150.0 ... 150.0
    static let tintStep = 1.0
    /// What the sliders show while no RAW is open: daylight, no tint.
    private static let placeholder = WhiteBalance(temperature: 5500, tint: 0)

    /// The white balance the camera recorded in the selected photo. `nil` when no photo is
    /// open or when it is not a RAW: only a RAW's white balance can be chosen again.
    var asShotWhiteBalance: WhiteBalance? {
        sources?.decoder.asShotWhiteBalance
    }

    var canAdjustWhiteBalance: Bool {
        asShotWhiteBalance != nil
    }

    /// Whether the selected photo is open and its white balance cannot be chosen.
    var whiteBalanceIsFixed: Bool {
        sources != nil && !canAdjustWhiteBalance
    }

    /// Where the sliders start and return to: what the camera recorded.
    var neutralWhiteBalance: WhiteBalance {
        asShotWhiteBalance ?? Self.placeholder
    }

    /// The range of the temperature slider: wide enough for the camera's own value.
    var temperatureRange: ClosedRange<Double> {
        let neutral = neutralWhiteBalance.temperature
        return min(Self.temperatureRange.lowerBound, neutral) ... max(Self.temperatureRange.upperBound, neutral)
    }

    /// The temperature of the selected photo. Set beside the camera's value, it goes back to
    /// it: the settings then say "as shot", and stay so on whatever photo they are applied to.
    var temperature: Double {
        get { settings.temperature ?? neutralWhiteBalance.temperature }
        set {
            let isAsShot = abs(newValue - neutralWhiteBalance.temperature) < Self.temperatureStep / 2
            settings.temperature = isAsShot ? nil : newValue
        }
    }

    /// The tint of the selected photo. See `temperature`.
    var tint: Double {
        get { settings.tint ?? neutralWhiteBalance.tint }
        set {
            let isAsShot = abs(newValue - neutralWhiteBalance.tint) < Self.tintStep / 2
            settings.tint = isAsShot ? nil : newValue
        }
    }
}
