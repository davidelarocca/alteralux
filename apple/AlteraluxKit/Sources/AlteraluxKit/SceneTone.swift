import CoreImage
import Foundation

/// The highlights and the shadows of the scene, changed before the film sees it (ADR 0019).
///
/// Each is light added to, or taken from, one end of the scene: the film, the paper and the scan
/// then answer it as they would a scene lit that way. Middle gray stays where the exposure put it.
public struct SceneTone: Codable, Equatable, Sendable {
    /// From -1 to 1: darkens (below 0) or brightens the brightest parts of the scene.
    public var highlights: Double
    /// From -1 to 1: deepens (below 0) or lifts the darkest parts of the scene.
    public var shadows: Double

    public init(highlights: Double = 0, shadows: Double = 0) {
        self.highlights = highlights
        self.shadows = shadows
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        highlights = try values.value(.highlights, or: 0)
        shadows = try values.value(.shadows, or: 0)
    }

    /// Whether the scene is left as it is.
    public var isNeutral: Bool {
        highlights == 0 && shadows == 0
    }
}

extension SceneTone {
    /// The stops a slider at its end adds to the far end of the scene.
    static let reach = 2.0
    /// How many stops under middle gray the shadows' change takes to grow whole.
    static let shadowSpan = 6.0
    /// How many stops over middle gray the highlights' change takes to grow whole.
    static let highlightSpan = 5.0
    /// The light the engine's meter takes as middle gray.
    static let middleGray = 0.184

    /// The stops added to light of `luminance`, where `middleGray` is the scene's middle gray once
    /// exposed. What the kernel computes for every pixel, here for the tests to compare it with.
    ///
    /// Nothing at middle gray, growing smoothly toward each end and constant past it, and never
    /// so fast that a brighter part of the scene ends up darker than a darker one: at most a
    /// quarter of `reach` a stop for the shadows, three tenths for the highlights.
    func stops(atLuminance luminance: Double) -> Double {
        let stops = log2(max(luminance, 1e-6) / Self.middleGray)
        func eased(_ value: Double) -> Double {
            let clamped = min(max(value, 0), 1)
            return clamped * clamped * (3 - 2 * clamped)
        }
        return Self.reach * (shadows * eased(-stops / Self.shadowSpan) + highlights * eased(stops / Self.highlightSpan))
    }
}

/// What a decode needs to put the scene's light into the pixels: the meter's exposure, read on
/// the photo as it was shot (ADR 0022), and the highlights and shadows with the exposure they are
/// measured from (ADR 0019). `nil` from adjustments that leave the scene as it is: the exposure
/// by hand, and no change of highlights or shadows.
public struct SceneToneRequest: Equatable, Sendable {
    public let tone: SceneTone
    /// The exposure compensation, in stops: the highlights and the shadows are those of the scene
    /// once exposed. 0 while they are left alone: it then changes nothing of what is decoded.
    public let exposureEV: Double
    /// How the scene is metered; `nil` with the meter off.
    public let meteringMethod: MeteringMethod?

    /// What `settings` ask; `nil` when the exposure is by hand and they leave the highlights and
    /// the shadows alone.
    public init?(_ settings: DevelopSettings) {
        guard settings.autoExposure || !settings.sceneTone.isNeutral else { return nil }
        tone = settings.sceneTone
        exposureEV = settings.sceneTone.isNeutral ? 0 : settings.exposureEV
        meteringMethod = settings.autoExposure ? settings.meteringMethod : nil
    }
}

/// Changes the highlights and the shadows of a photo with Core Image, on the scene-linear pixels
/// out of the decoder, before the engine (ADR 0019). The math is `SceneTone.stops(atLuminance:)`.
enum SceneToneKernel {
    private static let kernel = (try? CIColorKernel.kernels(withMetalString: source))?
        .compactMap { $0 as? CIColorKernel }.first { $0.name == "sceneTone" }

    /// Whether the kernel compiled on this Mac. Without it the scene is left as it is.
    static var isAvailable: Bool {
        kernel != nil
    }

    /// `image` with the light of `tone`.
    ///
    /// - Parameters:
    ///   - meteredEV: the stops the meter adds to the photo. They are put into the pixels, so
    ///     that the film is then exposed with the meter off and the meter does not answer the
    ///     change of light; 0 with the meter off.
    ///   - exposureEV: the exposure compensation, which stays the engine's to apply: it only
    ///     says where the scene's middle gray is.
    /// - Returns: `nil` when the kernel is not available.
    static func apply(_ tone: SceneTone, to image: CIImage, meteredEV: Double, exposureEV: Double) -> CIImage? {
        let arguments: [Any] = [
            image, pow(2, meteredEV), pow(2, exposureEV), SceneTone.reach * tone.shadows,
            SceneTone.reach * tone.highlights,
        ]
        return kernel?.apply(extent: image.extent, roiCallback: { _, rect in rect }, arguments: arguments)
    }

    /// Rec. 2020 luminance, since the working space is the scene's (`ImageLoader.sceneColorSpace`).
    private static let source = """
    #include <CoreImage/CoreImage.h>
    extern "C" {
        namespace coreimage {
            float eased(float value) {
                float clamped = clamp(value, 0.0, 1.0);
                return clamped * clamped * (3.0 - 2.0 * clamped);
            }

            [[stitchable]] float4 sceneTone(sample_t pixel, float metered, float exposure, float shadows, float highlights) {
                float3 light = pixel.rgb * metered;
                float luminance = dot(light, float3(0.2627, 0.6780, 0.0593)) * exposure;
                float stops = log2(max(luminance, 1e-6) / \(SceneTone.middleGray));
                float added = shadows * eased(-stops / \(SceneTone.shadowSpan)) + highlights * eased(stops / \(SceneTone.highlightSpan));
                return float4(light * exp2(added), pixel.a);
            }
        }
    }
    """
}
