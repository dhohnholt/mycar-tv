import AVFoundation
import UIKit

/// A place video can be shown: the CarPlay window or the phone's full-screen player.
/// PlayerController decides which surface is active and what it shows.
final class VideoSurfaceView: UIView {
    let playerLayer = AVPlayerLayer()
    private let messageLabel = UILabel()

    /// Fill the view (cropping edges) instead of fitting the whole picture with black bars.
    var fillsScreen = false {
        didSet {
            playerLayer.videoGravity = fillsScreen ? .resizeAspectFill : .resizeAspect
            setNeedsLayout()
        }
    }

    /// The embedded YouTube player, if any, so it can be scaled to cover the view in full screen.
    private weak var embeddedView: UIView?

    var message: String? {
        didSet {
            messageLabel.text = message
            messageLabel.isHidden = message == nil
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)

        messageLabel.textColor = .white
        messageLabel.font = .preferredFont(forTextStyle: .title3)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        messageLabel.isHidden = true
        messageLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        messageLabel.frame = bounds
        addSubview(messageLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
        scaleEmbeddedView()
    }

    /// The YouTube player letterboxes 16:9 video inside its frame, so full screen scales the whole
    /// player up until the video covers the view.
    private func scaleEmbeddedView() {
        guard let embeddedView, bounds.width > 0, bounds.height > 0 else { return }
        var scale: CGFloat = 1
        if fillsScreen {
            let viewAspect = bounds.width / bounds.height
            let videoAspect: CGFloat = 16 / 9
            scale = max(viewAspect / videoAspect, videoAspect / viewAspect)
        }
        embeddedView.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    func embed(_ view: UIView) {
        embeddedView = view
        defer { scaleEmbeddedView() }
        guard view.superview !== self else { return }
        view.removeFromSuperview()
        view.transform = .identity
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        insertSubview(view, belowSubview: messageLabel)
    }
}
