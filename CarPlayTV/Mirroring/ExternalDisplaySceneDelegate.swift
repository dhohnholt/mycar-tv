import Combine
import UIKit

/// The scene iOS creates when the app is shown on an external screen (the car display while CarPlay
/// video is presented, or any AirPlay screen). It shows the mirrored iPhone screen while a broadcast
/// is running, otherwise Car TV's own video.
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = ExternalDisplayViewController()
        window.isHidden = false
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        (window?.rootViewController as? ExternalDisplayViewController)?.tearDown()
        window = nil
    }
}

final class ExternalDisplayViewController: UIViewController {
    private let surface = VideoSurfaceView()
    private let mirrorLayer = CALayer()
    private let idleLabel = UILabel()
    private var cancellables: Set<AnyCancellable> = []

    override func loadView() {
        view = surface
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        mirrorLayer.contentsGravity = .resizeAspect
        mirrorLayer.backgroundColor = UIColor.black.cgColor
        mirrorLayer.isHidden = true
        mirrorLayer.zPosition = 10 // above an embedded YouTube player
        surface.layer.addSublayer(mirrorLayer)

        idleLabel.text = "Car TV"
        idleLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        idleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        idleLabel.translatesAutoresizingMaskIntoConstraints = false
        idleLabel.layer.zPosition = 11
        surface.addSubview(idleLabel)
        NSLayoutConstraint.activate([
            idleLabel.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
            idleLabel.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
        ])

        let player = PlayerController.shared
        let receiver = MirrorReceiver.shared
        player.registerExternal(surface)
        receiver.onFrame = { [weak self] image in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self?.mirrorLayer.contents = image
            CATransaction.commit()
        }
        receiver.start()

        Publishers.CombineLatest(receiver.$isMirroring, player.$current)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mirroring, current in
                guard let self else { return }
                self.mirrorLayer.isHidden = !mirroring
                if !mirroring { self.mirrorLayer.contents = nil }
                self.idleLabel.isHidden = mirroring || current != nil
            }
            .store(in: &cancellables)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mirrorLayer.frame = surface.bounds
        CATransaction.commit()
        surface.bringSubviewToFront(idleLabel)
    }

    func tearDown() {
        cancellables.removeAll()
        PlayerController.shared.unregister(surface)
        MirrorReceiver.shared.onFrame = nil
    }
}
