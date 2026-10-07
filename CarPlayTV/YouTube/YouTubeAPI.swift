import Foundation

/// YouTube Data API v3. Quota: search costs 100 units, everything else here costs 1
/// (default daily quota is 10,000 units, i.e. ~100 searches a day).
@MainActor
enum YouTubeAPI {
    private static let base = URL(string: "https://www.googleapis.com/youtube/v3")!

    static func search(_ query: String) async throws -> [YouTubeVideo] {
        let list: ListResponse<SearchItem> = try await get("search", [
            "part": "snippet", "type": "video", "maxResults": "25", "q": query,
        ])
        return list.items.compactMap { item in
            item.id.videoId.map { YouTubeVideo(id: $0, title: item.snippet.title.htmlDecoded,
                                               channelTitle: item.snippet.channelTitle.htmlDecoded,
                                               thumbnailURL: item.snippet.thumbnails.best) }
        }
    }

    static func liked() async throws -> [YouTubeVideo] {
        let list: ListResponse<VideoItem> = try await get("videos", [
            "part": "snippet", "myRating": "like", "maxResults": "50",
        ])
        return list.items.map {
            YouTubeVideo(id: $0.id, title: $0.snippet.title, channelTitle: $0.snippet.channelTitle, thumbnailURL: $0.snippet.thumbnails.best)
        }
    }

    /// Each subscription is returned as its channel's uploads playlist.
    static func subscriptions() async throws -> [YouTubePlaylist] {
        let list: ListResponse<SubscriptionItem> = try await get("subscriptions", [
            "part": "snippet", "mine": "true", "maxResults": "50", "order": "alphabetical",
        ])
        return list.items.compactMap { item in
            let channelID = item.snippet.resourceId.channelId
            guard let channelID, channelID.hasPrefix("UC") else { return nil }
            // A channel's uploads playlist ID is its channel ID with "UC" replaced by "UU".
            return YouTubePlaylist(id: "UU" + channelID.dropFirst(2), title: item.snippet.title, thumbnailURL: item.snippet.thumbnails?.best)
        }
    }

    static func playlists() async throws -> [YouTubePlaylist] {
        let list: ListResponse<PlaylistResource> = try await get("playlists", [
            "part": "snippet", "mine": "true", "maxResults": "50",
        ])
        return list.items.map { YouTubePlaylist(id: $0.id, title: $0.snippet.title, thumbnailURL: $0.snippet.thumbnails?.best) }
    }

    static func playlistVideos(_ playlistID: String) async throws -> [YouTubeVideo] {
        let list: ListResponse<PlaylistItem> = try await get("playlistItems", [
            "part": "snippet", "playlistId": playlistID, "maxResults": "50",
        ])
        return list.items.compactMap { item in
            guard let id = item.snippet.resourceId.videoId, item.snippet.thumbnails?.best != nil else { return nil } // skips private/deleted
            return YouTubeVideo(id: id, title: item.snippet.title, channelTitle: item.snippet.videoOwnerChannelTitle ?? "",
                                thumbnailURL: item.snippet.thumbnails?.best)
        }
    }

    private static func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        let token = try await GoogleAuth.shared.accessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await Net.session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 403 {
            throw YouTubeError.forbidden
        }
        try Net.check(response)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum YouTubeError: LocalizedError {
    case forbidden

    var errorDescription: String? {
        "YouTube refused the request (daily quota used up, or the API isn't enabled for your Google Cloud project)."
    }
}

// MARK: - Response shapes

private struct ListResponse<Item: Decodable>: Decodable {
    let items: [Item]
}

private struct Thumbnails: Decodable {
    struct Image: Decodable { let url: URL }
    let medium: Image?
    let high: Image?
    let `default`: Image?
    var best: URL? { medium?.url ?? high?.url ?? `default`?.url }
}

private struct Snippet: Decodable {
    let title: String
    let channelTitle: String
    let thumbnails: Thumbnails
}

private struct SearchItem: Decodable {
    struct ID: Decodable { let videoId: String? }
    let id: ID
    let snippet: Snippet
}

private struct VideoItem: Decodable {
    let id: String
    let snippet: Snippet
}

private struct ResourceID: Decodable {
    let videoId: String?
    let channelId: String?
}

private struct SubscriptionItem: Decodable {
    struct Snip: Decodable {
        let title: String
        let thumbnails: Thumbnails?
        let resourceId: ResourceID
    }
    let snippet: Snip
}

private struct PlaylistResource: Decodable {
    struct Snip: Decodable {
        let title: String
        let thumbnails: Thumbnails?
    }
    let id: String
    let snippet: Snip
}

private struct PlaylistItem: Decodable {
    struct Snip: Decodable {
        let title: String
        let videoOwnerChannelTitle: String?
        let thumbnails: Thumbnails?
        let resourceId: ResourceID
    }
    let snippet: Snip
}

private extension String {
    /// The search endpoint returns HTML-escaped titles.
    var htmlDecoded: String {
        replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
