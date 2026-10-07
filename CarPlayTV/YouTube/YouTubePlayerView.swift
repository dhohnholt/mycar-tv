import UIKit
import WebKit

/// Plays YouTube videos through the official IFrame embed player.
@MainActor
final class YouTubePlayerView: UIView {
    enum State: Int {
        case ended = 0, playing = 1, paused = 2, buffering = 3
    }

    var onStateChange: ((State) -> Void)?

    private let webView: WKWebView

    override init(frame: CGRect) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = false
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: frame)

        config.userContentController.add(MessageHandler(owner: self), name: "yt")
        backgroundColor = .black
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.frame = bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(webView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func load(videoID: String, autoplay: Bool) {
        // Video IDs are [A-Za-z0-9_-]; reject anything else before it reaches the HTML.
        guard videoID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return }
        webView.loadHTMLString(Self.html(videoID: videoID, autoplay: autoplay, origin: Self.origin), baseURL: URL(string: Self.origin))
    }

    func play() { webView.evaluateJavaScript("player && player.playVideo()") }
    func pause() { webView.evaluateJavaScript("player && player.pauseVideo()") }

    func stop() {
        webView.loadHTMLString("<html><body style='background:#000'></body></html>", baseURL: nil)
    }

    fileprivate func received(_ body: Any) {
        if let raw = body as? Int, let state = State(rawValue: raw) {
            onStateChange?(state)
        }
    }

    /// YouTube requires embeds to identify themselves; for apps this is an https URL built from the bundle ID.
    private static let origin = "https://\((Bundle.main.bundleIdentifier ?? "carplaytv").lowercased())"

    private static func html(videoID: String, autoplay: Bool, origin: String) -> String {
        """
        <!doctype html>
        <html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{position:absolute;inset:0;width:100%;height:100%}</style>
        </head><body>
        <div id="p"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player;
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('p', {
            videoId: '\(videoID)',
            playerVars: { playsinline: 1, autoplay: \(autoplay ? 1 : 0), rel: 0, origin: '\(origin)' },
            events: {
              onReady: function(e) { if (\(autoplay)) { e.target.playVideo(); } },
              onStateChange: function(e) { window.webkit.messageHandlers.yt.postMessage(e.data); }
            }
          });
        }
        </script>
        </body></html>
        """
    }
}

/// Holds the player weakly so the WKUserContentController doesn't retain it.
private final class MessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: YouTubePlayerView?

    init(owner: YouTubePlayerView) { self.owner = owner }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { owner?.received(message.body) }
    }
}
