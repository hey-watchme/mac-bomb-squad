import AppKit
import ApplicationServices
import Carbon

/// Deploys reviewed text back into the field the user was in when they pressed
/// the hotkey: writes the text to the clipboard, dismisses our panel, re-activates
/// the original app, and synthesizes ⌘V. Works with any app that supports paste
/// (Gmail, Slack, Apple Mail, Notion, …). The clipboard write also serves as a
/// fallback if Accessibility permission has not been granted yet.
final class PasteDeployer: Deployer {
    private let targetApp: NSRunningApplication?
    private let onDismiss: () -> Void

    init(targetApp: NSRunningApplication?, onDismiss: @escaping () -> Void) {
        self.targetApp = targetApp
        self.onDismiss = onDismiss
    }

    func deploy(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        // Preserve the user's clipboard; we only borrow it to synthesize ⌘V.
        let backup = ClipboardBackup.snapshot()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Close our panel first so focus can return to the target field.
        onDismiss()

        guard AXIsProcessTrusted() else {
            AccessibilityPermission.prompt()
            // No paste will happen; leave our text on the clipboard as a manual-
            // paste fallback (restoring here would defeat that fallback).
            return
        }

        // The panel is already dismissed and we have no other windows (accessory
        // app), so focus returns to the target app on the current Space — no
        // hide() and therefore no Space switch. Just re-activate and paste.
        let target = targetApp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            target?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                PasteDeployer.sendCommandV()
                // Restore the user's clipboard only after the paste is handled.
                // Earlier would risk pasting the restored (wrong) contents.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    ClipboardBackup.restore(backup)
                }
            }
        }
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV = CGKeyCode(kVK_ANSI_V)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
