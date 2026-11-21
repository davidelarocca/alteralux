import CoreGraphics
import Foundation

/// How a photo is framed: turned a quarter at a time and mirrored, turned by a small angle to
/// straighten it, then cut to a rectangle, in that order.
///
/// The frame is applied before the engine, so the engine takes the framed picture as one whole
/// frame of the film and the grain keeps its size relative to it (ADR 0010). The rectangle is
/// relative to the photo once turned and mirrored, so it holds at every size the photo is
/// decoded at. Every size passed to the methods here is the photo's own, as it is shown upright:
/// they turn it themselves.
public struct PhotoCrop: Codable, Equatable, Sendable {
    /// The left edge of the rectangle kept, from 0 (the photo's left edge) to 1.
    public var left: Double
    /// The top edge of the rectangle kept, from 0 (the photo's top edge) to 1.
    public var top: Double
    /// The width of the rectangle kept, as a fraction of the photo's width.
    public var width: Double
    /// The height of the rectangle kept, as a fraction of the photo's height.
    public var height: Double
    /// How far the picture is turned about its center, in degrees: positive turns it clockwise.
    public var angle: Double
    /// How many quarter turns clockwise the photo takes first, 0 to 3.
    public var quarterTurns: Int
    /// Whether the photo, once turned, is mirrored left to right.
    public var isFlipped: Bool

    /// The angles the straightening covers.
    public static let angleRange = -45.0 ... 45.0
    /// The whole photo, not turned.
    public static let whole = PhotoCrop(left: 0, top: 0, width: 1, height: 1, angle: 0)

    public init(
        left: Double, top: Double, width: Double, height: Double, angle: Double = 0,
        quarterTurns: Int = 0, isFlipped: Bool = false,
    ) {
        self.left = left
        self.top = top
        self.width = width
        self.height = height
        self.angle = angle
        self.quarterTurns = quarterTurns
        self.isFlipped = isFlipped
    }

    /// Reads a frame saved by any version of the app: one saved before photos could be turned
    /// a quarter at a time or mirrored is neither.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            left: values.decode(Double.self, forKey: .left),
            top: values.decode(Double.self, forKey: .top),
            width: values.decode(Double.self, forKey: .width),
            height: values.decode(Double.self, forKey: .height),
            angle: values.decodeIfPresent(Double.self, forKey: .angle) ?? 0,
            quarterTurns: values.decodeIfPresent(Int.self, forKey: .quarterTurns) ?? 0,
            isFlipped: values.decodeIfPresent(Bool.self, forKey: .isFlipped) ?? false,
        )
    }

    /// Whether this frame keeps the whole photo as it is.
    public var isWhole: Bool {
        let tolerance = 1e-6
        return abs(left) < tolerance && abs(top) < tolerance && abs(width - 1) < tolerance
            && abs(height - 1) < tolerance && abs(angle) < 1e-3 && turns == 0 && !isFlipped
    }

    /// The quarter turns, 0 to 3, whatever was stored.
    var turns: Int {
        ((quarterTurns % 4) + 4) % 4
    }

    /// The size of a photo of `photo` pixels once it is turned a quarter at a time.
    public func orientedSize(of photo: CGSize) -> CGSize {
        turns.isMultiple(of: 2) ? photo : CGSize(width: photo.height, height: photo.width)
    }

    /// The rectangle kept, relative to the photo (0 to 1, from the top left).
    public var rect: CGRect {
        CGRect(x: left, y: top, width: width, height: height)
    }

    /// The size of the framed picture, in pixels, for a photo of `photo` pixels.
    public func framedSize(of photo: CGSize) -> CGSize {
        let space = orientedSize(of: photo)
        return CGSize(width: width * space.width, height: height * space.height)
    }

    /// This frame with the photo turned a quarter counterclockwise: the picture turns with it.
    public func turnedLeft() -> PhotoCrop {
        var crop = self
        crop.left = top
        crop.top = 1 - (left + width)
        crop.width = height
        crop.height = width
        // A mirrored photo turns the other way under the mirror.
        crop.quarterTurns = (turns + (isFlipped ? 1 : 3)) % 4
        return crop
    }

    /// This frame with the photo turned a quarter clockwise: the picture turns with it.
    public func turnedRight() -> PhotoCrop {
        turnedLeft().turnedLeft().turnedLeft()
    }

    /// Whether the photo's width and height swap once it is turned: a quarter turn or three.
    public var swapsSides: Bool {
        !turns.isMultiple(of: 2)
    }

    /// Whether the frame turns or mirrors the photo.
    public var reorients: Bool {
        turns != 0 || isFlipped
    }

    /// This frame with the photo mirrored left to right: the picture is mirrored with it.
    public func flipped() -> PhotoCrop {
        var crop = self
        crop.left = 1 - (left + width)
        crop.angle = -angle
        crop.isFlipped.toggle()
        return crop
    }
}

// MARK: - Fitting the frame in the turned photo

