import AppKit

/// Bridges the staging text to the "live" destination.
/// MVP boundary: deploying means copying to the clipboard. A future
/// implementation will inject text into the focused field of another app
/// via the Accessibility API — only this protocol's implementation changes.
protocol Deployer {
    func deploy(_ text: String) throws
}

/// MVP deployer: writes the final text to the system clipboard.
struct ClipboardDeployer: Deployer {
    func deploy(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// Save/restore the system clipboard around our ⌘C/⌘V synthesis so the user's
/// own copied content survives. This is the standard pattern used by text-
/// expansion / launcher utilities (TextExpander, Alfred, Raycast, Espanso) that
/// inject text via the clipboard. It is a stopgap: once we inject straight into
/// the target field via the Accessibility API (see roadmap), the clipboard is no
/// longer touched and this disappears.
///
/// Limitations (inherent to the approach, not a bug): the surrounding paste/copy
/// is delay-based, so restoring too early can paste the wrong thing — callers
/// must restore only after the synthesized paste/copy has been handled.
enum ClipboardBackup {
    /// Deep-copies every item/type currently on the pasteboard. NSPasteboardItem
    /// instances can't be re-added once owned by a pasteboard, so we rebuild them.
    static func snapshot() -> [NSPasteboardItem] {
        let pasteboard = NSPasteboard.general
        return (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    /// Restores a previously captured snapshot, replacing whatever we wrote.
    static func restore(_ items: [NSPasteboardItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}
