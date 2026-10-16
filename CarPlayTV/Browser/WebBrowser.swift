import SwiftUI
import WebKit

/// A plain web browser for the car screen (as CarTV does), mainly for YouTube's mobile site, e.g. the
/// Watch Later playlist, which the YouTube Data API doesn't expose. Phone and car browsers share the
/// default website data store, so signing in to YouTube once on the phone also signs in the car.
enum WebBrowser {
    static let home = URL(string: "https://www.youtube.com/playlist?list=WL")!

    /// Identify as Safari: Google refuses sign-in from user agents it recognizes as embedded web views.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"

    @MainActor
    static func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.load(URLRequest(url: home))
        return webView
    }
}

/// Hosts an existing WKWebView (kept alive by its owner so pages survive leaving the browser).
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        attach(to: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        attach(to: uiView)
    }

    private func attach(to container: UIView) {
        guard webView.superview !== container else { return }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
    }
}

/// Phone browser, mainly for signing in to YouTube so the car browser is signed in too.
struct PhoneBrowserView: View {
    @StateObject private var page = BrowserPage()
    @ObservedObject private var player = PlayerController.shared

    private var webView: WKWebView { page.webView }

    var body: some View {
        WebViewContainer(webView: webView)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Web browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Plays the open YouTube video in Car TV's player: on the car screen when CarPlay is
                    // connected, otherwise in the phone player.
                    Button {
                        page.sendToPlayer()
                    } label: {
                        Label(player.carConnected ? "Play on car" : "Play in Car TV", systemImage: player.carConnected ? "car" : "play.rectangle")
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(page.videoID == nil)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { webView.goBack() } label: { Image(systemName: "chevron.left") }
                    Button { webView.goForward() } label: { Image(systemName: "chevron.right") }
                    Spacer()
                    Button { webView.load(URLRequest(url: WebBrowser.home)) } label: { Image(systemName: "house") }
                    Button { webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
    }
}

/// The phone browser's web view plus the YouTube video ID of the page it's on, if any.
@MainActor
final class BrowserPage: ObservableObject {
    let webView = WebBrowser.makeWebView()
    @Published private(set) var videoID: String?
    private var observation: NSKeyValueObservation?

    init() {
        observation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
            let id = webView.url.flatMap(Self.youTubeVideoID)
            DispatchQueue.main.async { self?.videoID = id }
        }
    }

    func sendToPlayer() {
        guard let id = videoID else { return }
        // Stop the page's own copy so only one plays.
        webView.evaluateJavaScript("document.querySelectorAll('video').forEach(function(v){v.pause()})")
        let title = (webView.title ?? "").replacingOccurrences(of: " - YouTube", with: "")
        let video = YouTubeVideo(id: id, title: title.isEmpty ? "YouTube video" : title, channelTitle: "YouTube",
                                 thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg"))
        PlayerController.shared.start(.youtube(video))
    }

    /// youtube.com/watch?v=ID, m.youtube.com/watch?v=ID, youtu.be/ID, youtube.com/shorts/ID, /live/ID.
    nonisolated static func youTubeVideoID(from url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        var candidate: String?
        if host == "youtu.be" {
            candidate = parts.first
        } else if host.hasSuffix("youtube.com") {
            if parts.first == "watch" {
                candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "v" })?.value
            } else if parts.count >= 2, ["shorts", "live", "embed"].contains(parts[0]) {
                candidate = parts[1]
            }
        }
        guard let id = candidate, id.count == 11,
              id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
        return id
    }
}