public extension PhotoCrop {
    /// Whether the rectangle lies inside the photo once it is turned, for a photo of `photo`
    /// pixels: a framed picture has no empty corners.
    func fits(in photo: CGSize) -> Bool {
        guard left >= -Self.slack, top >= -Self.slack, left + width <= 1 + Self.slack, top + height <= 1 + Self.slack else {
            return false
        }
        let space = orientedSize(of: photo)
        let pixels = pixelRect(in: space)
        let corners = [
            CGPoint(x: pixels.minX, y: pixels.minY), CGPoint(x: pixels.maxX, y: pixels.minY),
            CGPoint(x: pixels.minX, y: pixels.maxY), CGPoint(x: pixels.maxX, y: pixels.maxY),
        ]
        return corners.allSatisfy { Self.turnedPhoto(space, angle: angle, contains: $0) }
    }

    /// This frame made to fit in the turned photo: as it is when it fits, otherwise smaller
    /// about its center (about the photo's center when its own falls outside the photo).
    func fitted(in photo: CGSize) -> PhotoCrop {
        if fits(in: photo) {
            return self
        }
        let center = CGPoint(x: left + width / 2, y: top + height / 2)
        let space = orientedSize(of: photo)
        let centerInside = Self.turnedPhoto(
            space, angle: angle, contains: CGPoint(x: center.x * space.width, y: center.y * space.height),
        )
        let pivot = centerInside ? center : CGPoint(x: 0.5, y: 0.5)
        return Self.largest(fitting: photo) { scale in
            var crop = self
            crop.width = width * scale
            crop.height = height * scale
            crop.left = pivot.x - crop.width / 2
            crop.top = pivot.y - crop.height / 2
            return crop
        } ?? centered(in: photo)
    }

    /// The largest frame of `aspect` (width over height, in pixels; `nil` for the shape of the
    /// photo as it is turned) at the center of the photo, turned and straightened as this one.
    func largest(aspect: Double?, in photo: CGSize) -> PhotoCrop {
        let space = orientedSize(of: photo)
        let photoAspect = space.width / space.height
        let aspect = aspect ?? photoAspect
        // The fraction of the photo's width and height a frame of that shape takes, at most.
        var crop = self
        crop.width = aspect >= photoAspect ? 1 : aspect / photoAspect
        crop.height = aspect >= photoAspect ? photoAspect / aspect : 1
        crop.left = (1 - crop.width) / 2
        crop.top = (1 - crop.height) / 2
        return crop.fitted(in: photo)
    }

    /// A tiny frame at the center, for a frame that cannot be fitted any other way.
    private func centered(in photo: CGSize) -> PhotoCrop {
        let side = Self.minimumSide(of: orientedSize(of: photo))
        var crop = self
        crop.left = 0.5 - side.width / 2
        crop.top = 0.5 - side.height / 2
        crop.width = side.width
        crop.height = side.height
        return crop
    }
}

// MARK: - Moving and resizing

public extension PhotoCrop {
    /// What a drag takes hold of: an edge, a corner, or the whole frame to move it.
    struct Handle: Equatable, Sendable {
        /// The vertical edge the drag moves: -1 the left, 1 the right, 0 neither.
        public let horizontal: Int
        /// The horizontal edge the drag moves: -1 the top, 1 the bottom, 0 neither.
        public let vertical: Int

        public init(horizontal: Int, vertical: Int) {
            self.horizontal = horizontal
            self.vertical = vertical
        }

        /// The inside of the frame: the drag moves it.
        public static let inside = Handle(horizontal: 0, vertical: 0)
        public static let top = Handle(horizontal: 0, vertical: -1)
        public static let bottom = Handle(horizontal: 0, vertical: 1)
        public static let left = Handle(horizontal: -1, vertical: 0)
        public static let right = Handle(horizontal: 1, vertical: 0)
        public static let topLeft = Handle(horizontal: -1, vertical: -1)
        public static let topRight = Handle(horizontal: 1, vertical: -1)
        public static let bottomLeft = Handle(horizontal: -1, vertical: 1)
        public static let bottomRight = Handle(horizontal: 1, vertical: 1)
    }

    /// This frame after a drag of `handle` by `delta` (a fraction of the photo's width and
    /// height), keeping `aspect` (width over height, in pixels) when there is one. The frame
    /// goes as far as the drag while it stays in the turned photo, and no further.
    func dragged(_ handle: Handle, by delta: CGSize, aspect: Double?, in photo: CGSize) -> PhotoCrop {
        let candidate = { (fraction: Double) in
            handle == .inside
                ? self.moved(by: CGSize(width: delta.width * fraction, height: delta.height * fraction))
                : self.resized(handle, by: CGSize(width: delta.width * fraction, height: delta.height * fraction), aspect: aspect, in: photo)
        }
        if candidate(1).fits(in: photo) {
            return candidate(1)
        }
        guard fits(in: photo) else { return self }
        return Self.largest(fitting: photo, candidate) ?? self
    }

    private func moved(by delta: CGSize) -> PhotoCrop {
        var crop = self
        crop.left += delta.width
        crop.top += delta.height
        return crop
    }

