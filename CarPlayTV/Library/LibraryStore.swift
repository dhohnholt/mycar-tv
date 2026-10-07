import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    struct Sources: Codable {
        var playlistURLs: [URL] = []
        var xtream: XtreamAccount?
    }

    /// Playlist URLs usually embed credentials, so sources live in the Keychain, not UserDefaults.
    @Published var sources: Sources {
        didSet { Keychain.save(sources, for: "sources") }
    }

    @Published private(set) var live: [Channel] = []
    @Published private(set) var movies: [Channel] = []
    @Published private(set) var liveGroups: [ChannelGroup] = []
    @Published private(set) var movieGroups: [ChannelGroup] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private init() {
        sources = Keychain.load(Sources.self, for: "sources") ?? Sources()
    }

    func channels(_ kind: Channel.Kind) -> [Channel] { kind == .live ? live : movies }
    func groups(_ kind: Channel.Kind) -> [ChannelGroup] { kind == .live ? liveGroups : movieGroups }

    func reloadIfEmpty() async {
        if live.isEmpty && movies.isEmpty { await reload() }
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var live: [Channel] = []
        var movies: [Channel] = []
        var errors: [String] = []

        for url in sources.playlistURLs {
            do {
                let (data, response) = try await Net.session.data(from: url)
                try Net.check(response)
                for channel in M3UParser.parse(String(decoding: data, as: UTF8.self)) {
                    if channel.kind == .movie { movies.append(channel) } else { live.append(channel) }
                }
            } catch {
                errors.append("\(url.host() ?? "Playlist"): \(error.localizedDescription)")
            }
        }

        if let account = sources.xtream {
            let client = XtreamClient(account: account)
            do { live += try await client.liveChannels() } catch { errors.append("Xtream live: \(error.localizedDescription)") }
            do { movies += try await client.movies() } catch { errors.append("Xtream movies: \(error.localizedDescription)") }
        }

        self.live = live
        self.movies = movies
        liveGroups = Self.grouped(live)
        movieGroups = Self.grouped(movies)
        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    /// Groups channels by `group`, keeping the order groups first appear in the playlist.
    private static func grouped(_ channels: [Channel]) -> [ChannelGroup] {
        var order: [String] = []
        var byGroup: [String: [Channel]] = [:]
        for channel in channels {
            if byGroup[channel.group] == nil { order.append(channel.group) }
            byGroup[channel.group, default: []].append(channel)
        }
        return order.map { ChannelGroup(name: $0, channels: byGroup[$0] ?? []) }
    }
}
