import Combine
import SwiftUI
import UIKit
import WebKit

/// Car TV's own car screen, used when CarPlay hosts the app's scene directly (Car TV has both the audio
/// and video CarPlay entitlements, which in the Highlander gives it a plain window scene instead of
/// Apple's template host). The video layer (streams, the YouTube player, the mirrored iPhone screen)
/// fills the screen; a SwiftUI overlay provides browsing and playback controls.
final class CarScreenViewController: UIViewController {
    private let video = ExternalDisplayViewController()
    private let model = CarScreenModel()
    private lazy var overlay = UIHostingController(rootView: CarOverlayView(model: model))

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark

        for child in [video, overlay] as [UIViewController] {
            addChild(child)
            child.view.frame = view.bounds
            child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(child.view)
            child.didMove(toParent: self)
        }
        overlay.view.backgroundColor = .clear
    }

    func tearDown() {
        video.tearDown()
    }
}

/// What the car screen is showing.
@MainActor
final class CarScreenModel: ObservableObject {
    @Published var browsing = true
    @Published var controlsVisible = false
    /// The car browser is shown full screen. Its web view is kept so the page survives leaving it.
    @Published var showingBrowser = false
    private(set) lazy var webView: WKWebView = WebBrowser.makeWebView()
    private var hideTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        // A broadcast starting shows the mirror; playback ending returns to browsing.
        MirrorReceiver.shared.$isMirroring
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mirroring in
                guard let self else { return }
                if mirroring {
                    self.showingBrowser = false
                    self.watch()
                } else if PlayerController.shared.current == nil { self.browsing = true }
            }
            .store(in: &cancellables)
        // Something started playing (from the car or sent from the phone): show it full screen.
        PlayerController.shared.$current
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] current in
                guard let self else { return }
                if current != nil {
                    self.showingBrowser = false
                    self.watch()
                } else if !MirrorReceiver.shared.isMirroring {
                    self.browsing = true
                }
            }
            .store(in: &cancellables)
    }

    func play(_ item: MediaItem) {
        showingBrowser = false
        PlayerController.shared.play(item)
        watch()
    }

    /// Opens the browser full screen (optionally at a page). Car TV's own playback stops so the page's
    /// video has the audio.
    func openBrowser(at url: URL? = nil) {
        if PlayerController.shared.current != nil { PlayerController.shared.stop() }
        if let url { webView.load(URLRequest(url: url)) }
        showingBrowser = true
    }

    /// Switch from the browser to the full-screen video, flashing the controls briefly.
    func watch() {
        browsing = false
        showControls()
    }

    func showControls() {
        controlsVisible = true
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.controlsVisible = false
        }
    }
}

// MARK: - Overlay

private struct CarOverlayView: View {
    @ObservedObject var model: CarScreenModel
    @ObservedObject private var player = PlayerController.shared
    @ObservedObject private var receiver = MirrorReceiver.shared

    private var hasVideo: Bool { player.current != nil || receiver.isMirroring }

    var body: some View {
        ZStack {
            if model.showingBrowser {
                CarBrowserScreen(model: model)
            } else if model.browsing || !hasVideo {
                CarBrowseView(model: model)
                    .background(Color.black)
            } else {
                // Full-screen video: tap anywhere for controls.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.controlsVisible ? (model.controlsVisible = false) : model.showControls() }
                if model.controlsVisible {
                    CarPlayerControls(model: model)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.controlsVisible)
        .preferredColorScheme(.dark)
    }
}

private struct CarPlayerControls: View {
    @ObservedObject var model: CarScreenModel
    @ObservedObject private var player = PlayerController.shared
    @ObservedObject private var receiver = MirrorReceiver.shared

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                CarIconButton(symbol: "list.bullet") { model.browsing = true }
                Text(receiver.isMirroring ? "iPhone screen" : (player.current?.title ?? ""))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if player.current != nil {
                    CarIconButton(symbol: player.isPlaying ? "pause.fill" : "play.fill") {
                        player.togglePlayPause()
                        model.showControls()
                    }
                    CarIconButton(symbol: "stop.fill") { player.stop() }
                }
            }
            .padding(8)
            .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
            Spacer()
        }
        .foregroundStyle(.white)
    }
}

