import AppKit
import AVFoundation
import SwiftUI

extension Notification.Name {
    /// Posted by the menu-bar item to summon the panel.
    static let showPanel = Notification.Name("BombSquad.showPanel")
    /// Posted from the panel (Esc) to cancel/close it.
    static let closePanel = Notification.Name("BombSquad.closePanel")
    /// Posted by the menu bar (or the panel's login CTA) to open the on-demand
    /// management window. The target section is set on `ManagementNavigator.shared`
    /// before posting.
    static let showManagement = Notification.Name("BombSquad.showManagement")
}

/// Owns the global hotkey and the floating review panel summoned by ⌘J.
/// On hotkey: capture the frontmost app (the paste target), then show a floating
/// panel hosting the staging/review UI wired to a `PasteDeployer`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    /// The single on-demand management window (account/settings/history/pricing).
    /// Created lazily and reused; never always-on.
    private var managementWindow: NSWindow?
    private var currentViewModel: ReviewViewModel?
    private let authClient = BombSquadAuthClient.shared
    private let gesture = ShiftGestureMonitor()
    private let recorder = AudioRecorder()
    private let transcriber = GroqTranscriber()
    /// Guards against duplicate begin/end callbacks so the cues fire exactly once.
    private var isDictating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar accessory: no Dock icon, no window until summoned.
        NSApp.setActivationPolicy(.accessory)
        // Start the shared auth session subscription now (not on first summon),
        // so the panel never flashes the login screen while it loads.
        _ = AuthViewModel.shared
        // Guide the user to grant Accessibility once; needed for paste injection.
        AccessibilityPermission.prompt()
        // Pre-register sound cues so the first one is instant.
        SoundFeedback.prepare()
        // Pre-request mic access, then warm up the audio system off the hot path.
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.recorder.warmUp() }
        }
        // Right Shift double-tap = next: summon → review → deploy.
        // Right Shift long-press = hold-to-talk dictation. ⌘J toggles the panel.
        HotKeyCenter.shared.onHotKey = { [weak self] in self?.togglePanel() }
        HotKeyCenter.shared.register()
        gesture.onSingleTap = { [weak self] in self?.toggleEditorFocus() }
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
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleShowManagement), name: .showManagement, object: nil
        )
        // Modal-like: if focus leaves to another app/form, exit the mode (close).
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleResignActive),
            name: NSApplication.didResignActiveNotification, object: nil
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task {
            try? await authClient.handleIncomingURL(url)
        }
    }

    @objc private func handleResignActive() {
        // Login can legitimately move focus to the browser or Mail. Keep the
        // auth gate alive so the user has a visible return point after callback.
        guard authClient.currentSession() != nil else { return }

        // The staging panel is a transient "capture" mode; touching another app's
        // input releases it. Closing on resign makes it behave modally.
        if panel != nil { closePanel() }
    }

    /// Right Shift double-tap: if the panel is closed, summon it. If it's open,
    /// only the left draft editor responds: empty closes, otherwise it reviews.
    /// Invoked from the key-event monitor, which delivers on the main thread.
    private func advance() {
        if panel == nil {
            summon()
            return
        }
        MainActor.assumeIsolated {
            guard currentViewModel?.focusedField == .draft else { return }
            if currentViewModel?.isEmptyDraft ?? true {
                closePanel()
            } else {
                currentViewModel?.requestReviewFromHotkey()
            }
        }
    }

    private func toggleEditorFocus() {
        guard panel != nil else { return }
        MainActor.assumeIsolated {
            currentViewModel?.toggleFocusedField()
        }
    }

    /// Summon the panel. If the frontmost app has a current selection, pull it in
    /// as a received message to transform (receiving side); otherwise open the
    /// empty compose pane (sending side). The selection grab must happen before
    /// our panel steals focus, so it runs here while the target is still front.
    private func summon() {
        SelectionGrabber.grab { [weak self] selection in
            if let selection {
                self?.showPanel(prefill: selection, mode: .transform)
            } else {
                self?.showPanel(mode: .compose)
            }
        }
    }

    /// Right Shift long-press begins: give immediate feedback (sound + red mic) the instant
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

    /// Right Shift released: stop recording, transcribe, and append the text to the draft.
    private func stopDictationAndTranscribe() {
        guard isDictating else { return }
        isDictating = false
        let vm = currentViewModel
        recorder.onFinish = { SoundFeedback.recordingStopped() }
        guard let url = recorder.stop() else { return }
        MainActor.assumeIsolated {
            vm?.isRecording = false
            vm?.isTranscribing = true
        }
        Task {
            defer { try? FileManager.default.removeItem(at: url) }
            // Silence gate: drop near-silent or ultra-short clips before the API,
            // since Whisper hallucinates filler on silence. Thresholds are tunable;
            // if the file can't be inspected we fail open and transcribe anyway.
            if let clip = AudioRecorder.inspect(url: url),
               clip.duration < 0.4 || clip.averagePower < -45 {
                await MainActor.run { vm?.isTranscribing = false }
                return
            }
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

    /// Open (or bring to front) the single management window. The desired section
    /// has already been set on `ManagementNavigator.shared` by the caller.
    ///
    /// The capture panel is an always-on-top floating panel, so any normal window
    /// would open behind it. The panel is transient anyway, so we close it and let
    /// the management window take over (e.g. login → the account/login screen).
    @objc private func handleShowManagement() {
        if panel != nil { closePanel() }

        if let managementWindow {
            NSApp.activate(ignoringOtherApps: true)
            managementWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Bomb Squad"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.contentViewController = NSHostingController(rootView: ManagementView())
        window.setContentSize(NSSize(width: 820, height: 600))
        window.center()

        managementWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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

    private func showPanel(prefill: String? = nil, mode: ReviewMode = .compose) {
        // Capture the target BEFORE our panel activates and steals focus.
        let target = NSWorkspace.shared.frontmostApplication
        let deployer: Deployer
        switch mode {
        case .compose:
            deployer = PasteDeployer(targetApp: target) { [weak self] in self?.closePanel() }
        case .transform:
            // Received message: never write back into the sender's field. The
            // readable version is for reading, so "send" only copies to clipboard.
            deployer = ClipboardDeployer()
        }
        let viewModel = MainActor.assumeIsolated {
            ReviewViewModel(deployer: deployer, mode: mode)
        }
        currentViewModel = viewModel
        MainActor.assumeIsolated {
            viewModel.restorePersistedDraftIfNeeded()
        }
        if let prefill {
            MainActor.assumeIsolated {
                viewModel.draft = prefill
                // Receiving side: the selection is already captured, so run the
                // transform immediately — the panel opens with the readable
                // result already showing on the right (one stop, no second tap).
                if mode == .transform, authClient.currentSession() != nil {
                    Task { await viewModel.runReview() }
                }
            }
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        panel.title = "Bomb Squad"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(
            rootView: MainActor.assumeIsolated { RootPanelView(reviewViewModel: viewModel) }
        )
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
