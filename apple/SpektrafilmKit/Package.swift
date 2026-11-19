// swift-tools-version: 6.2
//
// SpektrafilmKit: the Swift side of the film engine.
//
//   SpektrafilmEngine  the generated bindings to the Rust engine
//   SpektrafilmKit     image loading (Core Image), rendering, export, settings
//
// `spektrafilm_ffiFFI.xcframework` (the compiled Rust engine) and
// `Sources/SpektrafilmEngine/Generated/` (the UniFFI bindings) are build
// products: run `scripts/build-engine.sh` once before opening this package.

import PackageDescription

let package = Package(
    name: "SpektrafilmKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SpektrafilmKit", targets: ["SpektrafilmKit"]),
        .library(name: "SpektrafilmEngine", targets: ["SpektrafilmEngine"]),
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
        .testTarget(
            name: "SpektrafilmEngineTests",
            dependencies: ["SpektrafilmEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SpektrafilmKitTests",
            dependencies: ["SpektrafilmKit"]
        ),
    ]
)
