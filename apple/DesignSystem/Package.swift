// swift-tools-version: 6.2
//
// DesignSystem: tokens and shared SwiftUI components of the app.
//
// The only place where raw visual values (colors, spacing, radii, font sizes,
// animation timings) are allowed. It depends on nothing app-specific.

import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            resources: [.process("Resources")],
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"],
        ),
    ],
)
