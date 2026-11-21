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

    /// The correction made with what the camera recorded, for the selected photo: who corrects the
    /// geometry and who the vignetting. `nil` when the photo carries nothing that applies.
    var cameraLensCorrection: CameraLensCorrection? {
        sources?.decoder.cameraLensCorrection
    }

    /// Whether the lens of the selected photo is corrected. Adjustments saved before the app
    /// had the choice show what the decoder does on its own, until it is changed.
    var isLensCorrected: Bool {
        get { correctsLens && (settings.lensCorrection ?? sources?.decoder.correctsLensByDefault ?? true) }
        set { settings.lensCorrection = newValue }
    }
}
