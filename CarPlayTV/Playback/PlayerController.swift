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

    let avPlayer: AVPlayer = {
        let player = AVPlayer()
        // CarPlay video apps must support AirPlay video; this is how video reaches the car display.
        player.allowsExternalPlayback = true
        return player
    }()

    private let youtube = YouTubePlayerView()
    private weak var phoneSurface: VideoSurfaceView?
    private var cancellables: Set<AnyCancellable> = []

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
        HistoryStore.shared.record(item)
        switch item {
        case .stream(let channel):
            avPlayer.replaceCurrentItem(with: AVPlayerItem(url: channel.streamURL))
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

    func unregister(_ surface: VideoSurfaceView) {
        if phoneSurface === surface { phoneSurface = nil }
        refreshSurface()
    }

    /// The YouTube player is kept alive in a hidden host while the phone player is closed, so its
    /// audio (and AirPlay video) keeps going.
    private func refreshSurface() {
        if case .stream = current {
            phoneSurface?.playerLayer.player = avPlayer
        } else {
            phoneSurface?.playerLayer.player = nil
        }

        if case .youtube = current {
            if let phoneSurface {
                phoneSurface.embed(youtube)
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
