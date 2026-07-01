import Foundation

protocol VisionProvider {
    func interpret(
        imageURL: URL,
        instruction: String?,
        language: OutputLanguage
    ) async throws -> VisionInterpretationResult
}
