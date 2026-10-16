import SwiftUI

struct YouTubeHomeView: View {
    @EnvironmentObject private var auth: GoogleAuth
    @State private var query = ""
    @State private var results: [YouTubeVideo]?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("YouTube")
                .alert("YouTube", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage ?? "")
                }
                .nowPlayingInset()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !auth.isConfigured {
            ContentUnavailableView {
                Label("YouTube isn't set up", systemImage: "key")
            } description: {
                Text("Add your Google OAuth client ID as GOOGLE_CLIENT_ID in project.yml, then rebuild. See the README.")
            }
        } else if !auth.isSignedIn {
            List {
                webSection
                Section {
                    Button("Sign in with Google") {
                        Task {
                            do { try await auth.signIn() } catch { errorMessage = error.localizedDescription }
                        }
                    }
                } footer: {
                    Text("Sign in to browse your subscriptions, playlists and liked videos, and to search.")
                }
            }
        } else {
            Group {
                if let results {
                    List(results) { VideoRow(video: $0) }
                } else {
                    List {
                        webSection
                        NavigationLink("Latest from subscriptions") {
                            VideoListView(title: "Latest from subscriptions") { try await YouTubeAPI.subscriptionFeed() }
                        }
                        NavigationLink("Trending") {
                            VideoListView(title: "Trending") { try await YouTubeAPI.trending() }
                        }
                        NavigationLink("Liked videos") {
                            VideoListView(title: "Liked videos") { try await YouTubeAPI.liked() }
                        }
                        NavigationLink("Subscriptions") {
                            PlaylistListView(title: "Subscriptions") { try await YouTubeAPI.subscriptions() }
                        }
                        NavigationLink("Playlists") {
                            PlaylistListView(title: "Playlists") { try await YouTubeAPI.playlists() }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search YouTube")
            .onSubmit(of: .search) {
                Task {
                    do { results = try await YouTubeAPI.search(query.trimmed) } catch { errorMessage = error.localizedDescription }
                }
            }
            .onChange(of: query) {
                if query.isEmpty { results = nil }
            }
        }
    }
}

extension YouTubeHomeView {
    /// Home and Watch Later come from YouTube's website, which needs its own sign-in (in the browser).
    var webSection: some View {
        Section {
            NavigationLink { PhoneBrowserView(start: WebBrowser.youTubeHome) } label: {
                Label("Home (your recommendations)", systemImage: "house")
            }
            NavigationLink { PhoneBrowserView(start: WebBrowser.watchLater) } label: {
                Label("Watch Later", systemImage: "clock")
            }
        } footer: {
            Text("Opens YouTube's website (sign in once there). Use Play on car to send a video to the car screen.")
        }
    }
}

struct VideoListView: View {
    let title: String
    let load: () async throws -> [YouTubeVideo]

    @State private var videos: [YouTubeVideo]?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if let videos {
                List(videos) { VideoRow(video: $0) }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .nowPlayingInset()
        .task {
            guard videos == nil else { return }
            do { videos = try await load() } catch { errorMessage = error.localizedDescription }
        }
    }
}

struct PlaylistListView: View {
    let title: String
    let load: () async throws -> [YouTubePlaylist]

    @State private var playlists: [YouTubePlaylist]?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if let playlists {
                List(playlists) { playlist in
                    NavigationLink {
                        VideoListView(title: playlist.title) { try await YouTubeAPI.playlistVideos(playlist.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Thumbnail(url: playlist.thumbnailURL).frame(width: 64)
                            Text(playlist.title).lineLimit(2)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .nowPlayingInset()
        .task {
            guard playlists == nil else { return }
            do { playlists = try await load() } catch { errorMessage = error.localizedDescription }
        }
    }
}

struct VideoRow: View {
    let video: YouTubeVideo

    @EnvironmentObject private var player: PlayerController

    var body: some View {
        Button { player.start(.youtube(video)) } label: {
            HStack(spacing: 12) {
                Thumbnail(url: video.thumbnailURL).frame(width: 120)
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title).foregroundStyle(.primary).lineLimit(2)
                    Text(video.channelTitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct Thumbnail: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.secondary.opacity(0.2)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
