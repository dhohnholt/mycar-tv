import CarPlay
import Combine
import UIKit

/// Builds the CarPlay templates: a map template (our video canvas) with TV / Movies / YouTube /
/// Search buttons, plus the list and search templates pushed on top of it.
@MainActor
final class CarPlayBrowser: NSObject {
    private let interfaceController: CPInterfaceController
    private let player = PlayerController.shared
    private let library = LibraryStore.shared
    private var cancellables: Set<AnyCancellable> = []
    private var lastSearchText = ""

    private var maxItems: Int { CPListTemplate.maximumItemCount }

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    func makeRootTemplate() -> CPMapTemplate {
        let map = CPMapTemplate()
        map.automaticallyHidesNavigationBar = false
        map.leadingNavigationBarButtons = [
            CPBarButton(title: "TV") { [weak self] _ in self?.showGroups(.live) },
            CPBarButton(title: "Movies") { [weak self] _ in self?.showGroups(.movie) },
        ]
        map.trailingNavigationBarButtons = [
            CPBarButton(title: "YouTube") { [weak self] _ in self?.showYouTube() },
            CPBarButton(image: Self.symbol("magnifyingglass")) { [weak self] _ in self?.showSearch() },
        ]

        let playPause = CPMapButton { [weak self] _ in self?.player.togglePlayPause() }
        playPause.image = Self.symbol("play.fill")
        let stop = CPMapButton { [weak self] _ in self?.player.stop() }
        stop.image = Self.symbol("stop.fill")
        map.mapButtons = [playPause, stop]

        player.$isPlaying
            .sink { playing in playPause.image = Self.symbol(playing ? "pause.fill" : "play.fill") }
            .store(in: &cancellables)

        return map
    }

    // MARK: IPTV

