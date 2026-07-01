import Foundation

enum HistoryEntryMode: String, Sendable {
    case compose
    case transform

    var displayName: String {
        switch self {
        case .compose: return "送信"
        case .transform: return "受信"
        }
    }

    var sourceLabel: String {
        switch self {
        case .compose: return "原文"
        case .transform: return "選択文"
        }
    }
}

enum HistoryAction: String, Sendable {
    case sent
    case copied

    var displayName: String {
        switch self {
        case .sent: return "送信"
        case .copied: return "コピー"
        }
    }
}

struct HistoryEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let mode: HistoryEntryMode
    let sourceText: String
    let finalText: String
    let modelID: String?
    let modelName: String?
    let outputLanguage: String?
    let action: HistoryAction

    var usedReview: Bool {
        modelName != nil
    }
}

struct HistoryEntryInput: Sendable {
    let mode: HistoryEntryMode
    let sourceText: String
    let finalText: String
    let modelID: String?
    let modelName: String?
    let outputLanguage: String?
    let action: HistoryAction
}
