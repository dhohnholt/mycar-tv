import AVFoundation

/// Keeps the app running in the background during screen mirroring by playing silence, mixed with
/// other apps' audio so whatever is being mirrored still plays its own sound. Fine for a private
/// TestFlight app; App Review would question background audio that isn't audible.
final class BackgroundKeepAlive {
    static let shared = BackgroundKeepAlive()

    private var player: AVAudioPlayer?

    private init() {}

    func start() {
        guard player == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        guard let silence = try? AVAudioPlayer(data: Self.silentWAV()) else { return }
        silence.numberOfLoops = -1
        silence.volume = 0
        silence.play()
        player = silence
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    /// One second of 16-bit mono silence as an in-memory WAV file.
    private static func silentWAV(sampleRate: Int = 8_000) -> Data {
        let dataSize = sampleRate * 2
        var wav = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + dataSize))
        wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        wav.append(contentsOf: Array("data".utf8)); append(UInt32(dataSize))
        wav.append(Data(count: dataSize))
        return wav
    }
}
