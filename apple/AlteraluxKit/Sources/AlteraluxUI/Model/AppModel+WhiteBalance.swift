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

    /// Whether the camera chose the selected photo's white balance itself: the automatic white
    /// balance then keeps it.
    var cameraChoseWhiteBalance: Bool {
        sources?.decoder.cameraChoseWhiteBalance ?? false
    }

    /// Whether the white balance of the selected photo is chosen from the light measured in it.
    /// Turned on, it lets go of a white balance chosen by hand; turned off, the white balance it
    /// gave stays as one chosen by hand, so the photo is as it was until a slider moves (ADR 0020).
    var isWhiteBalanceAutomatic: Bool {
        get { settings.autoWhiteBalance }
        set {
            guard newValue else {
                leaveAutomaticWhiteBalance()
                return
            }
            settings.autoWhiteBalance = true
            settings.temperature = nil
            settings.tint = nil
            measureAutomaticWhiteBalance()
        }
    }

    /// Where the sliders stand when no white balance was chosen by hand: the automatic one while
    /// it is on and measured, otherwise the camera's.
    private var startingWhiteBalance: WhiteBalance {
        settings.autoWhiteBalance ? automaticWhiteBalance ?? neutralWhiteBalance : neutralWhiteBalance
    }

    /// The temperature of the selected photo. Set beside the camera's value, it goes back to
    /// it: the settings then say "as shot", and stay so on whatever photo they are applied to.
    /// Moving it while the white balance is automatic chooses it by hand from where it stood.
    var temperature: Double {
        get { settings.temperature ?? startingWhiteBalance.temperature }
        set {
            leaveAutomaticWhiteBalance()
            let isAsShot = abs(newValue - neutralWhiteBalance.temperature) < Self.temperatureStep / 2
            settings.temperature = isAsShot ? nil : newValue
        }
    }

    /// The tint of the selected photo. See `temperature`.
    var tint: Double {
        get { settings.tint ?? startingWhiteBalance.tint }
        set {
            leaveAutomaticWhiteBalance()
            let isAsShot = abs(newValue - neutralWhiteBalance.tint) < Self.tintStep / 2
            settings.tint = isAsShot ? nil : newValue
        }
    }

    /// Turns the automatic white balance off, keeping the white balance it gave as one chosen
    /// by hand, so the slider not moved stays where it was.
    private func leaveAutomaticWhiteBalance() {
        guard settings.autoWhiteBalance else { return }
        let current = startingWhiteBalance
        settings.autoWhiteBalance = false
        let neutral = neutralWhiteBalance
        settings.temperature = abs(current.temperature - neutral.temperature) < Self.temperatureStep / 2
            ? nil : current.temperature
        settings.tint = abs(current.tint - neutral.tint) < Self.tintStep / 2 ? nil : current.tint
    }

    /// Measures the automatic white balance of the selected photo, when it is asked for and not
    /// measured yet, and shows it in the sliders.
    func measureAutomaticWhiteBalance() {
        guard settings.autoWhiteBalance, automaticWhiteBalance == nil, canAdjustWhiteBalance,
              let sources else { return }
        Task {
            let measured = await sources.measureWhiteBalance()
            if self.sources === sources {
                automaticWhiteBalance = measured
            }
        }
    }
}
