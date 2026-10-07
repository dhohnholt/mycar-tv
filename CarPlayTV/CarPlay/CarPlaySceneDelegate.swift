import CarPlay
import UIKit

/// CarPlay entry point. As a navigation-class app we get a full `CPWindow`, which is what lets us
/// draw video; templates (lists, search, buttons) float on top of it.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var window: CPWindow?
    private var surface: VideoSurfaceView?
    private var browser: CarPlayBrowser?

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {
        self.interfaceController = interfaceController
        self.window = window

        let surface = VideoSurfaceView()
        let viewController = UIViewController()
        viewController.view = surface
        window.rootViewController = viewController
        self.surface = surface

        let player = PlayerController.shared
        player.register(surface, as: .car)
        player.carConnected = true

        let browser = CarPlayBrowser(interfaceController: interfaceController)
        self.browser = browser
        interfaceController.setRootTemplate(browser.makeRootTemplate(), animated: false, completion: nil)

        // The app may have been launched from the car with the phone UI never shown.
        Task { await LibraryStore.shared.reloadIfEmpty() }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController,
                                  from window: CPWindow) {
        let player = PlayerController.shared
        player.carConnected = false
        if let surface { player.unregister(surface) }
        player.pause()
        surface = nil
        browser = nil
        self.window = nil
        self.interfaceController = nil
    }
}
