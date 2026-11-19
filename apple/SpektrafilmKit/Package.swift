// swift-tools-version: 6.0
//
// SpektrafilmKit: the Swift side of the engine bridge.
//
// `spektrafilm_ffiFFI.xcframework` (the compiled Rust engine) and
// `Sources/SpektrafilmEngine/Generated/` (the UniFFI bindings) are build
// products: run `scripts/build-engine.sh` once before opening this package.

import PackageDescription

let package = Package(
    name: "SpektrafilmKit",
    platforms: [.macOS(.v15)],
    products: [
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
            ]
        ),
        .testTarget(
            name: "SpektrafilmEngineTests",
            dependencies: ["SpektrafilmEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
