import Foundation

/// What a render smaller than the photo needs, of the lengths the engine takes in pixels, to look
/// as the photo developed whole looks once seen at that render's size (ADR 0023).
///
/// The engine sizes grain and halation from the film format, so most of the look follows the
/// size on its own. Three lengths do not: the grain's blur, the scan's sharpening and the scan's
/// lens blur are given in pixels, and weigh as much on a preview as on the whole photo, where
/// they mostly vanish once it is seen smaller. Measured on 2026-11-25 with
/// `PreviewFidelityTests`: before, a preview had two thirds of the grain of the photo seen at its
/// size and three to six times its sharpening.
enum PixelScaling {
    /// The engine blurs the grain only above this many pixels (upstream `grain.rs` and the GPU
    /// backend: `grain_blur > 0.4`).
    static let grainBlurThreshold = 0.4

    /// The grain's blur for a render `scale` times the photo's size. The grain of a smaller render
    /// is formed at its own pixels, and a pixel of it holds the grain of the photo's pixels it
    /// covers: the blur it needs is the one that takes as much from the grain as the photo's blur
    /// still takes once its pixels are averaged into the render's. Neither half of a pixel's
    /// width nor the engine's threshold allows the length scaled down: at a third of the
    /// photo's size the 0.65 pixels of a new photo become 0.43, not 0.22, which the engine would
    /// skip.
    static func grainBlur(_ blur: Double, scale: Double) -> Double {
        guard scale < 1, blur > grainBlurThreshold else { return blur }
        let box = averaging(over: 1 / scale)
        let target = sumOfSquares(convolving(box, kernel(blur))) / sumOfSquares(box)
        let lightest = grainBlurThreshold + 0.0001
        // Less than the lightest blur the engine draws takes away: whichever is closer.
        if target >= sumOfSquares(kernel(lightest)) {
            return 1 - target < target - sumOfSquares(kernel(lightest)) ? 0 : lightest
        }
        var low = lightest, high = blur
        for _ in 0 ..< 40 {
            let middle = (low + high) / 2
            if sumOfSquares(kernel(middle)) > target { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }

    /// The scan's sharpening strength for a render `scale` times the photo's size, its radius
    /// left as it is. A radius scaled down falls under a pixel, where the engine's kernel no
    /// longer sharpens; the strength scaled instead matches the photo seen at the render's size
    /// within a quarter at a third and a sixth of it (`PreviewFidelityTests`).
    static func sharpenAmount(_ amount: Double, scale: Double) -> Double {
        scale < 1 ? amount * scale : amount
    }

    /// A blur of `sigma` pixels as the engine draws it: a Gaussian over `ceil(3σ)` pixels on
    /// each side (the GPU backend; the CPU's is a pixel narrower at most, with weights under
    /// 10⁻⁴ there), normalized.
    static func kernel(_ sigma: Double) -> [Double] {
        let radius = Int((3 * sigma).rounded(.up))
        let weights = (-radius ... radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let total = weights.reduce(0, +)
        return weights.map { $0 / total }
    }

    /// The mean over `width` pixels along one axis, the last one in part when `width` is not
    /// whole: what seeing a picture `width` times smaller does to it.
    static func averaging(over width: Double) -> [Double] {
        let whole = Int(width)
        let part = width - Double(whole)
        let weights = Array(repeating: 1.0, count: whole) + (part > 0.0001 ? [part] : [])
        return weights.map { $0 / width }
    }

    /// Along one axis, the share of a noise's variance a filter keeps, for a noise drawn per
    /// pixel: the sum of its squared weights.
    static func sumOfSquares(_ weights: [Double]) -> Double {
        weights.reduce(0) { $0 + $1 * $1 }
    }

    static func convolving(_ first: [Double], _ second: [Double]) -> [Double] {
        var result = Array(repeating: 0.0, count: first.count + second.count - 1)
        for (row, left) in first.enumerated() {
            for (column, right) in second.enumerated() {
                result[row + column] += left * right
            }
        }
        return result
    }
}
