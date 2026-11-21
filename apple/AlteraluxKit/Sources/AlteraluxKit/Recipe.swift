import Foundation

/// A look saved under a name, to give to other photos.
///
/// A recipe holds every adjustment but the white balance and the frame: the temperature and the
/// tint belong to the light of each photo, and the crop to its picture, so a recipe saved on one
/// photo leaves them alone on the others (ADR 0009, ADR 0010).
/// A photo that receives a recipe keeps only the adjustments: it does not remember the recipe,
/// and a recipe changed later changes no photo. See ADR 0009.
public struct Recipe: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    /// The look. Its temperature, tint and crop are always `nil`.
    public let look: DevelopSettings
    /// Whether each photo that receives the recipe starts from its own light: the exposure
    /// metered in it, and an automatic white balance where the photo's is the camera's.
    public var adaptsToEachPhoto: Bool

    /// A recipe with the look of `settings`.
    public init(id: UUID = UUID(), name: String, from settings: DevelopSettings, adaptsToEachPhoto: Bool = false) {
        self.id = id
        self.name = name
        look = DevelopSettings().takingLook(of: settings)
        self.adaptsToEachPhoto = adaptsToEachPhoto
    }

    /// Reads a saved recipe. A white balance or a crop found in it, which only a file written by
    /// hand can hold, is left out.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            name: values.decode(String.self, forKey: .name),
            from: values.decode(DevelopSettings.self, forKey: .look),
            adaptsToEachPhoto: values.decodeIfPresent(Bool.self, forKey: .adaptsToEachPhoto) ?? false,
        )
    }

    /// The adjustments a photo with `settings` has once it received this recipe. A recipe that
    /// adapts meters each photo, and chooses its white balance automatically unless one was
    /// chosen for it by hand.
    public func applied(to settings: DevelopSettings) -> DevelopSettings {
        var result = settings.takingLook(of: look)
        if adaptsToEachPhoto {
            result.autoExposure = true
            if result.temperature == nil, result.tint == nil {
                result.autoWhiteBalance = true
            }
        }
        return result
    }
}

public extension DevelopSettings {
    /// These adjustments with the look of `other`: everything of `other` but the white balance,
    /// the lens correction and the crop, which belong to this photo's light, lens and picture
    /// and stay as they are here. What a recipe gives a photo, and what pasting the adjustments
    /// of another photo does.
    func takingLook(of other: DevelopSettings) -> DevelopSettings {
        var result = other
        result.temperature = temperature
        result.tint = tint
        result.autoWhiteBalance = autoWhiteBalance
        result.lensCorrection = lensCorrection
        result.crop = crop
        return result
    }
}
