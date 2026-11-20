import AlteraluxKit
import CoreGraphics

/// Cropping and straightening the selected photo (ADR 0010). While a frame is being chosen the
/// viewer shows the whole photo developed, with the frame over it; the frame becomes one step of
/// undo when it is kept.
extension AppModel {
    /// Whether the crop controls are on screen.
    var isCropping: Bool {
        cropSession != nil
    }

    /// A photo can be cropped once it is open.
    var canCrop: Bool {
        sources != nil && !showsLibrary
    }

    /// The original can be shown in place of the developed photo: once it is read, and not
    /// while a frame is being chosen.
    var canCompare: Bool {
        original != nil && !isCropping
    }

    /// The frame the preview is developed with: none while a frame is being chosen.
    var renderedCrop: PhotoCrop? {
        isCropping ? nil : settings.crop
    }

    /// The settings the preview is developed with.
    var renderedSettings: DevelopSettings {
        var rendered = settings
        rendered.crop = renderedCrop
        return rendered
    }

    /// Shows the crop controls, starting from the photo's frame.
    func beginCrop() {
        guard let sources, !isCropping, canCrop else { return }
        settleChange()
        showsOriginal = false
        cropSession = CropSession(photo: sources.decoder.size, crop: settings.crop)
        zoom(.fit)
        requestRender()
    }

    /// Keeps the frame chosen, as one step of undo, and develops the framed photo.
    func confirmCrop() {
        guard let session = cropSession else { return }
        cropSession = nil
        zoom(.fit)
        guard session.result != settings.crop else {
            requestRender()
            return
        }
        settings.crop = session.result
        settingsDidChange()
        settleChange()
    }

    /// Lets the frame chosen go: the photo keeps the frame it had.
    func cancelCrop() {
        guard isCropping else { return }
        cropSession = nil
        zoom(.fit)
        requestRender()
    }

    /// The angle of the straightening, in degrees, while a frame is being chosen.
    var cropAngle: Double {
        get { cropSession?.angle ?? 0 }
        set { cropSession?.angle = newValue }
    }

    /// Follows a drag on the frame: `translation` is how far the pointer went since the drag
    /// began, as a fraction of the photo's width and height.
    func dragCrop(_ handle: PhotoCrop.Handle, by translation: CGSize) {
        cropSession?.drag(handle, by: translation)
    }

    func endCropDrag() {
        cropSession?.endDrag()
    }

    func setCropAspect(_ aspect: CropAspect) {
        cropSession?.setAspect(aspect)
    }

    func setCropUpright(_ isUpright: Bool) {
        cropSession?.setUpright(isUpright)
    }

    /// Turns the photo a quarter counterclockwise, while a frame is being chosen.
    func turnCropLeft() {
        cropSession?.turnLeft()
    }

    /// Mirrors the photo left to right, while a frame is being chosen.
    func flipCrop() {
        cropSession?.flip()
    }

    /// Back to the whole photo as it was shot, while a frame is being chosen.
    func resetCrop() {
        cropSession?.reset()
    }
}
