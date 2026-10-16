import SwiftUI
import WebKit

/// A plain web browser for the car screen (as CarTV does), mainly for YouTube's mobile site, e.g. the
/// Watch Later playlist, which the YouTube Data API doesn't expose. Phone and car browsers share the
/// default website data store, so signing in to YouTube once on the phone also signs in the car.
enum WebBrowser {
    static let home = URL(string: "https://www.youtube.com/playlist?list=WL")!
    static let watchLater = home
    /// YouTube's personalized home feed (signed in), which the Data API doesn't provide.
    static let youTubeHome = URL(string: "https://m.youtube.com/")!

    /// Google's sign-in page, going straight back to the Watch Later list afterwards.
    static let signIn = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&passive=true&hl=en&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Dm%26next%3D%252Fplaylist%253Flist%253DWL")!

    /// Identify as Safari on this iPhone's real iOS version: Google refuses sign-in from user agents it
    /// recognizes as embedded web views, and a mismatched version looks suspicious.
    static let userAgent: String = {
        let version = UIDevice.current.systemVersion
        let underscored = version.replacingOccurrences(of: ".", with: "_")
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(underscored) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(version) Mobile/15E148 Safari/604.1"
    }()

    /// Google's sign-in opens some steps in new windows; open them in the same view instead of dropping them.
    private static let uiDelegate = SameWindowUIDelegate()

    @MainActor
    static func makeWebView(start: URL = home) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = userAgent
        webView.uiDelegate = uiDelegate
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.load(URLRequest(url: start))
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
    var start: URL = WebBrowser.home
    @StateObject private var page = BrowserPage()
    @ObservedObject private var player = PlayerController.shared

    private var webView: WKWebView { page.webView }

    var body: some View {
        WebViewContainer(webView: webView)
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .top, spacing: 0) { signInBar }
            .onAppear { page.open(start) }
            .navigationTitle("Web browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar) // its own back/forward/home bar sits where the tab bar would
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

extension PhoneBrowserView {
    /// Sign-in status, a direct sign-in button, and the passkey hint.
    @ViewBuilder
    var signInBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(page.signedIn ? "Signed in to YouTube" : "Not signed in to YouTube",
                      systemImage: page.signedIn ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(page.signedIn ? .green : .orange)
                Spacer()
                if page.signedIn {
                    Button("Sign out", role: .destructive) { page.signOut() }
                        .font(.subheadline)
                } else {
                    Button("Sign in") { webView.load(URLRequest(url: WebBrowser.signIn)) }
                        .buttonStyle(.borderedProminent)
                        .font(.subheadline)
                }
            }
            if !page.signedIn {
                Text("Passkeys don't work here. If Google offers one, tap \"Try another way\", then \"Enter your password\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// Loads pages that would open a new window (Google sign-in steps, target=_blank links) in the same view.
final class SameWindowUIDelegate: NSObject, WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == false {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

/// The phone browser's web view plus the YouTube video ID of the page it's on, if any.
@MainActor
final class BrowserPage: ObservableObject {
    let webView = WebBrowser.makeWebView()
    @Published private(set) var videoID: String?
    @Published private(set) var signedIn = false
    private var observation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?

    init() {
        observation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
            let id = webView.url.flatMap(Self.youTubeVideoID)
            DispatchQueue.main.async { self?.videoID = id }
        }
        // Re-check the sign-in cookies whenever a page finishes loading.
        loadingObservation = webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
            guard !webView.isLoading else { return }
            DispatchQueue.main.async { self?.refreshSignIn() }
        }
    }

    /// YouTube sets these cookies only for a signed-in Google account.
    /// Opens a start page. Watch Later only exists for a signed-in account (signed out, YouTube says the
    /// playlist doesn't exist), so go to Google's sign-in first, which returns to Watch Later afterwards.
    func open(_ start: URL) {
        Self.isSignedIn { signedIn in
            self.signedIn = signedIn
            let target = (start == WebBrowser.watchLater && !signedIn) ? WebBrowser.signIn : start
            if self.webView.url != target { self.webView.load(URLRequest(url: target)) }
        }
    }

    /// Calls back on the main thread with whether the browser is signed in to YouTube.
    static func isSignedIn(_ completion: @escaping @MainActor (Bool) -> Void) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let signedIn = cookies.contains { cookie in
                cookie.domain.hasSuffix("youtube.com") && ["SAPISID", "__Secure-3PAPISID", "LOGIN_INFO"].contains(cookie.name)
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(signedIn) } }
        }
    }

    func refreshSignIn() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            let signedIn = cookies.contains { cookie in
                cookie.domain.hasSuffix("youtube.com") && ["SAPISID", "__Secure-3PAPISID", "LOGIN_INFO"].contains(cookie.name)
            }
            DispatchQueue.main.async { self?.signedIn = signedIn }
        }
    }

    /// Clears the browser's cookies and site data (phone and car browsers share them).
    func signOut() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            DispatchQueue.main.async {
                self?.signedIn = false
                self?.webView.load(URLRequest(url: WebBrowser.home))
            }
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
