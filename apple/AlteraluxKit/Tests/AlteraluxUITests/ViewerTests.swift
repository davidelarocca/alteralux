import Testing
@testable import AlteraluxUI

@MainActor
struct ViewerTests {
    /// Mipmaps are built on the main thread for every new image: the viewer asks for them only
    /// where they change the picture.
    @Test func mipmapsAreBuiltOnlyBelowHalfSize() {
        // A preview fitted in the window is shown near its own size.
        #expect(!ImageScrollView.needsMipmaps(imagePixels: 2048, displayedPixels: 1800))
        #expect(!ImageScrollView.needsMipmaps(imagePixels: 2048, displayedPixels: 1024))
        // A full-resolution photo reduced to less than half.
        #expect(ImageScrollView.needsMipmaps(imagePixels: 6000, displayedPixels: 2400))
        // Nothing is laid out yet.
        #expect(!ImageScrollView.needsMipmaps(imagePixels: 2048, displayedPixels: 0))
    }

    /// The photo's scroll bars are the thin ones that show while scrolling, even when a mouse
    /// makes the system ask for the wide ones that stay.
    @Test func scrollBarsStayThin() {
        let viewer = ImageScrollView()
        #expect(viewer.scrollerStyle == .overlay)
        viewer.scrollerStyle = .legacy
        #expect(viewer.scrollerStyle == .overlay)
        #expect(viewer.scrollerKnobStyle == .light)
    }
}
