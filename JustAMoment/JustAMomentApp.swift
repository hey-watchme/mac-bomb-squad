import AppKit
import SwiftUI

/// just a moment — a staging layer between you and the message you send.
/// Runs as a menu-bar (accessory) app: no window at launch, no Dock icon.
/// The staging/review window only exists when summoned by the ⌘J hotkey, which
/// avoids a stray launch window stealing focus from the paste target.
@main
struct JustAMomentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("just a moment", systemImage: "text.bubble") {
            Button("入力ウィンドウを開く（⌘J）") {
                NotificationCenter.default.post(name: .showPanel, object: nil)
            }
            Divider()
            SettingsLink { Text("設定…") }
            Button("終了") { NSApplication.shared.terminate(nil) }
        }

        Settings {
            SettingsView()
        }
    }
}
