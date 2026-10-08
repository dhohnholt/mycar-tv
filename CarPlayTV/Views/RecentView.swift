import SwiftUI

struct RecentView: View {
    @ObservedObject private var history = HistoryStore.shared

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
                    Button("Clear", role: .destructive) { history.clear() }
                }
            }
            .nowPlayingInset()
        }
    }
}
