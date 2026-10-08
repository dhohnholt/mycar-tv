import CarPlay
import UIKit

/// CarPlay entry point. As a CarPlay video app, Car TV shows only system templates; iOS presents
/// the video itself on the car display when the car allows it.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var browser: AnyObject?

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        PlayerController.shared.carConnected = true

        if #available(iOS 27.0, *) {
            let browser = CarPlayBrowser(interfaceController: interfaceController)
            self.browser = browser
            interfaceController.setRootTemplate(browser.makeRootTemplate(), animated: false, completion: nil)
        } else {
            // The CarPlay video entitlement only exists on iOS 27; older systems never get here in practice.
            let info = CPInformationTemplate(title: "Car TV", layout: .leading,
                                             items: [CPInformationItem(title: "Requires iOS 27", detail: nil)],
                                             actions: [])
            interfaceController.setRootTemplate(info, animated: false, completion: nil)
        }

        // The app may have been launched from the car with the phone UI never shown.
        Task { await LibraryStore.shared.reloadIfEmpty() }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController) {
        PlayerController.shared.carConnected = false
        browser = nil
        self.interfaceController = nil
    }
}
