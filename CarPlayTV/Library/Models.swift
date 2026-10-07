import Foundation

struct Channel: Hashable, Identifiable, Codable {
    enum Kind: String, Codable { case live, movie }

    let id: String
    let name: String
    let group: String
    let logoURL: URL?
    let streamURL: URL
    let kind: Kind
}

struct ChannelGroup: Hashable, Identifiable {
    var id: String { name }
    let name: String
    let channels: [Channel]
}

struct YouTubeVideo: Hashable, Identifiable, Codable {
    let id: String
    let title: String
    let channelTitle: String
    let thumbnailURL: URL?
}

/// A playlist or a subscribed channel's uploads (which YouTube also exposes as a playlist).
struct YouTubePlaylist: Hashable, Identifiable {
    let id: String
    let title: String
    let thumbnailURL: URL?
}

enum MediaItem: Hashable {
    case stream(Channel)
    case youtube(YouTubeVideo)

    var title: String {
        switch self {
        case .stream(let c): c.name
        case .youtube(let v): v.title
        }
    }

    var subtitle: String {
        switch self {
        case .stream(let c): c.group
        case .youtube(let v): v.channelTitle
        }
    }

    var isLive: Bool {
        if case .stream(let c) = self { return c.kind == .live }
        return false
    }
}
