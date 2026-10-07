import Foundation

enum M3UParser {
    static func parse(_ text: String) -> [Channel] {
        var channels: [Channel] = []
        var pending: (name: String, attributes: [String: String])?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF") {
                pending = parseInfo(line)
            } else if line.isEmpty || line.hasPrefix("#") {
                continue
            } else if let url = URL(string: line), url.scheme != nil {
                let attributes = pending?.attributes ?? [:]
                let name = pending?.name.nilIfEmpty ?? attributes["tvg-name"] ?? url.lastPathComponent
                let path = url.path.lowercased()
                let kind: Channel.Kind = path.contains("/movie/") || path.hasSuffix(".mp4") || path.hasSuffix(".mkv") ? .movie : .live
                channels.append(Channel(
                    id: line,
                    name: name,
                    group: attributes["group-title"]?.nilIfEmpty ?? "Uncategorized",
                    logoURL: attributes["tvg-logo"].flatMap(URL.init(string:)),
                    streamURL: url,
                    kind: kind
                ))
                pending = nil
            }
        }
        return channels
    }

    /// `#EXTINF:-1 tvg-id="x" tvg-logo="http://…" group-title="News",Channel Name`
    private static func parseInfo(_ line: String) -> (String, [String: String]) {
        var attributes: [String: String] = [:]
        for match in line.matches(of: /([\w-]+)="([^"]*)"/) {
            attributes[String(match.1)] = String(match.2)
        }
        // The display name follows the first comma that is not inside quotes.
        var inQuotes = false
        var name = ""
        for (index, char) in zip(line.indices, line) {
            if char == "\"" { inQuotes.toggle() }
            if char == ",", !inQuotes {
                name = String(line[line.index(after: index)...]).trimmed
                break
            }
        }
        return (name, attributes)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
