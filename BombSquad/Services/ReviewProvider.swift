import Foundation

/// Which direction the middle layer is operating in.
/// - compose: the user's own outgoing draft → remove hostility before sending.
/// - transform: a received message → restructure into something readable for
///   someone who has difficulty parsing it (the receiving side).
enum ReviewMode {
    case compose
    case transform
}

/// Abstraction over the engine that reviews/transforms text.
/// MVP ships a Claude-backed implementation; a local-LLM implementation
/// can be swapped in later without touching the UI or the view model.
protocol ReviewProvider {
    func review(draft: String, mode: ReviewMode, language: OutputLanguage) async throws -> ReviewResult
}
