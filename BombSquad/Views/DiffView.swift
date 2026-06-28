import SwiftUI

/// Renders a word-level diff between the original draft and the revision.
/// Removed text is struck through in red; added text is green.
struct DiffView: View {
    let original: String
    let revised: String

    private var segments: [DiffSegment] {
        WordDiff.compute(original: original, revised: revised)
    }

    var body: some View {
        ScrollView {
            Text(attributed)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var attributed: AttributedString {
        var output = AttributedString()
        for segment in segments {
            var piece = AttributedString(segment.text)
            switch segment.kind {
            case .equal:
                piece.foregroundColor = .primary
            case .removed:
                piece.foregroundColor = .red
                piece.strikethroughStyle = .single
            case .added:
                piece.foregroundColor = .green
                piece.underlineStyle = .single
            }
            output.append(piece)
        }
        return output
    }
}
