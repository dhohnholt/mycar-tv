import CryptoKit
import Foundation

/// Where playback stopped in YouTube videos and movies (not live TV or the mirror), so playing them
/// again continues there. Items are keyed by a hash of their ID: M3U channel IDs are stream URLs that
/// often contain provider logins, and those shouldn't land in UserDefaults.
@MainActor
final class ResumeStore: ObservableObject {
    static let shared = ResumeStore()

    struct Entry: Codable {
        var seconds: Double
        var duration: Double
        var updated: Date
    }

    /// Under this, playing again starts from the beginning.
    private static let minimumSeconds: Double = 10
    /// Within this of the end (or past 95%), the item counts as watched and is forgotten.
    private static let finishedRemaining: Double = 30
    private static let limit = 300
    private static let key = "resume.entries"

    @Published private(set) var entries: [String: Entry]

    private init() {
        entries = (UserDefaults.standard.data(forKey: Self.key))
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    /// Seconds to resume from, if there's a saved position worth resuming.
    func position(for item: MediaItem) -> Double? {
        guard item.isResumable, let entry = entries[Self.key(for: item)] else { return nil }
        return entry.seconds >= Self.minimumSeconds ? entry.seconds : nil
    }

    /// Fraction watched (0...1), for progress bars.
    func progress(for item: MediaItem) -> Double? {
        guard position(for: item) != nil, let entry = entries[Self.key(for: item)], entry.duration > 0 else { return nil }
        return min(1, entry.seconds / entry.duration)
    }

    func remaining(for item: MediaItem) -> Double? {
        guard position(for: item) != nil, let entry = entries[Self.key(for: item)], entry.duration > 0 else { return nil }
        return max(0, entry.duration - entry.seconds)
    }

    func update(_ item: MediaItem, seconds: Double, duration: Double) {
        guard item.isResumable, seconds.isFinite, duration.isFinite, duration > 0 else { return }
        let key = Self.key(for: item)
        let finished = duration - seconds < Self.finishedRemaining || seconds / duration > 0.95
        if seconds < Self.minimumSeconds || finished {
            guard entries[key] != nil else { return }
            entries[key] = nil
        } else {
            entries[key] = Entry(seconds: seconds, duration: duration, updated: Date())
            if entries.count > Self.limit {
                let oldest = entries.sorted { $0.value.updated < $1.value.updated }.prefix(entries.count - Self.limit)
                oldest.forEach { entries[$0.key] = nil }
            }
        }
        save()
    }

    func forget(_ item: MediaItem) {
        guard entries.removeValue(forKey: Self.key(for: item)) != nil else { return }
        save()
    }

    func clear() {
        entries = [:]
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: Self.key)
    }

    private static func key(for item: MediaItem) -> String {
        SHA256.hash(data: Data(item.id.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

extension MediaItem {
    /// YouTube videos and movies can be resumed; live TV and the screen mirror can't.
    var isResumable: Bool {
        switch self {
        case .youtube: true
        case .stream(let channel): channel.kind == .movie && channel.id != PlayerController.mirrorChannel.id
        }
    }
}

/// "12:34" or "1:02:03".
func formatPlaybackTime(_ seconds: Double) -> String {
    let total = Int(seconds.rounded(.down))
    let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
