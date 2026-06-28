import AppKit
import Carbon

/// Registers a global hotkey (⌘J) via Carbon so it fires regardless of which
/// app is frontmost. Carbon hotkeys are system-wide and need no Accessibility
/// permission (only the later paste injection does).
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    /// Invoked on the main thread when the hotkey is pressed.
    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var installed = false

    private init() {}

    func register() {
        guard !installed else { return }
        installed = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // No-capture closure → convertible to a C function pointer; route via singleton.
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            HotKeyCenter.shared.onHotKey?()
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x4A4D4F54) /* 'JMOT' */, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_J), UInt32(cmdKey), id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
