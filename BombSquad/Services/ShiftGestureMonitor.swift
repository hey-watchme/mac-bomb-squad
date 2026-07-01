import AppKit

/// Distinguishes Right-Shift gestures, globally and within the app:
/// - single-tap  → switch editor focus
/// - double-tap  → "next" (summon / review / deploy)
/// - long-press  → hold-to-talk dictation (began on hold, ended on release)
///
/// Right Shift is used because the Command key conflicts with everyday
/// shortcuts (⌘C/⌘V/…): merely holding ⌘ before a shortcut would fire the
/// gesture. Right Shift is rarely held alone, and a gesture is only recognized
/// when Right Shift is pressed without any other modifier; pressing another key
/// (e.g. typing a capital letter) cancels the pending gesture.
/// Requires Accessibility permission (already requested for paste injection).
final class ShiftGestureMonitor {
    var onSingleTap: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    var onLongPressBegan: (() -> Void)?
    var onLongPressEnded: (() -> Void)?

    private let doubleTapThreshold: TimeInterval = 0.35
    private let longPressThreshold: TimeInterval = 0.3
    private var lastTapTime: TimeInterval = 0
    private var shiftDownClean = false
    private var isLongPressing = false
    private var longPressWork: DispatchWorkItem?
    private var singleTapWork: DispatchWorkItem?
    private var monitors: [Any] = []

    // Right Shift physical key code.
    private let shiftKeyCode: UInt16 = 60

    func start() {
        let flags: (NSEvent) -> Void = { [weak self] in self?.handleFlags($0) }
        let keys: (NSEvent) -> Void = { [weak self] _ in self?.invalidatePending() }

        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { flags($0); return $0 } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keys) as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { keys($0); return $0 } as Any)
    }

    private func handleFlags(_ event: NSEvent) {
        guard event.keyCode == shiftKeyCode else {
            // Another modifier changed → not a clean Right-Shift gesture.
            invalidatePending()
            return
        }

        if event.modifierFlags.contains(.shift) {
            // Pressed: clean only if no other modifier is held.
            let others: NSEvent.ModifierFlags = [.command, .option, .control, .function]
            shiftDownClean = event.modifierFlags.isDisjoint(with: others)
            if shiftDownClean { scheduleLongPress() }
        } else {
            // Released.
            longPressWork?.cancel()
            longPressWork = nil
            if isLongPressing {
                isLongPressing = false
                onLongPressEnded?()
            } else if shiftDownClean {
                let now = event.timestamp
                if now - lastTapTime <= doubleTapThreshold {
                    singleTapWork?.cancel()
                    singleTapWork = nil
                    lastTapTime = 0
                    onDoubleTap?()
                } else {
                    lastTapTime = now
                    scheduleSingleTap()
                }
            }
            shiftDownClean = false
        }
    }

    private func scheduleLongPress() {
        longPressWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.shiftDownClean, !self.isLongPressing else { return }
            self.isLongPressing = true
            self.onLongPressBegan?()
        }
        longPressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + longPressThreshold, execute: work)
    }

    private func scheduleSingleTap() {
        singleTapWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastTapTime = 0
            self.onSingleTap?()
        }
        singleTapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapThreshold, execute: work)
    }

    /// A non-modifier key was pressed → cancel any pending tap/long-press.
    /// Does not stop an already-running dictation (isLongPressing stays true).
    private func invalidatePending() {
        shiftDownClean = false
        lastTapTime = 0
        longPressWork?.cancel()
        longPressWork = nil
        singleTapWork?.cancel()
        singleTapWork = nil
    }
}
