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
