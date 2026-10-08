import SwiftUI

struct RecentView: View {
    @ObservedObject private var history = HistoryStore.shared
    @State private var confirmingClear = false

    var body: some View {
        NavigationStack {
            Group {
                if history.items.isEmpty {
                    ContentUnavailableView("Nothing watched yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("Videos and channels you play show up here."))
                } else {
                    List(history.items) { item in
                        switch item {
                        case .stream(let channel): ChannelRow(channel: channel)
                        case .youtube(let video): VideoRow(video: video)
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
