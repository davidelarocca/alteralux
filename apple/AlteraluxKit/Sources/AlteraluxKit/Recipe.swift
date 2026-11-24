import Foundation

/// A look saved under a name, to give to other photos, and the files it writes when photos are
/// developed with it.
///
/// A recipe holds every adjustment but the white balance and the frame: the temperature and the
/// tint belong to the light of each photo, and the crop to its picture, so a recipe saved on one
/// photo leaves them alone on the others (ADR 0009, ADR 0010). It does remember whether the
/// exposure and the white balance were automatic when it was saved: a recipe saved that way
/// starts each photo from its own light (ADR 0021).
/// A photo that receives a recipe keeps only the adjustments: it does not remember the recipe,
/// and a recipe changed later changes no photo. See ADR 0009.
public struct Recipe: NamedItem, Equatable {
    public static let storageKey = "recipe"

    public let id: UUID
    public var name: String
    /// The look. Its temperature, tint and crop are always `nil`; its `autoWhiteBalance` says
    /// whether the white balance was automatic when the recipe was saved.
    public let look: DevelopSettings
    /// The film model the look was made with (`FilmModel.version` when the recipe was saved);
    /// `nil` for a recipe saved before the app wrote it down. A rename keeps it.
    public let filmModel: String?
    /// The files written when photos are developed with the recipe, and what is asked each time.
    public var files: RecipeFiles

    /// A recipe with the look of `settings`, made with the film model the app is built with
    /// unless another is given, and writing the files a new recipe writes unless others are given.
    public init(
        id: UUID = UUID(), name: String, from settings: DevelopSettings, filmModel: String? = FilmModel.version,
        files: RecipeFiles = RecipeFiles(),
    ) {
        self.id = id
        self.name = name
        var look = DevelopSettings().takingLook(of: settings)
        look.autoWhiteBalance = settings.autoWhiteBalance
        self.look = look
        self.filmModel = filmModel
        self.files = files
    }

    /// Reads a saved recipe. A white balance or a crop found in it, which only a file written by
    /// hand can hold, is left out. A recipe saved before recipes wrote files (ADR 0021) writes
    /// what a new one does.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            name: values.decode(String.self, forKey: .name),
            from: values.decode(DevelopSettings.self, forKey: .look),
            filmModel: values.decodeIfPresent(String.self, forKey: .filmModel),
            files: values.decodeIfPresent(RecipeFiles.self, forKey: .files) ?? RecipeFiles(),
        )
    }

    /// The adjustments a photo with `settings` has once it received this recipe: its look, on
    /// the photo's own white balance, lens correction and frame. The exposure is the meter's
    /// when the recipe was saved with the automatic exposure, and the white balance is measured
    /// in the photo when the recipe was saved with the automatic one, unless a white balance was
    /// chosen for the photo by hand.
    public func applied(to settings: DevelopSettings) -> DevelopSettings {
        var result = settings.takingLook(of: look)
        if look.autoWhiteBalance, result.temperature == nil, result.tint == nil {
            result.autoWhiteBalance = true
        }
        return result
    }
}

public extension DevelopSettings {
    /// These adjustments with the look of `other`: everything of `other` but the white balance,
    /// the lens correction, the crop and the RAW decoder's noise reduction and highlight recovery,
    /// which belong to this photo's light, lens, picture and sensor and stay as they are here. What a recipe gives a photo, and what pasting the adjustments
    /// of another photo does.
    func takingLook(of other: DevelopSettings) -> DevelopSettings {
        var result = other
        result.temperature = temperature
        result.tint = tint
        result.autoWhiteBalance = autoWhiteBalance
        result.lensCorrection = lensCorrection
        result.crop = crop
        result.rawDecoding = rawDecoding
        return result
    }
}
