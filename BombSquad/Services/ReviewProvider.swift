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
    /// `context` is the optional L1 situational context (frontmost app and the
    /// conversation around the focused field) captured when the panel was
    /// summoned; nil when capture is off, not permitted, or excluded by the user.
    /// `memory` carries the persona/relationship cards (L2/L3) selected for
    /// this call; nil when memory is off or empty.
    func review(
        draft: String,
        mode: ReviewMode,
        language: OutputLanguage,
        context: SituationalContext?,
        memory: MemoryInjection?
    ) async throws -> ReviewResult
}

extension ReviewProvider {
    func review(draft: String, mode: ReviewMode, language: OutputLanguage) async throws -> ReviewResult {
        try await review(draft: draft, mode: mode, language: language, context: nil, memory: nil)
    }
}
