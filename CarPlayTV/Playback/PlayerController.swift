import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// Single source of truth for what's playing. On the phone, video shows in the full-screen player.
/// In the car, iOS presents video on the CarPlay display over AirPlay when the car allows it, and
/// otherwise shows Now Playing, so the app never draws on the car screen itself.
@MainActor
final class PlayerController: ObservableObject {
    static let shared = PlayerController()

    @Published private(set) var current: MediaItem?
    @Published private(set) var isPlaying = false
    @Published var phonePlayerPresented = false

    /// Set by the CarPlay scene. While connected, starting playback doesn't open the phone player.
    @Published var carConnected = false
    @Published private(set) var externalDisplayConnected = false

    let avPlayer: AVPlayer = {
        let player = AVPlayer()
        // CarPlay video apps must support AirPlay video; this is how video reaches the car display.
        player.allowsExternalPlayback = true
        return player
    }()

    private let youtube = YouTubePlayerView()
    private weak var phoneSurface: VideoSurfaceView?
    /// The external screen (car display or AirPlay screen), when iOS gives the app one. Video plays
    /// there in preference to the phone.
    private weak var externalSurface: VideoSurfaceView?
    private var cancellables: Set<AnyCancellable> = []

    /// The live screen-mirroring stream, played like any channel so it reaches the car display.
    static let mirrorChannel = Channel(
        id: "car-tv-mirror",
        name: "iPhone screen",
        group: "Screen mirroring",
        logoURL: nil,
        streamURL: MirrorHTTPServer.streamURL,
        kind: .live
    )

    var isPlayingMirror: Bool {
        if case .stream(let channel) = current { return channel.id == Self.mirrorChannel.id }
        return false
    }

    private init() {
        youtube.onStateChange = { [weak self] state in
            self?.isPlaying = state == .playing || state == .buffering
        }

        avPlayer.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated {
                    guard let self, case .stream = self.current else { return }
                    self.isPlaying = status != .paused
                }
            }
            .store(in: &cancellables)

        $isPlaying
            .dropFirst()
            .sink { [weak self] playing in MainActor.assumeIsolated { self?.updateNowPlayingRate(playing) } }
            .store(in: &cancellables)

