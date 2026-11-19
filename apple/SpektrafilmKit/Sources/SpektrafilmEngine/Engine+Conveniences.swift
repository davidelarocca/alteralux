import Foundation

// Small Swift-side helpers on top of the UniFFI-generated API
// (`Generated/spektrafilm_ffi.swift`, produced by scripts/build-engine.sh).

extension SourceImage {
    /// Creates a source from scene-linear `Float` pixels (RGB or RGBA,
    /// interleaved, no row padding).
    public static func fromFloats(
        _ pixels: [Float], width: Int, height: Int, channels: Int
    ) throws -> SourceImage {
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return try SourceImage.fromF32Pixels(
            width: UInt32(width), height: UInt32(height), channels: UInt8(channels), pixels: data
        )
    }
}

extension RenderRequest {
    /// A request with default parameters: Rec. 2020 scene-linear in,
    /// display-linear sRGB out (the reference spektrafilm look).
    public init(film: String, print: String, paramsJSON: String = "", maxDimension: Int = 0) {
        self.init(
            film: film,
            print: print,
            paramsJson: paramsJSON,
            color: RenderColor(input: .rec2020, output: .srgb),
            maxDimension: UInt32(maxDimension)
        )
    }
}
