import AppKit

/// Distinguishes Command-key gestures, globally and within the app:
/// - double-tap  → "next" (summon / review / deploy)
/// - long-press  → hold-to-talk dictation (began on hold, ended on release)
///
/// A gesture is only recognized when Command is pressed alone; ⌘C/⌘V/⌘A etc.
/// (Command + another key) cancel it, so editing shortcuts never trigger it.
/// Requires Accessibility permission (already requested for paste injection).
final class CommandGestureMonitor {
    var onDoubleTap: (() -> Void)?
    var onLongPressBegan: (() -> Void)?
    var onLongPressEnded: (() -> Void)?

    private let doubleTapThreshold: TimeInterval = 0.35
    private let longPressThreshold: TimeInterval = 0.3
    private var lastTapTime: TimeInterval = 0
    private var commandDownClean = false
    private var isLongPressing = false
    private var longPressWork: DispatchWorkItem?
    private var monitors: [Any] = []

    // Left/right Command physical key codes.
    private let commandKeyCodes: Set<UInt16> = [54, 55]

    func start() {
        let flags: (NSEvent) -> Void = { [weak self] in self?.handleFlags($0) }
        let keys: (NSEvent) -> Void = { [weak self] _ in self?.invalidatePending() }

        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { flags($0); return $0 } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keys) as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { keys($0); return $0 } as Any)
    }

    private func handleFlags(_ event: NSEvent) {
        guard commandKeyCodes.contains(event.keyCode) else {
            // Another modifier changed → not a clean Command gesture.
            invalidatePending()
            return
        }

        if event.modifierFlags.contains(.command) {
            // Pressed: clean only if no other modifier is held.
            let others: NSEvent.ModifierFlags = [.shift, .option, .control, .function]
            commandDownClean = event.modifierFlags.isDisjoint(with: others)
            if commandDownClean { scheduleLongPress() }
        } else {
            // Released.
            longPressWork?.cancel()
            longPressWork = nil
            if isLongPressing {
                isLongPressing = false
                onLongPressEnded?()
            } else if commandDownClean {
                let now = event.timestamp
                if now - lastTapTime <= doubleTapThreshold {
                    lastTapTime = 0
                    onDoubleTap?()
                } else {
                    lastTapTime = now
                }
            }
            commandDownClean = false
        }
    }

    private func scheduleLongPress() {
        longPressWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.commandDownClean, !self.isLongPressing else { return }
            self.isLongPressing = true
            self.onLongPressBegan?()
        }
        longPressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + longPressThreshold, execute: work)
    }

    /// A non-modifier key was pressed → cancel any pending tap/long-press.
    /// Does not stop an already-running dictation (isLongPressing stays true).
    private func invalidatePending() {
        commandDownClean = false
        lastTapTime = 0
        longPressWork?.cancel()
        longPressWork = nil
    }
}
