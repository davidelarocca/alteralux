// swift-tools-version: 6.2
//
// AlteraluxKit: everything of the app that is not the app shell.
//
//   AlteraluxEngine  the generated bindings to the Rust engine
//   AlteraluxKit     image loading (Core Image), rendering, export, settings
//   AlteraluxUI      the app model and the screens
//
// `alteralux_ffiFFI.xcframework` (the compiled Rust engine) and
// `Sources/AlteraluxEngine/Generated/` (the UniFFI bindings) are build
// products: run `scripts/bootstrap.sh` once before opening this package.
//
// The allowed dependencies between targets are listed in
// docs/architecture-contracts.json: change both together.

import PackageDescription

let package = Package(
    name: "AlteraluxKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AlteraluxUI", targets: ["AlteraluxUI"]),
        .library(name: "AlteraluxKit", targets: ["AlteraluxKit"]),
        .library(name: "AlteraluxEngine", targets: ["AlteraluxEngine"]),
    ],
    dependencies: [
        .package(path: "../DesignSystem"),
    ],
    targets: [
        .binaryTarget(
            name: "alteralux_ffiFFI",
            path: "Frameworks/alteralux_ffiFFI.xcframework",
        ),
        .target(
            name: "AlteraluxEngine",
            dependencies: ["alteralux_ffiFFI"],
            swiftSettings: [
                // UniFFI's generated code predates Swift 6 strict concurrency.
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                // Native dependencies of the static Rust library:
                // Accelerate (BLAS) and Metal (GPU backend via wgpu).
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
            ],
        ),
        .target(
            name: "AlteraluxKit",
            dependencies: ["AlteraluxEngine"],
        ),
        .target(
            name: "AlteraluxUI",
            dependencies: [
                "AlteraluxKit",
                "AlteraluxEngine",
                .product(name: "DesignSystem", package: "DesignSystem"),
            ],
        ),
        .testTarget(
            name: "AlteraluxEngineTests",
            dependencies: ["AlteraluxEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)],
        ),
        .testTarget(
            name: "AlteraluxKitTests",
            dependencies: ["AlteraluxKit"],
        ),
        .testTarget(
            name: "AlteraluxUITests",
            dependencies: [
                "AlteraluxUI",
                // The shared components are checked here, where the test helpers are.
                .product(name: "DesignSystem", package: "DesignSystem"),
            ],
        ),
    ],
)
