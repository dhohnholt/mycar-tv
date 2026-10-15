import CarPlay
import UIKit

/// CarPlay entry point. Car TV shows only system templates (it runs as a CarPlay audio or video app);
/// iOS presents the video itself on the car display when the car allows it.
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
            // Car TV's CarPlay UI needs iOS 27. As an audio app it can still be listed on older iOS, so show
            // a plain list (audio apps can't use the information template).
            let list = CPListTemplate(title: "Car TV", sections: [])
            list.emptyViewTitleVariants = ["Requires iOS 27"]
            interfaceController.setRootTemplate(list, animated: false, completion: nil)
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
