import Foundation

/// Category of a single review finding.
/// Mirrors the enum exposed to the model through the review tool schema.
enum IssueCategory: String, Codable, CaseIterable {
    case typo          // misspellings / typos
    case impoliteness  // rude or aggressive tone
    case unclear       // ambiguous or hard-to-read phrasing

    /// Human-facing Japanese label.
    var label: String {
        switch self {
        case .typo: return "誤字脱字"
        case .impoliteness: return "失礼・攻撃的"
        case .unclear: return "分かりにくい"
        }
    }
}

/// Relative importance of a finding.
enum Severity: String, Codable {
    case low, medium, high

    var label: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }

    /// Sort weight, high first.
    var weight: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

/// A single issue found in the draft.
/// `id` is generated locally and is intentionally excluded from the API JSON.
struct ReviewIssue: Identifiable, Codable, Hashable {
    var id = UUID()
    let category: IssueCategory
    let severity: Severity
    let excerpt: String      // offending span from the draft
    let explanation: String  // why it is a problem
    let suggestion: String   // how to fix it

    private enum CodingKeys: String, CodingKey {
        case category, severity, excerpt, explanation, suggestion
    }
}

/// Full structured result returned by the review tool.
struct ReviewResult: Codable, Hashable {
    let issues: [ReviewIssue]
    let revisedText: String   // full rewritten draft (deploy candidate)
    let summary: String       // one-line summary

    private enum CodingKeys: String, CodingKey {
        case issues
        case revisedText = "revised_text"
        case summary
    }

    /// Findings ordered by severity, high first.
    var sortedIssues: [ReviewIssue] {
        issues.sorted { $0.severity.weight < $1.severity.weight }
    }
}
