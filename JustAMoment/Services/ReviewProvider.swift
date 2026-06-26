import Foundation

/// Abstraction over the engine that reviews a draft.
/// MVP ships a Claude-backed implementation; a local-LLM implementation
/// can be swapped in later without touching the UI or the view model.
protocol ReviewProvider {
    func review(draft: String) async throws -> ReviewResult
}