private struct CarIconButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 36)
                .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Browser

private enum CarTab: String, CaseIterable, Identifiable {
    case youtube, tv, movies, browser, recent, mirror
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .tv: "tv"
        case .movies: "film"
        case .youtube: "play.rectangle"
        case .browser: "globe"
        case .recent: "clock.arrow.circlepath"
        case .mirror: "rectangle.on.rectangle"
        }
    }

    var title: String {
        switch self {
        case .tv: "TV"
        case .movies: "Movies"
        case .youtube: "YouTube"
        case .browser: "Browser"
        case .recent: "Recent"
        case .mirror: "iPhone screen"
        }
    }
}

/// A page shown to the right of the sidebar. Drill-downs push onto `stack`.
private enum CarPage {
    case groups(Channel.Kind)
    case channels(ChannelGroup)
    case youtubeMenu
    case videos(String, () async throws -> [YouTubeVideo])
    case playlists(String, () async throws -> [YouTubePlaylist])
    case recent
    case mirror
}

private struct CarBrowseView: View {
    @ObservedObject var model: CarScreenModel
    @State private var tab: CarTab = .youtube
    @State private var stack: [CarPage] = []

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                ForEach(CarTab.allCases) { item in
                    Button {
                        if item == .browser { return model.openBrowser() }
                        tab = item
                        stack = []
                    } label: {
                        Image(systemName: item.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 48, height: 40)
                            .foregroundStyle(tab == item ? Color.accentColor : Color.white.opacity(0.7))
                            .background(tab == item ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(Color.white.opacity(0.05))

            CarPageView(page: stack.last ?? root, title: title, canGoBack: !stack.isEmpty,
                        back: { stack.removeLast() }, push: { stack.append($0) }, model: model)
        }
        .foregroundStyle(.white)
    }

    private var root: CarPage {
        switch tab {
        case .tv: .groups(.live)
        case .movies: .groups(.movie)
        case .youtube, .browser: .youtubeMenu
        case .recent: .recent
        case .mirror: .mirror
        }
    }

    private var title: String {
        switch stack.last {
        case .channels(let group): group.name
        case .videos(let title, _), .playlists(let title, _): title
        default: tab.title
        }
    }
}

private struct CarPageView: View {
    let page: CarPage
    let title: String
    let canGoBack: Bool
    let back: () -> Void
    let push: (CarPage) -> Void
    @ObservedObject var model: CarScreenModel

    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var auth = GoogleAuth.shared
    @ObservedObject private var receiver = MirrorReceiver.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if canGoBack {
                    CarIconButton(symbol: "chevron.left", action: back)
                }
                Text(title).font(.system(size: 16, weight: .bold)).lineLimit(1)
                Spacer()
                if PlayerController.shared.current != nil || receiver.isMirroring {
                    Button("Now Playing") { model.watch() }
                        .font(.system(size: 13, weight: .semibold))
                        .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 40)

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .groups(let kind):
            let groups = library.groups(kind)
            if groups.isEmpty {
                CarMessage(library.isLoading ? "Loading…" : (kind == .live ? "No channels yet" : "No movies yet"))
            } else {
                CarList(groups.map { group in
                    CarRow(title: group.name, detail: "\(group.channels.count)", disclosure: true) { push(.channels(group)) }
                })
            }
        case .channels(let group):
            CarList(group.channels.prefix(300).map { channel in
                CarRow(title: channel.name, detail: nil, imageURL: channel.logoURL) { model.play(.stream(channel)) }
            })
        case .youtubeMenu:
            // Home and Watch Later come from YouTube's website (the API doesn't offer them).
            let webRows = [
                CarRow(title: "Home", detail: "Your recommendations (YouTube website)") { model.openBrowser(at: WebBrowser.youTubeHome) },
                CarRow(title: "Watch Later", detail: "YouTube website") { model.openBrowser(at: WebBrowser.watchLater) },
            ]
            if !auth.isSignedIn {
                CarList(webRows)
            } else {
                CarList(webRows + [
                    CarRow(title: "Latest from subscriptions", disclosure: true) {
                        push(.videos("Latest from subscriptions") { try await YouTubeAPI.subscriptionFeed() })
                    },
                    CarRow(title: "Trending", disclosure: true) { push(.videos("Trending") { try await YouTubeAPI.trending() }) },
                    CarRow(title: "Liked videos", disclosure: true) { push(.videos("Liked videos") { try await YouTubeAPI.liked() }) },
                    CarRow(title: "Subscriptions", disclosure: true) { push(.playlists("Subscriptions") { try await YouTubeAPI.subscriptions() }) },
                    CarRow(title: "Playlists", disclosure: true) { push(.playlists("Playlists") { try await YouTubeAPI.playlists() }) },
                ])
            }
        case .videos(let title, let load):
            CarLoadingList(id: "videos:\(title)", load: {
                try await load().map { video in
                    CarRow(title: video.title, detail: video.channelTitle, imageURL: video.thumbnailURL) { model.play(.youtube(video)) }
                }
            })
        case .playlists(let title, let load):
            CarLoadingList(id: "playlists:\(title)", load: {
                try await load().map { playlist in
                    CarRow(title: playlist.title, imageURL: playlist.thumbnailURL, disclosure: true) {
                        push(.videos(playlist.title) { try await YouTubeAPI.playlistVideos(playlist.id) })
                    }
                }
            })
        case .recent:
            if history.items.isEmpty {
                CarMessage("Nothing watched yet")
            } else {
                CarList(history.items.map { item in
                    CarRow(title: item.title, detail: item.subtitle, imageURL: item.artworkURL) { model.play(item) }
                })
            }
        case .mirror:
            if receiver.isMirroring {
                CarList([CarRow(title: "Show iPhone screen", detail: "Mirroring is on") { model.watch() }])
            } else {
                CarMessage("Start Car TV Mirror (screen broadcast) to show the iPhone screen here.")
            }
        }
    }
}

