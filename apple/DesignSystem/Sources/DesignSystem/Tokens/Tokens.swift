import SwiftUI

// Design tokens. Names describe intent, not the value: a caller says what it
// needs (`Spacing.m`, `Radius.thumbnail`), the design system decides how much.

public enum Spacing {
    /// Between a label and the control it belongs to.
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    /// Around the photo in the viewer.
    public static let xl: CGFloat = 24
}

public enum Radius {
    /// Thumbnails in the photo strip.
    public static let thumbnail: CGFloat = 5
    public static let control: CGFloat = 6
    /// The emblem of a film in a list.
    public static let emblem: CGFloat = 5
}

public enum Typography {
    public static let body = Font.body
    /// The name of what a window shows: the photo in the toolbar.
    public static let title = Font.headline
    /// The name of what a pane is about: the film at the top of the inspector.
    public static let heading = Font.title2.weight(.semibold)
    /// A line of context above or under a heading.
    public static let caption = Font.subheadline
    /// The title of a section in a pane.
    public static let sectionHeader = Font.body.weight(.semibold)
    /// The speed written on a film's emblem.
    public static let emblem = Font.subheadline.weight(.heavy)
    /// Numeric values next to a control: digits keep their width while they change.
    public static let value = Font.body.monospacedDigit()
    /// Short status labels drawn over the photo.
    public static let badge = Font.caption.weight(.semibold)
    /// Small diagnostics (render time, sizes).
    public static let technical = Font.caption.monospacedDigit()
}

public enum Motion {
    public static let quick = Animation.snappy(duration: 0.15)
    public static let standard = Animation.snappy(duration: 0.25)

    /// An animation that moves content (position, size, scale): none under Reduce Motion.
    /// `.animation(Motion.moving(Motion.standard, reduced: reduceMotion), value: isOpen)`
    public static func moving(_ animation: Animation, reduced: Bool) -> Animation? {
        reduced ? nil : animation
    }

    /// A transition that moves content: a fade under Reduce Motion.
    /// `.transition(Motion.moving(.move(edge: .top), reduced: reduceMotion))`
    public static func moving(_ transition: AnyTransition, reduced: Bool) -> AnyTransition {
        reduced ? .opacity : transition
    }
}

/// Reduce Motion as the design system reads it: `@ReduceMotion private var reduceMotion` in a
/// component. It is the system setting, unless a test or a preview sets
/// `.environment(\.reduceMotionOverride, true)`: SwiftUI's `accessibilityReduceMotion` is
/// read-only, so a test cannot turn it on.
@propertyWrapper
public struct ReduceMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var system
    @Environment(\.reduceMotionOverride) private var override

    public init() {}

    public var wrappedValue: Bool {
        override ?? system
    }
}

public extension EnvironmentValues {
    /// Set by tests and previews to check a component with Reduce Motion on or off.
    @Entry var reduceMotionOverride: Bool?
}
