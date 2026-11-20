import Foundation
import Testing
@testable import AlteraluxUI

/// The zoom as the controls under the photo read and set it.
@MainActor
struct ZoomTests {
    private func model(scale: Double, fitScale: Double, isFitted: Bool) -> AppModel {
        let model = AppModel()
        model.viewerDidChange(ViewerZoom(scale: scale, fitScale: fitScale, isFitted: isFitted))
        return model
    }

    @Test func theSliderReadsTheLogarithmOfTheScale() {
        let model = model(scale: 2, fitScale: 0.25, isFitted: false)
        #expect(abs(model.zoomLevel - 1) < 1e-9)
        #expect(abs(model.fitZoomLevel + 2) < 1e-9)
    }

    @Test func aScaleOutsideTheSliderStaysAtItsEnd() {
        // Before the viewer reports, the scale is 0: the slider must not read minus infinity.
        #expect(AppModel().zoomLevel == AppModel.zoomLevelRange.lowerBound)
        #expect(model(scale: 20, fitScale: 0.25, isFitted: false).zoomLevel == AppModel.zoomLevelRange.upperBound)
    }

    @Test func aLevelSetsItsScale() {
        let model = model(scale: 0.25, fitScale: 0.25, isFitted: true)
        model.setZoomLevel(1)
        #expect(model.zoomCommand == .scale(2))
    }

    @Test func aLevelBesideTheFittedPhotoFitsIt() {
        let model = model(scale: 1, fitScale: 0.25, isFitted: false)
        model.setZoomLevel(model.fitZoomLevel + AppModel.zoomLevelStep / 4)
        #expect(model.zoomCommand == .fit)
    }

    @Test func aLevelPastTheEndsIsHeldInTheRange() {
        let model = model(scale: 1, fitScale: 0.25, isFitted: false)
        model.setZoomLevel(10)
        #expect(model.zoomCommand == .scale(AppModel.zoomScaleRange.upperBound))
    }

    @Test func theNamedZoomsAreToldApart() {
        #expect(model(scale: 0.4, fitScale: 0.4, isFitted: true).zoomPreset == .fit)
        #expect(model(scale: 1, fitScale: 0.4, isFitted: false).zoomPreset == .actualSize)
        #expect(model(scale: 0.7, fitScale: 0.4, isFitted: false).zoomPreset == nil)
        // A small photo fits at 100%: it is fitted, and follows the window.
        #expect(model(scale: 1, fitScale: 1, isFitted: true).zoomPreset == .fit)
    }
}
