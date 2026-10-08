import SwiftUI

struct ChannelBrowserView: View {
    let kind: Channel.Kind

    @EnvironmentObject private var library: LibraryStore
    @State private var query = ""

    private var title: String { kind == .live ? "TV" : "Movies" }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationDestination(for: ChannelGroup.self) { group in
                    List(group.channels) { ChannelRow(channel: $0) }
                        .navigationTitle(group.name)
                        .nowPlayingInset()
                }
                .searchable(text: $query, prompt: "Search \(title)")
                .refreshable { await library.reload() }
                .nowPlayingInset()
        }
    }

    @ViewBuilder
    private var content: some View {
        let channels = library.channels(kind)
        if library.isLoading && channels.isEmpty {
            ProgressView("Loading your library…")
        } else if channels.isEmpty {
            ContentUnavailableView {
                Label(kind == .live ? "No channels yet" : "No movies yet", systemImage: kind == .live ? "tv" : "film")
            } description: {
                Text("Add an M3U playlist or an Xtream login in Settings.")
            }
        } else if !query.trimmed.isEmpty {
            let matches = channels.filter { $0.name.localizedCaseInsensitiveContains(query.trimmed) }
            if matches.isEmpty {
                ContentUnavailableView.search(text: query.trimmed)
            } else {
                List(matches) { ChannelRow(channel: $0) }
            }
        } else {
            List(library.groups(kind)) { group in
                NavigationLink(value: group) {
                    LabeledContent(group.name, value: "\(group.channels.count)")
                }
            }
        }
    }
}

struct ChannelRow: View {
    let channel: Channel

    @EnvironmentObject private var player: PlayerController

    var body: some View {
        Button { player.start(.stream(channel)) } label: {
            HStack(spacing: 12) {
                AsyncImage(url: channel.logoURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: channel.kind == .live ? "tv" : "film").foregroundStyle(.secondary)
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
                Text(channel.name)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
    }
}
