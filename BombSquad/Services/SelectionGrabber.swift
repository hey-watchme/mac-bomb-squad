import AppKit
import ApplicationServices
import Carbon

/// Grabs the current selection from the frontmost app by synthesizing ⌘C and
/// reading the pasteboard — the mirror image of `PasteDeployer`'s ⌘V. Used by
/// the receiving side: select a message in Slack/Gmail/…, then summon the panel
/// to pull it into the staging pane.
///
/// Returns nil when nothing was selected (the pasteboard didn't change), which
/// lets the caller fall back to the empty compose pane. Requires Accessibility
/// permission (already requested for paste injection).
enum SelectionGrabber {
    /// Synthesizes ⌘C in the frontmost app and delivers the freshly copied
    /// selection on the main queue, or nil if there was no selection.
    static func grab(completion: @escaping (String?) -> Void) {
        guard AXIsProcessTrusted() else {
            completion(nil)
            return
        }
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        sendCommandC()
        // The copy lands asynchronously after the target app handles ⌘C; give it
        // a beat (same order as PasteDeployer's paste delay) before reading.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard
                pasteboard.changeCount != before,
                let text = pasteboard.string(forType: .string),
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                completion(nil)
                return
            }
            completion(text)
        }
    }

    private static func sendCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyC = CGKeyCode(kVK_ANSI_C)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