    private func showGroups(_ kind: Channel.Kind) {
        let groups = library.groups(kind)
        guard !groups.isEmpty else {
            let what = kind == .live ? "channels" : "movies"
            return showAlert(library.isLoading ? "Still loading \(what)…" : "No \(what) yet. Add a playlist in the app on your iPhone.")
        }
        let recent = recentSection()
        let items = groups.prefix(maxItems - (recent == nil ? 0 : 1)).map { group in
            let item = CPListItem(text: group.name, detailText: "\(group.channels.count)")
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                self?.showChannels(group)
                completion()
            }
            return item
        }
        push(CPListTemplate(title: kind == .live ? "TV" : "Movies",
                            sections: [recent, CPListSection(items: items)].compactMap { $0 }))
    }

    private func showChannels(_ group: ChannelGroup) {
        var items = group.channels.prefix(maxItems).map(channelItem)
        if group.channels.count > items.count {
            items.removeLast()
            items.append(CPListItem(text: "\(group.channels.count - items.count) more — use Search", detailText: nil))
        }
        push(CPListTemplate(title: group.name, sections: [CPListSection(items: items)]))
    }

    private func channelItem(_ channel: Channel) -> CPListItem {
        let item = CPListItem(text: channel.name, detailText: channel.kind == .movie ? channel.group : nil)
        item.handler = { [weak self] _, completion in
            self?.play(.stream(channel))
            completion()
        }
        loadImage(channel.logoURL, into: item)
        return item
    }

    // MARK: Recently watched

    /// A "Recently watched" shortcut shown above the TV and Movies groups, if there's any history.
    private func recentSection() -> CPListSection? {
        guard !HistoryStore.shared.items.isEmpty else { return nil }
        let item = menuItem("Recently watched", symbol: "clock.arrow.circlepath") { [weak self] in self?.showRecent() }
        return CPListSection(items: [item])
    }

    private func showRecent() {
        let history = HistoryStore.shared.items
        guard !history.isEmpty else {
            return showAlert("Nothing watched yet.")
        }
        let items = history.prefix(maxItems).map { media in
            let item = CPListItem(text: media.title, detailText: media.subtitle)
            item.handler = { [weak self] _, completion in
                self?.play(media)
                completion()
            }
            loadImage(media.artworkURL, into: item)
            return item
        }
        push(CPListTemplate(title: "Recently watched", sections: [CPListSection(items: items)]))
    }

    // MARK: YouTube

    private func showYouTube() {
        guard GoogleAuth.shared.isSignedIn else {
            return showAlert("Sign in to YouTube in the app on your iPhone first.")
        }
        let items = [
            menuItem("Recently watched", symbol: "clock.arrow.circlepath") { [weak self] in self?.showRecent() },
            menuItem("Search", symbol: "magnifyingglass") { [weak self] in self?.showSearch() },
            menuItem("Liked videos", symbol: "hand.thumbsup") { [weak self] in
                self?.showVideos(title: "Liked videos") { try await YouTubeAPI.liked() }
            },
            menuItem("Subscriptions", symbol: "person.2") { [weak self] in
                self?.showPlaylists(title: "Subscriptions") { try await YouTubeAPI.subscriptions() }
            },
            menuItem("Playlists", symbol: "list.bullet") { [weak self] in
                self?.showPlaylists(title: "Playlists") { try await YouTubeAPI.playlists() }
            },
        ]
        push(CPListTemplate(title: "YouTube", sections: [CPListSection(items: items)]))
    }

    private func showPlaylists(title: String, load: @escaping () async throws -> [YouTubePlaylist]) {
        showLoadingList(title: title) { [weak self] in
            guard let self else { return [] }
            return try await load().prefix(self.maxItems).map { playlist in
                let item = CPListItem(text: playlist.title, detailText: nil)
                item.accessoryType = .disclosureIndicator
                item.handler = { [weak self] _, completion in
                    self?.showVideos(title: playlist.title) { try await YouTubeAPI.playlistVideos(playlist.id) }
                    completion()
                }
                self.loadImage(playlist.thumbnailURL, into: item)
                return item
            }
        }
    }

    private func showVideos(title: String, load: @escaping () async throws -> [YouTubeVideo]) {
        showLoadingList(title: title) { [weak self] in
            guard let self else { return [] }
            return try await load().prefix(self.maxItems).map { video in
                let item = CPListItem(text: video.title, detailText: video.channelTitle)
                item.handler = { [weak self] _, completion in
                    self?.play(.youtube(video))
                    completion()
                }
                self.loadImage(video.thumbnailURL, into: item)
                return item
            }
        }
    }

    /// Pushes an empty list immediately, then fills it once `load` finishes.
    private func showLoadingList(title: String, load: @escaping () async throws -> [CPListItem]) {
        let template = CPListTemplate(title: title, sections: [])
        template.emptyViewTitleVariants = ["Loading…"]
        push(template)
        Task {
            do {
                let items = try await load()
                template.emptyViewTitleVariants = ["Nothing here"]
                template.updateSections([CPListSection(items: items)])
            } catch {
                template.emptyViewTitleVariants = ["Couldn't load"]
                template.emptyViewSubtitleVariants = [error.localizedDescription]
                template.updateSections([])
            }
        }
    }

    // MARK: Search

    private func showSearch() {
        let template = CPSearchTemplate()
        template.delegate = self
        push(template)
    }

    private func searchYouTube(_ query: String) {
        guard GoogleAuth.shared.isSignedIn else {
            return showAlert("Sign in to YouTube in the app on your iPhone first.")
        }
        showVideos(title: query) { try await YouTubeAPI.search(query) }
    }

    // MARK: Helpers

    private func play(_ item: MediaItem) {
        player.play(item)
        interfaceController.popToRootTemplate(animated: true, completion: nil)
    }

    private func push(_ template: CPTemplate) {
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    private func showAlert(_ message: String) {
        let alert = CPAlertTemplate(titleVariants: [message], actions: [
            CPAlertAction(title: "OK", style: .cancel) { [weak self] _ in
                self?.interfaceController.dismissTemplate(animated: true, completion: nil)
            },
        ])
        interfaceController.presentTemplate(alert, animated: true, completion: nil)
    }

    private func menuItem(_ title: String, symbol: String, action: @escaping () -> Void) -> CPListItem {
        let item = CPListItem(text: title, detailText: nil, image: Self.symbol(symbol))
        item.accessoryType = .disclosureIndicator
        item.handler = { _, completion in
            action()
            completion()
        }
        return item
    }

    private func loadImage(_ url: URL?, into item: CPListItem) {
        guard let url else { return }
        Task {
            if let image = await ImageCache.shared.image(for: url, fitting: CPListItem.maximumImageSize) {
                item.setImage(image)
            }
        }
    }

    private static func symbol(_ name: String) -> UIImage {
        UIImage(systemName: name) ?? UIImage()
    }
}

extension CarPlayBrowser: CPSearchTemplateDelegate {
    func searchTemplate(_ searchTemplate: CPSearchTemplate, updatedSearchText searchText: String,
                        completionHandler: @escaping ([CPListItem]) -> Void) {
        let query = searchText.trimmed
        lastSearchText = query
        guard query.count >= 2 else { return completionHandler([]) }

        // Channel/movie matches are local and free; YouTube search costs API quota, so it's one tap away.
        let matches = (library.live + library.movies)
            .lazy
            .filter { $0.name.localizedCaseInsensitiveContains(query) }
            .prefix(12)
        var items: [CPListItem] = matches.map { channel in
            let item = CPListItem(text: channel.name, detailText: channel.group)
            item.userInfo = MediaItem.stream(channel)
            return item
        }
        if GoogleAuth.shared.isSignedIn {
            let youtube = CPListItem(text: "Search YouTube for “\(query)”", detailText: nil, image: Self.symbol("play.rectangle"))
            youtube.userInfo = query
            items.insert(youtube, at: 0)
        }
        completionHandler(items)
    }

    func searchTemplate(_ searchTemplate: CPSearchTemplate, selectedResult item: CPListItem,
                        completionHandler: @escaping () -> Void) {
        if let media = item.userInfo as? MediaItem {
            play(media)
        } else if let query = item.userInfo as? String {
            searchYouTube(query)
        }
        completionHandler()
    }

    func searchTemplateSearchButtonPressed(_ searchTemplate: CPSearchTemplate) {
        if lastSearchText.count >= 2 { searchYouTube(lastSearchText) }
    }
}
