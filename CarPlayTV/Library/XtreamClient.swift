import Foundation

struct XtreamAccount: Codable, Hashable {
    var server: URL
    var username: String
    var password: String
}

/// Minimal client for the Xtream Codes `player_api.php` API (live TV and movies).
struct XtreamClient {
    let account: XtreamAccount

    private struct Category: Decodable {
        let category_id: Flex
        let category_name: String
    }

    private struct Stream: Decodable {
        let stream_id: Flex
        let name: String?
        let stream_icon: String?
        let category_id: Flex?
        let container_extension: String?
    }

    func liveChannels() async throws -> [Channel] {
        try await load(.live, categories: "get_live_categories", streams: "get_live_streams")
    }

    func movies() async throws -> [Channel] {
        try await load(.movie, categories: "get_vod_categories", streams: "get_vod_streams")
    }

    private func load(_ kind: Channel.Kind, categories: String, streams: String) async throws -> [Channel] {
        async let categoryList: [Category] = get(categories)
        async let streamList: [Stream] = get(streams)
        let (cats, items) = try await (categoryList, streamList)
        let names = Dictionary(cats.map { ($0.category_id.value, $0.category_name) }, uniquingKeysWith: { first, _ in first })

        return items.map { item in
            let id = item.stream_id.value
            let ext = kind == .live ? "m3u8" : (item.container_extension ?? "mp4")
            let url = account.server.appending(components: kind == .live ? "live" : "movie",
                                               account.username, account.password, "\(id).\(ext)")
            return Channel(
                id: "xtream:\(kind.rawValue):\(id)",
                name: item.name ?? "Untitled",
                group: names[item.category_id?.value ?? ""] ?? "Uncategorized",
                logoURL: item.stream_icon.flatMap(URL.init(string:)),
                streamURL: url,
                kind: kind
            )
        }
    }

    private func get<T: Decodable>(_ action: String) async throws -> T {
        var components = URLComponents(url: account.server.appending(path: "player_api.php"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "username", value: account.username),
            URLQueryItem(name: "password", value: account.password),
            URLQueryItem(name: "action", value: action),
        ]
        let (data, response) = try await Net.session.data(from: components.url!)
        try Net.check(response)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Xtream servers are inconsistent about whether IDs are strings or numbers.
private struct Flex: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(Int(double))
        } else {
            value = ""
        }
    }
}
