import AlteraluxKit
import CoreGraphics
import Foundation

/// The shapes a frame can be held to.
enum CropAspect: String, CaseIterable, Identifiable {
    case freeform
    case original
    case square
    case fourByFive
    case twoByThree
    case nineBySixteen

    var id: Self {
        self
    }

    /// The name of the shape, written as it stands: "4:5" upright, "5:4" lying down.
    func title(isUpright: Bool) -> String {
        let sides: (long: Int, short: Int)
        switch self {
        case .freeform: return String(localized: "Freeform", comment: "A crop frame of any shape")
        case .original: return String(localized: "Original", comment: "A crop frame of the photo's own shape")
        case .square: return String(localized: "Square", comment: "A square crop frame")
        case .fourByFive: sides = (5, 4)
        case .twoByThree: sides = (3, 2)
        case .nineBySixteen: sides = (16, 9)
        }
        return isUpright ? "\(sides.short):\(sides.long)" : "\(sides.long):\(sides.short)"
    }

    /// Whether the shape can stand upright or lie down: every shape but the square. A free
    /// frame is laid down or stood up as it is, its sides swapped.
    var hasOrientation: Bool {
        self != .square
    }

    /// The width over the height of a frame of this shape, in pixels, upright or lying down;
    /// `nil` for a free frame.
    func ratio(photo: CGSize, isUpright: Bool) -> Double? {
        let longOverShort: Double
        switch self {
        case .freeform: return nil
        case .square: return 1
        case .original: longOverShort = max(photo.width, photo.height) / min(photo.width, photo.height)
        case .fourByFive: longOverShort = 5.0 / 4
        case .twoByThree: longOverShort = 3.0 / 2
        case .nineBySixteen: longOverShort = 16.0 / 9
        }
        return isUpright ? 1 / longOverShort : longOverShort
    }
}

/// A frame being chosen for the selected photo: what the crop controls change, until the frame
/// is kept or let go.
struct CropSession: Equatable {
    /// The size of the whole photo, in pixels, upright as it was shot.
    let photo: CGSize
    /// The frame on screen.
    private(set) var crop: PhotoCrop
    /// The shape the frame is held to.
    private(set) var aspect = CropAspect.freeform
    /// Whether a shape with an orientation is held upright.
    private var holdsUpright: Bool
    /// The frame as it was last set by hand or by a shape. A change of angle fits this one in the
    /// turned photo, so turning the photo and back gives the same frame again.
    private var intent: PhotoCrop
    /// The frame when the drag in progress began.
    private var dragStart: PhotoCrop?

    /// Starts from the frame the photo has, or from the whole photo.
    init(photo: CGSize, crop: PhotoCrop?) {
        self.photo = photo
        let crop = crop ?? .whole
        self.crop = crop
        intent = crop
        let framed = crop.framedSize(of: photo)
        holdsUpright = framed.height > framed.width
    }

    /// Whether the frame stands upright: a free frame when it is taller than wide.
    var isUpright: Bool {
        guard aspect == .freeform else { return holdsUpright }
        let framed = crop.framedSize(of: photo)
        return framed.height > framed.width
    }

    /// The frame to keep: `nil` for the whole photo.
    var result: PhotoCrop? {
        crop.isWhole ? nil : crop
    }

    /// The angle of the straightening, in degrees.
    var angle: Double {
        get { crop.angle }
        set {
            let angle = min(max(newValue, PhotoCrop.angleRange.lowerBound), PhotoCrop.angleRange.upperBound)
            var turned = intent
            turned.angle = angle
            crop = turned.fitted(in: photo)
            intent.angle = angle
        }
    }

    /// Follows a drag of `handle` by `translation` since it began, as a fraction of the photo's
    /// width and height.
    mutating func drag(_ handle: PhotoCrop.Handle, by translation: CGSize) {
        let start = dragStart ?? crop
        dragStart = start
        crop = start.dragged(handle, by: translation, aspect: ratio, in: photo)
        intent = crop
    }

    /// Ends the drag in progress.
    mutating func endDrag() {
        dragStart = nil
    }

    /// Holds the frame to `aspect`: the largest frame of that shape in the middle of the photo.
    mutating func setAspect(_ aspect: CropAspect) {
        // A shape starts the way the free frame stood.
        holdsUpright = isUpright
        self.aspect = aspect
        applyAspect()
    }

    /// Stands the frame upright or lays it down.
    mutating func setUpright(_ isUpright: Bool) {
        if aspect == .freeform, isUpright != self.isUpright {
            swapSides()
        }
        holdsUpright = isUpright
        applyAspect()
    }

    /// Turns the photo a quarter counterclockwise, the frame with it.
    mutating func turnLeft() {
        crop = crop.turnedLeft()
        intent = intent.turnedLeft()
        dragStart = nil
        holdsUpright.toggle()
    }

    /// Mirrors the photo left to right, the frame with it.
    mutating func flip() {
        crop = crop.flipped()
        intent = intent.flipped()
        dragStart = nil
    }

    /// Back to the whole photo as it was shot: straight, not turned nor mirrored, and free.
    mutating func reset() {
        aspect = .freeform
        crop = .whole
        intent = .whole
        let size = photo
        holdsUpright = size.height > size.width
    }

    private var ratio: Double? {
        aspect.ratio(photo: photo, isUpright: holdsUpright)
    }

    /// Lays a free frame down or stands it up: its width and height in pixels swap, about its
    /// center, as large as the photo lets it be.
    private mutating func swapSides() {
        let space = intent.orientedSize(of: photo)
        var width = intent.height * space.height / space.width
        var height = intent.width * space.width / space.height
        let shrink = min(1, 1 / width, 1 / height)
        width *= shrink
        height *= shrink
        let center = CGPoint(x: intent.left + intent.width / 2, y: intent.top + intent.height / 2)
        intent.width = width
        intent.height = height
        intent.left = min(max(center.x - width / 2, 0), 1 - width)
        intent.top = min(max(center.y - height / 2, 0), 1 - height)
        crop = intent.fitted(in: photo)
        dragStart = nil
    }

    private mutating func applyAspect() {
        guard let ratio else { return }
        var straight = crop
        straight.angle = 0
        intent = straight.largest(aspect: ratio, in: photo)
        intent.angle = crop.angle
        crop = intent.fitted(in: photo)
    }
}
