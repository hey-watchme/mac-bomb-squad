import Foundation

/// A single durable memory: either the user's own style profile (persona,
/// L3) or a per-contact relationship note (L2). Cards are plain Markdown so
/// the user can read and edit everything the app knows about them — the
/// memory page is a transparency feature, not just storage.
struct MemoryCard: Identifiable, Equatable {
    enum Kind: String {
        case persona
        case relationship
    }

    /// Where the current content came from. `userEdited` wins conceptually:
    /// distillation appends but never rewrites what the user wrote.
    enum Source: String {
        case bootstrap
        case distilled
        case userEdited = "user_edited"
    }

    let id: String
    let kind: Kind
    /// Display name of the contact for relationship cards; nil for persona.
    let subject: String?
    var contentMD: String
    var source: Source
    let createdAt: Date
    var updatedAt: Date
}

/// Memory selected for injection into one review call: the persona card plus
/// the relationship card matched against the situational context.
struct MemoryInjection {
    let personaMD: String?
    let relationshipSubject: String?
    let relationshipMD: String?

    var isEmpty: Bool { personaMD == nil && relationshipMD == nil }
}
