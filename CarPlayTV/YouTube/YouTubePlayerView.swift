import UIKit
import WebKit

/// Plays YouTube videos through the official IFrame embed player.
@MainActor
final class YouTubePlayerView: UIView {
    enum State: Int {
        case ended = 0, playing = 1, paused = 2, buffering = 3
    }

    var onStateChange: ((State) -> Void)?
    /// Pre-start buffering progress (0...1) and whether it has finished and playback started.
    var onPrerollProgress: ((Double, Bool) -> Void)?

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

    /// With `preroll` > 0 the video starts muted, is paused as soon as it plays, buffers until `preroll`
    /// seconds are loaded ahead (after at least `minimumWait`, at most `maximumWait` seconds), then
    /// unmutes and plays.
    func load(videoID: String, autoplay: Bool, startAt seconds: Int = 0,
              preroll: Double = 0, minimumWait: Double = 0, maximumWait: Double = 0) {
        // Video IDs are [A-Za-z0-9_-]; reject anything else before it reaches the HTML.
        guard videoID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return }
        let html = Self.html(videoID: videoID, autoplay: autoplay, start: max(0, seconds), origin: Self.origin,
                             preroll: autoplay ? max(0, preroll) : 0, minimumWait: minimumWait, maximumWait: maximumWait)
        webView.loadHTMLString(html, baseURL: URL(string: Self.origin))
    }

    /// Plays, ending any pre-start buffering early.
    func play() { webView.evaluateJavaScript("window.playNow && playNow()") }

    /// Current position and duration in seconds, if the player is ready.
    func progress(_ completion: @escaping (Double, Double) -> Void) {
        let script = "(window.player && player.getCurrentTime) ? [player.getCurrentTime(), player.getDuration()] : null"
        webView.evaluateJavaScript(script) { result, _ in
            guard let values = result as? [NSNumber], values.count == 2 else { return }
            completion(values[0].doubleValue, values[1].doubleValue)
        }
    }

    func seek(to seconds: Double) {
        webView.evaluateJavaScript("player && player.seekTo(\(max(0, seconds)), true)")
    }
    /// Pauses, cancelling any pre-start buffering.
    func pause() { webView.evaluateJavaScript("window.pauseNow && pauseNow()") }

    func stop() {
        webView.loadHTMLString("<html><body style='background:#000'></body></html>", baseURL: nil)
    }

    fileprivate func received(_ body: Any) {
        if let raw = body as? Int, let state = State(rawValue: raw) {
            onStateChange?(state)
        } else if let message = body as? [String: Any], let progress = message["preroll"] as? Double {
            onPrerollProgress?(progress, (message["done"] as? Bool) ?? false)
        }
    }

    /// YouTube requires embeds to identify themselves; for apps this is an https URL built from the bundle ID.
    private static let origin = "https://\((Bundle.main.bundleIdentifier ?? "carplaytv").lowercased())"

    private static func html(videoID: String, autoplay: Bool, start: Int, origin: String,
                             preroll: Double, minimumWait: Double, maximumWait: Double) -> String {
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
        var preroll = \(preroll), minWait = \(minimumWait), maxWait = \(maximumWait);
        var prerolling = preroll > 0, prerollTimer = null, prerollStart = 0;
        function post(m) { window.webkit.messageHandlers.yt.postMessage(m); }
        function endPreroll() {
          if (!prerolling) return false;
          prerolling = false;
          if (prerollTimer) { clearInterval(prerollTimer); prerollTimer = null; }
          player.unMute();
          post({ preroll: 1, done: true });
          return true;
        }
        function playNow() { if (!player) return; endPreroll(); player.playVideo(); }
        function pauseNow() { if (!player) return; endPreroll(); player.pauseVideo(); post(2); }
        function watchPreroll() {
          prerollStart = Date.now();
          prerollTimer = setInterval(function() {
            var waited = (Date.now() - prerollStart) / 1000;
            var d = player.getDuration() || 0, t = player.getCurrentTime() || 0;
            var frac = player.getVideoLoadedFraction() || 0;
            var ahead = frac * d - t;
            var full = frac >= 0.999;
            post({ preroll: Math.min(1, Math.max(ahead / preroll, waited / maxWait, full ? 1 : 0)), done: false });
            if (((ahead >= preroll || full) && waited >= minWait) || waited >= maxWait) {
              endPreroll();
              player.playVideo();
            }
          }, 250);
        }
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('p', {
            videoId: '\(videoID)',
            playerVars: { playsinline: 1, autoplay: \(autoplay ? 1 : 0), rel: 0, start: \(start), origin: '\(origin)' },
            events: {
              onReady: function(e) { if (\(autoplay)) { if (prerolling) { e.target.mute(); } e.target.playVideo(); } },
              onStateChange: function(e) {
                if (prerolling) {
                  // Started (muted): pause and let it buffer, then play from the same spot.
                  if (e.data == 1 && !prerollTimer) { player.pauseVideo(); watchPreroll(); }
                  return;
                }
                post(e.data);
              }
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
