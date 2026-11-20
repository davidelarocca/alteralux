import Testing
@testable import AlteraluxUI

/// The size of the preview for how large the viewer shows the photo.
struct PreviewSizeTests {
    /// A 24 MP photo.
    private let photo = 6000

    private func dimension(showing displayed: Double, of photoLongSide: Int? = nil) -> Int {
        PreviewSize.dimension(displayedLongSide: displayed, photoLongSide: photoLongSide ?? photo)
    }

    @Test func aPhotoSmallOnScreenGetsTheStandardPreview() {
        // Before the viewer has reported, too.
        #expect(dimension(showing: 0) == 2048)
        #expect(dimension(showing: 1200) == 2048)
        #expect(dimension(showing: 2048) == 2048)
    }

    @Test func aPreviewIsShownSlightlyEnlargedBeforeALargerOneIsRendered() {
        #expect(dimension(showing: 2300) == 2048)
        #expect(dimension(showing: 2400) == 2560)
    }

    /// A fitted photo in a large window on a 4K display: not the full resolution.
    @Test func aPhotoFittedInALargeWindowGetsWhatItShows() {
        #expect(dimension(showing: 2800) == 2560)
        #expect(dimension(showing: 3000) == 3072)
        #expect(dimension(showing: 3600) == 3584)
    }

    @Test func aPhotoAtActualSizeOrLargerIsRenderedWhole() {
        #expect(dimension(showing: 6000) == 0)
        #expect(dimension(showing: 48000) == 0)
        // Whatever its size: 2944 is 2560 enlarged exactly as far as a preview goes.
        for longSide in [2944, 2945, 3000, 5000, 9504] {
            #expect(dimension(showing: Double(longSide), of: longSide) == 0)
        }
    }

    /// Scaling it down would save little and cost a scaled copy.
    @Test func aPhotoBarelyLargerThanThePreviewIsRenderedWhole() {
        #expect(dimension(showing: 1000, of: 2300) == 0)
        #expect(dimension(showing: 1000, of: 2400) == 2048)
        #expect(dimension(showing: 5900, of: 6000) == 0)
        #expect(dimension(showing: 5000, of: 6000) == 4608)
    }

    @Test func aPhotoSmallerThanTheStandardPreviewIsRenderedWhole() {
        #expect(dimension(showing: 0, of: 1500) == 0)
        #expect(dimension(showing: 1500, of: 1500) == 0)
    }

    @Test func onlyALargePreviewComesAfterTheStandardOne() {
        #expect(!PreviewSize.comesAfterStandard(2048, photoLongSide: photo))
        #expect(!PreviewSize.comesAfterStandard(3072, photoLongSide: photo))
        #expect(PreviewSize.comesAfterStandard(3584, photoLongSide: photo))
        #expect(PreviewSize.comesAfterStandard(0, photoLongSide: photo))
        // The whole of a small photo is quick.
        #expect(!PreviewSize.comesAfterStandard(0, photoLongSide: 2400))
    }
}
