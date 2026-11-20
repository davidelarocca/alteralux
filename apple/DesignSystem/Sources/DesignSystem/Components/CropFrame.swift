import SwiftUI

/// The frame drawn over a photo while it is cropped, as Photos draws it: what falls outside is
/// darkened, the frame has a thin edge, lines in thirds and thick corners, and its edges, corners
/// and inside can be dragged. The pointer takes the shape of what it would drag.
///
/// It fills the view it is put in; `rect` is the frame in that view's coordinates. It reports
/// how far a drag went since it began, in points, and when it ends: the caller turns that into a
/// new `rect`. It is drawn for the dark surround of the photo, in either appearance, and lays its
/// edges out left to right whatever the language.
public struct CropFrame: View {
    /// What a drag takes hold of: an edge, a corner, or the inside, to move the frame.
    public struct Grip: Hashable, Sendable {
        /// The vertical edge taken: -1 the left one, 1 the right one, 0 neither.
        public let horizontal: Int
        /// The horizontal edge taken: -1 the top one, 1 the bottom one, 0 neither.
        public let vertical: Int

        public static let inside = Grip(horizontal: 0, vertical: 0)

        /// The eight edges and corners, then the inside.
        static let all: [Grip] = [-1, 0, 1].flatMap { vertical in
            [-1, 0, 1].map { Grip(horizontal: $0, vertical: vertical) }
        }
        .filter { $0 != .inside } + [.inside]
    }

    private let rect: CGRect
    private let onDrag: (Grip, CGSize) -> Void
    private let onDragEnd: () -> Void

    /// - Parameters:
    ///   - rect: the frame, in the coordinates of the view the frame fills.
    ///   - onDrag: a drag of a grip, with how far it went since it began, in points.
    ///   - onDragEnd: the drag in progress ended.
    public init(rect: CGRect, onDrag: @escaping (Grip, CGSize) -> Void, onDragEnd: @escaping () -> Void) {
        self.rect = rect
        self.onDrag = onDrag
        self.onDragEnd = onDragEnd
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            shade
            thirds
            Rectangle()
                .strokeBorder(Color.white.opacity(Self.edgeOpacity), lineWidth: Self.edgeWidth)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            corners
            ForEach(Grip.all, id: \.self) { grip in
                handle(grip)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.layoutDirection, .leftToRight)
    }

    /// Everything outside the frame, darkened.
    private var shade: some View {
        GeometryReader { proxy in
            Path { path in
                path.addRect(CGRect(origin: .zero, size: proxy.size))
                path.addRect(rect)
            }
            .fill(Color.black.opacity(Self.shadeOpacity), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The lines that cut the frame in thirds.
    private var thirds: some View {
        Path { path in
            for third in [1.0 / 3, 2.0 / 3] {
                let column = rect.minX + rect.width * third
                let row = rect.minY + rect.height * third
                path.move(to: CGPoint(x: column, y: rect.minY))
                path.addLine(to: CGPoint(x: column, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX, y: row))
                path.addLine(to: CGPoint(x: rect.maxX, y: row))
            }
        }
        .stroke(Color.white.opacity(Self.thirdsOpacity), lineWidth: Self.thirdsWidth)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The thick corners, just inside the frame.
    private var corners: some View {
        let length = min(Self.cornerLength, rect.width / 2, rect.height / 2)
        let inset = Self.cornerWidth / 2
        return Path { path in
            for (cornerX, cornerY, outX, outY) in [
                (rect.minX + inset, rect.minY + inset, 1.0, 1.0), (rect.maxX - inset, rect.minY + inset, -1.0, 1.0),
                (rect.minX + inset, rect.maxY - inset, 1.0, -1.0), (rect.maxX - inset, rect.maxY - inset, -1.0, -1.0),
            ] {
                path.move(to: CGPoint(x: cornerX + outX * length, y: cornerY))
                path.addLine(to: CGPoint(x: cornerX, y: cornerY))
                path.addLine(to: CGPoint(x: cornerX, y: cornerY + outY * length))
            }
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: Self.cornerWidth, lineCap: .square))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The area that takes a drag of `grip`, with the pointer it shows.
    private func handle(_ grip: Grip) -> some View {
        let area = area(of: grip)
        return Color.clear
            .contentShape(Rectangle())
            .frame(width: area.width, height: area.height)
            .offset(x: area.minX, y: area.minY)
            .pointerStyle(pointer(for: grip))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onDrag(grip, $0.translation) }
                    .onEnded { _ in onDragEnd() },
            )
            .accessibilityHidden(true)
    }

    /// Where a grip can be taken: a band across each edge, a square on each corner, the inside
    /// within the bands.
    private func area(of grip: Grip) -> CGRect {
        let reach = Self.gripReach
        let insideWidth = max(0, rect.width - reach)
        let insideHeight = max(0, rect.height - reach)
        let width: CGFloat = grip.horizontal == 0 ? insideWidth : reach
        let height: CGFloat = grip.vertical == 0 ? insideHeight : reach
        let left: CGFloat = switch grip.horizontal {
        case -1: rect.minX - reach / 2
        case 1: rect.maxX - reach / 2
        default: rect.midX - insideWidth / 2
        }
        let top: CGFloat = switch grip.vertical {
        case -1: rect.minY - reach / 2
        case 1: rect.maxY - reach / 2
        default: rect.midY - insideHeight / 2
        }
        return CGRect(x: left, y: top, width: width, height: height)
    }

    private func pointer(for grip: Grip) -> PointerStyle {
        let position: FrameResizePosition? = switch (grip.horizontal, grip.vertical) {
        case (-1, -1): .topLeading
        case (0, -1): .top
        case (1, -1): .topTrailing
        case (-1, 0): .leading
        case (1, 0): .trailing
        case (-1, 1): .bottomLeading
        case (0, 1): .bottom
        case (1, 1): .bottomTrailing
        default: nil
        }
        guard let position else { return .grabIdle }
        return .frameResize(position: position)
    }

    private static var shadeOpacity: Double {
        0.55
    }

    private static var edgeOpacity: Double {
        0.8
    }

    private static var edgeWidth: CGFloat {
        1
    }

    private static var thirdsOpacity: Double {
        0.35
    }

    private static var thirdsWidth: CGFloat {
        0.5
    }

    private static var cornerLength: CGFloat {
        18
    }

    private static var cornerWidth: CGFloat {
        3
    }

    /// How wide the band is that takes an edge or a corner, in points.
    private static var gripReach: CGFloat {
        20
    }
}

#Preview("Crop frame") {
    ZStack {
        Color.DS.thumbnailPlaceholder
            .frame(width: 320, height: 213)
        CropFrame(rect: CGRect(x: 80, y: 50, width: 220, height: 160), onDrag: { _, _ in }, onDragEnd: {})
    }
    .frame(width: 380, height: 260)
    .background(Color.DS.viewerSurround)
}

#Preview("Crop frame, whole photo") {
    ZStack {
        Color.DS.thumbnailPlaceholder
            .frame(width: 320, height: 213)
        CropFrame(rect: CGRect(x: 30, y: 23.5, width: 320, height: 213), onDrag: { _, _ in }, onDragEnd: {})
    }
    .frame(width: 380, height: 260)
    .background(Color.DS.viewerSurround)
}
