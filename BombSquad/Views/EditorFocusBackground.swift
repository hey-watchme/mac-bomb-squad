import SwiftUI

/// Editor background that emphasizes focus: a neutral fill normally, and a blue
/// border plus a faint blue tint when the editor is the active one.
struct EditorFocusBackground: View {
    let isFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        shape
            .fill(.quaternary.opacity(0.4))
            .overlay { shape.fill(Color.blue.opacity(isFocused ? 0.08 : 0)) }
            .overlay { shape.strokeBorder(isFocused ? Color.blue : .clear, lineWidth: 2) }
            .animation(.easeInOut(duration: 0.12), value: isFocused)
    }
}