private struct CarRow: Identifiable {
    let id = UUID()
    let title: String
    var detail: String?
    var imageURL: URL?
    var disclosure = false
    let action: () -> Void
}

private struct CarList: View {
    let rows: [CarRow]
    init(_ rows: [CarRow]) { self.rows = rows }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    Button(action: row.action) {
                        HStack(spacing: 8) {
                            if let url = row.imageURL {
                                AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { Color.white.opacity(0.08) }
                                    .frame(width: 44, height: 30)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                                if let detail = row.detail {
                                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            if row.disclosure {
                                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 42)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
    }
}

private struct CarLoadingList: View {
    let id: String
    let load: () async throws -> [CarRow]
    @State private var rows: [CarRow]?
    @State private var error: String?

    var body: some View {
        Group {
            if let error {
                CarMessage("Couldn't load: \(error)")
            } else if let rows {
                rows.isEmpty ? AnyView(CarMessage("Nothing here")) : AnyView(CarList(rows))
            } else {
                CarMessage("Loading…")
            }
        }
        .task(id: id) {
            rows = nil
            error = nil
            do { rows = try await load() } catch { self.error = error.localizedDescription }
        }
    }
}

private struct CarMessage: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Browser

/// Full-screen web browser on the car screen (home: YouTube Watch Later), with a few floating buttons.
private struct CarBrowserScreen: View {
    @ObservedObject var model: CarScreenModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            WebViewContainer(webView: model.webView)
                .ignoresSafeArea()
            HStack(spacing: 6) {
                CarIconButton(symbol: "list.bullet") { model.showingBrowser = false }
                CarIconButton(symbol: "chevron.left") { model.webView.goBack() }
                CarIconButton(symbol: "house") { model.webView.load(URLRequest(url: WebBrowser.home)) }
                CarIconButton(symbol: "arrow.clockwise") { model.webView.reload() }
            }
            .padding(6)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .padding(6)
            .foregroundStyle(.white)
        }
    }
}
