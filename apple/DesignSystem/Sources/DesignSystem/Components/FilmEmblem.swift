import SwiftUI

/// The small emblem of a film in a list: a ground, a band under it and the film's speed.
///
/// It tells the films apart at a glance, with colors suggested by each film's character. The
/// emblems are the app's own: they copy no maker's packaging. It is decoration: the film's
/// name beside it is what assistive technologies read.
public struct FilmEmblem: View {
    /// The size every emblem is drawn at, in points.
    public static let size = CGSize(width: 46, height: 30)

    private let ground: Ink
    private let band: Ink
    private let label: String

    /// - Parameter label: the speed as the film's name writes it ("400", "250D"), a few characters.
    public init(ground: Ink, band: Ink, label: String) {
        self.ground = ground
        self.band = band
        self.label = label
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: label)
                .font(Typography.emblem)
                .lineLimit(1)
                .minimumScaleFactor(Self.smallestLabelScale)
                .foregroundStyle(ground.isLight ? Self.darkLabel : Self.lightLabel)
                .padding(.horizontal, Spacing.xxs)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ground.color)
            band.color
                .frame(height: Self.bandHeight)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(.rect(cornerRadius: Radius.emblem))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.emblem)
                .strokeBorder(Self.outline, lineWidth: Self.lineWidth)
        }
        // The speed keeps its place: an emblem is a picture, not text to mirror.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    private static let bandHeight: CGFloat = 6
    private static let lineWidth: CGFloat = 1
    private static let smallestLabelScale = 0.7
    private static let outline = Color.white.opacity(0.14)
    private static let lightLabel = Color(white: 0.93)
    private static let darkLabel = Color(white: 0.09)

    /// The colors emblems are made of. A film's emblem pairs two of them.
    public enum Ink: CaseIterable, Sendable {
        case pine, mint, leaf, fern, petrol, slate
        case brick, vermilion, magenta, fuchsia
        case gold, amber, yellow, tungsten, bronze, umber
        case violet, deepViolet, darkViolet
        case cobalt, azure, royal, sky
        case bone, cream, silver, ash, white, graphite, black
        /// For a film the app has no emblem for yet.
        case plain

        var color: Color {
            Color(red: Double(rgb >> 16 & 0xFF) / 255, green: Double(rgb >> 8 & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
        }

        /// Whether a dark label reads better on it than a light one.
        var isLight: Bool {
            let red = Double(rgb >> 16 & 0xFF), green = Double(rgb >> 8 & 0xFF), blue = Double(rgb & 0xFF)
            return (0.299 * red + 0.587 * green + 0.114 * blue) / 255 > 0.55
        }

        private var rgb: UInt32 {
            switch self {
            case .pine: 0x2F7D4F
            case .mint: 0x7FB8A4
            case .leaf: 0x3A8F3A
            case .fern: 0x3A8F4A
            case .petrol: 0x1F3B45
            case .slate: 0x24424F
            case .brick: 0xA8322A
            case .vermilion: 0xB0302A
            case .magenta: 0xA02A6A
            case .fuchsia: 0xB83A7A
            case .gold: 0xD9A520
            case .amber: 0xE3B23C
            case .yellow: 0xE8C020
            case .tungsten: 0xE0A04A
            case .bronze: 0x7A4A12
            case .umber: 0x5A4A3A
            case .violet: 0x6B5A8E
            case .deepViolet: 0x57487A
            case .darkViolet: 0x453866
            case .cobalt: 0x2C5AA0
            case .azure: 0x2B5FA8
            case .royal: 0x2A4F9A
            case .sky: 0x9CC3E6
            case .bone: 0xE6E2CF
            case .cream: 0xE9DCC0
            case .silver: 0xD9D9D9
            case .ash: 0xD0D0D0
            case .white: 0xF0F0F0
            case .graphite: 0x3A3A3A
            case .black: 0x0C0C0C
            case .plain: 0x4A4A4A
            }
        }
    }
}

#Preview("Film emblems") {
    HStack(spacing: Spacing.s) {
        FilmEmblem(ground: .violet, band: .cream, label: "400")
        FilmEmblem(ground: .gold, band: .bronze, label: "200")
        FilmEmblem(ground: .darkViolet, band: .cream, label: "800+2")
        FilmEmblem(ground: .black, band: .white, label: "XX")
        FilmEmblem(ground: .plain, band: .ash, label: "")
    }
    .padding(Spacing.l)
}
