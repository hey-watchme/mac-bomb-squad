import AppKit
import SwiftUI

/// Borderless floating panel that can still take keyboard focus. The system
/// gives borderless windows no key status by default; the I//O panel is a
/// text-entry surface, so it must become key.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Esc anywhere in the panel (outside the editors, which handle it
    /// themselves) closes it — borderless windows have no close button.
    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: .closePanel, object: nil)
    }
}

/// Liquid Glass chrome for the floating panel: glass on macOS 26 (Tahoe),
/// regular material on earlier systems (design principle 3.5). The window
/// behind it is transparent; this shape IS the visible panel.
struct PanelChrome: ViewModifier {
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .clipShape(shape)
        }
    }
}

extension View {
    func panelChrome() -> some View {
        modifier(PanelChrome())
    }
}

/// Monochrome "I//O" glyph for the menu bar (template image so it follows
/// the menu bar appearance). The logo glyph and the diff colors are the only
/// custom visuals the design system allows.
enum MenuBarGlyph {
    static let image: NSImage = {
        let text = "I//O" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let size = text.size(withAttributes: attributes)
        let image = NSImage(
            size: NSSize(width: ceil(size.width), height: ceil(size.height)),
            flipped: false
        ) { _ in
            text.draw(at: .zero, withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        return image
    }()
}
