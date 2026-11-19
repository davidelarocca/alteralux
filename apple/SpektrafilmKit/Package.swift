// swift-tools-version: 6.2
//
// SpektrafilmKit: everything of the app that is not the app shell.
//
//   SpektrafilmEngine  the generated bindings to the Rust engine
//   SpektrafilmKit     image loading (Core Image), rendering, export, settings
//   SpektrafilmUI      the app model and the screens
//
// `spektrafilm_ffiFFI.xcframework` (the compiled Rust engine) and
// `Sources/SpektrafilmEngine/Generated/` (the UniFFI bindings) are build
// products: run `scripts/bootstrap.sh` once before opening this package.
//
// The allowed dependencies between targets are listed in
// docs/architecture-contracts.json: change both together.

import PackageDescription

let package = Package(
    name: "SpektrafilmKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SpektrafilmUI", targets: ["SpektrafilmUI"]),
        .library(name: "SpektrafilmKit", targets: ["SpektrafilmKit"]),
        .library(name: "SpektrafilmEngine", targets: ["SpektrafilmEngine"]),
    ],
    dependencies: [
        .package(path: "../DesignSystem")
    ],
    targets: [
        .binaryTarget(
            name: "spektrafilm_ffiFFI",
            path: "Frameworks/spektrafilm_ffiFFI.xcframework"
        ),
        .target(
            name: "SpektrafilmEngine",
            dependencies: ["spektrafilm_ffiFFI"],
            swiftSettings: [
                // UniFFI's generated code predates Swift 6 strict concurrency.
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                // Native dependencies of the static Rust library:
                // Accelerate (BLAS) and Metal (GPU backend via wgpu).
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
            ]
        ),
        .target(
            name: "SpektrafilmKit",
            dependencies: ["SpektrafilmEngine"]
        ),
        .target(
            name: "SpektrafilmUI",
            dependencies: [
                "SpektrafilmKit",
                "SpektrafilmEngine",
                .product(name: "DesignSystem", package: "DesignSystem"),
            ]
        ),
        .testTarget(
            name: "SpektrafilmEngineTests",
            dependencies: ["SpektrafilmEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SpektrafilmKitTests",
            dependencies: ["SpektrafilmKit"]
        ),
        .testTarget(
            name: "SpektrafilmUITests",
            dependencies: ["SpektrafilmUI"]
        ),
    ]
)
