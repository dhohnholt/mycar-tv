import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// Single source of truth for what's playing. Video goes to the CarPlay window when the car is
/// connected, otherwise to the phone's full-screen player.
@MainActor
final class PlayerController: ObservableObject {
    static let shared = PlayerController()

    enum SurfaceRole { case phone, car }

    @Published private(set) var current: MediaItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var drivingLocked = false
    @Published var phonePlayerPresented = false

    @Published var carConnected = false {
        didSet {
            refreshDrivingMonitor()
            applyDrivingLock()
            refreshSurfaces()
        }
    }

    let avPlayer = AVPlayer()
    private let youtube = YouTubePlayerView()
    private weak var phoneSurface: VideoSurfaceView?
    private weak var carSurface: VideoSurfaceView?
    private var cancellables: Set<AnyCancellable> = []

    private var speedLockEnabled: Bool { UserDefaults.standard.bool(forKey: AppSettings.speedLockKey) }

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

        DrivingMonitor.shared.$isMoving
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.applyDrivingLock() } }
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
            if !drivingLocked { avPlayer.play() }
        case .youtube(let video):
            youtube.load(videoID: video.id, autoplay: !drivingLocked)
        }
        refreshSurfaces()
        updateNowPlaying()
    }

    func resume() {
        guard !drivingLocked else { return }
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
        refreshSurfaces()
        updateNowPlaying()
    }

    private func stopPlayback() {
        avPlayer.replaceCurrentItem(with: nil)
        youtube.stop()
    }

    // MARK: Surfaces

    func register(_ surface: VideoSurfaceView, as role: SurfaceRole) {
        switch role {
        case .phone: phoneSurface = surface
        case .car: carSurface = surface
        }
        refreshSurfaces()
    }

    func unregister(_ surface: VideoSurfaceView) {
        if phoneSurface === surface { phoneSurface = nil }
        if carSurface === surface { carSurface = nil }
        refreshSurfaces()
    }

    private func refreshSurfaces() {
        let active = (carConnected ? carSurface : nil) ?? phoneSurface

        for surface in [phoneSurface, carSurface].compactMap({ $0 }) {
            let isActive = surface === active
            if case .stream = current, isActive {
                surface.playerLayer.player = avPlayer
            } else {
                surface.playerLayer.player = nil
            }
        }

        if case .youtube = current, let active {
            active.embed(youtube)
        } else {
            youtube.removeFromSuperview()
        }

        carSurface?.message = drivingLocked
            ? "Paused while the vehicle is moving"
            : (current == nil ? "Choose TV, Movies or YouTube above" : nil)
        phoneSurface?.message = (carConnected && carSurface != nil && current != nil) ? "Playing on CarPlay" : nil
    }

    // MARK: Driving lock

    func refreshDrivingMonitor() {
        DrivingMonitor.shared.setActive(carConnected && speedLockEnabled)
    }

    func applyDrivingLock() {
        let locked = carConnected && speedLockEnabled && DrivingMonitor.shared.isMoving
        guard locked != drivingLocked else { return }
        drivingLocked = locked
        if locked { pause() }
        refreshSurfaces()
    }

    // MARK: Now Playing / steering-wheel buttons

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
    }

    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = current.map { item in
            [
                MPMediaItemPropertyTitle: item.title,
                MPMediaItemPropertyArtist: item.subtitle,
                MPNowPlayingInfoPropertyIsLiveStream: item.isLive,
            ]
        }
    }
}
