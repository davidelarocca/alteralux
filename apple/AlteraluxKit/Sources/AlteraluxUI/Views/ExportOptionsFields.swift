import AlteraluxKit
import DesignSystem
import SwiftUI

/// The rows of a form that choose how developed photos are written: format, color profile,
/// quality, size and metadata. The same in the export sheet and in a workflow, where the format
/// and the size can also be left open, to be asked each time.
struct ExportOptionsFields: View {
    @Binding var options: ExportOptions
    /// For a workflow, the settings it asks each time it runs; `nil` for the export sheet.
    var asks: Binding<Set<Workflow.Setting>>?

    /// The long sides offered for the exported photo, in pixels, after the original size.
    static let longSides = [4096, 3072, 2048, 1600]

    /// The formats a photo is written in.
    static var formats: [WindowPopUpOption<ExportOptions.Format>] {
        [
            WindowPopUpOption(.jpeg, title: String(localized: "JPEG")),
            WindowPopUpOption(.heic, title: String(localized: "HEIC (10-bit)")),
            WindowPopUpOption(.tiff, title: String(localized: "TIFF (16-bit)")),
            WindowPopUpOption(.png, title: String(localized: "PNG (16-bit)")),
        ]
    }

    /// The sizes a photo is written at: the original's, or a long side in pixels.
    static var sizes: [WindowPopUpOption<Int?>] {
        [WindowPopUpOption(Int?.none, title: String(localized: "Original"))]
            + longSides.map { side in
                WindowPopUpOption(Int?.some(side), title: String(localized: "\(side) px on the long side"))
            }
    }

    var body: some View {
        if let asks {
            WindowPopUp("Format", selection: Self.asking(.format, asks, $options.format), options: Self.askingOptions(Self.formats))
        } else {
            WindowPopUp("Format", selection: $options.format, options: Self.formats)
        }
        WindowPopUp("Color profile", selection: $options.colorProfile, options: [
            WindowPopUpOption(.sRGB, title: String(localized: "sRGB")),
            WindowPopUpOption(.displayP3, title: String(localized: "Display P3")),
        ])
        if options.format == .jpeg || options.format == .heic || asks?.wrappedValue.contains(.format) == true {
            Slider(value: $options.quality, in: 0.5 ... 1) {
                Text("Quality")
            }
        }
        if let asks {
            WindowPopUp("Size", selection: Self.asking(.size, asks, $options.longSide), options: Self.askingOptions(Self.sizes))
        } else {
            WindowPopUp("Size", selection: $options.longSide, options: Self.sizes)
        }
        Toggle("Include camera metadata", isOn: $options.copiesMetadata)
    }

    /// `options` after "Ask Each Time".
    static func askingOptions<Value>(_ options: [WindowPopUpOption<Value>]) -> [WindowPopUpOption<Asked<Value>>] {
        [WindowPopUpOption(.ask, title: String(localized: "Ask Each Time"))]
            + options.map { WindowPopUpOption(.value($0.value), title: $0.title) }
    }

    /// A setting's value, or "Ask Each Time": choosing a value keeps it, choosing to ask keeps
    /// the value too, offered first when the workflow asks.
    static func asking<Value>(
        _ setting: Workflow.Setting, _ asks: Binding<Set<Workflow.Setting>>, _ value: Binding<Value>,
    ) -> Binding<Asked<Value>> {
        Binding(
            get: { asks.wrappedValue.contains(setting) ? .ask : .value(value.wrappedValue) },
            set: { choice in
                switch choice {
                case .ask:
                    asks.wrappedValue.insert(setting)
                case let .value(chosen):
                    asks.wrappedValue.remove(setting)
                    value.wrappedValue = chosen
                }
            },
        )
    }
}

/// A setting chosen in a workflow, or left open to be asked each time.
enum Asked<Value: Hashable>: Hashable {
    case ask
    case value(Value)
}
