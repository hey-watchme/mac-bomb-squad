import AVFoundation
import Foundation

/// Short audio cues for mic on/off.
enum SoundFeedback {
    private static let players = CuePlayers()

    /// Preload the players at launch so the first cue is instant.
    static func prepare() {
        players.prepare()
    }

    static func recordingStarted() { players.playStart() }
    static func recordingStopped() { players.playStop() }
}

private final class CuePlayers {
    private let startPlayer = makePlayer(named: "Morse")
    private let stopPlayer = makePlayer(named: "Bottle")

    func prepare() {
        startPlayer?.prepareToPlay()
        stopPlayer?.prepareToPlay()
    }

    func playStart() {
        play(startPlayer)
    }

    func playStop() {
        play(stopPlayer)
    }

    private func play(_ player: AVAudioPlayer?) {
        guard let player else { return }
        if player.isPlaying { player.stop() }
        player.currentTime = 0
        player.prepareToPlay()
        player.play()
    }

    private static func makePlayer(named name: String) -> AVAudioPlayer? {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }
}