        setUpRemoteCommands()
        observeMirroring()
        observeDiagnostics()
    }

    /// Records what the car-video investigation needs: whether video is going out over the external
    /// route, the stream's status and errors, and its video size.
    private func observeDiagnostics() {
        avPlayer.publisher(for: \.isExternalPlaybackActive)
            .removeDuplicates()
            .sink { active in Diagnostics.log("External playback active=\(active); audio: \(Diagnostics.describeRoute())") }
            .store(in: &cancellables)
        avPlayer.publisher(for: \.currentItem?.status)
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] status in
                let name = switch status {
                case .readyToPlay: "ready"
                case .failed: "FAILED: \(self?.avPlayer.currentItem?.error?.localizedDescription ?? "unknown")"
                default: "unknown"
                }
                Diagnostics.log("Stream status: \(name)")
            }
            .store(in: &cancellables)
        avPlayer.publisher(for: \.currentItem?.presentationSize)
            .compactMap { $0 }
            .filter { $0 != .zero }
            .removeDuplicates()
            .sink { size in Diagnostics.log("Stream video size: \(Int(size.width))x\(Int(size.height))") }
            .store(in: &cancellables)
    }

    /// In the car, a started broadcast plays automatically (as CarTV does: "cast from any app to watch
    /// it on the car screen"); when it ends, the mirror stops. The first segments take ~2 s to exist.
    private func observeMirroring() {
        MirrorReceiver.shared.$isMirroring
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] mirroring in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if mirroring {
                        guard self.carConnected else { return }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2.5))
                            if MirrorReceiver.shared.isMirroring, self.carConnected { self.playMirror() }
                        }
                    } else if self.isPlayingMirror {
                        self.stop()
                    }
                }
            }
            .store(in: &cancellables)
    }

    func playMirror() {
        play(.stream(Self.mirrorChannel))
    }

    // MARK: Playback

    /// Starts playback and, when the car isn't connected, opens the phone player.
    func start(_ item: MediaItem) {
        play(item)
        if !carConnected { phonePlayerPresented = true }
    }

    func play(_ item: MediaItem) {
        stopPlayback()
        current = item
        let isMirror = isPlayingMirror
        let kind = switch item {
        case .stream: isMirror ? "screen mirror" : "TV stream"
        case .youtube: "YouTube (web player)"
        }
        Diagnostics.log("Play \(kind) (car connected=\(carConnected), external playback allowed=\(avPlayer.allowsExternalPlayback))")
        if !isMirror { HistoryStore.shared.record(item) }
        switch item {
        case .stream(let channel):
            let playerItem = AVPlayerItem(url: channel.streamURL)
            if isMirror {
                // Stay as close to live as possible; a mirror that lags is worse than one that stutters.
                playerItem.preferredForwardBufferDuration = 1
                avPlayer.automaticallyWaitsToMinimizeStalling = false
            } else {
                avPlayer.automaticallyWaitsToMinimizeStalling = true
            }
            avPlayer.replaceCurrentItem(with: playerItem)
            avPlayer.play()
        case .youtube(let video):
            youtube.load(videoID: video.id, autoplay: true)
        }
        refreshSurface()
        updateNowPlaying()
    }

    func resume() {
        switch current {
        case .stream: avPlayer.play()
        case .youtube: youtube.play()
        case nil: break
        }
    }

    func pause() {
        switch current {
        case .stream: avPlayer.pause()
        case .youtube: youtube.pause()
        case nil: break
        }
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func stop() {
        stopPlayback()
        current = nil
        isPlaying = false
        phonePlayerPresented = false
        refreshSurface()
        updateNowPlaying()
    }

    private func stopPlayback() {
        avPlayer.replaceCurrentItem(with: nil)
        youtube.stop()
    }

    // MARK: Phone surface

    func register(_ surface: VideoSurfaceView) {
        phoneSurface = surface
        refreshSurface()
    }

    func registerExternal(_ surface: VideoSurfaceView) {
        externalSurface = surface
        externalDisplayConnected = true
        refreshSurface()
    }

    func unregister(_ surface: VideoSurfaceView) {
        if phoneSurface === surface { phoneSurface = nil }
        if externalSurface === surface {
            externalSurface = nil
            externalDisplayConnected = false
        }
        refreshSurface()
    }

    /// Shows video on the external screen if there is one, else on the phone player if it's open.
    /// Otherwise the YouTube player is kept alive in a hidden host so its audio (and AirPlay video)
    /// keeps going.
    private func refreshSurface() {
        let active = externalSurface ?? phoneSurface
        for surface in [phoneSurface, externalSurface].compactMap({ $0 }) {
            if case .stream = current, surface === active {
                surface.playerLayer.player = avPlayer
            } else {
                surface.playerLayer.player = nil
            }
        }

        if case .youtube = current {
            if let active {
                active.embed(youtube)
            } else {
                BackgroundHost.shared.embed(youtube)
            }
        } else {
            youtube.removeFromSuperview()
        }
    }

    // MARK: Now Playing / CarPlay and steering-wheel controls

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
            return .success
        }
    }

    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = current.map { item in
            [
                MPMediaItemPropertyTitle: item.title,
                MPMediaItemPropertyArtist: item.subtitle,
                MPNowPlayingInfoPropertyIsLiveStream: item.isLive,
                MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
                MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            ]
        }
    }

    private func updateNowPlayingRate(_ playing: Bool) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }
}

/// An offscreen-but-attached view for the YouTube player when no phone player is open. A WKWebView
/// must stay in a window to keep playing.
@MainActor
private final class BackgroundHost {
    static let shared = BackgroundHost()

    private var container: UIView?

    func embed(_ view: UIView) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return }
        if container?.window !== window {
            let host = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
            host.isUserInteractionEnabled = false
            host.alpha = 0.01
            window.insertSubview(host, at: 0)
            container = host
        }
        guard let container, view.superview !== container else { return }
        view.removeFromSuperview()
        view.frame = container.bounds
        container.addSubview(view)
    }
}
