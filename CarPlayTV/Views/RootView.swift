import SwiftUI

struct RootView: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        TabView {
            ChannelBrowserView(kind: .live)
                .tabItem { Label("TV", systemImage: "tv") }
            ChannelBrowserView(kind: .movie)
                .tabItem { Label("Movies", systemImage: "film") }
            YouTubeHomeView()
                .tabItem { Label("YouTube", systemImage: "play.rectangle") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: $player.phonePlayerPresented) {
            PhonePlayerView()
        }
    }
}

/// Mini player shown at the bottom of each tab while something is playing.
struct NowPlayingBar: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        if let item = player.current {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(player.carConnected ? "Playing on CarPlay" : item.subtitle)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                }
                Button { player.stop() } label: { Image(systemName: "stop.fill") }
            }
            .font(.title3)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
            .contentShape(Rectangle())
            .onTapGesture {
                if !player.carConnected { player.phonePlayerPresented = true }
            }
        }
    }
}

extension View {
    func nowPlayingInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { NowPlayingBar() }
    }
}
