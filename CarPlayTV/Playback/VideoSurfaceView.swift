import AVFoundation
import UIKit

/// A place video can be shown: the CarPlay window or the phone's full-screen player.
/// PlayerController decides which surface is active and what it shows.
final class VideoSurfaceView: UIView {
    let playerLayer = AVPlayerLayer()
    private let messageLabel = UILabel()

    var message: String? {
        didSet {
            messageLabel.text = message
            messageLabel.isHidden = message == nil
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
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
    }

    func embed(_ view: UIView) {
        guard view.superview !== self else { return }
        view.removeFromSuperview()
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        insertSubview(view, belowSubview: messageLabel)
    }
}
