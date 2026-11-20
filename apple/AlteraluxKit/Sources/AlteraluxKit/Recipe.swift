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

    /// A recipe with the look of `settings`.
    public init(id: UUID = UUID(), name: String, from settings: DevelopSettings) {
        self.id = id
        self.name = name
        look = DevelopSettings().takingLook(of: settings)
    }

    /// Reads a saved recipe. A white balance or a crop found in it, which only a file written by
    /// hand can hold, is left out.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            name: values.decode(String.self, forKey: .name),
            from: values.decode(DevelopSettings.self, forKey: .look),
        )
    }

    /// The adjustments a photo with `settings` has once it received this recipe.
    public func applied(to settings: DevelopSettings) -> DevelopSettings {
        settings.takingLook(of: look)
    }
}

public extension DevelopSettings {
    /// These adjustments with the look of `other`: everything of `other` but the white balance
    /// and the crop, which stay as they are here. What a recipe gives a photo, and what pasting
    /// the adjustments of another photo does.
    func takingLook(of other: DevelopSettings) -> DevelopSettings {
        var result = other
        result.temperature = temperature
        result.tint = tint
        result.crop = crop
        return result
    }
}
