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
    @State private var webView = WebBrowser.makeWebView()

    var body: some View {
        WebViewContainer(webView: webView)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Web browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
