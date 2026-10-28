import SwiftUI

struct RecentView: View {
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var resume = ResumeStore.shared
    @State private var confirmingClear = false

    private var inProgress: [MediaItem] { history.items.filter { resume.progress(for: $0) != nil } }

    var body: some View {
        NavigationStack {
            Group {
                if history.items.isEmpty {
                    ContentUnavailableView("Nothing watched yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("Videos and channels you play show up here."))
                } else {
                    List {
                        if !inProgress.isEmpty {
                            Section("Continue watching") {
                                ForEach(inProgress) { ContinueRow(item: $0) }
                            }
                        }
                        Section(inProgress.isEmpty ? "" : "All") {
                            ForEach(history.items) { item in
                                switch item {
                                case .stream(let channel): ChannelRow(channel: channel)
                                case .youtube(let video): VideoRow(video: video)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Recently watched")
            .toolbar {
                if !history.items.isEmpty {
                    Button("Clear", role: .destructive) { confirmingClear = true }
                }
            }
            .confirmationDialog("Clear watch history?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear watch history", role: .destructive) { history.clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your recently watched list from this iPhone.")
            }
            .nowPlayingInset()
        }
    }
}

/// A partly watched YouTube video or movie: resumes on tap; hold for Start over.
private struct ContinueRow: View {
    let item: MediaItem
    @EnvironmentObject private var player: PlayerController
    @ObservedObject private var resume = ResumeStore.shared

    var body: some View {
        Button { player.start(item) } label: {
            HStack(spacing: 12) {
                AsyncImage(url: item.artworkURL) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.2) }
                    .frame(width: 96, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).foregroundStyle(.primary).lineLimit(2)
                    ProgressView(value: resume.progress(for: item) ?? 0)
                        .tint(.red)
                    if let remaining = resume.remaining(for: item) {
                        Text("\(formatPlaybackTime(remaining)) left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .contextMenu {
            Button { player.start(item) } label: { Label("Resume", systemImage: "play.fill") }
            Button {
                ResumeStore.shared.forget(item)
                player.start(item)
            } label: { Label("Start over", systemImage: "backward.end.fill") }
            Button(role: .destructive) { ResumeStore.shared.forget(item) } label: {
                Label("Remove from Continue watching", systemImage: "xmark")
            }
        }
    }
}
