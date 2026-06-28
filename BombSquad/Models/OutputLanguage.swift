import Foundation

/// The language the deliverable (`revised_text`) is written in. The default is
/// Japanese: normally the user writes Japanese and reads Japanese, so both
/// compose (softened message to send) and transform (readable received message)
/// stay in Japanese. Selecting another language makes the result come out in it
/// regardless of the input language (e.g. write Japanese → send English; scan
/// Chinese → read Japanese).
enum OutputLanguage: String, CaseIterable, Identifiable {
    case japanese
    case english

    var id: String { rawValue }

    /// Shown in the picker.
    var displayName: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        }
    }

    /// Language name injected into the prompt instruction.
    var promptName: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "英語"
        }
    }
}