    private func resized(_ handle: Handle, by delta: CGSize, aspect: Double?, in photo: CGSize) -> PhotoCrop {
        let space = orientedSize(of: photo)
        let free = movingEdges(of: handle, by: delta, in: space)
        guard let aspect else { return free }
        return free.keepingShape(aspect * space.height / space.width, of: handle, from: self)
    }

    /// The frame with the edges `handle` takes moved by `delta`, no smaller than the smallest,
    /// in a photo of `space` pixels as it is turned.
    private func movingEdges(of handle: Handle, by delta: CGSize, in space: CGSize) -> PhotoCrop {
        let minimum = Self.minimumSide(of: space)
        var leftEdge = left, topEdge = top, rightEdge = left + width, bottomEdge = top + height
        if handle.horizontal < 0 {
            leftEdge = min(leftEdge + delta.width, rightEdge - minimum.width)
        } else if handle.horizontal > 0 {
            rightEdge = max(rightEdge + delta.width, leftEdge + minimum.width)
        }
        if handle.vertical < 0 {
            topEdge = min(topEdge + delta.height, bottomEdge - minimum.height)
        } else if handle.vertical > 0 {
            bottomEdge = max(bottomEdge + delta.height, topEdge + minimum.height)
        }
        var crop = self
        crop.left = leftEdge
        crop.top = topEdge
        crop.width = rightEdge - leftEdge
        crop.height = bottomEdge - topEdge
        return crop
    }

    /// This frame given the shape `ratio` (width over height, as fractions of the photo) after
    /// a drag of `handle` that started from `start`: the side the drag moved most leads, the
    /// other follows. The edges the drag did not take stay where they were in `start`; along a
    /// side the drag did not take at all, the frame keeps its center.
    private func keepingShape(_ ratio: Double, of handle: Handle, from start: PhotoCrop) -> PhotoCrop {
        var crop = self
        let leadsWithWidth = handle.vertical == 0
            || (handle.horizontal != 0 && width / start.width >= height / start.height)
        if leadsWithWidth {
            crop.height = width / ratio
        } else {
            crop.width = height * ratio
        }
        crop.left = Self.place(crop.width, side: handle.horizontal, start: start.left, length: start.width)
        crop.top = Self.place(crop.height, side: handle.vertical, start: start.top, length: start.height)
        return crop
    }

    /// Where a side of `length` begins along one axis, after a drag of the edge `side` (-1 the
    /// leading one, 1 the trailing one, 0 neither) of a side that was `start` to `start + old`.
    private static func place(_ length: Double, side: Int, start: Double, length old: Double) -> Double {
        if side < 0 {
            return start + old - length
        }
        if side > 0 {
            return start
        }
        return start + old / 2 - length / 2
    }
}

// MARK: - Geometry

extension PhotoCrop {
    /// How far past the photo's edge a frame may reach and still count as inside: rounding.
    private static let slack = 1e-9

    /// The smallest side of a frame: a small fraction of the photo's long side.
    static func minimumSide(of photo: CGSize) -> CGSize {
        let side = max(photo.width, photo.height) * 0.02
        return CGSize(width: side / photo.width, height: side / photo.height)
    }

    /// The rectangle in pixels, from the top left of the photo of `photo` pixels as it is turned.
    func pixelRect(in photo: CGSize) -> CGRect {
        CGRect(x: left * photo.width, y: top * photo.height, width: width * photo.width, height: height * photo.height)
    }

    /// Whether `point` (pixels, from the top left) lies on the photo once it is turned by
    /// `angle` degrees clockwise about its center.
    static func turnedPhoto(_ photo: CGSize, angle: Double, contains point: CGPoint) -> Bool {
        // Turning the point back the other way puts it where it was on the upright photo.
        let radians = -angle * .pi / 180
        let fromCenterX = point.x - photo.width / 2
        let fromCenterY = point.y - photo.height / 2
        // With y pointing down, a positive angle turns clockwise on screen.
        let upright = CGPoint(
            x: fromCenterX * cos(radians) - fromCenterY * sin(radians) + photo.width / 2,
            y: fromCenterX * sin(radians) + fromCenterY * cos(radians) + photo.height / 2,
        )
        let tolerance = max(photo.width, photo.height) * 1e-9
        return upright.x >= -tolerance && upright.y >= -tolerance
            && upright.x <= photo.width + tolerance && upright.y <= photo.height + tolerance
    }

    /// The largest value from 0 to 1 that `make` turns into a frame that fits, by halving.
    /// `nil` when even the smallest does not fit.
    static func largest(fitting photo: CGSize, _ make: (Double) -> PhotoCrop) -> PhotoCrop? {
        var low = 0.0, high = 1.0
        guard make(low).fits(in: photo) || make(1e-3).fits(in: photo) else { return nil }
        for _ in 0 ..< 40 {
            let middle = (low + high) / 2
            if make(middle).fits(in: photo) {
                low = middle
            } else {
                high = middle
            }
        }
        return make(low)
    }
}
