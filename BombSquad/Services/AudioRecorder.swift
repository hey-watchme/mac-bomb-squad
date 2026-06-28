import AVFoundation

enum AudioRecorderError: LocalizedError {
    case couldNotStart
    var errorDescription: String? {
        "録音を開始できませんでした（マイクの権限を確認してください）。"
    }
}

/// Records mic input to a temporary m4a file for transcription.
/// 16 kHz mono AAC keeps the upload small while staying ample for speech.
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private(set) var fileURL: URL?

    /// Called once the recording has officially finished and the audio input is
    /// released. This is the safe moment to play a cue sound — playing earlier
    /// (during teardown) makes the system sound crack/echo.
    var onFinish: (() -> Void)?

    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jam-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.prepareToRecord()
        guard recorder.record() else { throw AudioRecorderError.couldNotStart }
        self.recorder = recorder
        self.fileURL = url
    }

    /// Touch the audio system once so the first real recording starts faster.
    func warmUp() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jam-warmup.m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        if let warm = try? AVAudioRecorder(url: url, settings: settings) {
            warm.prepareToRecord()
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// Stops recording and returns the captured file URL. The recorder is kept
    /// alive until the finish delegate fires, then released.
    @discardableResult
    func stop() -> URL? {
        recorder?.stop()
        return fileURL
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        onFinish?()
        onFinish = nil
        self.recorder = nil
    }
}
