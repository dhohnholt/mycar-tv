import AVFoundation
import SwiftUI

@main
struct CarPlayTVApp: App {
    @StateObject private var library = LibraryStore.shared
    @StateObject private var player = PlayerController.shared
    @StateObject private var auth = GoogleAuth.shared

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        MirrorReceiver.shared.start()
        MirrorHTTPServer.shared.start()
        #if DEBUG
        DebugLogUploader.shared.start()
        #endif
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
