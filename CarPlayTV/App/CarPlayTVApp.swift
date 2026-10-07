import AVFoundation
import SwiftUI

enum AppSettings {
    static let speedLockKey = "speedLockEnabled"
}

@main
struct CarPlayTVApp: App {
    @StateObject private var library = LibraryStore.shared
    @StateObject private var player = PlayerController.shared
    @StateObject private var auth = GoogleAuth.shared

    init() {
        UserDefaults.standard.register(defaults: [AppSettings.speedLockKey: true])
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(auth)
                .task { await library.reloadIfEmpty() }
        }
    }
}
