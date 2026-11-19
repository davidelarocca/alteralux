import Foundation
import Testing
@testable import SpektrafilmEngine

/// The upstream data folder, straight from the git submodule.
private let dataDirectory: String = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // SpektrafilmEngineTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // SpektrafilmKit
    .deletingLastPathComponent()  // apple
    .deletingLastPathComponent()  // repository root
    .appendingPathComponent("engine/vendor/spektrafilm-rs/data")
    .path

private func chart(width: Int, height: Int) -> [Float] {
    var pixels: [Float] = []
    pixels.reserveCapacity(width * height * 3)
    for y in 0..<height {
        for x in 0..<width {
            let grey = 0.184 * pow(2, 8 * Float(x) / Float(width - 1) - 5)
            let tint = Float(y) / Float(height - 1)
            pixels += [grey * (1 + 0.5 * tint), grey, grey * (1 - 0.5 * tint)]
        }
    }
    return pixels
}

@Suite struct EngineTests {
    @Test func listsStocks() throws {
        let engine = try Engine(dataDir: dataDirectory, backend: .cpu)
        let stocks = try engine.stocks()
        #expect(stocks.contains { $0.id == "kodak_portra_400" && $0.kind == .film })
        #expect(stocks.contains { $0.id == "kodak_portra_endura" && $0.kind == .paper })
    }

    @Test(arguments: [BackendPreference.cpu, .automatic])
    func rendersAChart(backend: BackendPreference) throws {
        let engine = try Engine(dataDir: dataDirectory, backend: backend)
        let source = try SourceImage.fromFloats(chart(width: 64, height: 40), width: 64, height: 40, channels: 3)
        let image = try engine.render(
            source: source,
            request: RenderRequest(film: "kodak_portra_400", print: "kodak_portra_endura")
        )
        #expect(image.width() == 64 && image.height() == 40)
        let bytes = image.pixels(format: .rgbaF32)
        #expect(bytes.count == 64 * 40 * 16)
        let values = bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        #expect(values.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
        print("backend \(image.stats().backend): \(image.stats().totalMs) ms")
    }

    @Test func rejectsUnknownParameters() throws {
        let engine = try Engine(dataDir: dataDirectory, backend: .cpu)
        #expect(throws: EngineError.self) {
            _ = try engine.resolveParamsJson(paramsJson: #"{"camera": {"exposure": 1}}"#)
        }
    }
}
