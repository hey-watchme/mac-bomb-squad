import AppKit
import AVFoundation
import SwiftUI

extension Notification.Name {
    /// Posted by the menu-bar item to summon the panel.
    static let showPanel = Notification.Name("JustAMoment.showPanel")
    /// Posted from the panel (Esc) to cancel/close it.
    static let closePanel = Notification.Name("JustAMoment.closePanel")
}

/// Owns the global hotkey and the floating review panel summoned by ⌘J.
/// On hotkey: capture the frontmost app (the paste target), then show a floating
/// panel hosting the staging/review UI wired to a `PasteDeployer`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var currentViewModel: ReviewViewModel?
    private let gesture = CommandGestureMonitor()
    private let recorder = AudioRecorder()
    private let transcriber = GroqTranscriber()
    /// Guards against duplicate begin/end callbacks so the cues fire exactly once.
    private var isDictating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar accessory: no Dock icon, no window until summoned.
        NSApp.setActivationPolicy(.accessory)
        // Guide the user to grant Accessibility once; needed for paste injection.
        AccessibilityPermission.prompt()
        // Pre-register sound cues so the first one is instant.
        SoundFeedback.prepare()
        // Pre-request mic access, then warm up the audio system off the hot path.
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.recorder.warmUp() }
        }
        // ⌘⌘ (double-tap) = next: summon → review → deploy.
        // ⌘ long-press = hold-to-talk dictation. ⌘J toggles the panel.
        HotKeyCenter.shared.onHotKey = { [weak self] in self?.togglePanel() }
        HotKeyCenter.shared.register()
        gesture.onDoubleTap = { [weak self] in self?.advance() }
        gesture.onLongPressBegan = { [weak self] in self?.startDictation() }
        gesture.onLongPressEnded = { [weak self] in self?.stopDictationAndTranscribe() }
        gesture.start()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleShowPanel), name: .showPanel, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleClosePanel), name: .closePanel, object: nil
        )
        // Modal-like: if focus leaves to another app/form, exit the mode (close).
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleResignActive),
            name: NSApplication.didResignActiveNotification, object: nil
        )
    }

    @objc private func handleResignActive() {
        // The staging panel is a transient "capture" mode; touching another app's
        // input releases it. Closing on resign makes it behave modally.
        if panel != nil { closePanel() }
    }

    /// ⌘⌘: if the panel is closed, summon it. If it's open and empty, close it
    /// (a "never mind" gesture). Otherwise advance the flow.
    /// Invoked from the key-event monitor, which delivers on the main thread.
    private func advance() {
        if panel == nil {
            showPanel()
            return
        }
        MainActor.assumeIsolated {
            if currentViewModel?.isEmptyDraft ?? true {
                closePanel()
            } else {
                currentViewModel?.advance()
            }
        }
    }

    /// ⌘ long-press begins: give immediate feedback (sound + red mic) the instant
    /// the gesture is recognized, then start the recorder. The mic's warm-up adds
    /// ~0.5s, but firing the cue first makes it feel snappy; the tiny head clip is
    /// negligible in practice.
    private func startDictation() {
        guard !isDictating else { return }
        isDictating = true
        if panel == nil { showPanel() }
        let vm = currentViewModel
        SoundFeedback.recordingStarted()
        MainActor.assumeIsolated {
            vm?.errorMessage = nil
            vm?.isRecording = true
        }
        do {
            try recorder.start()
        } catch {
            MainActor.assumeIsolated {
                vm?.isRecording = false
                vm?.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// ⌘ released: stop recording, transcribe, and append the text to the draft.
    private func stopDictationAndTranscribe() {
        guard isDictating else { return }
        isDictating = false
        let vm = currentViewModel
        // Stop cue plays once the recording finishes. (Known minor issue: it can
        // sound like a short echo; kept because the on/off cue is useful.)
        recorder.onFinish = { SoundFeedback.recordingStopped() }
        guard let url = recorder.stop() else { return }
        MainActor.assumeIsolated {
            vm?.isRecording = false
            vm?.isTranscribing = true
        }
        Task {
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let text = try await transcriber.transcribe(fileURL: url)
                await MainActor.run {
                    vm?.appendTranscription(text)
                    vm?.isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    vm?.isTranscribing = false
                    vm?.errorMessage = "文字起こしに失敗: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
                }
            }
        }
    }

    @objc private func handleShowPanel() {
        togglePanel()
    }

    @objc private func handleClosePanel() {
        closePanel()
    }

    private func togglePanel() {
        if let panel, panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        // Capture the target BEFORE our panel activates and steals focus.
        let target = NSWorkspace.shared.frontmostApplication
        let deployer = PasteDeployer(targetApp: target) { [weak self] in self?.closePanel() }
        let viewModel = ReviewViewModel(deployer: deployer)
        currentViewModel = viewModel

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        panel.title = "just a moment"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: ContentView(viewModel: viewModel))
        // Enforce a fixed size so SwiftUI can't resize the window out from under
        // the centering math; then center exactly.
        panel.setContentSize(NSSize(width: 920, height: 620))
        centerOnActiveScreen(panel)

        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func closePanel() {
        panel?.orderOut(nil)
        panel = nil
        currentViewModel = nil
    }

    /// Center the panel on whichever screen the cursor is on, so it never spills
    /// off-screen (e.g. Gmail's right-side compose box).
    private func centerOnActiveScreen(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.midY - size.height / 2)
        panel.setFrameOrigin(origin)
    }
}
