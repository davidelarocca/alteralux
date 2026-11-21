import CoreImage
import Foundation

/// Applies a lens profile, or the corrections the camera recorded, to a photo with Core Image: distortion, chromatic aberration and
/// vignetting, on the scene-linear pixels out of the decoder, before the frame and before the engine
/// (ADR 0002, ADR 0010).
///
/// For each pixel of the corrected picture the kernel finds where it lies in the photo as shot, for
/// red, green and blue apart, samples it there and lifts the darkening of the lens's corners at that
/// place. The math is the one of `LensCorrection.sourcePoint(ofCorrected:channel:)` and
/// `LensCorrection.vignettingGain(at:)`, which the tests compare it with; the parameters are the
/// correction's, in its pixels (the first pixel's center at the origin).
enum LensWarp {
    /// The kernels, compiled once: one for lens profiles, one for the camera's own curves.
    private static let kernels = (try? CIKernel.kernels(withMetalString: source)) ?? []
    private static let kernel = kernels.first { $0.name == "lensCorrect" }
    private static let cameraKernel = kernels.first { $0.name == "lensCorrectByKnots" }

    /// Whether the kernel compiled on this Mac. Without it photos are left uncorrected.
    static var isAvailable: Bool {
        kernel != nil && cameraKernel != nil
    }

    /// `image`, the whole photo or a reduced copy of it, corrected for its lens.
    ///
    /// - Parameter fullSize: the size of the whole photo `correction` was made for, in pixels.
    static func apply(_ correction: LensCorrection, to image: CIImage, fullSize: CGSize) -> CIImage {
        guard let kernel, fullSize.width > 0 else { return image }
        let extent = image.extent
        // Pixels of `image` per pixel of the whole photo.
        let factor = extent.width / fullSize.width
        let distortion = polynomial(of: correction)
        let red = correction.tcaModel == .none ? SIMD3(1, 0, 0) : correction.tcaRed
        let blue = correction.tcaModel == .none ? SIMD3(1, 0, 0) : correction.tcaBlue
        let arguments: [Any] = [
            image.clampedToExtent(),
            CIVector(x: distortion.x, y: distortion.y, z: distortion.z, w: distortion.w),
            CIVector(
                x: correction.center.x, y: correction.center.y, z: correction.distortionUnit, w: correction.scale,
            ),
            CIVector(x: red.x, y: red.y, z: red.z, w: 0),
            CIVector(x: blue.x, y: blue.y, z: blue.z, w: 0),
            CIVector(
                x: correction.vignettingTerms.x, y: correction.vignettingTerms.y, z: correction.vignettingTerms.z,
                w: correction.vignettingUnit,
            ),
            CIVector(x: extent.minX, y: extent.maxY, z: factor, w: 0),
        ]
        let corrected = kernel.apply(extent: extent, roiCallback: { _, _ in image.extent }, arguments: arguments)
        return corrected?.cropped(to: extent) ?? image
    }

    /// `image`, the whole photo or a reduced copy of it, corrected with the curves its camera
    /// recorded. The math is `CameraLensCorrection.sourcePoint(ofCorrected:channel:)` and
    /// `CameraLensCorrection.vignettingGain(at:)`.
    ///
    /// - Parameter fullSize: the size of the whole photo `correction` was made for, in pixels.
    static func apply(_ correction: CameraLensCorrection, to image: CIImage, fullSize: CGSize) -> CIImage {
        guard let cameraKernel, fullSize.width > 0 else { return image }
        let extent = image.extent
        let factor = extent.width / fullSize.width
        var arguments: [Any] = [image.clampedToExtent()]
        for curve in [correction.red, correction.green, correction.blue, correction.vignetting] {
            arguments += knotVectors(of: curve)
        }
        arguments += [
            CIVector(x: correction.center.x, y: correction.center.y, z: correction.unit, w: correction.scale),
            CIVector(x: extent.minX, y: extent.maxY, z: factor, w: CGFloat(correction.knotCount)),
        ]
        let corrected = cameraKernel.apply(extent: extent, roiCallback: { _, _ in image.extent }, arguments: arguments)
        return corrected?.cropped(to: extent) ?? image
    }

    /// The sixteen values of a curve as four vectors, the knots past its end repeating its last
    /// value.
    static func knotVectors(of curve: [Double]) -> [CIVector] {
        let values = (0 ..< 16).map { CGFloat(curve[min($0, curve.count - 1)]) }
        return stride(from: 0, to: 16, by: 4).map { start in
            CIVector(x: values[start], y: values[start + 1], z: values[start + 2], w: values[start + 3])
        }
    }

    /// The distortion of `correction` as one polynomial, `f(r) = 1 + d1 r + d2 r^2 + d3 r^3 +
    /// d4 r^4`, returned as (d1, d2, d3, d4): every model of `LensCorrection` is one.
    static func polynomial(of correction: LensCorrection) -> SIMD4<Double> {
        let terms = correction.distortionTerms
        return switch correction.distortionModel {
        case .none: .zero
        case .poly3: SIMD4(0, terms.x, 0, 0)
        case .poly5: SIMD4(0, terms.x, 0, terms.y)
        case .ptlens: SIMD4(terms.z, terms.y, terms.x, 0)
        }
    }

