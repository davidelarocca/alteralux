import AlteraluxEngine

/// The film model that turns adjustments into pixels: the upstream engine the app is built with.
///
/// The same adjustments may give another picture once the engine is updated (a film measured
/// again, a stage of the simulation corrected). So what the app saves says which model it was
/// made with: a photo's adjustments (`EditStore`) and a recipe (`Recipe`). Nothing reads it back
/// yet but the tests; it is there for the day a look has to be told apart from one made before.
public enum FilmModel {
    /// The version of the upstream engine, as it declares it ("0.1.2").
    public static let version: String = engineVersion()
}
