import CarPlay
import UIKit

/// CarPlay entry point. Two ways CarPlay can host Car TV:
/// - Its own window scene (Car TV has the audio and video entitlements; the Highlander does this):
///   Car TV draws its own car screen (CarScreenViewController) with video, YouTube and the mirror.
/// - Apple's template host: system templates only; iOS presents video where the car supports it.
/// What the car reports is recorded in Diagnostics.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, UIWindowSceneDelegate,
                                  CPSessionConfigurationDelegate {
    var window: UIWindow?
    private var carScreen: CarScreenViewController?
    private var interfaceController: CPInterfaceController?
    private var browser: AnyObject?
    private var sessionConfiguration: CPSessionConfiguration?
    private var carWindowController: ExternalDisplayViewController?

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        connect(interfaceController, window: nil, scene: scene)
    }

    /// Only navigation apps are documented to get a car window, but CarTV implements this too, so if
    /// iOS ever offers one, use it to show video and the mirror directly.
    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {
        connect(interfaceController, window: window, scene: scene)
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController) {
        disconnect()
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController,
                                  from window: CPWindow) {
        disconnect()
    }

    // MARK: Own car scene

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        Diagnostics.log("CarPlaySceneDelegate.willConnect: \(type(of: scene)), role=\(session.role.rawValue)")
        // Template scenes are handled by the CPTemplateApplicationSceneDelegate methods.
        guard !(scene is CPTemplateApplicationScene), let windowScene = scene as? UIWindowScene else { return }
        let bounds = windowScene.screen.bounds
        Diagnostics.log("Car scene (own window): \(Int(bounds.width))x\(Int(bounds.height)) @\(windowScene.screen.scale)x, role=\(session.role.rawValue)")

        let player = PlayerController.shared
        player.carHasOwnScreen = true
        player.carConnected = true

        let controller = CarScreenViewController()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        carScreen = controller

        Task { await LibraryStore.shared.reloadIfEmpty() }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard carScreen != nil else { return }
        Diagnostics.log("Car scene (own window) disconnected")
        carScreen?.tearDown()
        carScreen = nil
        window = nil
        PlayerController.shared.carHasOwnScreen = false
        PlayerController.shared.carConnected = false
    }

    // MARK: Template scene

    private func connect(_ interfaceController: CPInterfaceController, window: CPWindow?,
                         scene: CPTemplateApplicationScene) {
        self.interfaceController = interfaceController
        PlayerController.shared.carConnected = true

        let configuration = CPSessionConfiguration(delegate: self)
        sessionConfiguration = configuration
        var report = "CarPlay connected"
        if #available(iOS 26.4, *) {
            report += "; supportsVideoPlayback=\(configuration.supportsVideoPlayback)"
        }
        report += "; limitedUI=\(configuration.limitedUserInterfaces.rawValue)"
        report += "; carWindow=\(window.map { "\(Int($0.bounds.width))x\(Int($0.bounds.height))" } ?? "none")"
        Diagnostics.log(report)

        // Cars without CarPlay video (supportsVideoPlayback=false, e.g. the Highlander) never get video
        // through the system route. CarTV handles that case with its "own window": every template scene
        // has a carWindow (documented for navigation apps). Try drawing video and the mirror there.
        var carWindow = window
        if carWindow == nil {
            Diagnostics.log("Checking the scene's car window…")
            carWindow = scene.carWindow
        }
        if let carWindow {
            Diagnostics.log("Car window: \(Int(carWindow.bounds.width))x\(Int(carWindow.bounds.height)), hidden=\(carWindow.isHidden), screen=\(Int(carWindow.screen.bounds.width))x\(Int(carWindow.screen.bounds.height))")
            let controller = ExternalDisplayViewController()
            carWindow.rootViewController = controller
            carWindow.isHidden = false
            carWindowController = controller
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                Diagnostics.log("Car window after 2 s: \(Int(carWindow.bounds.width))x\(Int(carWindow.bounds.height)), hidden=\(carWindow.isHidden), key=\(carWindow.isKeyWindow), view=\(Int(controller.view.bounds.width))x\(Int(controller.view.bounds.height))")
            }
        } else {
            Diagnostics.log("No car window available")
        }

        if #available(iOS 27.0, *) {
            let browser = CarPlayBrowser(interfaceController: interfaceController)
            self.browser = browser
            interfaceController.setRootTemplate(browser.makeRootTemplate(), animated: false, completion: nil)
        } else {
            // Car TV's CarPlay UI needs iOS 27. As an audio app it can still be listed on older iOS, so show
            // a plain list (audio apps can't use the information template).
            let list = CPListTemplate(title: "Car TV", sections: [])
            list.emptyViewTitleVariants = ["Requires iOS 27"]
            interfaceController.setRootTemplate(list, animated: false, completion: nil)
        }

        // The app may have been launched from the car with the phone UI never shown.
        Task { await LibraryStore.shared.reloadIfEmpty() }
    }

    private func disconnect() {
        Diagnostics.log("CarPlay disconnected")
        PlayerController.shared.carConnected = false
        carWindowController?.tearDown()
        carWindowController = nil
        sessionConfiguration = nil
        browser = nil
        interfaceController = nil
    }

    // MARK: CPSessionConfigurationDelegate

    func sessionConfiguration(_ sessionConfiguration: CPSessionConfiguration,
                              limitedUserInterfacesChanged limitedUserInterfaces: CPLimitableUserInterface) {
        var report = "CarPlay limits changed: limitedUI=\(limitedUserInterfaces.rawValue)"
        if #available(iOS 26.4, *) {
            report += "; supportsVideoPlayback=\(sessionConfiguration.supportsVideoPlayback)"
        }
        Diagnostics.log(report)
    }
}