    /// The kernel's Metal source. Coordinates go from Core Image's (origin at the bottom left, in
    /// pixels of `image`) to the whole photo's (origin at the top left), and back to sample.
    private static let source = """
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    // distortion: d1..d4 of f(r) = 1 + d1 r + d2 r^2 + d3 r^3 + d4 r^4, the radius in the photo as
    // shot being r f(r). geometry: center x, y, pixels per unit, scale. red, blue: v, c, b of
    // g(r) = v + c r + b r^2. vignetting: k1, k2, k3, pixels per unit. frame: the left and top of
    // the image in Core Image's coordinates, and its pixels per pixel of the whole photo.
    [[stitchable]] float4 lensCorrect(
        coreimage::sampler photo, float4 distortion, float4 geometry, float4 red, float4 blue,
        float4 vignetting, float4 frame, coreimage::destination dest
    ) {
        float factor = frame.z;
        float2 here = dest.coord();
        // In pixels of the whole photo from its top left, the first pixel's center at (0, 0).
        float2 point = float2(here.x - frame.x, frame.y - here.y) / factor - 0.5;
        float2 center = geometry.xy;
        float unit = geometry.z;

        float2 corrected = (point - center) / (unit * geometry.w);
        float r = length(corrected);
        float f = 1.0 + r * (distortion.x + r * (distortion.y + r * (distortion.z + r * distortion.w)));
        float2 green = corrected * f;
        float rg = length(green);
        float2 points[3] = {
            green * (red.x + red.y * rg + red.z * rg * rg),
            green,
            green * (blue.x + blue.y * rg + blue.z * rg * rg)
        };

        float3 color;
        for (int channel = 0; channel < 3; channel++) {
            float2 shot = center + points[channel] * unit;
            float2 offset = (shot - center) / vignetting.w;
            float r2 = dot(offset, offset);
            float gain = 1.0 / (1.0 + r2 * (vignetting.x + r2 * (vignetting.y + r2 * vignetting.z)));
            float2 sampled = float2((shot.x + 0.5) * factor + frame.x, frame.y - (shot.y + 0.5) * factor);
            color[channel] = photo.sample(photo.transform(sampled))[channel] * gain;
        }
        return float4(color, 1.0);
    }

    // The value of a curve of `count` knots at `radius`, in half diagonals: knot i lies at
    // (i + 0.5) / (count - 1), with straight lines between knots and the end values beyond.
    static float knotValue(thread const float *values, int count, float radius) {
        float position = radius * float(count - 1) - 0.5;
        if (position <= 0.0) { return values[0]; }
        if (position >= float(count - 1)) { return values[count - 1]; }
        int index = int(position);
        return mix(values[index], values[index + 1], position - float(index));
    }

    // r0..r3, g0..g3, b0..b3: the sixteen knots of the factor of the radius for red, green and
    // blue. v0..v3: those of the light the lens keeps. geometry: center x, y, half diagonal in
    // pixels, scale. frame: as above, and the number of knots.
    [[stitchable]] float4 lensCorrectByKnots(
        coreimage::sampler photo,
        float4 r0, float4 r1, float4 r2, float4 r3, float4 g0, float4 g1, float4 g2, float4 g3,
        float4 b0, float4 b1, float4 b2, float4 b3, float4 v0, float4 v1, float4 v2, float4 v3,
        float4 geometry, float4 frame, coreimage::destination dest
    ) {
        float curves[3][16] = {
            { r0.x, r0.y, r0.z, r0.w, r1.x, r1.y, r1.z, r1.w, r2.x, r2.y, r2.z, r2.w, r3.x, r3.y, r3.z, r3.w },
            { g0.x, g0.y, g0.z, g0.w, g1.x, g1.y, g1.z, g1.w, g2.x, g2.y, g2.z, g2.w, g3.x, g3.y, g3.z, g3.w },
            { b0.x, b0.y, b0.z, b0.w, b1.x, b1.y, b1.z, b1.w, b2.x, b2.y, b2.z, b2.w, b3.x, b3.y, b3.z, b3.w }
        };
        float light[16] = {
            v0.x, v0.y, v0.z, v0.w, v1.x, v1.y, v1.z, v1.w, v2.x, v2.y, v2.z, v2.w, v3.x, v3.y, v3.z, v3.w
        };
        int count = int(frame.w);
        float factor = frame.z;
        float2 here = dest.coord();
        float2 point = float2(here.x - frame.x, frame.y - here.y) / factor - 0.5;
        float2 center = geometry.xy;
        float unit = geometry.z;

        float2 offset = (point - center) / geometry.w;
        float radius = length(offset) / unit;
        float3 color;
        for (int channel = 0; channel < 3; channel++) {
            float2 shot = center + offset * knotValue(curves[channel], count, radius);
            float gain = 1.0 / max(knotValue(light, count, length(shot - center) / unit), 1e-4);
            float2 sampled = float2((shot.x + 0.5) * factor + frame.x, frame.y - (shot.y + 0.5) * factor);
            color[channel] = photo.sample(photo.transform(sampled))[channel] * gain;
        }
        return float4(color, 1.0);
    }
    """
}
