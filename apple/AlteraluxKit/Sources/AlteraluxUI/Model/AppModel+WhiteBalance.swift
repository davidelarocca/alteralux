import AlteraluxKit
import CoreGraphics
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

// The dropper: a click on the photo chooses the white balance that makes that point gray.

/// The white balance's dropper while it is on: for the photo it was turned on for alone, so
/// another photo, or none, puts it away.
struct NeutralPicker {
    weak var sources: PhotoSources?
    /// Whether the last point clicked had no color to make gray (clipped, or nearly black): the
    /// dropper stays, waiting for another point.
    var missed = false
}

extension AppModel {
    /// Whether a click on the photo chooses the white balance that makes that point gray.
    var isPickingNeutral: Bool {
        guard let sources, let picked = neutralPicker?.sources else { return false }
        return picked === sources
    }

    /// Whether the last point clicked with the dropper had no color to make gray.
    var missedNeutral: Bool {
        isPickingNeutral && neutralPicker?.missed == true
    }

    /// Whether the dropper can be used: a RAW is open and shown, not while it is being cropped.
    var canPickNeutral: Bool {
        canAdjustWhiteBalance && !isCropping
    }

    /// Whether the photo on screen is waiting for the dropper's click.
    var isPickingNeutralOnPhoto: Bool {
        isPickingNeutral && canPickNeutral && !showsOriginal
    }

    /// Turns the dropper on or off.
    func setPickingNeutral(_ isOn: Bool) {
        neutralPicker = isOn && canPickNeutral ? NeutralPicker(sources: sources) : nil
    }

    /// Chooses the white balance under which `point` of the photo on screen is gray, as one
    /// chosen by hand: the automatic white balance lets go of it. `point` is in the photo as it is
    /// framed on screen, from its top left corner, 0 to 1 across and down. A point that is clipped
    /// or nearly black changes nothing and leaves the dropper on.
    func pickNeutral(at point: CGPoint) {
        guard isPickingNeutralOnPhoto, let sources else { return }
        let settings = settings
        Task {
            do {
                let picked = try await sources.decoder.whiteBalance(neutralAt: point, settings: settings)
                guard self.sources === sources else { return }
                if let picked {
                    chooseWhiteBalance(picked)
                }
                neutralPicker = nil
            } catch {
                guard self.sources === sources, neutralPicker != nil else { return }
                neutralPicker?.missed = true
            }
        }
    }

    /// Sets the white balance chosen by hand, as one step of undo of its own, as a frame kept is.
    private func chooseWhiteBalance(_ chosen: WhiteBalance) {
        let neutral = neutralWhiteBalance
        var next = settings
        next.autoWhiteBalance = false
        next.temperature = abs(chosen.temperature - neutral.temperature) < Self.temperatureStep / 2
            ? nil : chosen.temperature
        next.tint = abs(chosen.tint - neutral.tint) < Self.tintStep / 2 ? nil : chosen.tint
        guard next != settings else { return }
        // A slider still moving becomes its own step first.
        settleChange()
        settings = next
        settingsDidChange()
        settleChange()
    }
}
