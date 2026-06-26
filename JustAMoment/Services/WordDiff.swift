import Foundation

/// One segment of a word-level diff.
struct DiffSegment: Identifiable, Hashable {
    enum Kind { case equal, removed, added }
    let id = UUID()
    let kind: Kind
    let text: String
}

/// Lightweight word-level diff based on a longest-common-subsequence.
/// Used to highlight what the revision changed versus the original draft.
enum WordDiff {
    static func compute(original: String, revised: String) -> [DiffSegment] {
        let a = tokenize(original)
        let b = tokenize(revised)
        guard !a.isEmpty || !b.isEmpty else { return [] }

        // LCS length table.
        let n = a.count, m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1
                                             : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }

        // Backtrack into coalesced segments.
        var segments: [DiffSegment] = []
        var i = 0, j = 0
        func append(_ kind: DiffSegment.Kind, _ token: String) {
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1] = DiffSegment(kind: kind, text: last.text + token)
            } else {
                segments.append(DiffSegment(kind: kind, text: token))
            }
        }
        while i < n && j < m {
            if a[i] == b[j] {
                append(.equal, a[i]); i += 1; j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                append(.removed, a[i]); i += 1
            } else {
                append(.added, b[j]); j += 1
            }
        }
        while i < n { append(.removed, a[i]); i += 1 }
        while j < m { append(.added, b[j]); j += 1 }
        return segments
    }

    /// Split into tokens while keeping whitespace/newlines as their own tokens,
    /// so Japanese text (few spaces) still diffs at character granularity.
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in text {
            if ch.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else if ch.isLetter || ch.isNumber {
                // Keep ASCII words together; treat CJK as single-character tokens.
                if ch.isASCII {
                    current.append(ch)
                } else {
                    if !current.isEmpty { tokens.append(current); current = "" }
                    tokens.append(String(ch))
                }
            } else {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
