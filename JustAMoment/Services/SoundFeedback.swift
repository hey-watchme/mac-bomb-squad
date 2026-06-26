import AudioToolbox
import Foundation

/// Short audio cues for mic on/off, like Amical. Uses AudioServices system
/// sounds: low-latency, fire-and-forget, single playback (no overlap/echo).
/// Sound IDs are registered once up front so the first cue isn't a cold load.
enum SoundFeedback {
    private static let startSound = makeSound("Tink") // "pico" — recording started
    private static let stopSound = makeSound("Pop")   // "poko" — recording stopped

    /// Pre-register the sounds at launch so the first play is instant.
    static func prepare() {
        _ = startSound
        _ = stopSound
    }

    static func recordingStarted() { play(startSound) }
    static func recordingStopped() { play(stopSound) }

    private static func play(_ id: SystemSoundID?) {
        guard let id else { return }
        AudioServicesPlaySystemSound(id)
    }

    private static func makeSound(_ name: String) -> SystemSoundID? {
        let path = "/System/Library/Sounds/\(name).aiff"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        var id: SystemSoundID = 0
        let url = URL(fileURLWithPath: path) as CFURL
        guard AudioServicesCreateSystemSoundID(url, &id) == noErr else { return nil }
        return id
    }
}
