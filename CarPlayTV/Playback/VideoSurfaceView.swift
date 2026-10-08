import AVFoundation
import UIKit

/// The phone's video area. PlayerController decides what it shows: the AVPlayer layer for streams,
/// or the embedded YouTube player.
final class VideoSurfaceView: UIView {
    let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
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
        addSubview(view)
    }
}
