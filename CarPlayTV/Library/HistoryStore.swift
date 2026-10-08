import Foundation

/// Everything played in this app, newest first. YouTube's API doesn't expose watch history,
/// so this is the app's own record.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    private static let limit = 50

    /// Kept in the Keychain because IPTV stream URLs often embed provider credentials.
    @Published private(set) var items: [MediaItem] {
        didSet { Keychain.save(items, for: "history") }
    }

    private init() {
        items = Keychain.load([MediaItem].self, for: "history") ?? []
    }

    func record(_ item: MediaItem) {
        var updated = items.filter { $0.id != item.id }
        updated.insert(item, at: 0)
        items = Array(updated.prefix(Self.limit))
    }

    func clear() {
        items = []
    }
}
