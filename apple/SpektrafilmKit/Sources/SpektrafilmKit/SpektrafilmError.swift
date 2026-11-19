import Foundation

/// Errors raised by SpektrafilmKit itself (engine errors pass through as
/// `EngineError`).
public enum SpektrafilmError: Error, Equatable, Sendable, LocalizedError {
    /// The file could not be decoded as an image.
    case unreadableImage(URL)
    /// Core Image could not render the decoded image into a pixel buffer.
    case renderingFailed
    /// The engine output could not be wrapped in a `CGImage`.
    case invalidEngineOutput
    /// The advanced parameter text is not a JSON object.
    case invalidAdvancedParameters
    /// Writing the exported file failed.
    case exportFailed(String)
    /// The engine data folder is missing from the app bundle.
    case missingEngineData

    public var errorDescription: String? {
        switch self {
        case .unreadableImage(let url):
            "“\(url.lastPathComponent)” could not be opened as an image."
        case .renderingFailed:
            "The image could not be prepared for development."
        case .invalidEngineOutput:
            "The developed image could not be displayed."
        case .invalidAdvancedParameters:
            "The advanced parameters are not valid JSON."
        case .exportFailed(let reason):
            "The export failed: \(reason)"
        case .missingEngineData:
            "The film data is missing from the app."
        }
    }
}
