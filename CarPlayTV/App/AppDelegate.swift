import AVFoundation
import CarPlay
import OSLog
import SwiftUI
import UIKit

/// UIKit app lifecycle. Car TV routes every scene itself: SwiftUI's App lifecycle claimed the car
/// scene CarPlay creates for Car TV (a plain window scene, since the app has the audio and video
/// entitlements) and crashed in AppSceneDelegate.responds(to:) with infinite recursion. The phone UI is
/// still SwiftUI, hosted by PhoneSceneDelegate.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    private static let log = Logger(subsystem: "com.hohnholt.carplaytv", category: "Diagnostics")

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        MirrorReceiver.shared.start()
        MirrorHTTPServer.shared.start()
        #if DEBUG
        DebugLogUploader.shared.start()
        #endif
        discardForeignSessions(application)
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let requested = session.configuration
        report("Scene request: role=\(session.role.rawValue), class=\(requested.sceneClass.map { String(describing: $0) } ?? "nil")")

        let configuration = UISceneConfiguration(name: requested.name, sessionRole: session.role)
        configuration.sceneClass = requested.sceneClass
        switch session.role {
        case .windowApplication:
            configuration.delegateClass = PhoneSceneDelegate.self
        case .windowExternalDisplayNonInteractive, UISceneSession.Role(rawValue: "UIWindowSceneSessionRoleExternalDisplay"):
            configuration.delegateClass = ExternalDisplaySceneDelegate.self
        default:
            // CarPlay: a template scene, or Car TV's own car window scene.
            configuration.delegateClass = CarPlaySceneDelegate.self
        }
        return configuration
    }

    /// iOS reuses remembered scene sessions without asking configurationForConnecting again. Sessions
    /// remembered from the SwiftUI lifecycle still name SwiftUI's handler, so discard them; iOS creates
    /// fresh ones that are routed above.
    private func discardForeignSessions(_ application: UIApplication) {
        let ours: [AnyClass] = [PhoneSceneDelegate.self, CarPlaySceneDelegate.self, ExternalDisplaySceneDelegate.self]
        for session in application.openSessions {
            let delegate = session.configuration.delegateClass
            guard !ours.contains(where: { $0 == delegate }) else { continue }
            report("Discarding stale scene session: role=\(session.role.rawValue), delegate=\(delegate.map { String(describing: $0) } ?? "nil")")
            application.requestSceneSessionDestruction(session, options: nil, errorHandler: nil)
        }
    }

    private func report(_ message: String) {
        Self.log.notice("CarTVDiag: \(message, privacy: .public)")
        Diagnostics.log(message)
    }
}

/// The phone's window: the SwiftUI interface.
final class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let root = RootView()
            .environmentObject(LibraryStore.shared)
            .environmentObject(PlayerController.shared)
            .environmentObject(GoogleAuth.shared)
            .task { await LibraryStore.shared.reloadIfEmpty() }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        self.window = window
    }
}
