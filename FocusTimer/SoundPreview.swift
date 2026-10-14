import AVFoundation

@MainActor
final class SoundPreview {
    static let shared = SoundPreview()
    private var player: AVAudioPlayer?

    func play(_ sound: AlarmSound) {
        player?.stop()
        guard let file = sound.shortFile, let url = Bundle.main.url(forResource: file, withExtension: nil) else {return}
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
