import CarPlay
import UIKit

/// CarPlay entry point. Car TV shows only system templates (it runs as a CarPlay audio app); iOS
/// presents video on the car display when the car allows it. What the car reports is recorded in
/// Diagnostics so a test drive can be read back afterwards.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPSessionConfigurationDelegate {
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
