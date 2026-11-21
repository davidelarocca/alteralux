import AlteraluxKit
import Foundation

// The lens correction of the selected photo, as the inspector shows and sets it.

extension AppModel {
    /// Whether the lens of the selected photo can be corrected: by the RAW decoder, with what the
    /// camera recorded, or with a lens profile. `false`
    /// while no photo is open.
    var correctsLens: Bool {
        sources?.decoder.correctsLens ?? false
    }

    /// The lens profile that corrects the selected photo, by the lens's name: `nil` when Apple's
    /// decoder corrects it itself, or when nothing does.
    var lensProfileName: String? {
        sources?.decoder.lensProfile?.lensName
    }

    /// The lens the camera recorded its own corrections for, which correct the selected photo:
    /// `nil` when Apple's decoder corrects it, or the photo carries none.
    var cameraCorrectedLensName: String? {
        sources?.decoder.cameraLensCorrection?.lensName
    }

    /// Whether the lens of the selected photo is corrected. Adjustments saved before the app
    /// had the choice show what the decoder does on its own, until it is changed.
    var isLensCorrected: Bool {
        get { correctsLens && (settings.lensCorrection ?? sources?.decoder.correctsLensByDefault ?? true) }
        set { settings.lensCorrection = newValue }
    }
}
